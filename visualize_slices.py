#!/usr/bin/env python3
"""
visualize_slices.py

Reads the pre-ASIC voxel data (occupancy + color) and renders each
Z-layer as a colored 2D slice, arranged in a grid and saved as a PNG.

Usage:
    python visualize_slices.py [--voxel-file out/voxels.mem]
                               [--color-file out/voxels_color.mem]
                               [--output voxel_slices.png]
                               [--cell-size 16]
                               [--cols 8]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _rgb565_to_rgb888(val: int):
    """Decode a 16-bit RGB565 integer to (R, G, B) uint8 tuple."""
    r5 = (val >> 11) & 0x1F
    g6 = (val >> 5)  & 0x3F
    b5 =  val        & 0x1F
    r = (r5 << 3) | (r5 >> 2)
    g = (g6 << 2) | (g6 >> 4)
    b = (b5 << 3) | (b5 >> 2)
    return (r, g, b)


def load_voxels(voxel_path: Path, color_path: Path, n: int = 32):
    """
    Load occupancy and color arrays from .mem files.

    Returns:
        occ   – bool ndarray shape (N, N, N)  [x, y, z]
        color – uint8 ndarray shape (N, N, N, 3)  [x, y, z, rgb]
    """
    voxel_lines = voxel_path.read_text().splitlines()
    color_lines = color_path.read_text().splitlines()

    total = n * n * n
    assert len(voxel_lines) >= total, f"voxels.mem too short: {len(voxel_lines)} < {total}"
    assert len(color_lines) >= total, f"voxels_color.mem too short: {len(color_lines)} < {total}"

    occ   = np.zeros((n, n, n), dtype=bool)
    color = np.zeros((n, n, n, 3), dtype=np.uint8)

    # Files written in z -> y -> x order
    for z in range(n):
        for y in range(n):
            for x in range(n):
                idx = z * n * n + y * n + x
                occ[x, y, z] = bool(int(voxel_lines[idx].strip()))
                rgb565 = int(color_lines[idx].strip(), 16)
                color[x, y, z] = _rgb565_to_rgb888(rgb565)

    return occ, color


def render_slices(
    occ: np.ndarray,
    color: np.ndarray,
    cell_size: int = 16,
    cols: int = 8,
    bg_color: tuple = (30, 30, 30),
    empty_color: tuple = (255, 255, 255),
    label_color: str = "white",
    border_color: tuple = (100, 100, 100),
) -> Image.Image:
    """
    Render all Y-layers side by side in a grid.

    Each panel is one Y-slice (X horizontal, Z vertical — Z=0 at bottom).
    Occupied voxels are drawn with their assigned color; empty voxels are
    drawn with empty_color.
    """
    n = occ.shape[0]        # grid size (32)
    num_slices = occ.shape[1]  # number of Y layers

    rows = (num_slices + cols - 1) // cols  # ceiling division

    label_h = 14   # pixels reserved for "Y=xx" label above each panel
    pad     = 4    # padding between panels

    panel_w = n * cell_size
    panel_h = n * cell_size

    total_w = cols * (panel_w + pad) + pad
    total_h = rows * (panel_h + label_h + pad) + pad

    canvas = Image.new("RGB", (total_w, total_h), bg_color)
    draw   = ImageDraw.Draw(canvas)

    # Try to load a small font; fall back to default if unavailable
    try:
        font = ImageFont.truetype("arial.ttf", 11)
    except Exception:
        font = ImageFont.load_default()

    for y in range(num_slices):
        col = y % cols
        row = y // cols

        panel_x = pad + col * (panel_w + pad)
        panel_y = pad + row * (panel_h + label_h + pad) + label_h

        # Draw label
        label = f"Y={y:02d}"
        draw.text((panel_x + 2, panel_y - label_h), label, fill=label_color, font=font)

        # Draw each voxel in the slice (X horizontal, Z vertical — Z=0 at bottom)
        for z in range(n):
            for x in range(n):
                px = panel_x + x * cell_size
                # Flip Z so Z=0 is at the bottom of the panel
                py = panel_y + (n - 1 - z) * cell_size

                if occ[x, y, z]:
                    fill = tuple(color[x, y, z].tolist())
                else:
                    fill = empty_color

                draw.rectangle(
                    [px, py, px + cell_size - 1, py + cell_size - 1],
                    fill=fill,
                )

        # Thin border around each panel
        draw.rectangle(
            [panel_x - 1, panel_y - 1, panel_x + panel_w, panel_y + panel_h],
            outline=border_color,
        )

    return canvas


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Visualize voxel grid slice by slice (Y layers)")
    parser.add_argument("--voxel-file", default="out/voxels.mem",       help="Occupancy .mem file (one bit per line)")
    parser.add_argument("--color-file", default="out/voxels_color.mem", help="RGB565 color .mem file (one hex word per line)")
    parser.add_argument("--output",     default="voxel_slices.png",     help="Output PNG filename")
    parser.add_argument("--cell-size",  type=int, default=16,           help="Pixels per voxel cell (default: 16)")
    parser.add_argument("--cols",       type=int, default=8,            help="Number of slice columns in the grid (default: 8)")
    parser.add_argument("--n",          type=int, default=32,           help="Voxel grid dimension (default: 32)")
    args = parser.parse_args()

    voxel_path = Path(args.voxel_file)
    color_path = Path(args.color_file)

    print(f"Loading occupancy : {voxel_path}")
    print(f"Loading colors    : {color_path}")

    occ, color = load_voxels(voxel_path, color_path, n=args.n)

    occupied_total = int(occ.sum())
    print(f"  Grid size       : {args.n}³ = {args.n**3} voxels")
    print(f"  Occupied voxels : {occupied_total} / {args.n**3} ({100*occupied_total/args.n**3:.1f}%)")

    print(f"Rendering {args.n} Y-slices at {args.cell_size}px/voxel, {args.cols} columns ...")
    img = render_slices(occ, color, cell_size=args.cell_size, cols=args.cols)

    out_path = Path(args.output)
    img.save(str(out_path))
    print(f"Saved → {out_path.resolve()}  ({out_path.stat().st_size // 1024} KB)")
    print(f"Image size: {img.width} × {img.height} px")


if __name__ == "__main__":
    main()
