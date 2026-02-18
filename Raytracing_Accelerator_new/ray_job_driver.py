"""
Cocotb driver for ray_job_if - feeds ray jobs to the raytracing accelerator
"""
import cocotb
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge
from cocotb.log import SimLog


class RayJob:
    """Container for a single ray job"""
    
    def __init__(self, px, py, ix0, iy0, iz0, sx, sy, sz, 
                 next_x, next_y, next_z, inc_x, inc_y, inc_z, max_steps):
        self.px = px
        self.py = py
        self.ix0 = ix0
        self.iy0 = iy0
        self.iz0 = iz0
        self.sx = sx
        self.sy = sy
        self.sz = sz
        self.next_x = next_x
        self.next_y = next_y
        self.next_z = next_z
        self.inc_x = inc_x
        self.inc_y = inc_y
        self.inc_z = inc_z
        self.max_steps = max_steps
        self.result = None  # Will store result after completion
    
    def __repr__(self):
        return (f"RayJob(px={self.px}, py={self.py}, "
                f"start=({self.ix0},{self.iy0},{self.iz0}), "
                f"s=({self.sx},{self.sy},{self.sz}), max_steps={self.max_steps})")


class RayJobDriver:
    """Driver for ray_job_if to feed ray jobs to the accelerator"""
    
    def __init__(self, dut, clock, log_prefix="RayJobDriver"):
        """
        Initialize the RayJobDriver
        
        Args:
            dut: The DUT module (should have ray_job_if interface signals)
            clock: The clock signal
            log_prefix: Prefix for log messages
        """
        self.dut = dut
        self.clock = clock
        self.log = SimLog(f"cocotb.{log_prefix}")
        
        # Input interface signals
        self.job_valid = dut.job_valid
        self.job_ready = dut.job_ready
        self.ix0 = dut.ix0
        self.iy0 = dut.iy0
        self.iz0 = dut.iz0
        self.sx = dut.sx
        self.sy = dut.sy
        self.sz = dut.sz
        self.next_x = dut.next_x
        self.next_y = dut.next_y
        self.next_z = dut.next_z
        self.inc_x = dut.inc_x
        self.inc_y = dut.inc_y
        self.inc_z = dut.inc_z
        self.max_steps = dut.max_steps
        
        # Output interface signals
        self.job_done = dut.job_done
        self.job_loaded = dut.job_loaded
        self.job_active = dut.job_active
        
        # Output registered job fields (for monitoring)
        self.ix0_q = dut.ix0_q
        self.iy0_q = dut.iy0_q
        self.iz0_q = dut.iz0_q
        self.sx_q = dut.sx_q
        self.sy_q = dut.sy_q
        self.sz_q = dut.sz_q
        self.next_x_q = dut.next_x_q
        self.next_y_q = dut.next_y_q
        self.next_z_q = dut.next_z_q
        self.inc_x_q = dut.inc_x_q
        self.inc_y_q = dut.inc_y_q
        self.inc_z_q = dut.inc_z_q
        self.max_steps_q = dut.max_steps_q
        
        # Initialize input signals
        self.job_valid.value = 0
        self._initialize_job_signals()
        
    def _initialize_job_signals(self):
        """Initialize all job input signals to 0"""
        self.ix0.value = 0
        self.iy0.value = 0
        self.iz0.value = 0
        self.sx.value = 0
        self.sy.value = 0
        self.sz.value = 0
        self.next_x.value = 0
        self.next_y.value = 0
        self.next_z.value = 0
        self.inc_x.value = 0
        self.inc_y.value = 0
        self.inc_z.value = 0
        self.max_steps.value = 0
    
    async def send_job(self, job, wait_for_completion=True, timeout_cycles=10000):
        """
        Send a single ray job to the accelerator
        
        Args:
            job: RayJob object
            wait_for_completion: If True, wait for job_done signal
            timeout_cycles: Maximum cycles to wait for completion
            
        Returns:
            True if job was accepted (and completed if wait_for_completion=True)
        """
        # Wait for ready signal
        ready_timeout = 1000
        cycles_waited = 0
        while not self.job_ready.value:
            await RisingEdge(self.clock)
            cycles_waited += 1
            if cycles_waited > ready_timeout:
                self.log.error(f"Timeout waiting for job_ready for {job}")
                return False
        
        # Drive job signals
        self.job_valid.value = 1
        self.ix0.value = job.ix0
        self.iy0.value = job.iy0
        self.iz0.value = job.iz0
        self.sx.value = job.sx
        self.sy.value = job.sy
        self.sz.value = job.sz
        self.next_x.value = job.next_x
        self.next_y.value = job.next_y
        self.next_z.value = job.next_z
        self.inc_x.value = job.inc_x
        self.inc_y.value = job.inc_y
        self.inc_z.value = job.inc_z
        self.max_steps.value = job.max_steps
        
        # Wait for acceptance
        await RisingEdge(self.clock)
        await ReadOnly()
        
        # Check if job was loaded
        if self.job_loaded.value:
            self.log.debug(f"Job accepted for pixel ({job.px},{job.py})")
        else:
            self.log.warning(f"Job not loaded for pixel ({job.px},{job.py})")
        
        # Deassert valid
        self.job_valid.value = 0
        self._initialize_job_signals()
        
        # Wait for completion if requested
        if wait_for_completion:
            cycles_waited = 0
            while not self.job_done.value:
                await RisingEdge(self.clock)
                await ReadOnly()
                cycles_waited += 1
                if cycles_waited > timeout_cycles:
                    self.log.error(f"Timeout waiting for job_done for {job} after {cycles_waited} cycles")
                    return False
            
            self.log.debug(f"Job completed for pixel ({job.px},{job.py}) in {cycles_waited} cycles")
        
        return True
    
    async def send_jobs_batch(self, jobs, progress_interval=100):
        """
        Send a batch of ray jobs
        
        Args:
            jobs: List of RayJob objects
            progress_interval: Print progress every N jobs
            
        Returns:
            Number of successfully completed jobs
        """
        total_jobs = len(jobs)
        self.log.info(f"Starting batch job submission: {total_jobs} jobs")
        
        completed = 0
        
        for idx, job in enumerate(jobs):
            success = await self.send_job(job, wait_for_completion=True)
            if success:
                completed += 1
            
            # Progress reporting
            if (idx + 1) % progress_interval == 0:
                self.log.info(f"Progress: {idx+1}/{total_jobs} jobs sent ({completed} completed)")
        
        self.log.info(f"Batch complete: {completed}/{total_jobs} jobs completed successfully")
        return completed
    
    @staticmethod
    def parse_ray_jobs_from_file(filename, skip_invalid=True):
        """
        Parse ray jobs from a ray_jobs.txt file
        
        File format (per line):
        px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps
        
        Args:
            filename: Path to ray_jobs.txt
            skip_invalid: Skip lines where valid=0
            
        Returns:
            List of RayJob objects
        """
        jobs = []
        
        with open(filename, 'r') as f:
            for line_num, line in enumerate(f, 1):
                parts = line.strip().split()
                
                if len(parts) < 16:
                    continue  # Skip incomplete lines
                
                try:
                    px = int(parts[0])
                    py = int(parts[1])
                    valid = int(parts[2])
                    
                    if skip_invalid and valid == 0:
                        continue
                    
                    ix0 = int(parts[3])
                    iy0 = int(parts[4])
                    iz0 = int(parts[5])
                    sx = int(parts[6])
                    sy = int(parts[7])
                    sz = int(parts[8])
                    next_x = int(parts[9])
                    next_y = int(parts[10])
                    next_z = int(parts[11])
                    inc_x = int(parts[12])
                    inc_y = int(parts[13])
                    inc_z = int(parts[14])
                    max_steps = int(parts[15])
                    
                    job = RayJob(px, py, ix0, iy0, iz0, sx, sy, sz,
                                next_x, next_y, next_z, inc_x, inc_y, inc_z, max_steps)
                    jobs.append(job)
                
                except (ValueError, IndexError) as e:
                    print(f"Warning: Failed to parse line {line_num}: {e}")
                    continue
        
        return jobs
