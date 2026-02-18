#!/usr/bin/env python3
"""
Color-Enabled Voxel Memory Viewer
Visualizes voxel memory with RGB565 color support using ANSI terminal colors
"""

import argparse
import os
import numpy as np

# ============================================================================
# COLOR CONVERSION
# ============================================================================

def rgb565_to_rgb888(rgb565):
    """Convert 16-bit RGB565 to 8-bit RGB."""
    r5 = (rgb565 >> 11) & 0x1F
    g6 = (rgb565 >> 5) & 0x3F
    b5 = rgb565 & 0x1F
    r = (r5 << 3) | (r5 >> 2)
    g = (g6 << 2) | (g6 >> 4)
    b = (b5 << 3) | (b5 >> 2)
    return r, g, b

def ansi_color(r, g, b, text='█'):
    """Return ANSI-colored text for terminal display."""
    return f"\033[38;2;{r};{g};{b}m{text}\033[0m"

def get_colored_block(rgb565):
    """Get ANSI-colored block for a voxel color."""
    if rgb565 == 0:
        return '·'  # Empty
    r, g, b = rgb565_to_rgb888(rgb565)
    return ansi_color(r, g, b, '█')

# ============================================================================
# VOXEL MEMORY SIMULATOR
# ============================================================================

class ColorVoxelMemory:
    """Simulates voxel RAM with color support."""
    
    def __init__(self, depth=32):
        self.depth = depth
        self.total = depth ** 3
        self.occupancy = np.zeros(self.total, dtype=np.uint8)
        self.colors = np.zeros(self.total, dtype=np.uint16)
        self.has_colors = False
    
    def xyz_to_addr(self, x, y, z):
        """Convert (x, y, z) to linear address."""
        return (z << 10) | (y << 5) | x
    
    def addr_to_xyz(self, addr):
        """Convert linear address to (x, y, z)."""
        x = addr & 0x1F
        y = (addr >> 5) & 0x1F
        z = (addr >> 10) & 0x1F
        return x, y, z
    
    def load_files(self, occ_file, color_file=None):
        """Load occupancy and optional color data."""
        print(f"Loading occupancy from: {occ_file}")
        
        with open(occ_file, 'r') as f:
            lines = f.readlines()
        
        for addr, line in enumerate(lines):
            if addr >= self.total:
                break
            self.occupancy[addr] = int(line.strip())
        
        occupied = np.sum(self.occupancy)
        print(f"  Loaded {len(lines)} voxels")
        print(f"  Occupied: {occupied} ({100*occupied/self.total:.1f}%)")
        
        # Try to load colors
        if color_file is None:
            color_file = occ_file.replace('voxels.mem', 'voxels_color.mem')
        
        if os.path.exists(color_file):
            print(f"\nLoading colors from: {color_file}")
            with open(color_file, 'r') as f:
                color_lines = f.readlines()
            
            for addr, line in enumerate(color_lines):
                if addr >= self.total:
                    break
                self.colors[addr] = int(line.strip(), 16)
            
            self.has_colors = True
            unique = len(np.unique(self.colors[self.occupancy == 1]))
            print(f"  Loaded {len(color_lines)} colors")
            print(f"  Unique colors: {unique}")
        else:
            print(f"\nNo color file found at: {color_file}")
            print("  Visualization will use default characters")
    
    def get_voxel(self, x, y, z):
        """Get voxel data at (x, y, z)."""
        addr = self.xyz_to_addr(x, y, z)
        return self.occupancy[addr], self.colors[addr]
    
    def dump_slice(self, z, use_colors=True):
        """Return string representation of a Z-slice."""
        lines = []
        lines.append(f"\n{'='*80}")
        lines.append(f"Z-LAYER {z:2d} (height = {z})".center(80))
        lines.append(f"{'='*80}")
        
        # Column header
        lines.append("     " + "0   4   8  12  16  20  24  28")
        lines.append("    " + "─"*64)
        
        solid_count = 0
        for y in range(self.depth):
            row = f"{y:2d} │"
            for x in range(self.depth):
                occ, color = self.get_voxel(x, y, z)
                if occ:
                    if use_colors and self.has_colors and color > 0:
                        char = get_colored_block(color)
                    else:
                        char = '█'
                    solid_count += 1
                else:
                    char = '·'
                row += char + char
            row += "│"
            lines.append(row)
        
        lines.append("    " + "─"*64)
        pct = 100 * solid_count / (self.depth ** 2)
        lines.append(f"Solid: {solid_count}/{self.depth**2} ({pct:.1f}%)".rjust(80))
        
        return '\n'.join(lines)
    
    def dump_all_slices(self, output_file, use_colors=True):
        """Write all Z-slices to file."""
        print(f"\nGenerating visualization...")
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("VOXEL MEMORY - 3D COLOR VISUALIZATION\n")
            f.write("="*80 + "\n")
            f.write(f"Grid: {self.depth}x{self.depth}x{self.depth}\n")
            f.write(f"Address: (z<<10) | (y<<5) | x\n")
            
            if use_colors and self.has_colors:
                f.write("Colors: RGB565 ANSI terminal colors\n")
            else:
                f.write("Display: █ = solid, · = empty\n")
            
            f.write("="*80 + "\n")
            
            for z in range(self.depth):
                f.write(self.dump_slice(z, use_colors))
                f.write("\n")
        
        print(f"  ✓ Written to: {output_file}")
    
    def dump_statistics(self, output_file):
        """Write statistics to file."""
        print(f"Generating statistics...")
        
        occupied = np.sum(self.occupancy)
        empty = self.total - occupied
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("VOXEL MEMORY STATISTICS\n")
            f.write("="*60 + "\n\n")
            
            f.write(f"Grid size:        {self.depth} x {self.depth} x {self.depth}\n")
            f.write(f"Total voxels:     {self.total:,}\n")
            f.write(f"Occupied voxels:  {occupied:,} ({100*occupied/self.total:.2f}%)\n")
            f.write(f"Empty voxels:     {empty:,} ({100*empty/self.total:.2f}%)\n")
            
            if self.has_colors:
                occupied_colors = self.colors[self.occupancy == 1]
                unique_colors = len(np.unique(occupied_colors))
                
                f.write(f"\nCOLOR INFORMATION\n")
                f.write(f"Format:           RGB565 (16-bit)\n")
                f.write(f"Unique colors:    {unique_colors}\n")
                
                # Color histogram
                color_counts = {}
                for c in occupied_colors:
                    color_counts[c] = color_counts.get(c, 0) + 1
                
                f.write(f"\nTop 15 Most Common Colors:\n")
                f.write("-"*60 + "\n")
                
                sorted_colors = sorted(color_counts.items(), key=lambda x: x[1], reverse=True)
                for i, (color, count) in enumerate(sorted_colors[:15]):
                    r, g, b = rgb565_to_rgb888(color)
                    pct = 100 * count / occupied
                    f.write(f"{i+1:2d}. RGB({r:3d},{g:3d},{b:3d}) [0x{color:04x}]: ")
                    f.write(f"{count:5d} voxels ({pct:5.1f}%)\n")
                
                f.write(f"\nMEMORY USAGE\n")
                f.write(f"Occupancy only:   {self.total // 8:,} bytes (1 bit/voxel)\n")
                f.write(f"Color only:       {self.total * 2:,} bytes (16 bits/voxel)\n")
                f.write(f"Combined:         {(self.total * 17) // 8:,} bytes (17 bits/voxel)\n")
            else:
                f.write(f"\nNo color data available\n")
        
        print(f"  ✓ Written to: {output_file}")

# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='View voxel memory with color')
    parser.add_argument('voxel_file', help='Path to voxels.mem')
    parser.add_argument('--color-file', help='Path to voxels_color.mem (auto-detected if not specified)')
    parser.add_argument('--output', default='sim_output_color', help='Output directory')
    parser.add_argument('--no-color', action='store_true', help='Disable ANSI colors')
    
    args = parser.parse_args()
    
    # Create output directory
    os.makedirs(args.output, exist_ok=True)
    
    # Load memory
    memory = ColorVoxelMemory(depth=32)
    memory.load_files(args.voxel_file, args.color_file)
    
    # Generate visualizations
    use_colors = (not args.no_color) and memory.has_colors
    
    slice_file = os.path.join(args.output, 'memory_3d_slices_color.txt')
    memory.dump_all_slices(slice_file, use_colors)
    
    stats_file = os.path.join(args.output, 'memory_stats_color.txt')
    memory.dump_statistics(stats_file)
    
    print(f"\n✓ Visualization complete!")
    print(f"\nOutput files in {args.output}/:")
    print(f"  - memory_3d_slices_color.txt (3D visualization)")
    print(f"  - memory_stats_color.txt (statistics)")
    
    if use_colors:
        print(f"\n💡 View with ANSI colors:")
        print(f"   cat {slice_file} | head -100")

if __name__ == '__main__':
    main()
