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
import math
import logging
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from voxel_loader import VoxelLoader

log = logging.getLogger("cocotb.test_raytracer")

# =============================================================================
# Configuration (overridable via environment variables)
# =============================================================================

VOXEL_FILE        = os.environ.get("VOXEL_FILE",        "voxels_load.txt")
COLOR_FILE        = os.environ.get("COLOR_FILE",        "voxels_color.mem")
RAY_FILE          = os.environ.get("RAY_FILE",          "ray_jobs.txt")
OUTPUT_PNG        = os.environ.get("OUTPUT_PNG",        "render.png")
CAMERA_LIGHT_FILE = os.environ.get("CAMERA_LIGHT_FILE", "")

# ---------------------------------------------------------------------------
# Light position: loaded from camera_light.json (written by rays_to_scene.py).
# To move the light, edit LIGHT_POS in rays_to_scene.py and re-run scene gen.
# Falls back to a sensible default if the JSON is not found.
# ---------------------------------------------------------------------------
def _load_camera_json() -> dict:
    """Load the full camera_light.json dict, or {} if not found."""
    import json
    candidates = []
    if CAMERA_LIGHT_FILE:
        candidates.append(CAMERA_LIGHT_FILE)
    if VOXEL_FILE:
        candidates.append(os.path.join(os.path.dirname(VOXEL_FILE), "camera_light.json"))
    candidates.append("camera_light.json")
    for path in candidates:
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)
    return {}


def _load_light_pos() -> np.ndarray:
    """Load light position from camera_light.json, or return fallback."""
    data = _load_camera_json()
    if data:
        return np.array(data["light"]["pos"], dtype=np.float32)
    return np.array([16.0, 60.0, 5.0], dtype=np.float32)


_CAMERA_JSON = _load_camera_json()
LIGHT_POS    = _load_light_pos()
AMBIENT      = 0.12
EXPOSURE     = 0.60   # overall brightness scale applied before gamma (< 1 = darker)
CONTRAST     = 1.10   # mild linear contrast applied before gamma (>1 increases contrast)
SKY_COLOR = np.array([0.4, 0.6, 1.0], dtype=np.float32)   # background blue

# =============================================================================
# Face normals table
# primary_face_id from step_update.sv encodes the LAST DDA STEP DIRECTION
# (the axis the ray was travelling when it entered the voxel), NOT the outward
# surface normal. The outward normal is the OPPOSITE of the step direction:
#   face_id=0: last step was +X → ray came from -X side → outward normal = -X
#   face_id=1: last step was -X → ray came from +X side → outward normal = +X
#   face_id=2: last step was +Y → ray came from -Y side → outward normal = -Y  (entered from below)
#   face_id=3: last step was -Y → ray came from +Y side → outward normal = +Y  (entered from top ← normal top-down hit)
#   face_id=4: last step was +Z → outward normal = -Z
#   face_id=5: last step was -Z → outward normal = +Z
# =============================================================================
FACE_NORMALS = np.array([
    [-1.0,  0.0,  0.0],   # 0: stepped +X → outward normal -X
    [ 1.0,  0.0,  0.0],   # 1: stepped -X → outward normal +X
    [ 0.0, -1.0,  0.0],   # 2: stepped +Y → outward normal -Y
    [ 0.0,  1.0,  0.0],   # 3: stepped -Y → outward normal +Y  (top face, top-down ray)
    [ 0.0,  0.0, -1.0],   # 4: stepped +Z → outward normal -Z
    [ 0.0,  0.0,  1.0],   # 5: stepped -Z → outward normal +Z
], dtype=np.float32)

# =============================================================================
# Utility functions
# =============================================================================

def _normalize(v: np.ndarray) -> np.ndarray:
    """Return unit vector; returns v unchanged if near-zero length."""
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


def _ray_origin_dir_for_pixel(px: int, py: int, cam_data: dict, img_w: int, img_h: int) -> tuple[np.ndarray, np.ndarray]:
    """Reconstruct the primary ray for (px,py) using camera_light.json.

    This matches rays_to_scene.generate_primary_ray():
      u,v in NDC -> scale by tan(fov/2) and aspect -> dir = normalize(fwd + u*right + v*up)
    """
    cam = cam_data.get("camera") if cam_data else None
    if not cam:
        raise KeyError("camera_light.json missing 'camera' block")

    cp = np.array(cam["pos"], dtype=np.float64)
    fwd = np.array(cam["forward"], dtype=np.float64)
    rt = np.array(cam["right"], dtype=np.float64)
    up = np.array(cam["up"], dtype=np.float64)
    fov = float(cam["fov_deg"])

    aspect = float(img_w) / float(img_h)
    tan_half = math.tan(math.radians(fov * 0.5))

    u = ((float(px) + 0.5) / float(img_w)) * 2.0 - 1.0
    v = 1.0 - ((float(py) + 0.5) / float(img_h)) * 2.0
    u *= aspect * tan_half
    v *= tan_half

    direction = _normalize(fwd + u * rt + v * up)
    return cp.astype(np.float32), direction.astype(np.float32)


def _hit_pos_on_voxel_face(
    voxel_x: int,
    voxel_y: int,
    voxel_z: int,
    outward_normal: np.ndarray,
    ray_origin: np.ndarray,
    ray_dir: np.ndarray,
) -> np.ndarray:
    """Compute a sub-voxel hit point on the reported hit voxel face.

    We intersect the camera ray with the plane of the hit face (chosen by the
    outward normal) and clamp to that face's bounds for numerical robustness.
    """
    nx, ny, nz = float(outward_normal[0]), float(outward_normal[1]), float(outward_normal[2])

    # Determine primary axis (FACE_NORMALS are axis-aligned).
    ax = 0
    if abs(ny) > abs(nx):
        ax = 1
    if abs(nz) > max(abs(nx), abs(ny)):
        ax = 2

    x0, x1 = float(voxel_x), float(voxel_x + 1)
    y0, y1 = float(voxel_y), float(voxel_y + 1)
    z0, z1 = float(voxel_z), float(voxel_z + 1)

    if ax == 0:
        plane = x0 if nx < 0.0 else x1
        denom = float(ray_dir[0])
        if abs(denom) < 1e-12:
            return np.array([voxel_x + 0.5, voxel_y + 0.5, voxel_z + 0.5], dtype=np.float32)
        t = (plane - float(ray_origin[0])) / denom
    elif ax == 1:
        plane = y0 if ny < 0.0 else y1
        denom = float(ray_dir[1])
        if abs(denom) < 1e-12:
            return np.array([voxel_x + 0.5, voxel_y + 0.5, voxel_z + 0.5], dtype=np.float32)
        t = (plane - float(ray_origin[1])) / denom
    else:
        plane = z0 if nz < 0.0 else z1
        denom = float(ray_dir[2])
        if abs(denom) < 1e-12:
            return np.array([voxel_x + 0.5, voxel_y + 0.5, voxel_z + 0.5], dtype=np.float32)
        t = (plane - float(ray_origin[2])) / denom

    if not np.isfinite(t) or t <= 0.0:
        return np.array([voxel_x + 0.5, voxel_y + 0.5, voxel_z + 0.5], dtype=np.float32)

    p = ray_origin.astype(np.float64) + ray_dir.astype(np.float64) * float(t)

    # Clamp to the hit face bounds (helps with tiny floating error).
    if ax == 0:
        p[0] = float(plane)
        p[1] = min(max(p[1], y0), y1)
        p[2] = min(max(p[2], z0), z1)
    elif ax == 1:
        p[1] = float(plane)
        p[0] = min(max(p[0], x0), x1)
        p[2] = min(max(p[2], z0), z1)
    else:
        p[2] = float(plane)
        p[0] = min(max(p[0], x0), x1)
        p[1] = min(max(p[1], y0), y1)

    return p.astype(np.float32)


def _project_to_pixel(world_pos: np.ndarray, cam_data: dict, img_w: int, img_h: int):
    """
    Project a 3-D world position to (px, py) using the pinhole camera model
    stored in camera_light.json.  Returns None if the point is behind the camera.
    """
    import math
    cam      = cam_data["camera"]
    cp       = np.array(cam["pos"],     dtype=np.float64)
    fwd      = np.array(cam["forward"], dtype=np.float64)
    rt       = np.array(cam["right"],   dtype=np.float64)
    up       = np.array(cam["up"],      dtype=np.float64)
    fov      = float(cam["fov_deg"])
    aspect   = img_w / img_h
    tan_half = math.tan(math.radians(fov * 0.5))

    delta = world_pos.astype(np.float64) - cp
    depth = float(np.dot(delta, fwd))
    if depth <= 0.0:
        return None  # behind camera

    x_v = float(np.dot(delta, rt)) / depth
    y_v = float(np.dot(delta, up)) / depth

    u = x_v / (aspect * tan_half)
    v = y_v / tan_half

    px_f = (u + 1.0) * 0.5 * img_w - 0.5
    py_f = (1.0 - v) * 0.5 * img_h - 0.5
    return int(round(px_f)), int(round(py_f))


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
            normal    = FACE_NORMALS[fid]

            # Use a continuous hit point on the voxel face plane for point-light shading.
            # This avoids the “1-voxel step” brightness banding you get when using
            # integer voxel indices as the lighting point.
            if _CAMERA_JSON:
                ray_o, ray_d = _ray_origin_dir_for_pixel(job["px"], job["py"], _CAMERA_JSON, img_w, img_h)
                hit_pos = _hit_pos_on_voxel_face(x, y, z, normal, ray_o, ray_d)
            else:
                hit_pos = np.array([x + 0.5, y + 0.5, z + 0.5], dtype=np.float32)

            light_dir = _normalize(LIGHT_POS - hit_pos)
            diffuse   = float(np.dot(normal, light_dir))
            diffuse   = max(0.0, diffuse)

            # Energy-conserving: diffuse scales from AMBIENT up to 1.0 (never clips)
            brightness = AMBIENT + (1.0 - AMBIENT) * diffuse
            pixel = base_color * brightness
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
    # 8. Overlay light source as a white dot
    # -------------------------------------------------------------------------
    if _CAMERA_JSON:
        lp = _project_to_pixel(LIGHT_POS.astype(np.float64), _CAMERA_JSON, img_w, img_h)
        if lp is not None:
            dot_r = max(3, int(min(img_w, img_h) * 0.04))
            for dy in range(-dot_r, dot_r + 1):
                for dx in range(-dot_r, dot_r + 1):
                    if dx * dx + dy * dy <= dot_r * dot_r:
                        ry, rx = lp[1] + dy, lp[0] + dx
                        if 0 <= ry < img_h and 0 <= rx < img_w:
                            image[ry, rx] = np.array([1.0, 1.0, 1.0], dtype=np.float32)
            log.info(f"  Light dot drawn at pixel ({lp[0]}, {lp[1]})  radius={dot_r}px")
        else:
            log.info("  Light source is behind the camera — dot not rendered")

    # -------------------------------------------------------------------------
    # 9. Gamma-correct, convert float [0,1] → uint8 [0,255] and save PNG
    #    Apply sRGB gamma (power 1/2.2) so that the linear shading values map
    #    to perceptually correct brightness on a standard monitor.
    # -------------------------------------------------------------------------
    image_lin = np.clip(image * EXPOSURE, 0.0, 1.0)
    image_lin = np.clip((image_lin - 0.5) * CONTRAST + 0.5, 0.0, 1.0)
    image_gamma = image_lin ** (1.0 / 2.2)
    img_uint8 = (image_gamma * 255.0).round().astype(np.uint8)
    pil_image = Image.fromarray(img_uint8, mode="RGB")

    pil_image.save(OUTPUT_PNG)

    log.info("=" * 60)
    log.info(f"  Render complete!")
    log.info(f"  Image size : {img_w} x {img_h} pixels")
    log.info(f"  Hit pixels : {hit_count}")
    log.info(f"  Sky pixels : {miss_count}")
    log.info(f"  Saved to   : {OUTPUT_PNG}")
    log.info("=" * 60)
