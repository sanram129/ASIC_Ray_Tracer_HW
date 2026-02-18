#!/usr/bin/env python3
"""
Generate test data for raytracing accelerator testbench
Creates voxels_load.txt and ray_jobs.txt files for testing
"""

import argparse
import random
import sys


def generate_simple_voxels(filename="voxels_load.txt", pattern="cube", size=32):
    """
    Generate a simple voxel pattern for testing
    
    Args:
        filename: Output filename
        pattern: Pattern type - "cube", "sphere", "random", "hollow_cube", "checkerboard"
        size: Grid size (default 32 for 32x32x32)
    """
    print(f"Generating voxel pattern: {pattern}")
    
    with open(filename, 'w') as f:
        voxels_written = 0
        
        if pattern == "cube":
            # Solid cube in center (8x8x8)
            for z in range(12, 20):
                for y in range(12, 20):
                    for x in range(12, 20):
                        addr = (z << 10) | (y << 5) | x
                        f.write(f"{addr} 1\n")
                        voxels_written += 1
        
        elif pattern == "hollow_cube":
            # Hollow cube shell
            for z in range(8, 24):
                for y in range(8, 24):
                    for x in range(8, 24):
                        # Only write voxels on the surface
                        if (x in [8, 23] or y in [8, 23] or z in [8, 23]):
                            addr = (z << 10) | (y << 5) | x
                            f.write(f"{addr} 1\n")
                            voxels_written += 1
        
        elif pattern == "sphere":
            # Sphere in center
            center = size // 2
            radius = 8
            for z in range(size):
                for y in range(size):
                    for x in range(size):
                        dx = x - center
                        dy = y - center
                        dz = z - center
                        if (dx*dx + dy*dy + dz*dz) <= (radius * radius):
                            addr = (z << 10) | (y << 5) | x
                            f.write(f"{addr} 1\n")
                            voxels_written += 1
        
        elif pattern == "checkerboard":
            # 3D checkerboard pattern
            for z in range(size):
                for y in range(size):
                    for x in range(size):
                        if ((x + y + z) % 2) == 0:
                            addr = (z << 10) | (y << 5) | x
                            f.write(f"{addr} 1\n")
                            voxels_written += 1
        
        elif pattern == "random":
            # Random voxels (50% density)
            for z in range(size):
                for y in range(size):
                    for x in range(size):
                        if random.random() < 0.5:
                            addr = (z << 10) | (y << 5) | x
                            f.write(f"{addr} 1\n")
                            voxels_written += 1
        
        elif pattern == "all_empty":
            # Write zeros for all addresses (for testing)
            for addr in range(size ** 3):
                f.write(f"{addr} 0\n")
                voxels_written += 1
        
        elif pattern == "all_solid":
            # Write ones for all addresses
            for addr in range(size ** 3):
                f.write(f"{addr} 1\n")
                voxels_written += 1
        
        else:
            print(f"Unknown pattern: {pattern}")
            print("Available patterns: cube, hollow_cube, sphere, checkerboard, random, all_empty, all_solid")
            sys.exit(1)
    
    print(f"[OK] Generated {voxels_written} voxels -> {filename}")
    return voxels_written


def generate_simple_ray_jobs(filename="ray_jobs.txt", image_size=16, num_jobs=256):
    """
    Generate simple ray jobs for testing
    
    Args:
        filename: Output filename
        image_size: Size of the output image (creates image_size x image_size rays)
        num_jobs: Maximum number of jobs to generate (may be less if image_size is small)
    """
    print(f"Generating ray jobs: {image_size}x{image_size} image")
    
    with open(filename, 'w') as f:
        jobs_written = 0
        
        # Generate rays for each pixel in the image
        for py in range(image_size):
            for px in range(image_size):
                # Simple orthographic projection
                # Rays start at edge of grid, shoot inward
                ix0 = 0  # Start at x=0
                iy0 = py % 32  # Map pixel y to voxel y
                iz0 = px % 32  # Map pixel x to voxel z
                
                # Direction: shoot in +x direction
                sx = 1  # Positive x
                sy = 0  # No y movement
                sz = 0  # No z movement
                
                # Fixed point values (24-bit)
                # For simple orthographic, these can be constants
                next_x = 0x010000  # 1.0 in fixed point (16.8 format)
                next_y = 0x000000
                next_z = 0x000000
                
                inc_x = 0x010000  # Step 1.0 in x
                inc_y = 0x000000
                inc_z = 0x000000
                
                max_steps = 32  # Traverse full grid
                
                valid = 1  # All jobs are valid
                
                # Write job line
                # Format: px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps
                f.write(f"{px} {py} {valid} ")
                f.write(f"{ix0} {iy0} {iz0} ")
                f.write(f"{sx} {sy} {sz} ")
                f.write(f"{next_x} {next_y} {next_z} ")
                f.write(f"{inc_x} {inc_y} {inc_z} ")
                f.write(f"{max_steps}\n")
                
                jobs_written += 1
                
                if jobs_written >= num_jobs:
                    break
            
            if jobs_written >= num_jobs:
                break
    
    print(f"[OK] Generated {jobs_written} ray jobs -> {filename}")
    return jobs_written


def main():
    parser = argparse.ArgumentParser(
        description="Generate test data for raytracing accelerator testbench",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate default test data
  python generate_test_data.py
  
  # Generate specific voxel pattern
  python generate_test_data.py --voxel-pattern hollow_cube
  
  # Generate with custom filenames
  python generate_test_data.py --voxel-out out/voxels.txt --ray-out out/rays.txt
  
  # Generate small dataset for quick testing
  python generate_test_data.py --image-size 8 --num-jobs 64
  
Available voxel patterns:
  cube          - Solid 8x8x8 cube in center
  hollow_cube   - Hollow cube shell
  sphere        - Solid sphere in center
  checkerboard  - 3D checkerboard pattern
  random        - Random 50% density
  all_empty     - All voxels empty
  all_solid     - All voxels solid
        """
    )
    
    parser.add_argument(
        "--voxel-out",
        default="voxels_load.txt",
        help="Output filename for voxels (default: voxels_load.txt)"
    )
    
    parser.add_argument(
        "--ray-out",
        default="ray_jobs.txt",
        help="Output filename for ray jobs (default: ray_jobs.txt)"
    )
    
    parser.add_argument(
        "--voxel-pattern",
        default="cube",
        choices=["cube", "hollow_cube", "sphere", "checkerboard", "random", "all_empty", "all_solid"],
        help="Voxel pattern to generate (default: cube)"
    )
    
    parser.add_argument(
        "--grid-size",
        type=int,
        default=32,
        help="Voxel grid size (default: 32 for 32x32x32)"
    )
    
    parser.add_argument(
        "--image-size",
        type=int,
        default=16,
        help="Output image size in pixels (default: 16 for 16x16)"
    )
    
    parser.add_argument(
        "--num-jobs",
        type=int,
        default=256,
        help="Maximum number of ray jobs to generate (default: 256)"
    )
    
    parser.add_argument(
        "--seed",
        type=int,
        help="Random seed for reproducible random patterns"
    )
    
    args = parser.parse_args()
    
    # Set random seed if provided
    if args.seed is not None:
        random.seed(args.seed)
        print(f"Using random seed: {args.seed}")
    
    print("=" * 60)
    print("Generating Test Data for Raytracing Accelerator")
    print("=" * 60)
    
    # Generate voxels
    voxels_count = generate_simple_voxels(
        filename=args.voxel_out,
        pattern=args.voxel_pattern,
        size=args.grid_size
    )
    
    # Generate ray jobs
    jobs_count = generate_simple_ray_jobs(
        filename=args.ray_out,
        image_size=args.image_size,
        num_jobs=args.num_jobs
    )
    
    print("=" * 60)
    print("[OK] Test data generation complete!")
    print(f"  Voxels: {voxels_count} -> {args.voxel_out}")
    print(f"  Jobs:   {jobs_count} -> {args.ray_out}")
    print()
    print("Run tests with:")
    print(f"  make VOXEL_FILE={args.voxel_out} RAY_FILE={args.ray_out}")
    print("=" * 60)


if __name__ == "__main__":
    main()
