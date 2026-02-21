# ASIC Ray Tracer — Gradio GUI

This adds a simple browser-based GUI so you can:
- drag & drop **one STL**
- move the **light source (x,y,z)**
- click **Render** and see the output image

Under the hood it runs the exact same pipeline you already have:
1) `rays_to_scene.py` (voxelize + generate rays + write `camera_light.json`)
2) `run_simulation.py` (Icarus + cocotb hardware sim + shading → PNG)

---

## Prereqs (same as before)

- **Icarus Verilog 12+** on your PATH (`iverilog -V`)
- **Python 3.10+**

---

## Install

From the repo folder:

```bash
python -m venv venv

# Windows:
.\venv\Scripts\python.exe -m pip install -r requirements.txt

# macOS/Linux:
venv/bin/python -m pip install -r requirements.txt
```

`requirements.txt` now includes **gradio**.

---

## Run the GUI

```bash
# Windows:
.\venv\Scripts\python.exe gui_gradio.py

# macOS/Linux:
venv/bin/python gui_gradio.py
```

Gradio will print a local URL (usually `http://127.0.0.1:7860`). Open it in your browser.

---

## Note about Python versions

If `pip install -r requirements.txt` fails for `gradio` due to wheel availability on your machine (your repo mentions Python 3.13), try using **Python 3.11 or 3.12** for the GUI venv.

---

## Where outputs go

Each render is saved to:

```
ui_runs/<run_id>/
  scene.stl
  render.png
  out/
    voxels_load.txt
    voxels_color.mem
    ray_jobs.txt
    camera_light.json
  sim_build/
```

This makes it easy to inspect artifacts per run.
