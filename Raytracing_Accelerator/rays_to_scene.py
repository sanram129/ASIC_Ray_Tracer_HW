#!/usr/bin/env python3
"""
scene_and_rays.py

1) Voxelize STL into 32^3 occupancy bits using stl_to_voxels.py
2) Choose a reasonable camera + key light
3) Generate one primary ray per pixel
4) Convert each ray into "Option B" DDA job fields for ray_job_if:
   ix0/iy0/iz0, sx/sy/sz, next_x/y/z, inc_x/y/z, max_steps  :contentReference[oaicite:3]{index=3}

Outputs (in out_dir):
  - voxels.mem, voxels_load.txt, voxel_meta.json   (from voxelizer)
  - ray_jobs.txt      (one line per pixel with the job fields)
  - camera_light.json (camera + light placement for your renderer)

Coordinate system used for ray jobs:
  world = [0,32]^3, voxel boundaries at integer coords, voxel indices 0..31.
  This matches the RAM addressing convention used by your loader flow.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Tuple

import numpy as np

# Import your voxelizer module (keep this file in the same folder as stl_to_voxels.py)
import stl_to_voxels  # :contentReference[oaicite:4]{index=4}


N = 32
WORLD_MIN = np.array([0.0, 0.0, 0.0], dtype=np.float64)
WORLD_MAX = np.array([float(N), float(N), float(N)], dtype=np.float64)

EPS_DIR = 1e-12
EPS_ADVANCE = 1e-6


def norm(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    if n < 1e-20:
        return v.copy()
    return v / n


def build_camera_basis(cam_pos: np.ndarray, look_at: np.ndarray, world_up: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Returns (forward, right, up) as unit vectors.
    """
    forward = norm(look_at - cam_pos)

    right = np.cross(forward, world_up)
    if np.linalg.norm(right) < 1e-9:
        # If forward is nearly parallel to world_up, pick a different up
        world_up = np.array([0.0, 0.0, 1.0], dtype=np.float64)
        right = np.cross(forward, world_up)

    right = norm(right)
    up = norm(np.cross(right, forward))
    return forward, right, up


def choose_camera_and_light(bounds_min_world: np.ndarray, bounds_max_world: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    "Ideal enough" defaults for a demo:
    - Camera placed on a diagonal so the object looks 3D (not flat head-on).
    - Light placed near camera but above/right so faces get readable shading.

    Returns: (cam_pos, look_at, light_pos)
    """
    center = 0.5 * (bounds_min_world + bounds_max_world)
    diag = float(np.linalg.norm(bounds_max_world - bounds_min_world))
    radius = max(diag * 0.5, 1.0)

    # Camera direction: from a diagonal (-z, +x, +y) viewpoint
    view_dir = norm(np.array([+1.0, +1.0, -1.3], dtype=np.float64))

    # Distance: scale with object size, but keep it comfortably outside [0,32]^3
    dist = max(3.2 * radius, 40.0)
    cam_pos = center + view_dir * dist
    look_at = center

    # Key light: near camera, but offset up+right so you get nice face contrast
    forward, right, up = build_camera_basis(cam_pos, look_at, np.array([0.0, 1.0, 0.0], dtype=np.float64))
    light_pos = cam_pos + (0.35 * dist) * up + (0.25 * dist) * right

    return cam_pos, look_at, light_pos


def intersect_aabb(origin: np.ndarray, direction: np.ndarray, bmin: np.ndarray, bmax: np.ndarray) -> Tuple[bool, float, float]:
    """
    Ray-AABB intersection (slab method). Returns (hit, t_enter, t_exit).
    AABB is [bmin, bmax]. We treat it as a closed box for intersection purposes.
    """
    tmin = -np.inf
    tmax = +np.inf

    for i in range(3):
        d = float(direction[i])
        o = float(origin[i])

        if abs(d) < EPS_DIR:
            # Ray parallel to slabs: must be within the slab
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


def to_fixed(x: float, wbits: int, frac: int) -> int:
    """
    Convert a non-negative real to unsigned fixed point.
    Saturates to max on overflow/inf/nan.
    """
    max_u = (1 << wbits) - 1
    if not np.isfinite(x) or x < 0.0:
        return max_u
    val = int(round(x * (1 << frac)))
    if val < 0:
        val = 0
    if val > max_u:
        val = max_u
    return val


def make_option_b_job(origin: np.ndarray, direction: np.ndarray, wbits: int, frac: int, max_steps: int) -> Tuple[int, ...]:
    """
    Build Option-B job fields for ray_job_if:
      ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps
    Returns a tuple of integers. If the ray never intersects the voxel world, returns a "valid=0" job.
    """
    hit, t_enter, t_exit = intersect_aabb(origin, direction, WORLD_MIN, WORLD_MAX)
    if (not hit) or (t_exit < 0.0):
        # valid=0, filler zeros
        return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    # Start inside the world: advance to entry point (or just past origin if already inside)
    t0 = max(t_enter, 0.0) + EPS_ADVANCE
    p0 = origin + direction * t0

    # Clamp to just inside [0,32) to avoid p0==32 edge cases
    p0 = np.minimum(np.maximum(p0, 0.0), float(N) - 1e-9)

    ix0 = int(np.floor(p0[0]))
    iy0 = int(np.floor(p0[1]))
    iz0 = int(np.floor(p0[2]))

    # Step sign bits: 0 => -1, 1 => +1  :contentReference[oaicite:5]{index=5}
    sx = 1 if direction[0] >= 0.0 else 0
    sy = 1 if direction[1] >= 0.0 else 0
    sz = 1 if direction[2] >= 0.0 else 0

    step_x = +1 if sx == 1 else -1
    step_y = +1 if sy == 1 else -1
    step_z = +1 if sz == 1 else -1

    # Next voxel boundary coordinates (integer planes)
    next_bx = (ix0 + 1) if step_x == 1 else ix0
    next_by = (iy0 + 1) if step_y == 1 else iy0
    next_bz = (iz0 + 1) if step_z == 1 else iz0

    # Compute timers and increments in "world units" (voxel size = 1)
    # tMax = distance along ray to next boundary plane; tDelta = distance between crossings
    def axis_t(dcomp: float, pcomp: float, next_b: int) -> Tuple[float, float]:
        if abs(dcomp) < EPS_DIR:
            return (np.inf, np.inf)
        tmax = (float(next_b) - pcomp) / dcomp
        if tmax < 0.0:
            # Numerical edge: should be ~0, clamp
            tmax = 0.0
        tdelta = abs(1.0 / dcomp)
        return (tmax, tdelta)

    tmax_x, tdelta_x = axis_t(float(direction[0]), float(p0[0]), next_bx)
    tmax_y, tdelta_y = axis_t(float(direction[1]), float(p0[1]), next_by)
    tmax_z, tdelta_z = axis_t(float(direction[2]), float(p0[2]), next_bz)

    next_x = to_fixed(tmax_x, wbits, frac)
    next_y = to_fixed(tmax_y, wbits, frac)
    next_z = to_fixed(tmax_z, wbits, frac)

    inc_x = to_fixed(tdelta_x, wbits, frac)
    inc_y = to_fixed(tdelta_y, wbits, frac)
    inc_z = to_fixed(tdelta_z, wbits, frac)

    # Clamp max_steps to a reasonable range
    max_steps_u = int(max(0, min(max_steps, 1023)))

    # valid=1 is handled outside (we store it separately in file)
    return (ix0, iy0, iz0, sx, sy, sz, next_x, next_y, next_z, inc_x, inc_y, inc_z, max_steps_u, 1)


def generate_primary_ray(cam_pos: np.ndarray, forward: np.ndarray, right: np.ndarray, up: np.ndarray,
                         px: int, py: int, w: int, h: int, fov_deg: float) -> Tuple[np.ndarray, np.ndarray]:
    """
    Pinhole camera: one ray per pixel.
    """
    aspect = float(w) / float(h)
    fov = np.deg2rad(float(fov_deg))
    tan_half = np.tan(0.5 * fov)

    # Normalized device coords in [-1,1]
    u = ((px + 0.5) / float(w)) * 2.0 - 1.0
    v = 1.0 - ((py + 0.5) / float(h)) * 2.0

    u *= aspect * tan_half
    v *= tan_half

    direction = norm(forward + u * right + v * up)
    return cam_pos.copy(), direction


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stl", type=Path, required=True, help="Input STL file")
    ap.add_argument("--out_dir", type=Path, default=Path("out"), help="Output directory")
    ap.add_argument("--pad", type=float, default=0.01, help="Voxelizer pad in unit cube (same as stl_to_voxels)")
    ap.add_argument("--w", type=int, default=64, help="Image width (rays across)")
    ap.add_argument("--h", type=int, default=64, help="Image height (rays down)")
    ap.add_argument("--fov", type=float, default=55.0, help="Vertical FOV degrees")
    ap.add_argument("--wbits", type=int, default=24, help="Fixed-point width W for next/inc")
    ap.add_argument("--frac", type=int, default=16, help="Fixed-point fractional bits")
    ap.add_argument("--max_steps", type=int, default=512, help="max_steps sent to ASIC")
    ap.add_argument("--downsample", action="store_true", help="Downsample to 16x16x16 at corner with floor and walls")
    args = ap.parse_args()

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    # --- 1) Voxelize STL (re-using your voxelizer code) ---
    mesh = stl_to_voxels.load_mesh(args.stl)
    mesh_u, tf = stl_to_voxels.normalize_to_unit_cube(mesh, pad=args.pad)
    occ = stl_to_voxels.voxelize_by_center_contains(mesh_u, n=N)

    # Apply downsampling with walls if requested
    if args.downsample:
        occ = stl_to_voxels.create_downsampled_with_walls(occ)
        print("Applied downsampling: 16x16x16 model at corner with floor and two walls")

    voxels_mem = out_dir / "voxels.mem"
    voxels_load = out_dir / "voxels_load.txt"
    meta_json = out_dir / "voxel_meta.json"

    stl_to_voxels.write_voxels_mem(occ, voxels_mem)
    stl_to_voxels.write_voxels_load_txt(occ, voxels_load)

    # Bounds in world coords [0,32]^3:
    # When downsampled, the model is at (3-18, 3-18, 1-16) - sitting on floor
    if args.downsample:
        bmin_w = np.array([3.0, 3.0, 1.0], dtype=np.float64)
        bmax_w = np.array([19.0, 19.0, 17.0], dtype=np.float64)
    else:
        bmin_u, bmax_u = mesh_u.bounds
        bmin_w = bmin_u * float(N)
        bmax_w = bmax_u * float(N)

    meta = {
        "n": N,
        "bit_meaning": {"0": "empty/transparent", "1": "solid"},
        "address_mapping": "addr = (z<<10) | (y<<5) | x  (for 32^3)",
        "downsampled": args.downsample,
        "normalize_transform": {
            "scale": float(tf.scale),
            "offset": tf.offset.tolist(),
            "in_bounds_min": tf.in_bounds_min.tolist(),
            "in_bounds_max": tf.in_bounds_max.tolist(),
            "out_bounds_min_world": bmin_w.tolist(),
            "out_bounds_max_world": bmax_w.tolist(),
        },
        "stats": {"solid_voxels": int(np.count_nonzero(occ)), "total_voxels": int(occ.size)},
    }
    meta_json.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    # --- 2) Choose camera + light ---
    cam_pos, look_at, light_pos = choose_camera_and_light(bmin_w, bmax_w)
    forward, right, up = build_camera_basis(cam_pos, look_at, np.array([0.0, 1.0, 0.0], dtype=np.float64))

    cam_light = {
        "world_box": {"min": WORLD_MIN.tolist(), "max": WORLD_MAX.tolist()},
        "camera": {
            "pos": cam_pos.tolist(),
            "look_at": look_at.tolist(),
            "forward": forward.tolist(),
            "right": right.tolist(),
            "up": up.tolist(),
            "fov_deg": float(args.fov),
            "image_w": int(args.w),
            "image_h": int(args.h),
        },
        "light": {
            "type": "point",
            "pos": light_pos.tolist(),
            "note": "Key light near camera, offset up+right for readable face shading.",
        },
        "fixed_point": {"W": int(args.wbits), "FRAC": int(args.frac)},
    }
    (out_dir / "camera_light.json").write_text(json.dumps(cam_light, indent=2), encoding="utf-8")

    # --- 3) Generate rays -> Option-B jobs ---
    jobs_path = out_dir / "ray_jobs.txt"
    with jobs_path.open("w", encoding="utf-8") as f:
        f.write("# px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps\n")
        for py in range(args.h):
            for px in range(args.w):
                origin, direction = generate_primary_ray(cam_pos, forward, right, up, px, py, args.w, args.h, args.fov)
                job = make_option_b_job(origin, direction, args.wbits, args.frac, args.max_steps)

                # job returns (..., max_steps, valid_flag) as last element
                ix0, iy0, iz0, sx, sy, sz, nx, ny, nz, ix, iy, iz, ms, valid = job

                f.write(f"{px} {py} {valid} {ix0} {iy0} {iz0} {sx} {sy} {sz} {nx} {ny} {nz} {ix} {iy} {iz} {ms}\n")

    print(f"[OK] Wrote scene: {voxels_mem} (for scene_loader_if -> voxel_ram)")
    print(f"[OK] Wrote jobs : {jobs_path} (for ray_job_if)")
    print(f"[OK] Wrote cam/light: {out_dir / 'camera_light.json'}")


if __name__ == "__main__":
    main()
