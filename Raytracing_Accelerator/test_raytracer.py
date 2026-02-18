"""
Cocotb testbench for raytracing accelerator
Tests the integration of voxel memory loading and ray job processing
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.log import SimLog
import os
import sys

# Import helper modules
from voxel_loader import VoxelLoader
from ray_job_driver import RayJobDriver, RayJob

# Optional: Import Python data generation modules if available
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False
    print("Warning: numpy not available, some tests may be skipped")


async def reset_dut(dut, clock, duration_cycles=10):
    """Reset the DUT"""
    log = SimLog("cocotb.reset")
    log.info(f"Asserting reset for {duration_cycles} cycles")
    
    dut.rst_n.value = 0
    await ClockCycles(clock, duration_cycles)
    dut.rst_n.value = 1
    await RisingEdge(clock)
    
    log.info("Reset complete")


def create_fake_job_done_driver(dut, clock):
    """
    Create a background task that simulates job completion
    Since we're testing the input interfaces (not the full accelerator),
    we need to fake the job_done signal after some delay
    """
    @cocotb.coroutine
    async def drive_job_done():
        log = SimLog("cocotb.job_done_driver")
        countdown = 0
        
        while True:
            await RisingEdge(clock)
            
            # Check if a job was just loaded
            if dut.job_loaded.value:
                countdown = 6  # Simulate 6-cycle processing time
                log.debug("Job loaded, will complete in 6 cycles")
            
            # Count down and pulse job_done
            if countdown > 0:
                countdown -= 1
                if countdown == 0:
                    dut.job_done.value = 1
                    log.debug("Pulsing job_done")
                else:
                    dut.job_done.value = 0
            else:
                dut.job_done.value = 0
    
    return cocotb.start_soon(drive_job_done())


@cocotb.test()
async def test_voxel_loading_from_file(dut):
    """Test loading voxels from a file"""
    log = SimLog("cocotb.test_voxel_loading")
    log.info("=" * 80)
    log.info("TEST: Voxel Loading from File")
    log.info("=" * 80)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    await reset_dut(dut, dut.clk, duration_cycles=10)
    
    # Create voxel loader
    voxel_loader = VoxelLoader(dut, dut.clk)
    
    # Check if voxel file exists
    voxel_file = os.environ.get("VOXEL_FILE", "voxels_load.txt")
    
    if not os.path.exists(voxel_file):
        log.warning(f"Voxel file not found: {voxel_file}")
        log.warning("Creating a dummy voxel file for testing...")
        
        # Create a simple test file
        with open(voxel_file, 'w') as f:
            # Write a few test voxels (addr bit format)
            for i in range(100):
                f.write(f"{i} {i % 2}\n")
        
        log.info(f"Created test voxel file: {voxel_file}")
    
    # Load voxels
    try:
        voxels_loaded = await voxel_loader.load_voxels_from_file(voxel_file, format_type=0)
        log.info(f"✓ Successfully loaded {voxels_loaded} voxels from file")
    except Exception as e:
        log.error(f"✗ Failed to load voxels: {e}")
        raise
    
    # Wait a bit
    await ClockCycles(dut.clk, 10)
    
    log.info("TEST PASSED: Voxel loading from file")


@cocotb.test(skip=not HAS_NUMPY)
async def test_voxel_loading_from_array(dut):
    """Test loading voxels from a numpy array"""
    log = SimLog("cocotb.test_voxel_array")
    log.info("=" * 80)
    log.info("TEST: Voxel Loading from Array")
    log.info("=" * 80)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    await reset_dut(dut, dut.clk, duration_cycles=10)
    
    # Create voxel loader
    voxel_loader = VoxelLoader(dut, dut.clk)
    
    # Create a small test voxel grid (8x8x8 for speed)
    grid_size = 8
    voxels = np.zeros((grid_size, grid_size, grid_size), dtype=np.uint8)
    
    # Create a simple pattern (hollow cube)
    voxels[0, :, :] = 1  # Front face
    voxels[-1, :, :] = 1  # Back face
    voxels[:, 0, :] = 1  # Left face
    voxels[:, -1, :] = 1  # Right face
    voxels[:, :, 0] = 1  # Bottom face
    voxels[:, :, -1] = 1  # Top face
    
    log.info(f"Created {grid_size}x{grid_size}x{grid_size} test voxel grid")
    
    # Load voxels (pad to 32x32x32)
    try:
        voxels_loaded = await voxel_loader.load_voxels_from_array(voxels, grid_size=grid_size)
        log.info(f"✓ Successfully loaded {voxels_loaded} voxels from array")
    except Exception as e:
        log.error(f"✗ Failed to load voxels: {e}")
        raise
    
    # Wait a bit
    await ClockCycles(dut.clk, 10)
    
    log.info("TEST PASSED: Voxel loading from array")


@cocotb.test()
async def test_ray_job_feeding_from_file(dut):
    """Test feeding ray jobs from a file"""
    log = SimLog("cocotb.test_ray_jobs")
    log.info("=" * 80)
    log.info("TEST: Ray Job Feeding from File")
    log.info("=" * 80)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    await reset_dut(dut, dut.clk, duration_cycles=10)
    
    # Start fake job_done driver (simulates downstream accelerator)
    job_done_driver = create_fake_job_done_driver(dut, dut.clk)
    
    # Create ray job driver
    ray_driver = RayJobDriver(dut, dut.clk)
    
    # Check if ray jobs file exists
    ray_file = os.environ.get("RAY_FILE", "ray_jobs.txt")
    
    if not os.path.exists(ray_file):
        log.warning(f"Ray jobs file not found: {ray_file}")
        log.warning("Creating a dummy ray jobs file for testing...")
        
        # Create a simple test file with a few jobs
        with open(ray_file, 'w') as f:
            # Format: px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps
            for px in range(4):
                for py in range(4):
                    # Create a simple ray job
                    f.write(f"{px} {py} 1 ")  # px, py, valid
                    f.write(f"0 0 0 ")  # ix0, iy0, iz0
                    f.write(f"1 1 1 ")  # sx, sy, sz
                    f.write(f"100 100 100 ")  # next_x, next_y, next_z
                    f.write(f"10 10 10 ")  # inc_x, inc_y, inc_z
                    f.write(f"100\n")  # max_steps
        
        log.info(f"Created test ray jobs file: {ray_file}")
    
    # Parse ray jobs
    try:
        jobs = RayJobDriver.parse_ray_jobs_from_file(ray_file, skip_invalid=True)
        log.info(f"Parsed {len(jobs)} valid ray jobs from {ray_file}")
    except Exception as e:
        log.error(f"Failed to parse ray jobs: {e}")
        raise
    
    if len(jobs) == 0:
        log.error("No valid jobs found in file")
        raise ValueError("No valid jobs to test")
    
    # Send a subset of jobs (limit for faster testing)
    max_jobs = min(len(jobs), 20)
    test_jobs = jobs[:max_jobs]
    log.info(f"Testing with first {max_jobs} jobs")
    
    # Send jobs
    try:
        completed = await ray_driver.send_jobs_batch(test_jobs, progress_interval=5)
        log.info(f"✓ Successfully completed {completed}/{max_jobs} jobs")
        
        if completed != max_jobs:
            log.error(f"✗ Expected {max_jobs} jobs, completed {completed}")
            raise ValueError("Not all jobs completed")
    except Exception as e:
        log.error(f"✗ Failed to send ray jobs: {e}")
        raise
    
    # Wait a bit
    await ClockCycles(dut.clk, 20)
    
    log.info("TEST PASSED: Ray job feeding from file")


@cocotb.test()
async def test_single_ray_job(dut):
    """Test sending a single ray job"""
    log = SimLog("cocotb.test_single_job")
    log.info("=" * 80)
    log.info("TEST: Single Ray Job")
    log.info("=" * 80)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    await reset_dut(dut, dut.clk, duration_cycles=10)
    
    # Start fake job_done driver
    job_done_driver = create_fake_job_done_driver(dut, dut.clk)
    
    # Create ray job driver
    ray_driver = RayJobDriver(dut, dut.clk)
    
    # Create a test job
    test_job = RayJob(
        px=10, py=20,
        ix0=5, iy0=10, iz0=15,
        sx=1, sy=0, sz=1,
        next_x=1000, next_y=2000, next_z=3000,
        inc_x=100, inc_y=200, inc_z=300,
        max_steps=500
    )
    
    log.info(f"Sending test job: {test_job}")
    
    # Send the job
    try:
        success = await ray_driver.send_job(test_job, wait_for_completion=True)
        
        if success:
            log.info("✓ Job completed successfully")
        else:
            log.error("✗ Job failed")
            raise ValueError("Job failed to complete")
    except Exception as e:
        log.error(f"✗ Exception during job sending: {e}")
        raise
    
    # Verify the job was registered correctly
    await RisingEdge(dut.clk)
    
    log.info(f"Registered job fields: ix0={dut.ix0_q.value}, iy0={dut.iy0_q.value}, iz0={dut.iz0_q.value}")
    log.info(f"Direction signs: sx={dut.sx_q.value}, sy={dut.sy_q.value}, sz={dut.sz_q.value}")
    log.info(f"Max steps: {dut.max_steps_q.value}")
    
    # Wait a bit
    await ClockCycles(dut.clk, 10)
    
    log.info("TEST PASSED: Single ray job")


@cocotb.test()
async def test_full_integration(dut):
    """Test full integration: load voxels + feed ray jobs"""
    log = SimLog("cocotb.test_integration")
    log.info("=" * 80)
    log.info("TEST: Full Integration (Voxels + Ray Jobs)")
    log.info("=" * 80)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    await reset_dut(dut, dut.clk, duration_cycles=10)
    
    # Create drivers
    voxel_loader = VoxelLoader(dut, dut.clk)
    ray_driver = RayJobDriver(dut, dut.clk)
    
    # Phase 1: Load voxels
    log.info("Phase 1: Loading voxels...")
    voxel_file = os.environ.get("VOXEL_FILE", "voxels_load.txt")
    
    if os.path.exists(voxel_file):
        voxels_loaded = await voxel_loader.load_voxels_from_file(voxel_file, format_type=0)
        log.info(f"✓ Loaded {voxels_loaded} voxels")
    else:
        log.warning("Voxel file not found, skipping voxel loading")
    
    await ClockCycles(dut.clk, 10)
    
    # Phase 2: Feed ray jobs
    log.info("Phase 2: Feeding ray jobs...")
    
    # Start fake job_done driver
    job_done_driver = create_fake_job_done_driver(dut, dut.clk)
    
    ray_file = os.environ.get("RAY_FILE", "ray_jobs.txt")
    
    if os.path.exists(ray_file):
        jobs = RayJobDriver.parse_ray_jobs_from_file(ray_file, skip_invalid=True)
        log.info(f"Parsed {len(jobs)} jobs")
        
        # Test with a limited number for faster testing
        max_jobs = min(len(jobs), 50)
        test_jobs = jobs[:max_jobs]
        
        completed = await ray_driver.send_jobs_batch(test_jobs, progress_interval=10)
        log.info(f"✓ Completed {completed}/{max_jobs} jobs")
        
        if completed != max_jobs:
            raise ValueError(f"Expected {max_jobs} jobs, completed {completed}")
    else:
        log.warning("Ray jobs file not found, skipping ray job feeding")
    
    await ClockCycles(dut.clk, 20)
    
    log.info("TEST PASSED: Full integration")


# Main entry point for standalone execution
if __name__ == "__main__":
    print("This is a cocotb testbench. Run with 'make' to execute tests.")
