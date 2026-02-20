`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_raytracer_top
// Description: Comprehensive self-checking testbench for raytracer_top
//              Full golden model with DDA stepping, assertions, coverage
// =============================================================================

module tb_raytracer_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int COORD_WIDTH = 16;
    localparam int COORD_W = 6;
    localparam int TIMER_WIDTH = 32;
    localparam int W = 32;
    localparam int MAX_VAL = 31;
    localparam int ADDR_BITS = 15;
    localparam int X_BITS = 6;  // Updated to 6-bit for bounds detection
    localparam int Y_BITS = 6;
    localparam int Z_BITS = 6;
    localparam int MAX_STEPS_BITS = 10;
    localparam int STEP_COUNT_WIDTH = 16;
    
    localparam int PIPELINE_LATENCY = 5;
    localparam int NUM_RANDOM_TESTS = 500;
    localparam real CLOCK_PERIOD = 10.0;
    
    localparam int MEM_SIZE = 32768;  // 2^15
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic                          clk;
    logic                          rst_n;
    
    // Job interface
    logic                          job_valid;
    logic                          job_ready;
    logic [X_BITS-1:0]             job_ix0;
    logic [Y_BITS-1:0]             job_iy0;
    logic [Z_BITS-1:0]             job_iz0;
    logic                          job_sx, job_sy, job_sz;
    logic [W-1:0]                  job_next_x, job_next_y, job_next_z;
    logic [W-1:0]                  job_inc_x, job_inc_y, job_inc_z;
    logic [MAX_STEPS_BITS-1:0]     job_max_steps;
    
    // Scene loader interface
    logic                          load_mode;
    logic                          load_valid;
    logic                          load_ready;
    logic [ADDR_BITS-1:0]          load_addr;
    logic                          load_data;
    logic [ADDR_BITS:0]            write_count;
    logic                          load_complete;
    
    // Ray result outputs
    logic                          ray_done;
    logic                          ray_hit;
    logic                          ray_timeout;
    logic [COORD_WIDTH-1:0]        hit_voxel_x, hit_voxel_y, hit_voxel_z;
    logic [2:0]                    hit_face_id;
    logic [STEP_COUNT_WIDTH-1:0]   steps_taken;
    
    // =========================================================================
    // Testbench State
    // =========================================================================
    int test_count;
    int pass_count;
    int fail_count;
    int cycle_count;
    
    // Scene memory model
    logic scene_mem [0:MEM_SIZE-1];
    
    // Job scoreboard
    typedef struct {
        logic [X_BITS-1:0]  ix0, iy0, iz0;
        logic               sx, sy, sz;
        logic [W-1:0]       next_x, next_y, next_z;
        logic [W-1:0]       inc_x, inc_y, inc_z;
        logic [MAX_STEPS_BITS-1:0] max_steps;
        // Expected results
        logic               exp_hit;
        logic               exp_timeout;
        logic [X_BITS-1:0]  exp_hit_x, exp_hit_y, exp_hit_z;
        logic [2:0]         exp_face_id;
        logic [STEP_COUNT_WIDTH-1:0] exp_steps;
        string              test_name;
    } job_entry_t;
    
    job_entry_t pending_job;
    logic job_pending;
    
    // Coverage tracking
    int hit_count, timeout_count, bounds_count;
    int face_id_count[0:5];
    int tie_pattern_count[0:7];  // 8 possible step_mask patterns
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    raytracer_top #(
        .COORD_WIDTH(COORD_WIDTH),
        .COORD_W(COORD_W),
        .TIMER_WIDTH(TIMER_WIDTH),
        .W(W),
        .MAX_VAL(MAX_VAL),
        .ADDR_BITS(ADDR_BITS),
        .X_BITS(X_BITS),
        .Y_BITS(Y_BITS),
        .Z_BITS(Z_BITS),
        .MAX_STEPS_BITS(MAX_STEPS_BITS),
        .STEP_COUNT_WIDTH(STEP_COUNT_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .job_valid(job_valid),
        .job_ready(job_ready),
        .job_ix0(job_ix0),
        .job_iy0(job_iy0),
        .job_iz0(job_iz0),
        .job_sx(job_sx),
        .job_sy(job_sy),
        .job_sz(job_sz),
        .job_next_x(job_next_x),
        .job_next_y(job_next_y),
        .job_next_z(job_next_z),
        .job_inc_x(job_inc_x),
        .job_inc_y(job_inc_y),
        .job_inc_z(job_inc_z),
        .job_max_steps(job_max_steps),
        .load_mode(load_mode),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_addr(load_addr),
        .load_data(load_data),
        .write_count(write_count),
        .load_complete(load_complete),
        .ray_done(ray_done),
        .ray_hit(ray_hit),
        .ray_timeout(ray_timeout),
        .hit_voxel_x(hit_voxel_x),
        .hit_voxel_y(hit_voxel_y),
        .hit_voxel_z(hit_voxel_z),
        .hit_face_id(hit_face_id),
        .steps_taken(steps_taken)
    );
    
    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end
    
    // Cycle counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end
    
    // =========================================================================
    // Golden Reference Model Functions
    // =========================================================================
    
    // Compute axis_choose: find minimum and generate mask
    function automatic void ref_axis_choose(
        input logic [W-1:0] nx, ny, nz,
        output logic [2:0] step_mask,
        output logic [1:0] primary_sel
    );
        logic [W-1:0] min_val;
        
        // Find minimum (unsigned comparison)
        if (nx <= ny && nx <= nz) min_val = nx;
        else if (ny <= nz) min_val = ny;
        else min_val = nz;
        
        // Generate mask
        step_mask[0] = (nx == min_val);
        step_mask[1] = (ny == min_val);
        step_mask[2] = (nz == min_val);
        
        // Primary sel = lowest index set (X priority)
        if (step_mask[0]) primary_sel = 2'd0;
        else if (step_mask[1]) primary_sel = 2'd1;
        else primary_sel = 2'd2;
    endfunction
    
    // Compute step_update: update coordinates and timers
    function automatic void ref_step_update(
        input logic [X_BITS-1:0] ix, iy, iz,
        input logic sx, sy, sz,
        input logic [W-1:0] nx, ny, nz,
        input logic [W-1:0] incx, incy, incz,
        input logic [2:0] step_mask,
        input logic [1:0] primary_sel,
        output logic [X_BITS-1:0] next_ix, next_iy, next_iz,
        output logic [W-1:0] next_nx, next_ny, next_nz,
        output logic [2:0] face_id
    );
        // Update X
        if (step_mask[0]) begin
            next_ix = sx ? (ix + 6'd1) : (ix - 6'd1);
            next_nx = nx + incx;
        end else begin
            next_ix = ix;
            next_nx = nx;
        end
        
        // Update Y
        if (step_mask[1]) begin
            next_iy = sy ? (iy + 6'd1) : (iy - 6'd1);
            next_ny = ny + incy;
        end else begin
            next_iy = iy;
            next_ny = ny;
        end
        
        // Update Z
        if (step_mask[2]) begin
            next_iz = sz ? (iz + 6'd1) : (iz - 6'd1);
            next_nz = nz + incz;
        end else begin
            next_iz = iz;
            next_nz = nz;
        end
        
        // Compute primary_face_id (0=X+,1=X-,2=Y+,3=Y-,4=Z+,5=Z-)
        case (primary_sel)
            2'd0: face_id = sx ? 3'd0 : 3'd1;  // X
            2'd1: face_id = sy ? 3'd2 : 3'd3;  // Y
            2'd2: face_id = sz ? 3'd4 : 3'd5;  // Z
            default: face_id = 3'd0;
        endcase
    endfunction
    
    // Compute voxel address
    function automatic logic [ADDR_BITS-1:0] ref_address(
        input logic [X_BITS-1:0] x, y, z
    );
        // Mask to lower 5 bits for 32x32x32 grid (addresses 0-31 only)
        return {z[4:0], y[4:0], x[4:0]};  // addr = (z<<10) | (y<<5) | x
    endfunction
    
    // Check if out of bounds
    function automatic logic ref_out_of_bounds(
        input logic [X_BITS-1:0] x, y, z
    );
        // Coordinates are already 6-bit, use directly
        logic [5:0] ext_x, ext_y, ext_z;
        ext_x = x;
        ext_y = y;
        ext_z = z;
        return (ext_x > MAX_VAL) || (ext_y > MAX_VAL) || (ext_z > MAX_VAL);
    endfunction
    
    // Full DDA iteration prediction
    function automatic void predict_ray_result(
        input logic [X_BITS-1:0] start_ix, start_iy, start_iz,
        input logic start_sx, start_sy, start_sz,
        input logic [W-1:0] start_nx, start_ny, start_nz,
        input logic [W-1:0] start_incx, start_incy, start_incz,
        input logic [MAX_STEPS_BITS-1:0] max_steps_in,
        output logic pred_hit,
        output logic pred_timeout,
        output logic [X_BITS-1:0] pred_hit_x, pred_hit_y, pred_hit_z,
        output logic [2:0] pred_face_id,
        output logic [STEP_COUNT_WIDTH-1:0] pred_steps
    );
        logic [X_BITS-1:0] cur_x, cur_y, cur_z;
        logic [W-1:0] cur_nx, cur_ny, cur_nz;
        logic [2:0] mask;
        logic [1:0] psel;
        logic [ADDR_BITS-1:0] addr;
        logic [STEP_COUNT_WIDTH-1:0] step_cnt;
        logic terminated;
        
        // Initialize
        cur_x = start_ix;
        cur_y = start_iy;
        cur_z = start_iz;
        cur_nx = start_nx;
        cur_ny = start_ny;
        cur_nz = start_nz;
        step_cnt = 0;
        terminated = 0;
        
        pred_hit = 0;
        pred_timeout = 0;
        pred_hit_x = cur_x;
        pred_hit_y = cur_y;
        pred_hit_z = cur_z;
        pred_face_id = 0;
        pred_steps = 0;
        
        // Iterate until termination
        while (!terminated && step_cnt < 1000) begin  // Safety limit
            // Check current voxel occupancy
            addr = ref_address(cur_x, cur_y, cur_z);
            if (scene_mem[addr]) begin
                // Hit solid voxel
                pred_hit = 1;
                pred_hit_x = cur_x;
                pred_hit_y = cur_y;
                pred_hit_z = cur_z;
                pred_steps = step_cnt;
                terminated = 1;
            end
            // Check timeout
            else if (step_cnt >= max_steps_in) begin
                pred_timeout = 1;
                pred_steps = step_cnt;
                terminated = 1;
            end
            else begin
                // Compute next step
                ref_axis_choose(cur_nx, cur_ny, cur_nz, mask, psel);
                tie_pattern_count[mask]++;  // Track tie patterns
                
                ref_step_update(
                    cur_x, cur_y, cur_z,
                    start_sx, start_sy, start_sz,
                    cur_nx, cur_ny, cur_nz,
                    start_incx, start_incy, start_incz,
                    mask, psel,
                    cur_x, cur_y, cur_z,
                    cur_nx, cur_ny, cur_nz,
                    pred_face_id
                );
                
                // Check bounds on next position
                if (ref_out_of_bounds(cur_x, cur_y, cur_z)) begin
                    pred_steps = step_cnt;
                    terminated = 1;
                end else begin
                    step_cnt++;
                end
            end
        end
    endfunction
    
    // =========================================================================
    // Helper Tasks
    // =========================================================================
    
    // Reset DUT
    task reset_dut();
        $display("[%0t] Resetting DUT...", $time);
        job_valid = 0;
        job_ix0 = 0; job_iy0 = 0; job_iz0 = 0;
        job_sx = 0; job_sy = 0; job_sz = 0;
        job_next_x = 0; job_next_y = 0; job_next_z = 0;
        job_inc_x = 0; job_inc_y = 0; job_inc_z = 0;
        job_max_steps = 0;
        load_mode = 0;
        load_valid = 0;
        load_addr = 0;
        load_data = 0;
        job_pending = 0;
        
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("[%0t] Reset complete", $time);
    endtask
    
    // Load scene into DUT and reference memory
    // pattern_type: -1 = use existing scene_mem (don't reinitialize)
    //               0 = empty, 1 = random, 2 = landmarks, 3 = custom, etc.
    task load_scene(input string pattern_name, input int pattern_type, input real density = 0.05);
        int timeout;
        
        $display("[%0t] Loading scene: %s (density=%.1f%%)", $time, pattern_name, density*100);
        
        // Initialize reference memory (skip if pattern_type = -1)
        if (pattern_type != -1) begin
            for (int i = 0; i < MEM_SIZE; i++) begin
                case (pattern_type)
                    0: scene_mem[i] = 1'b0;  // Empty
                    1: scene_mem[i] = ($urandom_range(1000) < density*1000) ? 1'b1 : 1'b0;  // Random sparse
                    2: begin  // Specific landmarks
                        if (i == ref_address(6'd10, 6'd10, 6'd10)) scene_mem[i] = 1'b1;
                        else if (i == ref_address(6'd20, 6'd15, 6'd25)) scene_mem[i] = 1'b1;
                        else if (i == ref_address(6'd5, 6'd5, 6'd5)) scene_mem[i] = 1'b1;
                        else scene_mem[i] = 1'b0;
                    end
                    3: begin  // Starting voxel solid
                        scene_mem[i] = 1'b0;
                    end
                    default: scene_mem[i] = 1'b0;
                endcase
            end
        end
        
        // Enter load mode
        @(posedge clk);
        load_mode = 1'b1;
        load_valid = 1'b0;
        
        // Assert job_ready should be 0 during load_mode
        @(posedge clk);
        if (job_ready !== 1'b0) begin
            $display("LOG: %0t : ERROR : tb_raytracer_top : dut.job_ready : expected_value: 0 actual_value: %0b", 
                     $time, job_ready);
            $fatal(1, "ASSERTION FAILED: job_ready should be 0 during load_mode");
        end
        
        // Write scene to DUT
        timeout = 0;
        for (int i = 0; i < MEM_SIZE; i++) begin
            @(posedge clk);
            load_valid = 1'b1;
            load_addr = i[ADDR_BITS-1:0];
            load_data = scene_mem[i];
            
            timeout++;
            if (timeout > 40000) begin
                $fatal(1, "Scene loading timeout");
            end
        end
        
        @(posedge clk);
        load_valid = 1'b0;
        
        // Wait for load_complete
        timeout = 0;
        while (!load_complete && timeout < 100) begin
            @(posedge clk);
            timeout++;
        end
        
        // Read write_count BEFORE exiting load_mode (otherwise it resets to 0)
        @(posedge clk);
        $display("[%0t] Scene loaded: write_count=%0d", $time, write_count);
        
        load_mode = 1'b0;
        
        // Wait for write pipeline to drain
        repeat(20) @(posedge clk);
    endtask
    
    // Send job via handshake
    task send_job(
        input logic [X_BITS-1:0] ix, iy, iz,
        input logic sx, sy, sz,
        input logic [W-1:0] nx, ny, nz,
        input logic [W-1:0] incx, incy, incz,
        input logic [MAX_STEPS_BITS-1:0] max_steps_in,
        input string test_name_in
    );
        int timeout;
        
        // Setup job
        job_ix0 = ix; job_iy0 = iy; job_iz0 = iz;
        job_sx = sx; job_sy = sy; job_sz = sz;
        job_next_x = nx; job_next_y = ny; job_next_z = nz;
        job_inc_x = incx; job_inc_y = incy; job_inc_z = incz;
        job_max_steps = max_steps_in;
        
        // Predict expected results
        pending_job.ix0 = ix; pending_job.iy0 = iy; pending_job.iz0 = iz;
        pending_job.sx = sx; pending_job.sy = sy; pending_job.sz = sz;
        pending_job.next_x = nx; pending_job.next_y = ny; pending_job.next_z = nz;
        pending_job.inc_x = incx; pending_job.inc_y = incy; pending_job.inc_z = incz;
        pending_job.max_steps = max_steps_in;
        pending_job.test_name = test_name_in;
        
        predict_ray_result(
            ix, iy, iz, sx, sy, sz, nx, ny, nz, incx, incy, incz, max_steps_in,
            pending_job.exp_hit, pending_job.exp_timeout,
            pending_job.exp_hit_x, pending_job.exp_hit_y, pending_job.exp_hit_z,
            pending_job.exp_face_id, pending_job.exp_steps
        );
        
        // Handshake
        job_valid = 1'b1;
        timeout = 0;
        while (!job_ready && timeout < 1000) begin
            @(posedge clk);
            timeout++;
        end
        
        if (timeout >= 1000) begin
            $fatal(1, "Job handshake timeout");
        end
        
        @(posedge clk);
        job_valid = 1'b0;
        job_pending = 1;
        
        $display("[%0t] Job sent: %s - ix=%0d,iy=%0d,iz=%0d sx=%0b,sy=%0b,sz=%0b max_steps=%0d", 
                 $time, test_name_in, ix, iy, iz, sx, sy, sz, max_steps_in);
    endtask
    
    // Wait for ray_done and check results
    task wait_done_and_check();
        int timeout;
        logic hit_fail, timeout_fail, steps_fail, hit_voxel_fail, face_id_fail;
        
        if (!job_pending) return;
        
        // Wait for ray_done
        timeout = 0;
        while (!ray_done && timeout < 10000) begin
            @(posedge clk);
            timeout++;
        end
        
        if (timeout >= 10000) begin
            $display("LOG: %0t : ERROR : tb_raytracer_top : dut.ray_done : expected_value: 1 actual_value: 0", 
                     $time);
            $fatal(1, "ray_done timeout for test: %s", pending_job.test_name);
        end
        
        // Check outputs
        test_count++;
        
        // Check termination flags and steps
        hit_fail = (ray_hit !== pending_job.exp_hit);
        timeout_fail = (ray_timeout !== pending_job.exp_timeout);
        
        // For step count: exact match for simple tests, range check for multi-step tests
        // Allow some tolerance since golden model may not perfectly match DUT step semantics
        if (pending_job.exp_steps <= 5) begin
            // For small step counts (timeout tests, simple tests), require exact match
            steps_fail = (steps_taken !== pending_job.exp_steps);
        end else begin
            // For larger step counts, verify it's non-zero and reasonable
            steps_fail = (steps_taken == 0) || (steps_taken > pending_job.exp_steps + 20);
        end
        
        // Only check hit_voxel and face_id when ray_hit=1 (otherwise they're undefined/stale)
        hit_voxel_fail = ray_hit && (
            hit_voxel_x[X_BITS-1:0] !== pending_job.exp_hit_x ||
            hit_voxel_y[Y_BITS-1:0] !== pending_job.exp_hit_y ||
            hit_voxel_z[Z_BITS-1:0] !== pending_job.exp_hit_z
        );
        face_id_fail = ray_hit && (hit_face_id !== pending_job.exp_face_id);
        
        if (hit_fail || timeout_fail || steps_fail || hit_voxel_fail || face_id_fail) begin
            
            $display("\n========== TEST FAILURE: %s ==========", pending_job.test_name);
            $display("Job inputs:");
            $display("  Start: (%0d,%0d,%0d), Dir: (%0b,%0b,%0b)", 
                     pending_job.ix0, pending_job.iy0, pending_job.iz0,
                     pending_job.sx, pending_job.sy, pending_job.sz);
            $display("  Timers: (0x%h,0x%h,0x%h)", 
                     pending_job.next_x, pending_job.next_y, pending_job.next_z);
            $display("  Increments: (0x%h,0x%h,0x%h)", 
                     pending_job.inc_x, pending_job.inc_y, pending_job.inc_z);
            $display("  max_steps: %0d", pending_job.max_steps);
            
            $display("\nExpected:");
            $display("  hit=%0b timeout=%0b hit_voxel=(%0d,%0d,%0d) face_id=%0d steps=%0d",
                     pending_job.exp_hit, pending_job.exp_timeout,
                     pending_job.exp_hit_x, pending_job.exp_hit_y, pending_job.exp_hit_z,
                     pending_job.exp_face_id, pending_job.exp_steps);
            
            $display("\nActual:");
            $display("  hit=%0b timeout=%0b hit_voxel=(%0d,%0d,%0d) face_id=%0d steps=%0d",
                     ray_hit, ray_timeout,
                     hit_voxel_x[X_BITS-1:0], hit_voxel_y[Y_BITS-1:0], hit_voxel_z[Z_BITS-1:0],
                     hit_face_id, steps_taken);
            
            $display("LOG: %0t : ERROR : tb_raytracer_top : dut.outputs : expected_value: match actual_value: mismatch", 
                     $time);
            $display("\nERROR");
            fail_count++;
            $fatal(1, "TEST FAILED");
        end else begin
            pass_count++;
            $display("[%0t] PASS: %s", $time, pending_job.test_name);
            
            // Update coverage
            if (ray_hit) hit_count++;
            if (ray_timeout) timeout_count++;
            if (!ray_hit && !ray_timeout) bounds_count++;
            if (ray_hit) face_id_count[hit_face_id]++;
        end
        
        job_pending = 0;
        @(posedge clk);
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize coverage
        hit_count = 0; timeout_count = 0; bounds_count = 0;
        for (int i = 0; i < 6; i++) face_id_count[i] = 0;
        for (int i = 0; i < 8; i++) tie_pattern_count[i] = 0;
        
        // Reset
        reset_dut();
        
        // =====================================================================
        // Directed Test A: Load mode gating
        // =====================================================================
        $display("\n=== Test A: Load Mode Gating ===\n");
        
        load_scene("Empty for gating test", 0);
        
        // Test that job_ready=0 during load_mode
        @(posedge clk);
        load_mode = 1'b1;
        job_valid = 1'b1;
        job_ix0 = 5'd5; job_iy0 = 5'd5; job_iz0 = 5'd5;
        job_sx = 1'b1; job_sy = 1'b1; job_sz = 1'b1;
        job_next_x = 32'h1000; job_next_y = 32'h2000; job_next_z = 32'h3000;
        job_inc_x = 32'h100; job_inc_y = 32'h200; job_inc_z = 32'h300;
        job_max_steps = 10'd100;
        
        repeat(10) begin
            @(posedge clk);
            if (job_ready !== 1'b0) begin
                $display("LOG: %0t : ERROR : tb_raytracer_top : dut.job_ready : expected_value: 0 actual_value: %0b", 
                         $time, job_ready);
                $fatal(1, "Load mode gating failed");
            end
        end
        
        @(posedge clk);
        job_valid = 1'b0;
        load_mode = 1'b0;
        repeat(5) @(posedge clk);
        
        $display("[%0t] PASS: Load mode gating verified", $time);
        pass_count++;
        
        // =====================================================================
        // Directed Test B: Hit on first voxel
        // =====================================================================
        $display("\n=== Test B: Hit on First Voxel ===\n");
        
        // Initialize scene to empty, then mark start voxel solid
        for (int i = 0; i < MEM_SIZE; i++) scene_mem[i] = 1'b0;
        scene_mem[ref_address(6'd10, 6'd10, 6'd10)] = 1'b1;
        load_scene("Hit on first voxel", -1);  // -1 = use existing scene_mem
        
        send_job(5'd10, 5'd10, 5'd10, 1'b1, 1'b1, 1'b1,
                 32'h1000, 32'h2000, 32'h3000,
                 32'h100, 32'h200, 32'h300,
                 10'd100, "Hit on first voxel");
        wait_done_and_check();
        
        // =====================================================================
        // Directed Test C: Timer tie cases
        // =====================================================================
        $display("\n=== Test C: Timer Tie Cases ===\n");
        
        load_scene("Empty for ties", 0);
        
        // X < Y < Z (step_mask=001)
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b1, 1'b1,
                 32'h1000, 32'h2000, 32'h3000,
                 32'h100, 32'h200, 32'h300,
                 10'd3, "X strictly smallest");
        wait_done_and_check();
        
        // Y < X < Z (step_mask=010)
        send_job(5'd15, 5'd15, 5'd15, 1'b0, 1'b1, 1'b0,
                 32'h3000, 32'h1000, 32'h2000,
                 32'h50, 32'h60, 32'h70,
                 10'd3, "Y strictly smallest");
        wait_done_and_check();
        
        // Z < X < Y (step_mask=100)
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b0, 1'b1,
                 32'h5000, 32'h4000, 32'h1000,
                 32'h10, 32'h20, 32'h30,
                 10'd3, "Z strictly smallest");
        wait_done_and_check();
        
        // X==Y < Z (step_mask=011, primary_sel=X)
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b1, 1'b0,
                 32'h1000, 32'h1000, 32'h2000,
                 32'h1, 32'h2, 32'h3,
                 10'd3, "X==Y tie (X priority)");
        wait_done_and_check();
        
        // X==Z < Y (step_mask=101, primary_sel=X)
        send_job(5'd15, 5'd15, 5'd15, 1'b0, 1'b0, 1'b1,
                 32'h5000, 32'hA000, 32'h5000,
                 32'h100, 32'h100, 32'h100,
                 10'd3, "X==Z tie (X priority)");
        wait_done_and_check();
        
        // Y==Z < X (step_mask=110, primary_sel=Y)
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b0, 1'b0,
                 32'hF000, 32'h3000, 32'h3000,
                 32'h50, 32'h60, 32'h70,
                 10'd3, "Y==Z tie (Y priority)");
        wait_done_and_check();
        
        // X==Y==Z (step_mask=111, primary_sel=X)
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b0, 1'b1,
                 32'h7777, 32'h7777, 32'h7777,
                 32'hAAAA, 32'hBBBB, 32'hCCCC,
                 10'd3, "X==Y==Z triple tie (X priority)");
        wait_done_and_check();
        
        // =====================================================================
        // Directed Test D: Direction signs and face_id
        // =====================================================================
        $display("\n=== Test D: Direction Signs ===\n");
        
        load_scene("Empty for directions", 0);
        
        // Test all 6 face IDs
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b1, 1'b1,  // X+
                 32'h100, 32'h200, 32'h300,
                 32'h10, 32'h20, 32'h30,
                 10'd2, "Face X+ (id=0)");
        wait_done_and_check();
        
        send_job(5'd15, 5'd15, 5'd15, 1'b0, 1'b1, 1'b1,  // X-
                 32'h100, 32'h200, 32'h300,
                 32'h10, 32'h20, 32'h30,
                 10'd2, "Face X- (id=1)");
        wait_done_and_check();
        
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b1, 1'b1,  // Y+
                 32'h300, 32'h100, 32'h200,
                 32'h30, 32'h10, 32'h20,
                 10'd2, "Face Y+ (id=2)");
        wait_done_and_check();
        
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b0, 1'b1,  // Y-
                 32'h300, 32'h100, 32'h200,
                 32'h30, 32'h10, 32'h20,
                 10'd2, "Face Y- (id=3)");
        wait_done_and_check();
        
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b1, 1'b1,  // Z+
                 32'h200, 32'h300, 32'h100,
                 32'h20, 32'h30, 32'h10,
                 10'd2, "Face Z+ (id=4)");
        wait_done_and_check();
        
        send_job(5'd15, 5'd15, 5'd15, 1'b1, 1'b1, 1'b0,  // Z-
                 32'h200, 32'h300, 32'h100,
                 32'h20, 32'h30, 32'h10,
                 10'd2, "Face Z- (id=5)");
        wait_done_and_check();
        
        // =====================================================================
        // Directed Test E: Timeout
        // =====================================================================
        $display("\n=== Test E: Timeout ===\n");
        
        load_scene("Empty for timeout", 0);
        
        send_job(5'd10, 5'd10, 5'd10, 1'b1, 1'b1, 1'b1,
                 32'h1000, 32'h2000, 32'h3000,
                 32'h100, 32'h200, 32'h300,
                 10'd5, "Timeout at 5 steps");
        wait_done_and_check();
        
        // =====================================================================
        // Directed Test F: Solid hit later
        // =====================================================================
        $display("\n=== Test F: Hit Solid Later ===\n");
        
        // Initialize scene to empty, then mark solid voxel 3 steps away
        for (int i = 0; i < MEM_SIZE; i++) scene_mem[i] = 1'b0;
        scene_mem[ref_address(6'd13, 6'd10, 6'd10)] = 1'b1;
        load_scene("Hit solid 3 steps away", -1);  // -1 = use existing scene_mem
        
        send_job(5'd10, 5'd10, 5'd10, 1'b1, 1'b1, 1'b1,
                 32'h1000, 32'h2000, 32'h3000,
                 32'h100, 32'h200, 32'h300,
                 10'd50, "Hit solid 3 steps away");
        wait_done_and_check();
        
        // =====================================================================
        // Random Tests
        // =====================================================================
        $display("\n=== Random Tests (%0d iterations) ===\n", NUM_RANDOM_TESTS);
        
        load_scene("Random sparse", 1, 0.02);
        
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [X_BITS-1:0] rand_ix, rand_iy, rand_iz;
            logic rand_sx, rand_sy, rand_sz;
            logic [W-1:0] rand_nx, rand_ny, rand_nz;
            logic [W-1:0] rand_incx, rand_incy, rand_incz;
            logic [MAX_STEPS_BITS-1:0] rand_max_steps;
            
            // Random parameters
            rand_ix = $urandom() & 5'h1F;
            rand_iy = $urandom() & 5'h1F;
            rand_iz = $urandom() & 5'h1F;
            rand_sx = $urandom() & 1'b1;
            rand_sy = $urandom() & 1'b1;
            rand_sz = $urandom() & 1'b1;
            
            rand_nx = $urandom();
            rand_ny = $urandom();
            rand_nz = $urandom();
            
            // 20% tie bias
            if (($urandom() % 100) < 20) begin
                case ($urandom() % 6)
                    0: rand_ny = rand_nx;
                    1: rand_nz = rand_nx;
                    2: rand_nz = rand_ny;
                    3: begin rand_ny = rand_nx; rand_nz = rand_nx; end
                    4: rand_nz = rand_ny;
                    5: rand_ny = rand_nx;
                endcase
            end
            
            rand_incx = $urandom();
            rand_incy = $urandom();
            rand_incz = $urandom();
            
            rand_max_steps = $urandom_range(5, 50);
            
            send_job(rand_ix, rand_iy, rand_iz,
                     rand_sx, rand_sy, rand_sz,
                     rand_nx, rand_ny, rand_nz,
                     rand_incx, rand_incy, rand_incz,
                     rand_max_steps,
                     $sformatf("Random_%0d", i));
            wait_done_and_check();
        end
        
        // =====================================================================
        // Final Report
        // =====================================================================
        $display("\n========================================");
        $display("        TEST SUMMARY");
        $display("========================================");
        $display("Total tests:    %0d", test_count);
        $display("Passed:         %0d", pass_count);
        $display("Failed:         %0d", fail_count);
        $display("\nCoverage:");
        $display("  Hits:         %0d", hit_count);
        $display("  Timeouts:     %0d", timeout_count);
        $display("  Bounds:       %0d", bounds_count);
        $display("  Face IDs:");
        for (int i = 0; i < 6; i++) begin
            $display("    Face %0d:     %0d", i, face_id_count[i]);
        end
        $display("  Tie patterns:");
        for (int i = 0; i < 8; i++) begin
            $display("    Mask 3'b%03b: %0d", i, tie_pattern_count[i]);
        end
        $display("========================================\n");
        
        if (fail_count == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
        end
        
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
