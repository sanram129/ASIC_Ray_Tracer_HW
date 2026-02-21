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


def _load_light_position() -> np.ndarray:
    """Load a single point light position from camera_light.json."""
    data = _load_camera_json()
    fallback = np.array([16.0, 60.0, 5.0], dtype=np.float32)
    if not data:
        return fallback

    try:
        pos = np.array(data["light"]["pos"], dtype=np.float32)
        return pos if pos.shape == (3,) else fallback
    except Exception:
        return fallback


_CAMERA_JSON = _load_camera_json()
LIGHT_POS = _load_light_position()
AMBIENT      = 0.12
EXPOSURE     = 0.60   # overall brightness scale applied before gamma (< 1 = darker)
CONTRAST     = 1.10   # mild linear contrast applied before gamma (>1 increases contrast)
SKY_COLOR = np.array([0.4, 0.6, 1.0], dtype=np.float32)   # background blue

# =============================================================================
# Shadows
# =============================================================================
# Hard shadows via secondary ray toward the point light.
# We reuse the ASIC DDA core as an occlusion tester.
ENABLE_SHADOWS = True
SHADOW_BIAS = 1e-3      # world-units bias along surface normal to avoid self-hit
SHADOW_EPS_T = 1e-4     # small reduction from light distance to avoid boundary tie


async def _is_shadowed_to_light(
    dut,
    *,
    hit_pos: np.ndarray,
    normal: np.ndarray,
    light_pos: np.ndarray,
    primary_voxel_xyz: tuple[int, int, int],
    px: int,
    py: int,
) -> bool:
    """Return True if geometry occludes the segment from the surface to the light."""

    # Shadow ray: start slightly outside the surface to avoid self-hit.
    hit_pos64 = hit_pos.astype(np.float64)
    normal64 = normal.astype(np.float64)
    light64 = light_pos.astype(np.float64)
    shadow_origin = hit_pos64 + normal64 * float(SHADOW_BIAS)

    to_light = light64 - shadow_origin
    dist = float(np.linalg.norm(to_light))
    if dist <= 1e-6:
        return False

    shadow_dir = _normalize(to_light.astype(np.float64))

    sjob = _make_option_b_job(
        shadow_origin,
        shadow_dir,
        wbits=FIXED_W,
        frac=FIXED_FRAC,
        max_steps=512,
    )
    if not sjob.get("valid", 0):
        return False

    # Limit travel to the light distance.
    t_end = max(0.0, dist - float(SHADOW_EPS_T))
    t_end_fx = _to_fixed_nonneg(t_end, FIXED_W, FIXED_FRAC)
    sjob["max_steps"] = _shadow_step_budget(sjob, t_end_fx)

    sjob["px"] = px
    sjob["py"] = py

    ok_shadow = await _send_ray_job(dut, sjob, timeout_cycles=4000)
    if not ok_shadow:
        return False
    if not dut.ray_hit.value:
        return False

    sxh = int(dut.hit_voxel_x.value)
    syh = int(dut.hit_voxel_y.value)
    szh = int(dut.hit_voxel_z.value)
    x0, y0, z0 = primary_voxel_xyz
    # Ignore pathological self-hit if it happens.
    return not (sxh == x0 and syh == y0 and szh == z0)

# Fixed-point settings used by ray job encoding (must match rays_to_scene.py output)
_FIXED = (_CAMERA_JSON.get("fixed_point", {}) if _CAMERA_JSON else {})
FIXED_W = int(_FIXED.get("W", 24))
FIXED_FRAC = int(_FIXED.get("FRAC", 16))

# Ray job world bounds (32^3 voxel world)
N = 32
WORLD_MIN = np.array([0.0, 0.0, 0.0], dtype=np.float64)
WORLD_MAX = np.array([float(N), float(N), float(N)], dtype=np.float64)
EPS_DIR = 1e-12
EPS_ADVANCE = 1e-6

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


def _to_fixed_nonneg(x: float, wbits: int, frac: int) -> int:
    """Convert non-negative float to unsigned fixed-point, truncating.

    Matches rays_to_scene.to_fixed(): saturates to max on NaN/inf/negative.
    """
    max_u = (1 << int(wbits)) - 1
    if (not math.isfinite(x)) or x < 0.0:
        return max_u
    val = int(x * (1 << int(frac)))
    if val < 0:
        return 0
    if val > max_u:
        return max_u
    return val


def _intersect_aabb(origin: np.ndarray, direction: np.ndarray, bmin: np.ndarray, bmax: np.ndarray) -> tuple[bool, float, float]:
    """Ray-AABB intersection (slab method). Returns (hit, t_enter, t_exit)."""
    tmin = -float("inf")
    tmax = +float("inf")
    for i in range(3):
        d = float(direction[i])
        o = float(origin[i])
        if abs(d) < EPS_DIR:
            if o < float(bmin[i]) or o > float(bmax[i]):
                return False, 0.0, 0.0
            continue
        inv = 1.0 / d
        t0 = (float(bmin[i]) - o) * inv
        t1 = (float(bmax[i]) - o) * inv
        if t0 > t1:
            t0, t1 = t1, t0
        tmin = max(tmin, t0)
        tmax = min(tmax, t1)
        if tmax < tmin:
            return False, 0.0, 0.0
    return True, float(tmin), float(tmax)


def _make_option_b_job(
    origin: np.ndarray,
    direction: np.ndarray,
    wbits: int,
    frac: int,
    max_steps: int,
) -> dict:
    """Build an Option-B ray job dict compatible with _send_ray_job().

    Returns a dict with keys used by the DUT job interface plus a `valid` flag.
    """
    hit, t_enter, t_exit = _intersect_aabb(origin, direction, WORLD_MIN, WORLD_MAX)
    if (not hit) or (t_exit < 0.0):
        return {"valid": 0}

    t0 = max(t_enter, 0.0) + EPS_ADVANCE
    p0 = origin + direction * t0
    # Clamp to just inside [0,32)
    p0 = np.minimum(np.maximum(p0, 0.0), float(N) - 1e-9)

    ix0 = int(np.floor(float(p0[0])))
    iy0 = int(np.floor(float(p0[1])))
    iz0 = int(np.floor(float(p0[2])))

    sx = 1 if float(direction[0]) >= 0.0 else 0
    sy = 1 if float(direction[1]) >= 0.0 else 0
    sz = 1 if float(direction[2]) >= 0.0 else 0

    step_x = +1 if sx == 1 else -1
    step_y = +1 if sy == 1 else -1
    step_z = +1 if sz == 1 else -1

    next_bx = (ix0 + 1) if step_x == 1 else ix0
    next_by = (iy0 + 1) if step_y == 1 else iy0
    next_bz = (iz0 + 1) if step_z == 1 else iz0

    def axis_t(dcomp: float, pcomp: float, next_b: int) -> tuple[float, float]:
        if abs(dcomp) < EPS_DIR:
            return (float("inf"), float("inf"))
        tmax = (float(next_b) - pcomp) / dcomp
        if tmax < 0.0:
            tmax = 0.0
        tdelta = abs(1.0 / dcomp)
        return (float(tmax), float(tdelta))

    tmax_x, tdelta_x = axis_t(float(direction[0]), float(p0[0]), next_bx)
    tmax_y, tdelta_y = axis_t(float(direction[1]), float(p0[1]), next_by)
    tmax_z, tdelta_z = axis_t(float(direction[2]), float(p0[2]), next_bz)

    next_x = _to_fixed_nonneg(tmax_x, wbits, frac)
    next_y = _to_fixed_nonneg(tmax_y, wbits, frac)
    next_z = _to_fixed_nonneg(tmax_z, wbits, frac)
    inc_x  = _to_fixed_nonneg(tdelta_x, wbits, frac)
    inc_y  = _to_fixed_nonneg(tdelta_y, wbits, frac)
    inc_z  = _to_fixed_nonneg(tdelta_z, wbits, frac)

    max_steps_u = int(max(0, min(int(max_steps), 1023)))

    return {
        "valid": 1,
        "ix0": ix0,
        "iy0": iy0,
        "iz0": iz0,
        "sx": sx,
        "sy": sy,
        "sz": sz,
        "next_x": next_x,
        "next_y": next_y,
        "next_z": next_z,
        "inc_x": inc_x,
        "inc_y": inc_y,
        "inc_z": inc_z,
        "max_steps": max_steps_u,
    }


def _shadow_step_budget(job: dict, t_end_fx: int) -> int:
    """Compute max_steps so the ASIC won't march past the point light.

    We simulate the same axis selection policy as axis_choose.sv:
      pick min(next_x,next_y,next_z), with tie-break X then Y then Z.
    Terminate when min(next_*) > t_end_fx.
    """
    if not job.get("valid", 0):
        return 0

    ix = int(job["ix0"])
    iy = int(job["iy0"])
    iz = int(job["iz0"])
    sx = int(job["sx"])
    sy = int(job["sy"])
    sz = int(job["sz"])

    next_x = int(job["next_x"])
    next_y = int(job["next_y"])
    next_z = int(job["next_z"])
    inc_x  = int(job["inc_x"])
    inc_y  = int(job["inc_y"])
    inc_z  = int(job["inc_z"])

    step_x = 1 if sx == 1 else -1
    step_y = 1 if sy == 1 else -1
    step_z = 1 if sz == 1 else -1

    steps = 0
    # Upper bound: never need more than a few hundred for a 32^3 world, but cap defensively.
    for _ in range(2048):
        m = next_x
        if next_y < m:
            m = next_y
        if next_z < m:
            m = next_z
        # Stop before stepping to/through the voxel boundary at the light distance.
        if m >= int(t_end_fx):
            break

        # Deterministic tie-break matches axis_choose.sv
        if next_x <= next_y and next_x <= next_z:
            ix += step_x
            next_x += inc_x
        elif next_y <= next_z:
            iy += step_y
            next_y += inc_y
        else:
            iz += step_z
            next_z += inc_z

        steps += 1

        # If we leave the world bounds, ASIC will terminate on out_of_bounds anyway.
        if ix < 0 or ix > 31 or iy < 0 or iy > 31 or iz < 0 or iz > 31:
            break

        if steps >= 1023:
            break

    return int(steps)


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
                    "valid":  valid,
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
    # Optional performance stats (for presentations / theme writeups)
    stats = job.get("_stats") if isinstance(job, dict) else None
    if stats is not None and not isinstance(stats, dict):
        stats = None

    # --- 1. Wait for job_ready (stay in ReadWrite phase so we can write after) ---
    ready_wait_cycles = 0
    for _ in range(1000):
        await RisingEdge(dut.clk)
        ready_wait_cycles += 1
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
    done_wait_cycles = 0
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        done_wait_cycles += 1
        if dut.ray_done.value:
            if stats is not None:
                stats.setdefault("ready_wait_cycles", []).append(int(ready_wait_cycles))
                stats.setdefault("done_wait_cycles", []).append(int(done_wait_cycles))
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
    # Parse ALL pixels including valid=0 rays so the output resolution matches
    # the requested image size; invalid rays become sky pixels.
    jobs = _parse_ray_jobs(RAY_FILE, skip_invalid=False)
    if not jobs:
        log.error(f"No valid ray jobs found in {RAY_FILE}")
        assert False, "No ray jobs to process"

    # Determine intended image resolution. Prefer camera_light.json (authoritative).
    if _CAMERA_JSON and _CAMERA_JSON.get("camera"):
        img_w = int(_CAMERA_JSON["camera"].get("image_w", 0))
        img_h = int(_CAMERA_JSON["camera"].get("image_h", 0))
    else:
        img_w = 0
        img_h = 0
    if img_w <= 0 or img_h <= 0:
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

    perf = {
        "ready_wait_cycles": [],
        "done_wait_cycles": [],
        "steps_taken": [],
        "clock_period_ns": 10.0,
    }

    for idx, job in enumerate(jobs):

        # valid=0 means the primary ray never intersects the voxel world AABB.
        # Leave pixel as sky and do not submit a job to hardware.
        if not job.get("valid", 1):
            image[job["py"], job["px"]] = SKY_COLOR
            miss_count += 1
            continue

        # Attach stats collector for primary rays only.
        job["_stats"] = perf
        ok = await _send_ray_job(dut, job)
        job.pop("_stats", None)
        if not ok:
            # Timeout: leave pixel as sky colour
            miss_count += 1
            continue

        # Record steps_taken for this ray (valid after ray_done)
        try:
            perf["steps_taken"].append(int(dut.steps_taken.value))
        except Exception:
            pass

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

            # Lambertian diffuse shading from a single point light.
            light_dir = _normalize(LIGHT_POS - hit_pos)
            diff = float(np.dot(normal, light_dir))
            if diff <= 0.0:
                diff = 0.0
            elif ENABLE_SHADOWS and diff > 1e-6:
                shadowed = await _is_shadowed_to_light(
                    dut,
                    hit_pos=hit_pos,
                    normal=normal,
                    light_pos=LIGHT_POS,
                    primary_voxel_xyz=(x, y, z),
                    px=job["px"],
                    py=job["py"],
                )
                if shadowed:
                    diff = 0.0

            brightness = AMBIENT + (1.0 - AMBIENT) * float(min(1.0, max(0.0, diff)))

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
        dot_r = max(3, int(min(img_w, img_h) * 0.04))
        lp = _project_to_pixel(LIGHT_POS.astype(np.float64), _CAMERA_JSON, img_w, img_h)
        if lp is None:
            log.info("  Light is behind the camera — dot not rendered")
        else:
            for dy in range(-dot_r, dot_r + 1):
                for dx in range(-dot_r, dot_r + 1):
                    if dx * dx + dy * dy <= dot_r * dot_r:
                        ry, rx = lp[1] + dy, lp[0] + dx
                        if 0 <= ry < img_h and 0 <= rx < img_w:
                            image[ry, rx] = np.array([1.0, 1.0, 1.0], dtype=np.float32)
            log.info(f"  Light dot drawn at pixel ({lp[0]}, {lp[1]})  radius={dot_r}px")

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

    # -------------------------------------------------------------------------
    # 10. Performance summary (jobs/s, cycles/ray, steps/ray)
    # -------------------------------------------------------------------------
    try:
        import statistics as _stats_mod

        rr = perf.get("ready_wait_cycles", [])
        dd = perf.get("done_wait_cycles", [])
        ss = perf.get("steps_taken", [])
        if dd:
            clk_ns = float(perf.get("clock_period_ns", 10.0))
            f_hz = 1e9 / clk_ns
            avg_ready = float(_stats_mod.mean(rr)) if rr else 0.0
            avg_done = float(_stats_mod.mean(dd))
            avg_steps = float(_stats_mod.mean(ss)) if ss else float("nan")

            # Total cycles per ray from job latch to ray_done. (Does not include scene load.)
            rays_per_sec_100mhz = f_hz / avg_done if avg_done > 0 else 0.0
            rays_per_sec_66mhz = (66e6 / f_hz) * rays_per_sec_100mhz if f_hz > 0 else 0.0
            rays_per_sec_33mhz = (33e6 / f_hz) * rays_per_sec_100mhz if f_hz > 0 else 0.0

            log.info("-" * 60)
            log.info("Performance (primary rays only):")
            log.info(f"  Clock period        : {clk_ns:.1f} ns  ({f_hz/1e6:.1f} MHz)")
            log.info(f"  Avg ready-wait      : {avg_ready:.1f} cycles")
            log.info(f"  Avg cycles to done  : {avg_done:.1f} cycles")
            if ss:
                log.info(f"  Avg DDA steps_taken : {avg_steps:.1f} steps")
            log.info(f"  Throughput @ {f_hz/1e6:.1f} MHz: {rays_per_sec_100mhz:,.0f} rays/s")
            log.info(f"  Scaled @ 66 MHz     : {rays_per_sec_66mhz:,.0f} rays/s")
            log.info(f"  Scaled @ 33 MHz     : {rays_per_sec_33mhz:,.0f} rays/s")
            log.info("-" * 60)
    except Exception as e:
        log.warning(f"Perf summary skipped: {e}")

    log.info("=" * 60)
    log.info(f"  Render complete!")
    log.info(f"  Image size : {img_w} x {img_h} pixels")
    log.info(f"  Hit pixels : {hit_count}")
    log.info(f"  Sky pixels : {miss_count}")
    log.info(f"  Saved to   : {OUTPUT_PNG}")
    log.info("=" * 60)
