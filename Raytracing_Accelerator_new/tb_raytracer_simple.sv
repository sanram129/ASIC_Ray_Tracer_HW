`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Simplified Comprehensive Testbench for Raytracer Top
// Compatible with Icarus Verilog (no unpacked structs)
// 
// Tests:
// - Basic ray tracing functionality
// - Edge cases (boundaries, immediate hits, timeouts)
// - 1000 random rays for robustness testing
// =============================================================================

module tb_raytracer_simple;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int COORD_WIDTH = 16;
    localparam int COORD_W = 6;
    localparam int TIMER_WIDTH = 32;
    localparam int W = 32;
    localparam int MAX_VAL = 31;
    localparam int ADDR_BITS = 15;
    localparam int X_BITS = 5;
    localparam int Y_BITS = 5;
    localparam int Z_BITS = 5;
    localparam int MAX_STEPS_BITS = 10;
    localparam int STEP_COUNT_WIDTH = 16;
    
    localparam int GRID_SIZE = 32;
    localparam real CLK_PERIOD = 10.0; // 10ns = 100MHz
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic clk, rst_n;
    
    // Job interface
    logic                          job_valid, job_ready;
    logic [X_BITS-1:0]             job_ix0;
    logic [Y_BITS-1:0]             job_iy0;
    logic [Z_BITS-1:0]             job_iz0;
    logic                          job_sx, job_sy, job_sz;
    logic [W-1:0]                  job_next_x, job_next_y, job_next_z;
    logic [W-1:0]                  job_inc_x, job_inc_y, job_inc_z;
    logic [MAX_STEPS_BITS-1:0]     job_max_steps;
    
    // Scene loading
    logic                          load_mode, load_valid, load_ready;
    logic [ADDR_BITS-1:0]          load_addr;
    logic                          load_data;
    logic [ADDR_BITS:0]            write_count;
    logic                          load_complete;
    
    // Results
    logic                          ray_done, ray_hit, ray_timeout;
    logic [COORD_WIDTH-1:0]        hit_voxel_x, hit_voxel_y, hit_voxel_z;
    logic [2:0]                    hit_face_id;
    logic [STEP_COUNT_WIDTH-1:0]   steps_taken;
    
    // =========================================================================
    // Test Infrastructure
    // =========================================================================
    bit voxel_grid [0:GRID_SIZE-1][0:GRID_SIZE-1][0:GRID_SIZE-1];
    int total_tests, passed_tests, failed_tests;
    
    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
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
    // Helper Tasks
    // =========================================================================
    
    task reset_dut();
        rst_n = 0;
        job_valid = 0;
        load_mode = 0;
        load_valid = 0;
        load_addr = 0;
        load_data = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("[%0t] Reset complete", $time);
    endtask
    
    task clear_grid();
        for (int x = 0; x < GRID_SIZE; x++) begin
            for (int y = 0; y < GRID_SIZE; y++) begin
                for (int z = 0; z < GRID_SIZE; z++) begin
                    voxel_grid[x][y][z] = 0;
                end
            end
        end
    endtask
    
    task set_voxel(int x, int y, int z, bit value);
        if (x >= 0 && x < GRID_SIZE && y >= 0 && y < GRID_SIZE && z >= 0 && z < GRID_SIZE) begin
            voxel_grid[x][y][z] = value;
        end
    endtask
    
    task load_scene();
        int addr, loaded;
        loaded = 0;
        $display("[%0t] Loading scene...", $time);
        load_mode = 1;
        
        for (int z = 0; z < GRID_SIZE; z++) begin
            for (int y = 0; y < GRID_SIZE; y++) begin
                for (int x = 0; x < GRID_SIZE; x++) begin
                    addr = (z << 10) | (y << 5) | x;
                    @(posedge clk);
                    load_addr = addr;
                    load_data = voxel_grid[x][y][z];
                    load_valid = 1;
                    wait(load_ready);
                    loaded++;
                end
            end
        end
        
        @(posedge clk);
        load_valid = 0;
        load_mode = 0;
        repeat(10) @(posedge clk);
        $display("[%0t] Scene loaded: %0d voxels", $time, loaded);
    endtask
    
    task submit_and_wait_ray(
        input int ix0, iy0, iz0,
        input bit sx, sy, sz,
        input int nx, ny, nz,
        input int incx, incy, incz,
        input int max_steps
    );
        int timeout_cycles;
        timeout_cycles = 0;
        
        // Wait for ready
        while (!job_ready && timeout_cycles < 1000) begin
            @(posedge clk);
            timeout_cycles++;
        end
        
        if (timeout_cycles >= 1000) begin
            $display("ERROR: job_ready timeout!");
            failed_tests++;
        end else begin
        
        // Submit job
        @(posedge clk);
        job_valid = 1;
        job_ix0 = ix0;
        job_iy0 = iy0;
        job_iz0 = iz0;
        job_sx = sx;
        job_sy = sy;
        job_sz = sz;
        job_next_x = nx;
        job_next_y = ny;
        job_next_z = nz;
        job_inc_x = incx;
        job_inc_y = incy;
        job_inc_z = incz;
        job_max_steps = max_steps;
        
        @(posedge clk);
        job_valid = 0;
        
        // Wait for result
        timeout_cycles = 0;
        while (!ray_done && timeout_cycles < 100000) begin
            @(posedge clk);
            timeout_cycles++;
        end
        
        if (timeout_cycles >= 100000) begin
            $display("ERROR: ray_done timeout!");
            failed_tests++;
        end
        end
        
        @(posedge clk);
    endtask
    
    // =========================================================================
    // Test Cases
    // =========================================================================
    
    task test_simple_x_ray();
        $display("\n[TEST 1] Simple X-axis ray");
        clear_grid();
        set_voxel(5, 0, 0, 1);
        load_scene();
        
        submit_and_wait_ray(0, 0, 0, 1, 1, 1, 100, 1000, 1000, 100, 200, 200, 100);
        
        if (ray_hit && hit_voxel_x == 5 && hit_voxel_y == 0 && hit_voxel_z == 0) begin
            $display("  PASS: Hit voxel at (5,0,0)");
            passed_tests++;
        end else begin
            $display("  FAIL: Expected hit at (5,0,0), got hit=%0b at (%0d,%0d,%0d)", 
                     ray_hit, hit_voxel_x, hit_voxel_y, hit_voxel_z);
            failed_tests++;
        end
        total_tests++;
    endtask
    
    task test_boundary();
        $display("\n[TEST 2] Boundary test");
        clear_grid();
        load_scene();
        
        submit_and_wait_ray(31, 31, 31, 1, 1, 1, 100, 100, 100, 100, 100, 100, 10);
        
        if (!ray_hit && !ray_timeout) begin
            $display("  PASS: Correctly went out of bounds");
            passed_tests++;
        end else begin
            $display("  FAIL: Expected out of bounds, got hit=%0b timeout=%0b", ray_hit, ray_timeout);
            failed_tests++;
        end
        total_tests++;
    endtask
    
    task test_immediate_hit();
        $display("\n[TEST 3] Immediate hit");
        clear_grid();
        set_voxel(10, 10, 10, 1);
        load_scene();
        
        submit_and_wait_ray(10, 10, 10, 1, 1, 1, 100, 100, 100, 100, 100, 100, 100);
        
        if (ray_hit && steps_taken == 0) begin
            $display("  PASS: Immediate hit detected");
            passed_tests++;
        end else begin
            $display("  FAIL: Expected immediate hit, got hit=%0b steps=%0d", ray_hit, steps_taken);
            failed_tests++;
        end
        total_tests++;
    endtask
    
    task test_timeout();
        $display("\n[TEST 4] Timeout");
        clear_grid();
        load_scene();
        
        submit_and_wait_ray(0, 0, 0, 1, 1, 1, 100, 200, 300, 100, 100, 100, 5);
        
        if (ray_timeout) begin
            $display("  PASS: Timeout detected after %0d steps", steps_taken);
            passed_tests++;
        end else begin
            $display("  FAIL: Expected timeout, got hit=%0b timeout=%0b", ray_hit, ray_timeout);
            failed_tests++;
        end
        total_tests++;
    endtask
    
    task test_diagonal();
        $display("\n[TEST 5] Diagonal ray");
        clear_grid();
        set_voxel(15, 15, 15, 1);
        load_scene();
        
        submit_and_wait_ray(0, 0, 0, 1, 1, 1, 100, 100, 100, 100, 100, 100, 50);
        
        if (ray_hit && hit_voxel_x == 15 && hit_voxel_y == 15 && hit_voxel_z == 15) begin
            $display("  PASS: Diagonal ray hit target");
            passed_tests++;
        end else begin
            $display("  FAIL: Expected hit at (15,15,15), got (%0d,%0d,%0d)", 
                     hit_voxel_x, hit_voxel_y, hit_voxel_z);
            failed_tests++;
        end
        total_tests++;
    endtask
    
    task run_random_tests(int num_tests);
        int pass_count;
        int rx, ry, rz, num_voxels;
        pass_count = 0;
        
        $display("\n[RANDOM TESTS] Running %0d tests...", num_tests);
        
        for (int test_num = 0; test_num < num_tests; test_num++) begin
            // Random scene
            clear_grid();
            num_voxels = $urandom_range(100, 500);
            for (int i = 0; i < num_voxels; i++) begin
                rx = $urandom_range(0, GRID_SIZE-1);
                ry = $urandom_range(0, GRID_SIZE-1);
                rz = $urandom_range(0, GRID_SIZE-1);
                set_voxel(rx, ry, rz, 1);
            end
            
            if (test_num % 10 == 0) load_scene();
            
            // Random ray
            submit_and_wait_ray(
                $urandom_range(0, GRID_SIZE-1),
                $urandom_range(0, GRID_SIZE-1),
                $urandom_range(0, GRID_SIZE-1),
                $urandom_range(0, 1),
                $urandom_range(0, 1),
                $urandom_range(0, 1),
                $urandom_range(100, 1000),
                $urandom_range(100, 1000),
                $urandom_range(100, 1000),
                $urandom_range(100, 500),
                $urandom_range(100, 500),
                $urandom_range(100, 500),
                $urandom_range(20, 100)
            );
            
            // Just check it completed without error
            if (ray_done) pass_count++;
            
            total_tests++;
            
            if ((test_num + 1) % 100 == 0) begin
                $display("  Progress: %0d / %0d", test_num + 1, num_tests);
            end
        end
        
        passed_tests += pass_count;
        $display("[RANDOM TESTS] Completed: %0d / %0d", pass_count, num_tests);
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        $display("=============================================================================");
        $display("Comprehensive Raytracer Verification");
        $display("Testing: Full integration with 5-stage pipeline and FSM");
        $display("=============================================================================\n");
        
        total_tests = 0;
        passed_tests = 0;
        failed_tests = 0;
        
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
        
        reset_dut();
        
        $display("=== EDGE CASE TESTS ===");
        // Edge case tests
        test_simple_x_ray();
        test_boundary();
        test_immediate_hit();
        test_timeout();
        test_diagonal();
        
        // Random tests
        run_random_tests(1000);
        
        // Final report
        $display("\n=============================================================================");
        $display("TEST SUMMARY");
        $display("=============================================================================");
        $display("Total tests:  %0d", total_tests);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);
        $display("=============================================================================");
        
        if (failed_tests == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100ms;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule

`default_nettype wire
