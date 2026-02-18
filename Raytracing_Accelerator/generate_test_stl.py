#!/usr/bin/env python3
"""
Generate a simple test STL file for raytracing accelerator testing
Creates a cube that fits nicely in a 32x32x32 voxel grid
"""
import struct
import argparse


def write_stl_binary(filename, triangles):
    """
    Write triangles to a binary STL file
    
    Args:
        filename: Output STL filename
        triangles: List of triangles, each is (normal, v1, v2, v3)
                   where each vector is (x, y, z)
    """
    with open(filename, 'wb') as f:
        # Header (80 bytes)
        header = b'Binary STL generated for raytracing test' + b'\x00' * 39
        f.write(header)
        
        # Number of triangles (uint32)
        f.write(struct.pack('<I', len(triangles)))
        
        # Write each triangle
        for normal, v1, v2, v3 in triangles:
            # Normal vector (3 floats)
            f.write(struct.pack('<fff', *normal))
            # Vertex 1 (3 floats)
            f.write(struct.pack('<fff', *v1))
            # Vertex 2 (3 floats)
            f.write(struct.pack('<fff', *v2))
            # Vertex 3 (3 floats)
            f.write(struct.pack('<fff', *v3))
            # Attribute byte count (uint16)
            f.write(struct.pack('<H', 0))


def generate_cube_stl(filename, center=(16, 16, 16), size=12):
    """
    Generate a cube STL file centered in 32x32x32 grid
    
    Args:
        filename: Output filename
        center: Center point of cube (default: center of 32x32x32 grid)
        size: Size of cube (default: 12 units)
    """
    cx, cy, cz = center
    half = size / 2
    
    # Define 8 vertices of cube
    vertices = [
        (cx - half, cy - half, cz - half),  # 0: back-bottom-left
        (cx + half, cy - half, cz - half),  # 1: back-bottom-right
        (cx + half, cy + half, cz - half),  # 2: back-top-right
        (cx - half, cy + half, cz - half),  # 3: back-top-left
        (cx - half, cy - half, cz + half),  # 4: front-bottom-left
        (cx + half, cy - half, cz + half),  # 5: front-bottom-right
        (cx + half, cy + half, cz + half),  # 6: front-top-right
        (cx - half, cy + half, cz + half),  # 7: front-top-left
    ]
    
    # Define 12 triangles (2 per face, 6 faces)
    triangles = []
    
    # Back face (z-)
    triangles.append(((0, 0, -1), vertices[0], vertices[1], vertices[2]))
    triangles.append(((0, 0, -1), vertices[0], vertices[2], vertices[3]))
    
    # Front face (z+)
    triangles.append(((0, 0, 1), vertices[4], vertices[6], vertices[5]))
    triangles.append(((0, 0, 1), vertices[4], vertices[7], vertices[6]))
    
    # Left face (x-)
    triangles.append(((-1, 0, 0), vertices[0], vertices[3], vertices[7]))
    triangles.append(((-1, 0, 0), vertices[0], vertices[7], vertices[4]))
    
    # Right face (x+)
    triangles.append(((1, 0, 0), vertices[1], vertices[5], vertices[6]))
    triangles.append(((1, 0, 0), vertices[1], vertices[6], vertices[2]))
    
    # Bottom face (y-)
    triangles.append(((0, -1, 0), vertices[0], vertices[4], vertices[5]))
    triangles.append(((0, -1, 0), vertices[0], vertices[5], vertices[1]))
    
    # Top face (y+)
    triangles.append(((0, 1, 0), vertices[3], vertices[2], vertices[6]))
    triangles.append(((0, 1, 0), vertices[3], vertices[6], vertices[7]))
    
    write_stl_binary(filename, triangles)
    print(f"[OK] Generated cube STL: {filename}")
    print(f"  Center: {center}")
    print(f"  Size: {size} units")
    print(f"  Triangles: {len(triangles)}")
    print(f"  Bounds: ({cx-half:.1f}, {cy-half:.1f}, {cz-half:.1f}) to ({cx+half:.1f}, {cy+half:.1f}, {cz+half:.1f})")


def generate_sphere_stl(filename, center=(16, 16, 16), radius=8, resolution=16):
    """
    Generate a sphere STL file
    
    Args:
        filename: Output filename
        center: Center point of sphere
        radius: Radius of sphere
        resolution: Number of subdivisions (higher = smoother)
    """
    import math
    
    cx, cy, cz = center
    triangles = []
    
    # Generate sphere using UV sphere algorithm
    for i in range(resolution):
        lat0 = math.pi * (-0.5 + float(i) / resolution)
        z0 = radius * math.sin(lat0)
        zr0 = radius * math.cos(lat0)
        
        lat1 = math.pi * (-0.5 + float(i + 1) / resolution)
        z1 = radius * math.sin(lat1)
        zr1 = radius * math.cos(lat1)
        
        for j in range(resolution):
            lng0 = 2 * math.pi * float(j) / resolution
            x0 = math.cos(lng0)
            y0 = math.sin(lng0)
            
            lng1 = 2 * math.pi * float(j + 1) / resolution
            x1 = math.cos(lng1)
            y1 = math.sin(lng1)
            
            # Define 4 vertices of quad
            v0 = (cx + x0 * zr0, cy + y0 * zr0, cz + z0)
            v1 = (cx + x1 * zr0, cy + y1 * zr0, cz + z0)
            v2 = (cx + x1 * zr1, cy + y1 * zr1, cz + z1)
            v3 = (cx + x0 * zr1, cy + y0 * zr1, cz + z1)
            
            # Calculate normals (for sphere, normal = normalized vertex - center)
            def normalize(v):
                vx, vy, vz = v
                length = math.sqrt(vx**2 + vy**2 + vz**2)
                if length > 0:
                    return (vx/length, vy/length, vz/length)
                return (0, 0, 1)
            
            n0 = normalize((v0[0] - cx, v0[1] - cy, v0[2] - cz))
            n2 = normalize((v2[0] - cx, v2[1] - cy, v2[2] - cz))
            
            # Split quad into 2 triangles
            triangles.append((n0, v0, v1, v2))
            triangles.append((n2, v0, v2, v3))
    
    write_stl_binary(filename, triangles)
    print(f"[OK] Generated sphere STL: {filename}")
    print(f"  Center: {center}")
    print(f"  Radius: {radius} units")
    print(f"  Triangles: {len(triangles)}")


def main():
    parser = argparse.ArgumentParser(description="Generate test STL files for raytracing")
    parser.add_argument('--type', choices=['cube', 'sphere'], default='cube',
                        help='Type of shape to generate')
    parser.add_argument('--output', default='test_model.stl',
                        help='Output STL filename')
    parser.add_argument('--size', type=float, default=12,
                        help='Size/radius of shape')
    parser.add_argument('--resolution', type=int, default=16,
                        help='Resolution for sphere (number of subdivisions)')
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("Generating Test STL File for Raytracing Accelerator")
    print("=" * 60)
    
    if args.type == 'cube':
        generate_cube_stl(args.output, size=args.size)
    elif args.type == 'sphere':
        generate_sphere_stl(args.output, radius=args.size, resolution=args.resolution)
    
    print("=" * 60)
    print("[OK] STL file generation complete!")
    print(f"Use with: python stl_to_voxels.py --input {args.output}")
    print("=" * 60)


if __name__ == "__main__":
    main()
