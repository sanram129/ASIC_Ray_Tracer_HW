"""
Cocotb driver for scene_loader_if - loads voxel data into voxel_ram
"""
import cocotb
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb.log import SimLog
import numpy as np


class VoxelLoader:
    """Driver for scene_loader_if to load voxel data into RAM"""
    
    def __init__(self, dut, clock, log_prefix="VoxelLoader"):
        """
        Initialize the VoxelLoader
        
        Args:
            dut: The DUT module (should have scene_loader_if interface signals)
            clock: The clock signal
            log_prefix: Prefix for log messages
        """
        self.dut = dut
        self.clock = clock
        self.log = SimLog(f"cocotb.{log_prefix}")
        
        # Interface signals (scene_loader_if)
        self.load_mode = dut.load_mode
        self.load_valid = dut.load_valid
        self.load_ready = dut.load_ready
        self.load_addr = dut.load_addr
        self.load_data = dut.load_data
        
        # Initialize signals
        self.load_mode.value = 0
        self.load_valid.value = 0
        self.load_addr.value = 0
        self.load_data.value = 0
        
    async def load_voxels_from_array(self, voxels, grid_size=32):
        """
        Load voxels from a 3D numpy array into the voxel RAM
        
        Args:
            voxels: 3D numpy array [x, y, z] with boolean/int values (0=empty, 1=solid)
            grid_size: Size of the voxel grid (default 32 for 32x32x32)
        """
        self.log.info(f"Starting voxel load: {grid_size}x{grid_size}x{grid_size} grid")
        
        # Enter load mode
        self.load_mode.value = 1
        await RisingEdge(self.clock)
        
        voxels_loaded = 0
        
        # Iterate through all voxels in ZYX order (matches voxel_addr_map default)
        for z in range(grid_size):
            for y in range(grid_size):
                for x in range(grid_size):
                    # Calculate address: (z << 10) | (y << 5) | x for 32^3 grid
                    addr = (z << 10) | (y << 5) | x
                    
                    # Get voxel data (handle out of bounds)
                    if (x < voxels.shape[0] and 
                        y < voxels.shape[1] and 
                        z < voxels.shape[2]):
                        bit = int(voxels[x, y, z] != 0)
                    else:
                        bit = 0
                    
                    # Drive the interface
                    self.load_addr.value = addr
                    self.load_data.value = bit
                    self.load_valid.value = 1
                    
                    # Wait for acceptance
                    await RisingEdge(self.clock)
                    await ReadOnly()  # Wait for signals to settle
                    
                    # Check if ready (should always be ready per scene_loader_if design)
                    if self.load_ready.value:
                        voxels_loaded += 1
                    else:
                        self.log.warning(f"Load not ready at addr={addr}")
                    
                    # Progress indicator
                    if voxels_loaded % 4096 == 0:
                        self.log.info(f"Loaded {voxels_loaded}/{grid_size**3} voxels...")
        
        # Deassert valid
        self.load_valid.value = 0
        await RisingEdge(self.clock)
        
        # Exit load mode
        self.load_mode.value = 0
        await RisingEdge(self.clock)
        
        self.log.info(f"Voxel load complete: {voxels_loaded} voxels written")
        return voxels_loaded
    
    async def load_voxels_from_file(self, filename, format_type=0):
        """
        Load voxels from a text file (alternative to array loading)
        
        Args:
            filename: Path to voxel file
            format_type: 0 for "addr bit" format, 1 for "bit per line" format
        """
        self.log.info(f"Loading voxels from file: {filename} (format={format_type})")
        
        # Enter load mode
        self.load_mode.value = 1
        await RisingEdge(self.clock)
        
        voxels_loaded = 0
        
        try:
            with open(filename, 'r') as f:
                if format_type == 0:
                    # Format: "addr bit" per line
                    for line in f:
                        parts = line.strip().split()
                        if len(parts) == 2:
                            addr = int(parts[0])
                            bit = int(parts[1])
                            
                            self.load_addr.value = addr
                            self.load_data.value = bit
                            self.load_valid.value = 1
                            
                            await RisingEdge(self.clock)
                            await ReadOnly()
                            
                            if self.load_ready.value:
                                voxels_loaded += 1
                            
                            if voxels_loaded % 4096 == 0:
                                self.log.info(f"Loaded {voxels_loaded} voxels...")
                
                else:
                    # Format: "bit" per line, addr = line number
                    addr = 0
                    for line in f:
                        bit = int(line.strip())
                        
                        self.load_addr.value = addr
                        self.load_data.value = bit
                        self.load_valid.value = 1
                        
                        await RisingEdge(self.clock)
                        await ReadOnly()
                        
                        if self.load_ready.value:
                            voxels_loaded += 1
                        
                        addr += 1
                        
                        if voxels_loaded % 4096 == 0:
                            self.log.info(f"Loaded {voxels_loaded} voxels...")
        
        except FileNotFoundError:
            self.log.error(f"File not found: {filename}")
            raise
        
        # Deassert valid
        self.load_valid.value = 0
        await RisingEdge(self.clock)
        
        # Exit load mode
        self.load_mode.value = 0
        await RisingEdge(self.clock)
        
        self.log.info(f"Voxel load complete: {voxels_loaded} voxels from file")
        return voxels_loaded
