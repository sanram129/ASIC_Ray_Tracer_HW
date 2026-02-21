#!/usr/bin/env python3
"""Gradio front-end for the ASIC Ray Tracer demo.

What it does
------------
1) User uploads ONE STL
2) User adjusts light position (+ a few render params)
3) We run the existing pipeline:
   - rays_to_scene.py  (scene + rays + camera_light.json)
   - run_simulation.py (Icarus+cocotb hardware sim + shaded PNG)
4) The rendered PNG is shown in the UI.

This intentionally keeps your existing scripts as the source of truth.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import textwrap
import uuid
from pathlib import Path
from typing import Tuple

import gradio as gr


PROJ = Path(__file__).resolve().parent
RUNS_DIR = PROJ / "ui_runs"


def _which(cmd: str) -> str | None:
    from shutil import which

    return which(cmd)


def _ensure_prereqs() -> Tuple[bool, str]:
    """Quick preflight checks. Return (ok, message)."""
    if _which("iverilog") is None:
        return (
            False,
            "Icarus Verilog (iverilog) was not found on PATH. Install Icarus Verilog 12+ and reopen your terminal.",
        )
    return (True, "")


def _run(cmd: list[str], cwd: Path) -> Tuple[int, str]:
    """Run a subprocess and capture combined stdout/stderr."""
    p = subprocess.run(
        cmd,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return p.returncode, p.stdout


def render_scene(
    stl_path: str,
    lx: float,
    ly: float,
    lz: float,
    w: int,
    h: int,
    fov: float,
    max_steps: int,
    downsample: bool,
) -> Tuple[str | None, str]:
    """Gradio callback: returns (render_png_path, logs)."""

    ok, msg = _ensure_prereqs()
    if not ok:
        return None, msg

    if not stl_path or not Path(stl_path).exists():
        return None, "Please upload a valid .stl file."

    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    run_id = uuid.uuid4().hex[:10]
    run_dir = RUNS_DIR / run_id
    out_dir = run_dir / "out"
    run_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Copy STL into the run folder for reproducibility.
    stl_src = Path(stl_path)
    stl_dst = run_dir / "scene.stl"
    shutil.copyfile(stl_src, stl_dst)

    logs = []
    logs.append(f"Run ID: {run_id}")
    logs.append(f"STL: {stl_src.name} -> {stl_dst}")
    try:
        lx = float(lx)
        ly = float(ly)
        lz = float(lz)
    except Exception:
        lx, ly, lz = (10.0, 40.0, 30.0)

    logs.append(f"Light: ({lx:.3f}, {ly:.3f}, {lz:.3f})")
    logs.append(f"Resolution: {w} x {h} | FOV: {fov} deg | max_steps: {max_steps} | downsample: {downsample}")
    logs.append("\n=== [1/2] rays_to_scene.py (voxelize + rays) ===")

    cmd1 = [
        sys.executable,
        str(PROJ / "rays_to_scene.py"),
        "--stl",
        str(stl_dst),
        "--out_dir",
        str(out_dir),
        "--w",
        str(int(w)),
        "--h",
        str(int(h)),
        "--fov",
        str(float(fov)),
        "--max_steps",
        str(int(max_steps)),
    ]
    cmd1.extend(["--light", str(float(lx)), str(float(ly)), str(float(lz))])
    if downsample:
        cmd1.append("--downsample")

    rc1, out1 = _run(cmd1, cwd=PROJ)
    logs.append(out1)
    if rc1 != 0:
        logs.append("[ERROR] rays_to_scene.py failed.")
        return None, "\n".join(logs)

    logs.append("\n=== [2/2] run_simulation.py (ASIC sim + shading) ===")
    render_png = run_dir / "render.png"

    cmd2 = [
        sys.executable,
        str(PROJ / "run_simulation.py"),
        "--voxel-file",
        str(out_dir / "voxels_load.txt"),
        "--color-file",
        str(out_dir / "voxels_color.mem"),
        "--ray-file",
        str(out_dir / "ray_jobs.txt"),
        "--output",
        str(render_png),
        "--build-dir",
        str(run_dir / "sim_build"),
    ]

    # Keep the environment clean/explicit.
    env = os.environ.copy()
    env["PYTHONPATH"] = str(PROJ)
    p = subprocess.run(
        cmd2,
        cwd=str(PROJ),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    logs.append(p.stdout)
    if p.returncode != 0:
        logs.append("[ERROR] run_simulation.py failed.")
        return None, "\n".join(logs)

    if not render_png.exists():
        logs.append("[ERROR] Render finished but render.png not found.")
        return None, "\n".join(logs)

    logs.append(f"\n[OK] Rendered -> {render_png}")
    return str(render_png), "\n".join(logs)


def build_ui() -> gr.Blocks:
    intro = textwrap.dedent(
        """
        Upload a single STL, adjust the light position, then click **Render**.

        Notes:
        - This runs your real RTL (Icarus + cocotb) and can take a bit depending on resolution.
        - Each render is saved under `ui_runs/<run_id>/` so you can inspect artifacts.
        """
    ).strip()

    with gr.Blocks(title="ASIC Ray Tracer GUI") as demo:
        gr.Markdown(f"# ASIC Ray Tracer — Demo GUI\n\n{intro}")

        with gr.Row():
            stl = gr.File(
                label="STL file (single)",
                file_types=[".stl"],
                file_count="single",
                type="filepath",
            )

            with gr.Column():
                gr.Markdown("### Light Position (voxel-world coords)")
                lx = gr.Slider(-64, 96, value=10.0, step=1.0, label="Light X")
                ly = gr.Slider(-64, 128, value=40.0, step=1.0, label="Light Y")
                lz = gr.Slider(-64, 96, value=30.0, step=1.0, label="Light Z")

        with gr.Row():
            with gr.Column():
                gr.Markdown("### Render Parameters")
                w = gr.Slider(32, 256, value=128, step=16, label="Width (pixels)")
                h = gr.Slider(32, 256, value=128, step=16, label="Height (pixels)")
                fov = gr.Slider(20, 120, value=55.0, step=1.0, label="Vertical FOV (deg)")
                max_steps = gr.Slider(64, 1024, value=512, step=32, label="Max DDA steps")
                downsample = gr.Checkbox(value=False, label="Downsample scene (16³ + floor/walls)")

                render_btn = gr.Button("Render", variant="primary")

            with gr.Column():
                img = gr.Image(label="Rendered Output", type="filepath")

        logs = gr.Textbox(label="Logs", lines=18, interactive=False)

        render_btn.click(
            fn=render_scene,
            inputs=[stl, lx, ly, lz, w, h, fov, max_steps, downsample],
            outputs=[img, logs],
        )

    return demo


if __name__ == "__main__":
    app = build_ui()
    # queue() prevents UI freezes and supports longer-running renders.
    try:
        app = app.queue(default_concurrency_limit=1)
    except TypeError:
        # Older Gradio versions used concurrency_count.
        app = app.queue(concurrency_count=1)
    app.launch()
