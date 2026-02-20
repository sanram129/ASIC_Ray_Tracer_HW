`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Bug Fix Verification Testbench
// Tests the two critical bug fixes:
//   Bug #1: Bounds detection (6-bit coordinates, no wrapping)
//   Bug #2: Face ID latching on hit
// =============================================================================

module tb_bugfix_verification;

    // Parameters
    localparam int COORD_WIDTH = 16;
    localparam int COORD_W = 6;
    localparam int TIMER_WIDTH = 32;
    localparam int W = 32;
    localparam int MAX_VAL = 31;
    localparam int ADDR_BITS = 15;
    localparam int X_BITS = 6;  // 6-bit for bounds detection
    localparam int Y_BITS = 6;
    localparam int Z_BITS = 6;
    localparam int MAX_STEPS_BITS = 10;
    localparam int STEP_COUNT_WIDTH = 16;
    localparam int GRID_SIZE = 32;
    localparam real CLK_PERIOD = 10.0;
    
    // DUT signals
    logic clk, rst_n;
    logic job_valid, job_ready;
    logic [X_BITS-1:0] job_ix0, job_iy0, job_iz0;
    logic job_sx, job_sy, job_sz;
    logic [W-1:0] job_next_x, job_next_y, job_next_z;
    logic [W-1:0] job_inc_x, job_inc_y, job_inc_z;
    logic [MAX_STEPS_BITS-1:0] job_max_steps;
    logic load_mode, load_valid, load_ready;
    logic [ADDR_BITS-1:0] load_addr;
    logic load_data;
    logic [ADDR_BITS:0] write_count;
    logic load_complete;
    logic ray_done, ray_hit, ray_timeout;
    logic [COORD_WIDTH-1:0] hit_voxel_x, hit_voxel_y, hit_voxel_z;
    logic [2:0] hit_face_id;
    logic [STEP_COUNT_WIDTH-1:0] steps_taken;
    
    // Test infrastructure
    bit voxel_grid [0:GRID_SIZE-1][0:GRID_SIZE-1][0:GRID_SIZE-1];
    int tests_passed, tests_failed;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT instantiation
    raytracer_top #(
        .COORD_WIDTH(COORD_WIDTH), .COORD_W(COORD_W),
        .TIMER_WIDTH(TIMER_WIDTH), .W(W),
        .MAX_VAL(MAX_VAL), .ADDR_BITS(ADDR_BITS),
        .X_BITS(X_BITS), .Y_BITS(Y_BITS), .Z_BITS(Z_BITS),
        .MAX_STEPS_BITS(MAX_STEPS_BITS),
        .STEP_COUNT_WIDTH(STEP_COUNT_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .job_valid(job_valid), .job_ready(job_ready),
        .job_ix0(job_ix0), .job_iy0(job_iy0), .job_iz0(job_iz0),
        .job_sx(job_sx), .job_sy(job_sy), .job_sz(job_sz),
        .job_next_x(job_next_x), .job_next_y(job_next_y), .job_next_z(job_next_z),
        .job_inc_x(job_inc_x), .job_inc_y(job_inc_y), .job_inc_z(job_inc_z),
        .job_max_steps(job_max_steps),
        .load_mode(load_mode), .load_valid(load_valid), .load_ready(load_ready),
        .load_addr(load_addr), .load_data(load_data),
        .write_count(write_count), .load_complete(load_complete),
        .ray_done(ray_done), .ray_hit(ray_hit), .ray_timeout(ray_timeout),
        .hit_voxel_x(hit_voxel_x), .hit_voxel_y(hit_voxel_y), .hit_voxel_z(hit_voxel_z),
        .hit_face_id(hit_face_id), .steps_taken(steps_taken)
    );
    
    // Helper tasks
    task reset_dut();
        rst_n = 0; job_valid = 0; load_mode = 0; load_valid = 0;
        load_addr = 0; load_data = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("[%0t] Reset complete", $time);
    endtask
    
    task clear_grid();
        for (int x = 0; x < GRID_SIZE; x++)
            for (int y = 0; y < GRID_SIZE; y++)
                for (int z = 0; z < GRID_SIZE; z++)
                    voxel_grid[x][y][z] = 0;
    endtask
    
    task load_scene();
        int addr;
        load_mode = 1;
        for (int z = 0; z < GRID_SIZE; z++)
            for (int y = 0; y < GRID_SIZE; y++)
                for (int x = 0; x < GRID_SIZE; x++) begin
                    addr = (z << 10) | (y << 5) | x;
                    @(posedge clk);
                    load_addr = addr;
                    load_data = voxel_grid[x][y][z];
                    load_valid = 1;
                    wait(load_ready);
                end
        @(posedge clk);
        load_valid = 0; load_mode = 0;
        repeat(10) @(posedge clk);
    endtask
    
    task trace_ray(
        input int ix, iy, iz, input bit sx, sy, sz,
        input int nx, ny, nz, input int incx, incy, incz, input int max_steps
    );
        int timeout = 0;
        while (!job_ready && timeout < 1000) begin @(posedge clk); timeout++; end
        @(posedge clk);
        job_valid = 1;
        job_ix0 = ix; job_iy0 = iy; job_iz0 = iz;
        job_sx = sx; job_sy = sy; job_sz = sz;
        job_next_x = nx; job_next_y = ny; job_next_z = nz;
        job_inc_x = incx; job_inc_y = incy; job_inc_z = incz;
        job_max_steps = max_steps;
        @(posedge clk);
        job_valid = 0;
        timeout = 0;
        while (!ray_done && timeout < 50000) begin @(posedge clk); timeout++; end
        @(posedge clk);
    endtask
    
    // Main test
    initial begin
        $display("TEST START");
        $display("=============================================================================");
        $display("Bug Fix Verification Testbench");
        $display("Testing: Bug #1 (Bounds) and Bug #2 (Face ID)");
        $display("=============================================================================\n");
        
        tests_passed = 0;
        tests_failed = 0;
        
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
        
        reset_dut();
        
        // =====================================================================
        // BUG #1 TEST: Bounds Detection (No Wrapping)
        // =====================================================================
        $display("\n[BUG #1 TEST] Out-of-bounds detection");
        $display("  Ray from (31,15,15) moving in +X direction");
        $display("  Should exit at boundary, NOT wrap to (0,15,15)");
        
        clear_grid();
        voxel_grid[0][15][15] = 1;  // Place solid at wrap position
        load_scene();
        
        trace_ray(31, 15, 15, 1, 1, 1, 100, 1000, 1000, 100, 200, 200, 10);
        
        if (!ray_hit && !ray_timeout) begin
            $display("  ✓ PASS: Ray correctly exited bounds (no wrap-around)");
            $display("    ray_hit=%0b, ray_timeout=%0b", ray_hit, ray_timeout);
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Ray should have exited bounds");
            $display("    ray_hit=%0b (should be 0), ray_timeout=%0b", ray_hit, ray_timeout);
            if (ray_hit) $display("    Hit at (%0d,%0d,%0d) - wrapped!", hit_voxel_x, hit_voxel_y, hit_voxel_z);
            tests_failed++;
        end
        
        // =====================================================================
        // BUG #1 TEST: Negative Direction Bounds
        // =====================================================================
        $display("\n[BUG #1 TEST] Negative direction bounds");
        $display("  Ray from (0,15,15) moving in -X direction");
        $display("  Should exit at boundary, NOT wrap to (31,15,15)");
        
        clear_grid();
        voxel_grid[31][15][15] = 1;  // Place solid at wrap position
        load_scene();
        
        trace_ray(0, 15, 15, 0, 1, 1, 100, 1000, 1000, 100, 200, 200, 10);
        
        if (!ray_hit && !ray_timeout) begin
            $display("  ✓ PASS: Ray correctly exited bounds in negative direction");
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Ray should have exited bounds");
            if (ray_hit) $display("    Hit at (%0d,%0d,%0d) - wrapped!", hit_voxel_x, hit_voxel_y, hit_voxel_z);
            tests_failed++;
        end
        
        // =====================================================================
        // BUG #2 TEST: Face ID Latching on Hit
        // =====================================================================
        $display("\n[BUG #2 TEST] Face ID correct on hit");
        $display("  Ray from (10,10,10) moving in +X, hitting voxel at (15,10,10)");
        $display("  Expected face_id: 0 (X+ face)");
        
        clear_grid();
        voxel_grid[15][10][10] = 1;
        load_scene();
        
        trace_ray(10, 10, 10, 1, 1, 1, 100, 1000, 1000, 100, 200, 200, 50);
        
        if (ray_hit && hit_voxel_x == 15 && hit_face_id == 3'd0) begin
            $display("  ✓ PASS: Correct face_id=0 (X+ face) for X-axis ray");
            $display("    Hit at (%0d,%0d,%0d), face_id=%0d", hit_voxel_x, hit_voxel_y, hit_voxel_z, hit_face_id);
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Incorrect face_id");
            $display("    Expected face_id=0, got face_id=%0d", hit_face_id);
            $display("    Hit at (%0d,%0d,%0d)", hit_voxel_x, hit_voxel_y, hit_voxel_z);
            tests_failed++;
        end
        
        // =====================================================================
        // BUG #2 TEST: Y-axis Face ID
        // =====================================================================
        $display("\n[BUG #2 TEST] Y-axis face ID");
        $display("  Ray from (10,10,10) moving in +Y, hitting voxel at (10,18,10)");
        $display("  Expected face_id: 2 (Y+ face)");
        
        clear_grid();
        voxel_grid[10][18][10] = 1;
        load_scene();
        
        trace_ray(10, 10, 10, 1, 1, 1, 1000, 100, 1000, 200, 100, 200, 50);
        
        if (ray_hit && hit_voxel_y == 18 && hit_face_id == 3'd2) begin
            $display("  ✓ PASS: Correct face_id=2 (Y+ face) for Y-axis ray");
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Incorrect face_id for Y-axis ray");
            $display("    Expected face_id=2, got face_id=%0d", hit_face_id);
            tests_failed++;
        end
        
        // =====================================================================
        // BUG #2 TEST: Z-axis Face ID
        // =====================================================================
        $display("\n[BUG #2 TEST] Z-axis face ID");
        $display("  Ray from (10,10,10) moving in +Z, hitting voxel at (10,10,20)");
        $display("  Expected face_id: 4 (Z+ face)");
        
        clear_grid();
        voxel_grid[10][10][20] = 1;
        load_scene();
        
        // Verify voxel was loaded
        $display("  Scene check: voxel_grid[10][10][20] = %0b", voxel_grid[10][10][20]);
        
        // Make Z have much smaller timer to ensure Z-only stepping
        trace_ray(10, 10, 10, 1, 1, 1, 10000, 10000, 100, 2000, 2000, 50, 50);
        
        $display("  Result: ray_hit=%0b, ray_timeout=%0b, hit=(%0d,%0d,%0d), face=%0d, steps=%0d",
                 ray_hit, ray_timeout, hit_voxel_x, hit_voxel_y, hit_voxel_z, hit_face_id, steps_taken);
        
        if (ray_hit && hit_voxel_z == 20 && hit_face_id == 3'd4) begin
            $display("  ✓ PASS: Correct face_id=4 (Z+ face) for Z-axis ray");
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Incorrect result for Z-axis ray");
            $display("    ray_hit=%0b (expected 1), hit_voxel_z=%0d (expected 20), face_id=%0d (expected 4)", 
                     ray_hit, hit_voxel_z, hit_face_id);
            $display("    Full hit position: (%0d,%0d,%0d)", hit_voxel_x, hit_voxel_y, hit_voxel_z);
            tests_failed++;
        end
        
        // =====================================================================
        // INTEGRATION TEST: Immediate Hit Position & Face
        // =====================================================================
        $display("\n[INTEGRATION TEST] Immediate hit position and face");
        $display("  Ray starting AT solid voxel (12,12,12)");
        $display("  Should detect immediate hit with correct position");
        
        clear_grid();
        voxel_grid[12][12][12] = 1;
        load_scene();
        
        trace_ray(12, 12, 12, 1, 1, 1, 100, 100, 100, 100, 100, 100, 50);
        
        if (ray_hit && hit_voxel_x == 12 && hit_voxel_y == 12 && hit_voxel_z == 12 && steps_taken == 0) begin
            $display("  ✓ PASS: Immediate hit detected at correct position");
            $display("    Hit at (%0d,%0d,%0d), steps=%0d", hit_voxel_x, hit_voxel_y, hit_voxel_z, steps_taken);
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Immediate hit not detected correctly");
            $display("    Hit at (%0d,%0d,%0d), steps=%0d", hit_voxel_x, hit_voxel_y, hit_voxel_z, steps_taken);
            tests_failed++;
        end
        
        // =====================================================================
        // INTEGRATION TEST: Simple Path
        // =====================================================================
        $display("\n[INTEGRATION TEST] Simple straight-line path");
        $display("  Ray from (0,10,10) to (5,10,10) in +X");
        
        clear_grid();
        voxel_grid[5][10][10] = 1;
        load_scene();
        
        trace_ray(0, 10, 10, 1, 1, 1, 100, 1000, 1000, 100, 200, 200, 50);
        
        if (ray_hit && hit_voxel_x == 5 && hit_voxel_y == 10 && hit_voxel_z == 10 && hit_face_id == 0) begin
            $display("  ✓ PASS: Hit correct voxel with correct face");
            tests_passed++;
        end else begin
            $display("  ✗ FAIL: Incorrect hit");
            $display("    Expected: (5,10,10) face=0");
            $display("    Got: (%0d,%0d,%0d) face=%0d", hit_voxel_x, hit_voxel_y, hit_voxel_z, hit_face_id);
            tests_failed++;
        end
        
        // Final report
        $display("\n=============================================================================");
        $display("BUG FIX VERIFICATION SUMMARY");
        $display("=============================================================================");
        $display("Total tests:  %0d", tests_passed + tests_failed);
        $display("Passed:       %0d", tests_passed);
        $display("Failed:       %0d", tests_failed);
        $display("=============================================================================\n");
        
        if (tests_failed == 0) begin
            $display("TEST PASSED - ALL BUG FIXES VERIFIED!");
        end else begin
            $display("TEST FAILED - %0d bug(s) still present", tests_failed);
        end
        
        $finish;
    end
    
    initial begin
        #50ms;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule

`default_nettype wire
