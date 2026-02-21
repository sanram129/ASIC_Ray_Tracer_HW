# ASIC Ray Tracer — How to Run

## Demo GUI (recommended)

If you just want to upload an STL, move the light, and render from your browser, use the Gradio GUI:

- Instructions: **HOW_TO_RUN_GUI.md**
- Launch: `python gui_gradio.py` (inside your venv)

## Prerequisites

- **Icarus Verilog 12** on your `PATH` (`iverilog -V` should work)
- **Python 3.10+** installed
- A virtual environment at `./venv/` with all packages installed (see setup below)

---

## One-Time Setup

Run once to create the virtual environment and install dependencies:

### Windows (PowerShell)

From the repo folder (the one containing `rays_to_scene.py`):

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

### macOS/Linux (bash)

```bash
python3 -m venv venv
./venv/bin/python -m pip install -r requirements.txt
```

---

## Every Time You Run

### Step 1 — Generate the scene (camera, rays, voxels)

#### Windows (PowerShell)

```powershell
.\venv\Scripts\python.exe rays_to_scene.py --stl Minecraft_ore_hollow.stl --out_dir out --w 128 --h 128
```

#### macOS/Linux (bash)

```bash
./venv/bin/python rays_to_scene.py --stl Minecraft_ore_hollow.stl --out_dir out --w 128 --h 128
```

**Options:**

| Flag | Description | Default |
|------|-------------|---------|
| `--stl` | Input STL file | *(required)* |
| `--out_dir` | Output folder for scene data | `out` |
| `--w` / `--h` | Image width / height in pixels (= rays) | `64` |
| `--fov` | Vertical field of view in degrees | `55.0` |
| `--max_steps` | Max DDA steps per ray sent to ASIC | `512` |

Outputs written to `out/`:
- `voxels_load.txt` — voxel occupancy for hardware RAM
- `voxels_color.mem` — per-voxel RGB565 colours
- `ray_jobs.txt` — one DDA job per pixel
- `camera_light.json` — camera + **light position** (see below)

---

### Step 2 — Run the ASIC hardware simulation + render

#### Windows (PowerShell)

```powershell
.\venv\Scripts\python.exe run_simulation.py `
    --voxel-file out/voxels_load.txt `
    --color-file out/voxels_color.mem `
    --ray-file   out/ray_jobs.txt `
    --output     minecraft_render.png
```

#### macOS/Linux (bash)

```bash
./venv/bin/python run_simulation.py \
    --voxel-file out/voxels_load.txt \
    --color-file out/voxels_color.mem \
    --ray-file   out/ray_jobs.txt \
    --output     minecraft_render.png
```

This will:
1. Compile all 11 SystemVerilog ASIC files with Icarus Verilog
2. Run the cocotb simulation — each ray is traced through the real hardware DDA pipeline
3. Apply Lambertian shading using the face normals returned by the ASIC
4. Save the rendered image to `minecraft_render.png`

---

## Viewing the Output

### Windows (PowerShell)

```powershell
Start-Process .\minecraft_render.png
```

### macOS

```bash
open minecraft_render.png
```

### Linux

```bash
xdg-open minecraft_render.png
```

---

## Changing the Light Position

You can either pass a flag **or** edit the constant.

### Option A (recommended): CLI flag

```powershell
.\venv\Scripts\python.exe rays_to_scene.py --stl Minecraft_ore_hollow.stl --out_dir out --w 128 --h 128 --light 16 60 5
```

### Option B: edit the constant

Edit **one line** in `rays_to_scene.py`:

```python
# rays_to_scene.py — line ~40
LIGHT_POS = np.array([16.0, 60.0, 5.0], dtype=np.float64)  # [X, Y, Z] in voxel world coords [0,32]
```

Then re-run **both** steps above. The light position is written into `out/camera_light.json` by Step 1 and automatically read by the simulator in Step 2.

---

## Changing the Camera Angle

Edit `choose_camera_and_light()` in `rays_to_scene.py`. The current camera is top-down (directly above the block looking straight down). Then re-run both steps.

---

## Quick Reference — Full Run (copy-paste)

```powershell
# Step 1: generate scene
.\venv\Scripts\python.exe rays_to_scene.py --stl Minecraft_ore_hollow.stl --out_dir out --w 128 --h 128

# Step 2: run hardware simulation + render
.\venv\Scripts\python.exe run_simulation.py --voxel-file out/voxels_load.txt --color-file out/voxels_color.mem --ray-file out/ray_jobs.txt --output minecraft_render.png

# View result
Start-Process minecraft_render.png
```
