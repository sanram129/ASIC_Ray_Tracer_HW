"""
run_simulation.py
=================
Windows-compatible cocotb simulation runner.
Bypasses GNU Make entirely and uses cocotb_tools.runner
to compile + simulate the ASIC SystemVerilog files directly.

Usage:
    python run_simulation.py \
        --voxel-file out/voxels_load.txt \
        --color-file out/voxels_color.mem \
        --ray-file   out/ray_jobs.txt \
        --output     minecraft_render.png

All paths are relative to this script's directory.
"""

import argparse
import os
import sys
from pathlib import Path

# ── locate project root (same directory as this script) ──────────────────────
PROJ = Path(__file__).resolve().parent

SV_SOURCES = [
    PROJ / "axis_choose.sv",
    PROJ / "bounds_check.sv",
    PROJ / "voxel_addr_map.sv",
    PROJ / "voxel_ram.sv",
    PROJ / "scene_loader_if.sv",
    PROJ / "step_update.sv",
    PROJ / "step_control_fsm.sv",
    PROJ / "voxel_raytracer_core.sv",
    PROJ / "ray_job_if.sv",
    PROJ / "raytracer_top.sv",
    PROJ / "tb_raytracer_cocotb.sv",
]


def parse_args():
    p = argparse.ArgumentParser(description="Run ASIC ray-tracer cocotb simulation")
    p.add_argument("--voxel-file", default=str(PROJ / "out" / "voxels_load.txt"),
                   help="Path to voxel occupancy file (default: out/voxels_load.txt)")
    p.add_argument("--color-file", default=str(PROJ / "out" / "voxels_color.mem"),
                   help="Path to voxel color memory file (default: out/voxels_color.mem)")
    p.add_argument("--ray-file",   default=str(PROJ / "out" / "ray_jobs.txt"),
                   help="Path to ray jobs file (default: out/ray_jobs.txt)")
    p.add_argument("--output",     default="render.png",
                   help="Output PNG filename (default: render.png)")
    p.add_argument("--build-dir",  default=str(PROJ / "sim_build"),
                   help="Build / compilation directory (default: sim_build)")
    p.add_argument("--waves",      action="store_true",
                   help="Enable VCD waveform dump")
    p.add_argument("--verbose",    action="store_true",
                   help="Verbose compiler/simulator output")
    return p.parse_args()


def main():
    args = parse_args()

    # ── validate input files exist ────────────────────────────────────────────
    for attr, label in [("voxel_file", "VOXEL_FILE"),
                        ("color_file", "COLOR_FILE"),
                        ("ray_file",   "RAY_FILE")]:
        path = getattr(args, attr)
        if not Path(path).exists():
            print(f"ERROR: {label} not found: {path}", file=sys.stderr)
            print("Run rays_to_scene.py first to generate the scene data.", file=sys.stderr)
            sys.exit(1)

    # ── validate SV sources exist ─────────────────────────────────────────────
    for src in SV_SOURCES:
        if not src.exists():
            print(f"ERROR: SV source not found: {src}", file=sys.stderr)
            sys.exit(1)

    # ── import runner (cocotb_tools ships it) ─────────────────────────────────
    try:
        from cocotb_tools.runner import get_runner
    except ImportError:
        print("ERROR: cocotb_tools not installed. Activate the venv and re-run.", file=sys.stderr)
        sys.exit(1)

    print("=" * 60)
    print("ASIC Ray Tracer — cocotb Simulation")
    print("=" * 60)
    print(f"  VOXEL_FILE : {args.voxel_file}")
    print(f"  COLOR_FILE : {args.color_file}")
    print(f"  RAY_FILE   : {args.ray_file}")
    print(f"  OUTPUT_PNG : {args.output}")
    print(f"  BUILD_DIR  : {args.build_dir}")
    print("=" * 60)

    runner = get_runner("icarus")

    # ── Step 1: Compile all SV files with iverilog ────────────────────────────
    print("\n[1/2] Compiling SystemVerilog sources with Icarus Verilog...")
    runner.build(
        verilog_sources=[str(s) for s in SV_SOURCES],
        hdl_toplevel="tb_raytracer_cocotb",
        build_args=["-g2012"],          # SystemVerilog-2012 mode
        build_dir=args.build_dir,
        always=True,                    # always recompile (safe default)
        timescale=("1ns", "1ps"),
        waves=args.waves,
        verbose=args.verbose,
    )
    print("    Compilation complete.")

    # ── Step 2: Run simulation with cocotb test ────────────────────────────────
    print("\n[2/2] Running simulation (test_render_image)...")
    results = runner.test(
        test_module="test_raytracer",
        hdl_toplevel="tb_raytracer_cocotb",
        testcase="test_render_image",
        extra_env={
            "VOXEL_FILE": str(Path(args.voxel_file).resolve()),
            "COLOR_FILE": str(Path(args.color_file).resolve()),
            "RAY_FILE":   str(Path(args.ray_file).resolve()),
            "OUTPUT_PNG": str(Path(args.output).resolve()),
        },
        build_dir=args.build_dir,
        waves=args.waves,
        verbose=args.verbose,
    )

    # ── Report ─────────────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    output_path = Path(args.output).resolve()
    if output_path.exists():
        size_kb = output_path.stat().st_size // 1024
        print(f"SUCCESS: Rendered image saved → {output_path.resolve()}  ({size_kb} KB)")
    else:
        print("WARNING: Simulation finished but output PNG not found.")
        print(f"  Expected: {output_path.resolve()}")
    print("=" * 60)


if __name__ == "__main__":
    main()
