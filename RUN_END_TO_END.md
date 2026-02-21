# Run End-to-End (GUI + ASIC)

This repo renders an image by running your **real SystemVerilog DDA ray-tracer** in an **Icarus Verilog + cocotb** simulation.

There are two ways to drive it:

- **GUI (recommended):** run `gui_gradio.py`, upload 1 STL, click Render.
- **CLI:** run `rays_to_scene.py` (scene prep) then `run_simulation.py` (ASIC sim + PNG).

Everything below uses **relative paths** so it works for anyone who clones the repo.

---

## 1) Prerequisites

- **Icarus Verilog 12+** on PATH:

  Windows PowerShell:

    iverilog -V

- **Python 3.10+**

---

## 2) One-time Python setup (create venv + install deps)

Run these commands from the repo folder (the directory containing `gui_gradio.py`).

### Windows (PowerShell)

    python -m venv venv
    .\venv\Scripts\python.exe -m pip install -r requirements.txt

### macOS/Linux (bash)

    python3 -m venv venv
    ./venv/bin/python -m pip install -r requirements.txt

If `gradio` install fails on your machine, try Python **3.11 or 3.12** for the venv.

---

## 3) Run via the GUI

### Windows

    .\venv\Scripts\python.exe gui_gradio.py

### macOS/Linux

    ./venv/bin/python gui_gradio.py

Open the printed URL (usually `http://127.0.0.1:7860/`).

In the UI:

1) Upload **one** `.stl` (example files in this repo include `Minecraft_ore_hollow.stl`, `sphere.stl`, etc.)
2) Set **Light X/Y/Z**
3) Choose resolution + params
4) Click **Render**

### Where GUI runs are saved

Each click creates a reproducible folder:

    ui_runs/<run_id>/
      scene.stl
      render.png
      out/
        voxels_load.txt
        voxels_color.mem
        ray_jobs.txt
        camera_light.json
      sim_build/

---

## 4) Run via the CLI (same pipeline as the GUI)

The CLI is two steps.

### Step A — Generate the scene (voxels + ray jobs)

Windows:

    .\venv\Scripts\python.exe rays_to_scene.py --stl Minecraft_ore_hollow.stl --out_dir out --w 128 --h 128 --light 10 40 30

macOS/Linux:

    ./venv/bin/python rays_to_scene.py --stl Minecraft_ore_hollow.stl --out_dir out --w 128 --h 128 --light 10 40 30

This writes `out/voxels_load.txt`, `out/voxels_color.mem`, `out/ray_jobs.txt`, and `out/camera_light.json`.

### Step B — Run the ASIC simulation + save PNG

Windows:

    .\venv\Scripts\python.exe run_simulation.py --voxel-file out/voxels_load.txt --color-file out/voxels_color.mem --ray-file out/ray_jobs.txt --output render.png

macOS/Linux:

    ./venv/bin/python run_simulation.py --voxel-file out/voxels_load.txt --color-file out/voxels_color.mem --ray-file out/ray_jobs.txt --output render.png

---

## 5) Troubleshooting

- **GUI opens but Render fails:** open the “Logs” box in the GUI; it shows both subprocess commands and their output.
- **`iverilog` not found:** install Icarus Verilog and reopen your terminal so PATH updates.
- **Python package issues:** delete `venv/` and recreate it, then re-run the install step.
