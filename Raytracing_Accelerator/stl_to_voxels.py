#!/usr/bin/env python3
"""
stl_to_voxels32.py

Voxelize an STL into a 32x32x32 1-bit occupancy grid:
  bit=1 => solid
  bit=0 => empty/transparent

Outputs:
  - voxels.mem       : 32768 lines of 0/1, line index == RAM address
  - voxels_load.txt  : "addr bit" per line (same ordering)
  - voxel_meta.json  : normalization transform metadata

Address mapping (MUST match your Verilog voxel_addr_map):
  addr = (z << 10) | (y << 5) | x    for 32^3
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Tuple

import numpy as np

try:
    import trimesh
except ImportError as e:
    raise SystemExit(
        "Missing dependency trimesh. Install with:\n"
        "  pip install trimesh numpy\n"
        "Then re-run."
    ) from e


@dataclass(frozen=True)
class NormalizeTransform:
    # Mapping from original STL coords -> normalized coords in [pad, 1-pad]^3:
    # p_norm = p_stl * scale + offset
    scale: float
    offset: np.ndarray  # shape (3,)
    in_bounds_min: np.ndarray  # shape (3,)
    in_bounds_max: np.ndarray  # shape (3,)
    out_bounds_min: np.ndarray  # shape (3,)
    out_bounds_max: np.ndarray  # shape (3,)


def load_mesh(stl_path: Path) -> "trimesh.Trimesh":
    mesh = trimesh.load_mesh(stl_path, force="mesh")
    if not isinstance(mesh, trimesh.Trimesh):
        raise ValueError(f"Expected a Trimesh, got {type(mesh)} from {stl_path}")

    # Basic cleanup that often helps STL inputs
    mesh.remove_duplicate_faces()
    mesh.remove_degenerate_faces()
    mesh.remove_unreferenced_vertices()
    mesh.process(validate=True)

    # If watertightness is important, you can check:
    # print("watertight:", mesh.is_watertight)
    return mesh


def normalize_to_unit_cube(mesh: "trimesh.Trimesh", pad: float) -> Tuple["trimesh.Trimesh", NormalizeTransform]:
    """
    Scale+translate the mesh so it fits inside [pad, 1-pad]^3.
    We use uniform scaling based on the mesh's max extent.
    """
    if not (0.0 <= pad < 0.5):
        raise ValueError("pad must be in [0, 0.5)")

    bounds = mesh.bounds  # [[minx,miny,minz],[maxx,maxy,maxz]]
    bmin = bounds[0].astype(np.float64)
    bmax = bounds[1].astype(np.float64)
    size = bmax - bmin
    max_extent = float(np.max(size))
    if max_extent <= 0:
        raise ValueError("Mesh appears to have zero size (degenerate bounds).")

    scale = (1.0 - 2.0 * pad) / max_extent

    # p_norm = (p_stl - bmin) * scale + pad
    offset = (-bmin * scale) + np.array([pad, pad, pad], dtype=np.float64)

    mesh_n = mesh.copy()
    mesh_n.apply_scale(scale)
    mesh_n.apply_translation(offset)

    out_bounds = mesh_n.bounds
    t = NormalizeTransform(
        scale=scale,
        offset=offset,
        in_bounds_min=bmin,
        in_bounds_max=bmax,
        out_bounds_min=out_bounds[0].astype(np.float64),
        out_bounds_max=out_bounds[1].astype(np.float64),
    )
    return mesh_n, t


def voxelize_by_center_contains(mesh_unit: "trimesh.Trimesh", n: int) -> np.ndarray:
    """
    Returns occupancy array occ[x,y,z] bool, size (n,n,n),
    using mesh.contains() at voxel centers.
    """
    # voxel centers in normalized [0,1]^3
    centers_1d = (np.arange(n, dtype=np.float64) + 0.5) / float(n)
    xv, yv, zv = np.meshgrid(centers_1d, centers_1d, centers_1d, indexing="ij")
    pts = np.stack([xv.ravel(), yv.ravel(), zv.ravel()], axis=1)

    inside = mesh_unit.contains(pts)  # bool array len n^3
    occ = inside.reshape((n, n, n))   # occ[x,y,z]
    return occ


def write_voxels_mem(occ: np.ndarray, out_path: Path) -> None:
    """
    Write 32768 lines (for 32^3): each line is '0' or '1'
    Line index corresponds to addr = (z<<10)|(y<<5)|x.
    """
    n = occ.shape[0]
    assert occ.shape == (n, n, n)

    with out_path.open("w", encoding="utf-8") as f:
        for z in range(n):
            for y in range(n):
                for x in range(n):
                    bit = 1 if occ[x, y, z] else 0
                    f.write(f"{bit}\n")


def write_voxels_load_txt(occ: np.ndarray, out_path: Path) -> None:
    """
    Write 'addr bit' per line for debug or a driver that wants explicit addr.
    """
    n = occ.shape[0]
    with out_path.open("w", encoding="utf-8") as f:
        for z in range(n):
            for y in range(n):
                for x in range(n):
                    addr = (z << 10) | (y << 5) | x
                    bit = 1 if occ[x, y, z] else 0
                    f.write(f"{addr} {bit}\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stl", type=Path, required=True, help="Input STL file path")
    ap.add_argument("--n", type=int, default=32, help="Voxel resolution per axis (default: 32)")
    ap.add_argument("--pad", type=float, default=0.01, help="Padding inside unit cube (default: 0.01)")
    ap.add_argument("--out_dir", type=Path, default=Path("."), help="Output directory")
    args = ap.parse_args()

    if args.n != 32:
        raise SystemExit("This project expects n=32 for the ASIC (32x32x32). Set --n 32.")

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    mesh = load_mesh(args.stl)
    mesh_u, tf = normalize_to_unit_cube(mesh, pad=args.pad)
    occ = voxelize_by_center_contains(mesh_u, n=args.n)

    voxels_mem = out_dir / "voxels.mem"
    voxels_load = out_dir / "voxels_load.txt"
    meta_json = out_dir / "voxel_meta.json"

    write_voxels_mem(occ, voxels_mem)
    write_voxels_load_txt(occ, voxels_load)

    meta = {
        "n": int(args.n),
        "bit_meaning": {"0": "empty/transparent", "1": "solid"},
        "address_mapping": "addr = (z<<10) | (y<<5) | x  (for 32^3)",
        "normalize_transform": {
            "scale": tf.scale,
            "offset": tf.offset.tolist(),
            "in_bounds_min": tf.in_bounds_min.tolist(),
            "in_bounds_max": tf.in_bounds_max.tolist(),
            "out_bounds_min": tf.out_bounds_min.tolist(),
            "out_bounds_max": tf.out_bounds_max.tolist(),
        },
        "stats": {
            "solid_voxels": int(np.count_nonzero(occ)),
            "total_voxels": int(occ.size),
        },
    }
    meta_json.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    print(f"Wrote: {voxels_mem}  (one bit per addr, 32768 lines)")
    print(f"Wrote: {voxels_load} (addr bit)")
    print(f"Wrote: {meta_json}   (transform + stats)")


if __name__ == "__main__":
    main()
