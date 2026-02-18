#!/usr/bin/env python3
"""
Color-enabled voxelization script.
Extends stl_to_voxels.py to support RGB565 color extraction from meshes.

NEW FEATURES:
- Extracts color from PLY, OBJ, GLTF files (trimesh supported formats)
- Uses RGB565 (16-bit) color format
- Generates additional color memory files
- Falls back to default colors for STL files (which have no color)
"""

import argparse
import json
import os
import numpy as np
import trimesh

# ============================================================================
# COLOR CONVERSION FUNCTIONS
# ============================================================================

def rgb888_to_rgb565(r, g, b):
    """Convert 8-bit RGB to 16-bit RGB565 format.
    RGB565: RRRRR GGGGGG BBBBB (5-6-5 bits)
    """
    r5 = (r >> 3) & 0x1F  # 5 bits for red
    g6 = (g >> 2) & 0x3F  # 6 bits for green
    b5 = (b >> 3) & 0x1F  # 5 bits for blue
    return (r5 << 11) | (g6 << 5) | b5

def rgb565_to_rgb888(rgb565):
    """Convert 16-bit RGB565 back to 8-bit RGB."""
    r5 = (rgb565 >> 11) & 0x1F
    g6 = (rgb565 >> 5) & 0x3F
    b5 = rgb565 & 0x1F
    # Expand bits: 5->8 by replicating MSBs
    r = (r5 << 3) | (r5 >> 2)
    g = (g6 << 2) | (g6 >> 4)
    b = (b5 << 3) | (b5 >> 2)
    return r, g, b

# ============================================================================
# MESH LOADING & VOXELIZATION
# ============================================================================

def load_mesh(mesh_path):
    """Load mesh from file. Supports STL, PLY, OBJ, GLTF, etc."""
    print(f"Loading mesh from: {mesh_path}")
    mesh = trimesh.load(mesh_path, force='mesh')
    
    print(f"  Vertices: {len(mesh.vertices)}")
    print(f"  Faces: {len(mesh.faces)}")
    print(f"  Bounds: {mesh.bounds}")
    
    # Check for color information
    has_color = False
    if hasattr(mesh, 'visual'):
        if hasattr(mesh.visual, 'vertex_colors'):
            if mesh.visual.vertex_colors is not None and len(mesh.visual.vertex_colors) > 0:
                print(f"  Has vertex colors: {mesh.visual.vertex_colors.shape}")
                has_color = True
        if hasattr(mesh.visual, 'face_colors'):
            if mesh.visual.face_colors is not None and len(mesh.visual.face_colors) > 0:
                print(f"  Has face colors: {mesh.visual.face_colors.shape}")
                has_color = True
    
    if not has_color:
        print("  No color information found (STL files don't support color)")
        print("  Will use default colors based on geometry")
    
    return mesh

def extract_voxel_colors(mesh, voxel_grid, resolution=32):
    """
    Extract colors for each voxel in the grid.
    
    For colored meshes: samples color from nearest surface point
    For non-colored meshes: generates colors based on position/geometry
    
    Returns: 3D array of RGB565 colors (uint16)
    """
    print("Extracting voxel colors...")
    
    colors = np.zeros((resolution, resolution, resolution), dtype=np.uint16)
    
    # Check if mesh has color data
    has_vertex_colors = (hasattr(mesh, 'visual') and 
                        hasattr(mesh.visual, 'vertex_colors') and
                        mesh.visual.vertex_colors is not None and
                        len(mesh.visual.vertex_colors) > 0)
    
    has_face_colors = (hasattr(mesh, 'visual') and 
                      hasattr(mesh.visual, 'face_colors') and
                      mesh.visual.face_colors is not None and
                      len(mesh.visual.face_colors) > 0)
    
    # Get voxel positions from grid
    matrix = voxel_grid.matrix
    pitch = voxel_grid.pitch
    
    # Get transform info
    transform = voxel_grid.transform
    
    # Process each voxel
    color_count = 0
    for x in range(resolution):
        for y in range(resolution):
            for z in range(resolution):
                if matrix[x, y, z]:
                    # Voxel is occupied
                    # Get voxel center in world space
                    voxel_local = np.array([x + 0.5, y + 0.5, z + 0.5]) * pitch
                    voxel_world = transform[:3, :3] @ voxel_local + transform[:3, 3]
                    
                    if has_face_colors or has_vertex_colors:
                        try:
                            # Sample color from mesh
                            closest_point, distance, face_idx = mesh.nearest.on_surface([voxel_world])
                            
                            if has_face_colors and face_idx[0] < len(mesh.visual.face_colors):
                                # Use face color
                                rgba = mesh.visual.face_colors[face_idx[0]]
                                colors[x, y, z] = rgb888_to_rgb565(rgba[0], rgba[1], rgba[2])
                                color_count += 1
                            
                            elif has_vertex_colors:
                                # Interpolate vertex colors
                                face = mesh.faces[face_idx[0]]
                                v_colors = mesh.visual.vertex_colors[face[:3]]
                                avg_color = np.mean(v_colors[:, :3], axis=0).astype(np.uint8)
                                colors[x, y, z] = rgb888_to_rgb565(avg_color[0], avg_color[1], avg_color[2])
                                color_count += 1
                        except:
                            # Fallback to height-based color
                            height_ratio = z / resolution
                            r = int(80 + height_ratio * 120)
                            g = int(150 + height_ratio * 80)
                            b = int(180 + height_ratio * 50)
                            colors[x, y, z] = rgb888_to_rgb565(r, g, b)
                    
                    else:
                        # Generate color based on height (z-position)
                        # This gives a nice gradient effect for STL files
                        height_ratio = z / resolution
                        
                        # Minecraft ore-like colors: blue-green gradient
                        r = int(80 + height_ratio * 120)
                        g = int(150 + height_ratio * 80)
                        b = int(180 + height_ratio * 50)
                        
                        colors[x, y, z] = rgb888_to_rgb565(r, g, b)
    
    if has_face_colors or has_vertex_colors:
        print(f"  Extracted {color_count} voxel colors from mesh")
    else:
        print(f"  Generated gradient colors for {np.sum(matrix)} voxels")
    
    return colors

def voxelize_mesh_with_colors(mesh, resolution=32):
    """
    Voxelize mesh and extract colors.
    
    Returns:
        occupancy: bool array (resolution^3)
        colors: RGB565 uint16 array (resolution^3)
    """
    print(f"\nVoxelizing to {resolution}x{resolution}x{resolution}...")
    
    # Calculate pitch from mesh bounds
    bounds = mesh.bounds
    size = bounds[1] - bounds[0]
    pitch = max(size) / resolution
    
    # Voxelize
    voxel_grid = mesh.voxelized(pitch=pitch, max_iter=100)
    matrix = voxel_grid.matrix
    
    # Resize if needed
    if matrix.shape != (resolution, resolution, resolution):
        print(f"  Resizing from {matrix.shape} to ({resolution}, {resolution}, {resolution})")
        from scipy.ndimage import zoom
        scale = np.array([resolution / matrix.shape[i] for i in range(3)])
        matrix = zoom(matrix.astype(float), scale, order=0) > 0.5
    
    print(f"  Occupied voxels: {np.sum(matrix)} / {resolution**3}")
    
    # Extract colors
    colors = extract_voxel_colors(mesh, voxel_grid, resolution)
    
    return matrix, colors

# ============================================================================
# DOWNSAMPLING WITH SCENE ELEMENTS
# ============================================================================

def create_scene_with_colors(occ_full, colors_full):
    """
    Create 32x32x32 scene with:
    - 16x16x16 downsampled model at (3-18, 3-18, 1-16)
    - Floor at z=0 (brown)
    - Walls at x=0, y=0 (gray)
    """
    result_occ = np.zeros((32, 32, 32), dtype=bool)
    result_colors = np.zeros((32, 32, 32), dtype=np.uint16)
    
    # Downsample model (every 2nd voxel)
    downsampled_occ = occ_full[::2, ::2, ::2]
    downsampled_colors = colors_full[::2, ::2, ::2]
    
    # Place model at offset (3-18, 3-18, 1-16)
    # Override model colors to gray
    model_gray = rgb888_to_rgb565(128, 128, 128)  # Gray for model
    result_occ[3:19, 3:19, 1:17] = downsampled_occ
    result_colors[3:19, 3:19, 1:17] = model_gray  # Use gray instead of extracted colors
    
    # Colors for scene elements
    floor_color = rgb888_to_rgb565(0, 180, 0)      # Green floor
    wall_color = rgb888_to_rgb565(30, 144, 255)    # Blue walls
    
    # Floor at z=0
    result_occ[:, :, 0] = True
    result_colors[:, :, 0] = floor_color
    
    # Walls
    result_occ[0, :, :] = True
    result_colors[0, :, :] = wall_color
    result_occ[:, 0, :] = True
    result_colors[:, 0, :] = wall_color
    
    print(f"Created scene with floor and walls")
    
    return result_occ, result_colors

# ============================================================================
# OUTPUT FILE GENERATION
# ============================================================================

def write_color_memory_files(occ, colors, output_dir):
    """
    Write voxel data with color to memory files.
    
    Files generated:
    - voxels.mem: 1 bit occupancy per line (backward compatible)
    - voxels_color.mem: 16-bit RGB565 color per line (hex)
    - voxels_combined.mem: 17 bits (1 occ + 16 color) per line (hex)
    - voxels_load.txt: addr bit color tuples
    - voxel_meta.json: metadata including color info
    """
    os.makedirs(output_dir, exist_ok=True)
    
    depth = 32
    total_voxels = depth ** 3
    
    print(f"\nWriting color-enabled memory files to {output_dir}/...")
    
    # 1. voxels.mem (backward compatible - occupancy only)
    mem_file = os.path.join(output_dir, 'voxels.mem')
    with open(mem_file, 'w') as f:
        for z in range(depth):
            for y in range(depth):
                for x in range(depth):
                    bit = '1' if occ[x, y, z] else '0'
                    f.write(f"{bit}\n")
    print(f"  ✓ {mem_file} (32,768 bits - occupancy)")
    
    # 2. voxels_color.mem (RGB565 colors)
    color_file = os.path.join(output_dir, 'voxels_color.mem')
    with open(color_file, 'w') as f:
        for z in range(depth):
            for y in range(depth):
                for x in range(depth):
                    color = colors[x, y, z]
                    f.write(f"{color:04x}\n")  # 4-digit hex
    print(f"  ✓ {color_file} (32,768 x 16-bit colors)")
    
    # 3. voxels_combined.mem (occupancy + color in one file)
    combined_file = os.path.join(output_dir, 'voxels_combined.mem')
    with open(combined_file, 'w') as f:
        for z in range(depth):
            for y in range(depth):
                for x in range(depth):
                    occ_bit = 1 if occ[x, y, z] else 0
                    color = int(colors[x, y, z])  # Convert to int to avoid overflow
                    combined = (occ_bit << 16) | color  # 17 bits total
                    f.write(f"{combined:05x}\n")  # 5-digit hex
    print(f"  ✓ {combined_file} (32,768 x 17-bit entries)")
    
    # 4. voxels_load.txt (human-readable with colors)
    load_file = os.path.join(output_dir, 'voxels_load.txt')
    occupied_count = 0
    with open(load_file, 'w') as f:
        f.write("// Voxel Memory with Color Data\n")
        f.write("// Format: address(decimal) occupancy color(RGB565_hex) R G B\n")
        f.write("// Address = (z<<10) | (y<<5) | x\n\n")
        
        for z in range(depth):
            for y in range(depth):
                for x in range(depth):
                    if occ[x, y, z]:
                        addr = (z << 10) | (y << 5) | x
                        color = colors[x, y, z]
                        r, g, b = rgb565_to_rgb888(color)
                        f.write(f"{addr:5d} 1 0x{color:04x}  RGB({r:3d},{g:3d},{b:3d})\n")
                        occupied_count += 1
    print(f"  ✓ {load_file} ({occupied_count} occupied voxels)")
    
    # 5. Metadata
    unique_colors = len(np.unique(colors[occ]))
    
    meta_file = os.path.join(output_dir, 'voxel_meta.json')
    meta = {
        'resolution': depth,
        'total_voxels': total_voxels,
        'occupied_voxels': int(np.sum(occ)),
        'empty_voxels': int(total_voxels - np.sum(occ)),
        'occupancy_ratio': float(np.sum(occ)) / total_voxels,
        'color_format': 'RGB565',
        'color_bits': 16,
        'unique_colors': int(unique_colors),
        'address_format': '(z<<10) | (y<<5) | x',
        'memory_layout': {
            'occupancy_only': '1 bit per voxel = 4,096 bytes',
            'color_only': '16 bits per voxel = 65,536 bytes',
            'combined': '17 bits per voxel = 69,632 bytes'
        }
    }
    
    with open(meta_file, 'w') as f:
        json.dump(meta, f, indent=2)
    print(f"  ✓ {meta_file}")
    print(f"\nColor Statistics:")
    print(f"  Unique colors: {unique_colors}")
    print(f"  Format: RGB565 (16-bit)")
    
# ============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS FOR rays_to_scene.py
# ============================================================================

class NormalizeTransform:
    """Simple container for normalization transform data"""
    def __init__(self, scale, offset, in_bounds_min, in_bounds_max):
        self.scale = scale
        self.offset = offset
        self.in_bounds_min = in_bounds_min
        self.in_bounds_max = in_bounds_max

def normalize_to_unit_cube(mesh, pad=0.01):
    """
    Normalize mesh to fit in [0,1]^3 with padding.
    Returns (normalized_mesh, transform_info)
    """
    bounds = mesh.bounds
    in_bounds_min = bounds[0]
    in_bounds_max = bounds[1]
    
    size = in_bounds_max - in_bounds_min
    max_size = max(size)
    scale = (1.0 - 2*pad) / max_size
    
    center = (in_bounds_min + in_bounds_max) / 2
    offset = np.array([0.5, 0.5, 0.5]) - center * scale
    
    # Apply transformation
    normalized_mesh = mesh.copy()
    normalized_mesh.apply_scale(scale)
    normalized_mesh.apply_translation(offset)
    
    tf = NormalizeTransform(scale, offset, in_bounds_min, in_bounds_max)
    return normalized_mesh, tf

def voxelize_by_center_contains(mesh, n=32):
    """
    Voxelize mesh using center-contains method.
    Returns bool array (n, n, n)
    """
    pitch = 1.0 / n
    voxel_grid = mesh.voxelized(pitch=pitch, max_iter=100)
    matrix = voxel_grid.matrix
    
    # Resize if needed
    if matrix.shape != (n, n, n):
        from scipy.ndimage import zoom
        scale = np.array([n / matrix.shape[i] for i in range(3)])
        matrix = zoom(matrix.astype(float), scale, order=0) > 0.5
    
    return matrix

def create_downsampled_with_walls(occ_full):
    """
    Create 32x32x32 scene with downsampled 16x16x16 model, floor, and walls.
    Compatible with non-color version.
    """
    result = np.zeros((32, 32, 32), dtype=bool)
    
    # Downsample (every 2nd voxel)
    downsampled = occ_full[::2, ::2, ::2]
    
    # Place at (3-18, 3-18, 1-16)
    result[3:19, 3:19, 1:17] = downsampled
    
    # Floor at z=0
    result[:, :, 0] = True
    
    # Walls at x=0, y=0
    result[0, :, :] = True
    result[:, 0, :] = True
    
    return result

def write_voxels_mem(occ, filepath):
    """
    Write occupancy array to .mem file (one bit per line).
    Compatible with non-color version.
    """
    depth = 32
    with open(filepath, 'w') as f:
        for z in range(depth):
            for y in range(depth):
                for x in range(depth):
                    bit = '1' if occ[x, y, z] else '0'
                    f.write(f"{bit}\n")

def write_voxels_load_txt(occ, filepath):
    """
    Write occupancy array to load.txt file (address + bit format).
    Compatible with non-color version.
    """
    depth = 32
    with open(filepath, 'w') as f:
        f.write("// Voxel Memory Load File\n")
        f.write("// Format: address(decimal) bit\n")
        f.write("// Address = (z<<10) | (y<<5) | x\n\n")
        
        for z in range(depth):
            for y in range(depth):
                for x in range(depth):
                    if occ[x, y, z]:
                        addr = (z << 10) | (y << 5) | x
                        f.write(f"{addr:5d} 1\n")

# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Voxelize mesh with color support')
    parser.add_argument('--mesh', required=True, help='Input mesh file (STL, PLY, OBJ, GLTF, etc.)')
    parser.add_argument('--output', default='test_output', help='Output directory')
    parser.add_argument('--resolution', type=int, default=32, help='Voxel grid resolution')
    parser.add_argument('--downsample', action='store_true', help='Apply downsampling with scene')
    
    args = parser.parse_args()
    
    # Load mesh
    mesh = load_mesh(args.mesh)
    
    # Voxelize with colors
    occ, colors = voxelize_mesh_with_colors(mesh, args.resolution)
    
    # Apply scene downsampling if requested
    if args.downsample:
        print("\nApplying scene generation...")
        occ, colors = create_scene_with_colors(occ, colors)
    
    # Write output files
    write_color_memory_files(occ, colors, args.output)
    
    print("\n✓ Color voxelization complete!")
    print(f"\nOutput files in {args.output}/:")
    print("  - voxels.mem (occupancy - backward compatible)")
    print("  - voxels_color.mem (RGB565 colors)")
    print("  - voxels_combined.mem (occupancy + color)")
    print("  - voxels_load.txt (human-readable)")
    print("  - voxel_meta.json (metadata)")

if __name__ == '__main__':
    main()
