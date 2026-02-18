# Raytracer Pipeline Guide

## Complete Data Flow: STL → ASIC Outputs

### Stage 1: Voxelization (Python)
```bash
python stl_to_voxels_color.py --mesh Minecraft_ore_solid.stl \
       --output test_output_color --downsample
```

**Outputs:**
- `voxels.mem` - 32,768 lines of 0/1 (occupancy)
- `voxels_color.mem` - RGB565 colors (hex)
- `voxels_combined.mem` - 17-bit combined
- `voxels_load.txt` - Human readable
- `voxel_meta.json` - Metadata

**Scene Generated:**
- 16×16×16 gray model at (3-18, 3-18, 1-16)
- Green floor at z=0
- Blue walls at x=0, y=0

---

### Stage 2: Ray Job Generation (Python)
```bash
python rays_to_scene.py --stl Minecraft_ore_solid.stl \
       --out_dir test_output_color --downsample \
       --w 64 --h 64 --fov 55 --max_steps 512
```

**Outputs:**
- `ray_jobs.txt` - One ray per line (64×64 = 4,096 rays)
  - Format: `px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps`
- `camera_light.json` - Camera metadata

---

### Stage 3: SystemVerilog Simulation

**A) Compile:**
```bash
iverilog -g2012 -o raytracer.vvp \
  raytracer_top.sv step_control_fsm.sv ray_job_if.sv \
  voxel_raytracer_core.sv step_update.sv axis_choose.sv \
  bounds_check.sv voxel_addr_map.sv voxel_ram.sv \
  scene_loader_if.sv tb_raytracer_top.sv
```

**B) Run:**
```bash
vvp raytracer.vvp +VOXELS_FILE=test_output_color/voxels.mem \
                  +JOBS_FILE=test_output_color/ray_jobs.txt
```

---

### ASIC Data Flow

```
INPUT: voxels.mem + ray_jobs.txt

1. LOAD SCENE (32,768 voxels)
   load_mode=1, load_valid=1, load_addr, load_data
   → scene_loader_if → voxel_ram

2. FOR EACH RAY (4,096 jobs):
   
   job_valid=1 with parameters:
   - Starting position (ix0, iy0, iz0)
   - Direction signs (sx, sy, sz)
   - Timers (next_x/y/z, inc_x/y/z)
   - Max steps limit
   
   ↓ raytracer_top
   ↓ ray_job_if (latch job)
   ↓ step_control_fsm (execute DDA):
     • Compare timers → choose axis
     • Step to next voxel
     • Read from voxel_ram
     • Check if solid/bounds
     • Repeat until hit or timeout
   
   ray_done=1, outputs:
   - ray_hit (0=miss, 1=hit)
   - ray_timeout (exceeded max steps)
   - hit_voxel_x/y/z (collision coordinates)
   - hit_face_id (0-5: X+/X-/Y+/Y-/Z+/Z-)
   - steps_taken (DDA step count)

OUTPUT: 64×64 image with per-pixel hit data
```

---

## Fixed Issues ✅

1. **rays_to_scene.py import fixed**
   - Changed: `import stl_to_voxels` 
   - To: `import stl_to_voxels_color as stl_to_voxels`

2. **Added compatibility functions to stl_to_voxels_color.py:**
   - `normalize_to_unit_cube()`
   - `voxelize_by_center_contains()`
   - `create_downsampled_with_walls()`
   - `write_voxels_mem()`
   - `write_voxels_load_txt()`

## Pipeline Status: ✅ 100% WORKING

All files are now compatible and the complete pipeline works end-to-end.
