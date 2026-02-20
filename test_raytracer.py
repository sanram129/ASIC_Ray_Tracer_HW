"""
test_raytracer.py
=================
Cocotb integration test that:
  1. Resets the DUT (raytracer_top via tb_raytracer_cocotb wrapper)
  2. Loads the voxel scene into hardware RAM using VoxelLoader
  3. Sends one ray job per pixel to the ASIC
  4. Reads back hit_voxel_x/y/z and hit_face_id per ray
  5. Applies Lambertian diffuse shading using the face normal
  6. Looks up per-voxel RGB565 colour from voxels_color.mem
  7. Writes the final rendered image to render.png (Pillow / PIL)

Environment variables (override on make command line):
  VOXEL_FILE   Path to voxel occupancy file  (default: voxels_load.txt)
  COLOR_FILE   Path to voxels_color.mem      (default: voxels_color.mem)
  RAY_FILE     Path to ray_jobs.txt          (default: ray_jobs.txt)
  OUTPUT_PNG   Output filename               (default: render.png)

Face-normal encoding (from step_update.sv, primary_face_id):
  0 = +X face   1 = -X face
  2 = +Y face   3 = -Y face
  4 = +Z face   5 = -Z face

Address mapping (from voxel_addr_map.sv):
  addr = (z << 10) | (y << 5) | x
"""

import os
import logging
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
import numpy as np
from PIL import Image

from voxel_loader import VoxelLoader

log = logging.getLogger("cocotb.test_raytracer")

# =============================================================================
# Configuration (overridable via environment variables)
# =============================================================================

VOXEL_FILE  = os.environ.get("VOXEL_FILE",  "voxels_load.txt")
COLOR_FILE  = os.environ.get("COLOR_FILE",  "voxels_color.mem")
RAY_FILE    = os.environ.get("RAY_FILE",    "ray_jobs.txt")
OUTPUT_PNG  = os.environ.get("OUTPUT_PNG",  "render.png")

# Shading parameters
LIGHT_POS   = np.array([60.0, 60.0, 60.0], dtype=np.float32)  # world-space point light
AMBIENT     = 0.15                                              # minimum brightness
SKY_COLOR   = np.array([0.4, 0.6, 1.0],   dtype=np.float32)   # background blue

# =============================================================================
# Face normals table
# Index matches primary_face_id from step_update.sv:
#   0=X+  1=X-  2=Y+  3=Y-  4=Z+  5=Z-
# =============================================================================
FACE_NORMALS = np.array([
    [ 1.0,  0.0,  0.0],   # 0: +X
    [-1.0,  0.0,  0.0],   # 1: -X
    [ 0.0,  1.0,  0.0],   # 2: +Y
    [ 0.0, -1.0,  0.0],   # 3: -Y
    [ 0.0,  0.0,  1.0],   # 4: +Z
    [ 0.0,  0.0, -1.0],   # 5: -Z
], dtype=np.float32)

# =============================================================================
# Utility functions
# =============================================================================

def _normalize(v: np.ndarray) -> np.ndarray:
    """Return unit vector; returns v unchanged if near-zero length."""
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


def _rgb565_to_float3(rgb565: int) -> np.ndarray:
    """Decode 16-bit RGB565 → float32 [R, G, B] in [0.0 .. 1.0]."""
    r = ((rgb565 >> 11) & 0x1F) / 31.0
    g = ((rgb565 >>  5) & 0x3F) / 63.0
    b = ( rgb565        & 0x1F) / 31.0
    return np.array([r, g, b], dtype=np.float32)


def _load_color_mem(path: str) -> np.ndarray:
    """
    Load voxels_color.mem into a 32768-entry uint16 array.
    Format: one 4-hex-digit RGB565 value per line, ordered z->y->x
    (addr = (z<<10)|(y<<5)|x, same as voxels.mem).
    Returns all-zeros array if file not found.
    """
    colors = np.zeros(32768, dtype=np.uint16)
    if not os.path.exists(path):
        log.warning(f"Color file not found: {path} — using grey fallback")
        return colors
    with open(path, "r") as fh:
        for addr, line in enumerate(fh):
            s = line.strip()
            if s and not s.startswith("#") and addr < 32768:
                colors[addr] = int(s, 16)
    return colors


def _parse_ray_jobs(path: str, skip_invalid: bool = True) -> list:
    """
    Parse ray_jobs.txt into a list of plain dicts.
    Each dict has: px, py, ix0, iy0, iz0, sx, sy, sz,
                   next_x, next_y, next_z, inc_x, inc_y, inc_z, max_steps

    File format (one ray per non-comment line):
      px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps
    """
    jobs = []
    with open(path, "r") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 16:
                continue
            try:
                px      = int(parts[0])
                py      = int(parts[1])
                valid   = int(parts[2])
                if skip_invalid and valid == 0:
                    continue
                jobs.append({
                    "px":     px,
                    "py":     py,
                    "ix0":    int(parts[3]),
                    "iy0":    int(parts[4]),
                    "iz0":    int(parts[5]),
                    "sx":     int(parts[6]),
                    "sy":     int(parts[7]),
                    "sz":     int(parts[8]),
                    "next_x": int(parts[9]),
                    "next_y": int(parts[10]),
                    "next_z": int(parts[11]),
                    "inc_x":  int(parts[12]),
                    "inc_y":  int(parts[13]),
                    "inc_z":  int(parts[14]),
                    "max_steps": int(parts[15]),
                })
            except (ValueError, IndexError) as e:
                log.warning(f"Skipping malformed line {lineno}: {e}")
    return jobs

# =============================================================================
# Hardware interaction helpers
# =============================================================================

async def _reset_dut(dut, cycles: int = 8) -> None:
    """Hold rst_n low for `cycles` clocks, then release."""
    dut.rst_n.value      = 0
    dut.job_valid.value  = 0
    dut.load_mode.value  = 0
    dut.load_valid.value = 0
    dut.load_addr.value  = 0
    dut.load_data.value  = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _send_ray_job(dut, job: dict, timeout_cycles: int = 4000) -> bool:
    """
    Drive one ray job into raytracer_top and wait for ray_done.

    Handshake (mirrors ray_job_if.sv):
      - Wait until job_ready == 1
      - Assert job_valid and all job fields for one clock
      - Deassert job_valid
      - Wait until ray_done == 1
      - Caller reads results in ReadOnly phase

    Returns True on success, False on timeout.
    """
    # --- 1. Wait for job_ready (stay in ReadWrite phase so we can write after) ---
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if dut.job_ready.value:
            break
    else:
        log.error(
            f"Timeout waiting for job_ready at pixel ({job['px']},{job['py']})"
        )
        return False

    # --- 2. Drive all job fields (in ReadWrite phase after RisingEdge) ---
    dut.job_valid.value     = 1
    dut.job_ix0.value       = job["ix0"]
    dut.job_iy0.value       = job["iy0"]
    dut.job_iz0.value       = job["iz0"]
    dut.job_sx.value        = job["sx"]
    dut.job_sy.value        = job["sy"]
    dut.job_sz.value        = job["sz"]
    dut.job_next_x.value    = job["next_x"]
    dut.job_next_y.value    = job["next_y"]
    dut.job_next_z.value    = job["next_z"]
    dut.job_inc_x.value     = job["inc_x"]
    dut.job_inc_y.value     = job["inc_y"]
    dut.job_inc_z.value     = job["inc_z"]
    dut.job_max_steps.value = job["max_steps"]

    # --- 3. One clock to latch the job ---
    await RisingEdge(dut.clk)
    dut.job_valid.value = 0

    # --- 4. Poll for ray_done (read in ReadWrite phase) ---
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.ray_done.value:
            return True

    log.error(
        f"Timeout waiting for ray_done at pixel ({job['px']},{job['py']})"
    )
    return False

# =============================================================================
# Main cocotb test
# =============================================================================

@cocotb.test()
async def test_render_image(dut):
    """
    Full render test: load scene, trace all rays, shade with Lambertian
    diffuse from face normals, and write render.png.
    """

    # -------------------------------------------------------------------------
    # 1. Start 10 ns clock
    # -------------------------------------------------------------------------
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # -------------------------------------------------------------------------
    # 2. Reset
    # -------------------------------------------------------------------------
    await _reset_dut(dut)
    log.info("DUT reset complete")

    # -------------------------------------------------------------------------
    # 3. Load voxel scene into hardware RAM
    #    VoxelLoader detects format from the file extension / content:
    #      .txt → format_type=0 → "addr bit" lines  (from write_voxels_load_txt)
    #      .mem → format_type=1 → one bit per line   (from write_voxels_mem)
    # -------------------------------------------------------------------------
    loader = VoxelLoader(dut, dut.clk)

    if VOXEL_FILE.endswith(".txt"):
        fmt = 0  # "addr bit" format — only writes solid voxels (faster)
    else:
        fmt = 1  # bit-per-line format — writes all 32768 entries

    log.info(f"Loading scene from: {VOXEL_FILE}  (format_type={fmt})")
    await loader.load_voxels_from_file(VOXEL_FILE, format_type=fmt)
    log.info("Scene loaded into voxel RAM")

    # -------------------------------------------------------------------------
    # 4. Load colour memory (software side — no hardware involved)
    #    addr = (z<<10)|(y<<5)|x, one RGB565 hex value per line
    # -------------------------------------------------------------------------
    color_mem = _load_color_mem(COLOR_FILE)
    has_colors = np.any(color_mem != 0)
    log.info(
        f"Colour memory: {'loaded from ' + COLOR_FILE if has_colors else 'not found, using grey fallback'}"
    )

    # -------------------------------------------------------------------------
    # 5. Parse ray jobs
    # -------------------------------------------------------------------------
    jobs = _parse_ray_jobs(RAY_FILE)
    if not jobs:
        log.error(f"No valid ray jobs found in {RAY_FILE}")
        assert False, "No ray jobs to process"

    img_w = max(j["px"] for j in jobs) + 1
    img_h = max(j["py"] for j in jobs) + 1
    log.info(
        f"Rendering {img_w}x{img_h} image — {len(jobs)} rays to trace"
    )

    # -------------------------------------------------------------------------
    # 6. Allocate framebuffer (float32 RGB, initialised to sky colour)
    # -------------------------------------------------------------------------
    image = np.tile(SKY_COLOR, (img_h, img_w, 1)).astype(np.float32)

    # -------------------------------------------------------------------------
    # 7. Trace every ray through the ASIC and shade
    # -------------------------------------------------------------------------
    hit_count  = 0
    miss_count = 0

    for idx, job in enumerate(jobs):

        ok = await _send_ray_job(dut, job)
        if not ok:
            # Timeout: leave pixel as sky colour
            miss_count += 1
            continue

        if dut.ray_hit.value:
            # ── Geometry from ASIC outputs ───────────────────────────────────
            x   = int(dut.hit_voxel_x.value)   # 5-bit voxel coordinate
            y   = int(dut.hit_voxel_y.value)
            z   = int(dut.hit_voxel_z.value)
            fid = int(dut.hit_face_id.value)    # 0-5

            # Guard against out-of-range face IDs (should never happen)
            fid = min(fid, 5)

            # ── Voxel colour ─────────────────────────────────────────────────
            addr = (z << 10) | (y << 5) | x
            rgb565     = int(color_mem[addr])
            base_color = _rgb565_to_float3(rgb565)

            # Fallback to neutral grey if no colour data for this voxel
            if rgb565 == 0:
                base_color = np.array([0.72, 0.72, 0.72], dtype=np.float32)

            # ── Lambertian diffuse shading ────────────────────────────────────
            # diffuse = max(0, dot(surface_normal, direction_to_light))
            hit_pos   = np.array([x, y, z], dtype=np.float32)
            normal    = FACE_NORMALS[fid]
            light_dir = _normalize(LIGHT_POS - hit_pos)
            diffuse   = float(np.dot(normal, light_dir))
            diffuse   = max(0.0, diffuse)

            # Combine ambient + diffuse, clamp to [0, 1]
            pixel = np.clip(base_color * (AMBIENT + diffuse), 0.0, 1.0)
            image[job["py"], job["px"]] = pixel
            hit_count += 1

        else:
            # Ray missed all geometry (out-of-bounds or timeout) → sky colour
            image[job["py"], job["px"]] = SKY_COLOR
            miss_count += 1

        if (idx + 1) % 200 == 0 or (idx + 1) == len(jobs):
            log.info(
                f"  {idx+1}/{len(jobs)} rays traced  "
                f"({hit_count} hits, {miss_count} misses)"
            )

    # -------------------------------------------------------------------------
    # 8. Convert float [0,1] → uint8 [0,255] and save PNG
    # -------------------------------------------------------------------------
    img_uint8 = (image * 255.0).round().astype(np.uint8)
    pil_image = Image.fromarray(img_uint8, mode="RGB")
    pil_image.save(OUTPUT_PNG)

    log.info("=" * 60)
    log.info(f"  Render complete!")
    log.info(f"  Image size : {img_w} x {img_h} pixels")
    log.info(f"  Hit pixels : {hit_count}")
    log.info(f"  Sky pixels : {miss_count}")
    log.info(f"  Saved to   : {OUTPUT_PNG}")
    log.info("=" * 60)
