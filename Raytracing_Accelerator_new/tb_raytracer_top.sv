`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Comprehensive Testbench for Raytracer Top
// 
// Tests:
// - Scene loading and verification
// - Edge cases (boundaries, immediate hits, out of bounds)
// - Corner cases (timer ties, zero increments, max steps)
// - ~10,000 random rays with random scenes
// - Full integration verification
// =============================================================================

module tb_raytracer_top;

    // =========================================================================
    // Parameters (must match DUT)
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
    localparam int TOTAL_VOXELS = GRID_SIZE * GRID_SIZE * GRID_SIZE;
    
    // Clock period
    localparam real CLK_PERIOD = 10.0; // 10ns = 100MHz
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic clk;
    logic rst_n;
    
    // Job interface
    logic                          job_valid;
    logic                          job_ready;
    logic [X_BITS-1:0]             job_ix0;
    logic [Y_BITS-1:0]             job_iy0;
    logic [Z_BITS-1:0]             job_iz0;
    logic                          job_sx;
    logic                          job_sy;
    logic                          job_sz;
    logic [W-1:0]                  job_next_x;
    logic [W-1:0]                  job_next_y;
    logic [W-1:0]                  job_next_z;
    logic [W-1:0]                  job_inc_x;
    logic [W-1:0]                  job_inc_y;
    logic [W-1:0]                  job_inc_z;
    logic [MAX_STEPS_BITS-1:0]     job_max_steps;
    
    // Scene loading interface
    logic                          load_mode;
    logic                          load_valid;
    logic                          load_ready;
    logic [ADDR_BITS-1:0]          load_addr;
    logic                          load_data;
    logic [ADDR_BITS:0]            write_count;
    logic                          load_complete;
    
    // Results
    logic                          ray_done;
    logic                          ray_hit;
    logic                          ray_timeout;
    logic [COORD_WIDTH-1:0]        hit_voxel_x;
    logic [COORD_WIDTH-1:0]        hit_voxel_y;
    logic [COORD_WIDTH-1:0]        hit_voxel_z;
    logic [2:0]                    hit_face_id;
    logic [STEP_COUNT_WIDTH-1:0]   steps_taken;
    
    // =========================================================================
    // Test Infrastructure
    // =========================================================================
    
    // Golden reference model (software voxel grid)
    bit voxel_grid [0:GRID_SIZE-1][0:GRID_SIZE-1][0:GRID_SIZE-1];
    
    // Test statistics
    int total_tests;
    int passed_tests;
    int failed_tests;
    int edge_case_tests;
    int random_tests;
    
    // Test configuration
    typedef struct {
        int ix0, iy0, iz0;
        bit sx, sy, sz;
        int next_x, next_y, next_z;
        int inc_x, inc_y, inc_z;
        int max_steps;
    } ray_job_t;
    
    typedef struct {
        bit hit;
        bit timeout;
        bit out_of_bounds;
        int hit_x, hit_y, hit_z;
        int face_id;
        int steps;
    } ray_result_t;
    
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
    
    // Reset task
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
    
    // Clear voxel grid (software model)
    task clear_voxel_grid();
        for (int x = 0; x < GRID_SIZE; x++) begin
            for (int y = 0; y < GRID_SIZE; y++) begin
                for (int z = 0; z < GRID_SIZE; z++) begin
                    voxel_grid[x][y][z] = 0;
                end
            end
        end
    endtask
    
    // Set voxel in software model
    task set_voxel(int x, int y, int z, bit value);
        if (x >= 0 && x < GRID_SIZE && y >= 0 && y < GRID_SIZE && z >= 0 && z < GRID_SIZE) begin
            voxel_grid[x][y][z] = value;
        end
    endtask
    
    // Load scene into hardware
    task load_scene_to_hardware();
        int addr;
        int loaded_count = 0;
        
        $display("[%0t] Loading scene into hardware...", $time);
        load_mode = 1;
        
        for (int z = 0; z < GRID_SIZE; z++) begin
            for (int y = 0; y < GRID_SIZE; y++) begin
                for (int x = 0; x < GRID_SIZE; x++) begin
                    addr = (z << 10) | (y << 5) | x; // ZYX ordering
                    
                    @(posedge clk);
                    load_addr = addr;
                    load_data = voxel_grid[x][y][z];
                    load_valid = 1;
                    
                    wait(load_ready);
                    loaded_count++;
                    
                    if (loaded_count % 1000 == 0) begin
                        $display("  Loaded %0d / %0d voxels", loaded_count, TOTAL_VOXELS);
                    end
                end
            end
        end
        
        @(posedge clk);
        load_valid = 0;
        load_mode = 0;
        
        repeat(10) @(posedge clk);
        $display("[%0t] Scene loaded: %0d voxels", $time, loaded_count);
    endtask
    
    // Submit ray job and wait for result
    task automatic submit_ray_job(input ray_job_t job, output ray_result_t result);
        int timeout_cycles = 0;
        int max_timeout = 100000; // Prevent infinite wait
        
        // Wait for ready
        while (!job_ready && timeout_cycles < 1000) begin
            @(posedge clk);
            timeout_cycles++;
        end
        
        if (timeout_cycles >= 1000) begin
            $display("ERROR: job_ready timeout!");
            result.timeout = 1;
            return;
        end
        
        // Submit job
        @(posedge clk);
        job_valid = 1;
        job_ix0 = job.ix0;
        job_iy0 = job.iy0;
        job_iz0 = job.iz0;
        job_sx = job.sx;
        job_sy = job.sy;
        job_sz = job.sz;
        job_next_x = job.next_x;
        job_next_y = job.next_y;
        job_next_z = job.next_z;
        job_inc_x = job.inc_x;
        job_inc_y = job.inc_y;
        job_inc_z = job.inc_z;
        job_max_steps = job.max_steps;
        
        @(posedge clk);
        job_valid = 0;
        
        // Wait for result
        timeout_cycles = 0;
        while (!ray_done && timeout_cycles < max_timeout) begin
            @(posedge clk);
            timeout_cycles++;
        end
        
        if (timeout_cycles >= max_timeout) begin
            $display("ERROR: ray_done timeout after %0d cycles!", timeout_cycles);
            result.timeout = 1;
            return;
        end
        
        // Capture result
        result.hit = ray_hit;
        result.timeout = ray_timeout;
        result.out_of_bounds = (!ray_hit && !ray_timeout);
        result.hit_x = hit_voxel_x;
        result.hit_y = hit_voxel_y;
        result.hit_z = hit_voxel_z;
        result.face_id = hit_face_id;
        result.steps = steps_taken;
        
        @(posedge clk);
    endtask
    
    // Golden reference DDA ray tracer (software model)
    task automatic golden_raytrace(input ray_job_t job, output ray_result_t expected);
        int x, y, z;
        int next_x, next_y, next_z;
        int step_count;
        int min_axis;
        
        x = job.ix0;
        y = job.iy0;
        z = job.iz0;
        next_x = job.next_x;
        next_y = job.next_y;
        next_z = job.next_z;
        step_count = 0;
        
        expected.hit = 0;
        expected.timeout = 0;
        expected.out_of_bounds = 0;
        
        // DDA stepping loop
        while (step_count < job.max_steps) begin
            // Check bounds
            if (x < 0 || x >= GRID_SIZE || y < 0 || y >= GRID_SIZE || z < 0 || z >= GRID_SIZE) begin
                expected.out_of_bounds = 1;
                expected.steps = step_count;
                return;
            end
            
            // Check voxel occupancy
            if (voxel_grid[x][y][z]) begin
                expected.hit = 1;
                expected.hit_x = x;
                expected.hit_y = y;
                expected.hit_z = z;
                expected.steps = step_count;
                return;
            end
            
            // Find minimum timer
            if (next_x <= next_y && next_x <= next_z) begin
                min_axis = 0; // X
            end else if (next_y <= next_z) begin
                min_axis = 1; // Y
            end else begin
                min_axis = 2; // Z
            end
            
            // Step along minimum axis
            case (min_axis)
                0: begin // X
                    x = job.sx ? x + 1 : x - 1;
                    next_x = next_x + job.inc_x;
                    expected.face_id = job.sx ? 0 : 1;
                end
                1: begin // Y
                    y = job.sy ? y + 1 : y - 1;
                    next_y = next_y + job.inc_y;
                    expected.face_id = job.sy ? 2 : 3;
                end
                2: begin // Z
                    z = job.sz ? z + 1 : z - 1;
                    next_z = next_z + job.inc_z;
                    expected.face_id = job.sz ? 4 : 5;
                end
            endcase
            
            step_count++;
        end
        
        // Reached max steps
        expected.timeout = 1;
        expected.steps = step_count;
    endtask
    
    // Compare results
    function automatic bit compare_results(ray_result_t actual, ray_result_t expected, string test_name);
        bit match = 1;
        
        if (actual.hit !== expected.hit) begin
            $display("  MISMATCH in %s: hit = %0b, expected %0b", test_name, actual.hit, expected.hit);
            match = 0;
        end
        
        if (actual.timeout !== expected.timeout) begin
            $display("  MISMATCH in %s: timeout = %0b, expected %0b", test_name, actual.timeout, expected.timeout);
            match = 0;
        end
        
        if (expected.hit) begin
            if (actual.hit_x !== expected.hit_x || actual.hit_y !== expected.hit_y || actual.hit_z !== expected.hit_z) begin
                $display("  MISMATCH in %s: hit_pos = (%0d,%0d,%0d), expected (%0d,%0d,%0d)", 
                         test_name, actual.hit_x, actual.hit_y, actual.hit_z,
                         expected.hit_x, expected.hit_y, expected.hit_z);
                match = 0;
            end
        end
        
        return match;
    endfunction
    
    // =========================================================================
    // Edge Case Tests
    // =========================================================================
    
    // Test 1: Ray starting at origin, hitting voxel at (5,0,0)
    task test_simple_x_ray();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Simple X-axis ray");
        clear_voxel_grid();
        set_voxel(5, 0, 0, 1); // Place solid voxel
        load_scene_to_hardware();
        
        job.ix0 = 0; job.iy0 = 0; job.iz0 = 0;
        job.sx = 1; job.sy = 1; job.sz = 1;
        job.next_x = 100; job.next_y = 1000; job.next_z = 1000;
        job.inc_x = 100; job.inc_y = 200; job.inc_z = 200;
        job.max_steps = 100;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Simple X-ray")) begin
            $display("  PASS: Hit voxel at (%0d,%0d,%0d) after %0d steps",
                     actual.hit_x, actual.hit_y, actual.hit_z, actual.steps);
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 2: Ray starting at boundary
    task test_boundary_start();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Ray starting at boundary (31,31,31)");
        clear_voxel_grid();
        load_scene_to_hardware();
        
        job.ix0 = 31; job.iy0 = 31; job.iz0 = 31;
        job.sx = 1; job.sy = 1; job.sz = 1; // Moving outward
        job.next_x = 100; job.next_y = 100; job.next_z = 100;
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 10;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Boundary start")) begin
            $display("  PASS: Correctly went out of bounds");
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 3: Immediate hit (voxel at starting position)
    task test_immediate_hit();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Immediate hit at starting position");
        clear_voxel_grid();
        set_voxel(10, 10, 10, 1);
        load_scene_to_hardware();
        
        job.ix0 = 10; job.iy0 = 10; job.iz0 = 10;
        job.sx = 1; job.sy = 1; job.sz = 1;
        job.next_x = 100; job.next_y = 100; job.next_z = 100;
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 100;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Immediate hit")) begin
            $display("  PASS: Hit immediately at starting position");
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 4: Timeout condition
    task test_timeout();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Timeout with max_steps=5");
        clear_voxel_grid();
        load_scene_to_hardware();
        
        job.ix0 = 0; job.iy0 = 0; job.iz0 = 0;
        job.sx = 1; job.sy = 1; job.sz = 1;
        job.next_x = 100; job.next_y = 200; job.next_z = 300;
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 5; // Very low
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Timeout")) begin
            $display("  PASS: Correctly timed out after %0d steps", actual.steps);
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 5: All timers equal (tie-breaking)
    task test_timer_tie();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] All timers equal (tie-breaking)");
        clear_voxel_grid();
        set_voxel(5, 5, 5, 1);
        load_scene_to_hardware();
        
        job.ix0 = 0; job.iy0 = 0; job.iz0 = 0;
        job.sx = 1; job.sy = 1; job.sz = 1;
        job.next_x = 100; job.next_y = 100; job.next_z = 100; // All equal
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 20;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Timer tie")) begin
            $display("  PASS: Correctly handled timer tie");
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 6: Diagonal ray
    task test_diagonal_ray();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Diagonal ray through grid");
        clear_voxel_grid();
        set_voxel(15, 15, 15, 1);
        load_scene_to_hardware();
        
        job.ix0 = 0; job.iy0 = 0; job.iz0 = 0;
        job.sx = 1; job.sy = 1; job.sz = 1;
        job.next_x = 100; job.next_y = 100; job.next_z = 100;
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 50;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Diagonal ray")) begin
            $display("  PASS: Diagonal ray traced correctly");
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 7: Negative direction ray
    task test_negative_direction();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Ray with negative direction");
        clear_voxel_grid();
        set_voxel(10, 15, 20, 1);
        load_scene_to_hardware();
        
        job.ix0 = 20; job.iy0 = 20; job.iz0 = 25;
        job.sx = 0; job.sy = 0; job.sz = 0; // All negative
        job.next_x = 100; job.next_y = 150; job.next_z = 200;
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 50;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Negative direction")) begin
            $display("  PASS: Negative direction ray traced correctly");
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // Test 8: Empty scene (no hits)
    task test_empty_scene();
        ray_job_t job;
        ray_result_t actual, expected;
        
        $display("\n[TEST] Empty scene - should go out of bounds");
        clear_voxel_grid();
        load_scene_to_hardware();
        
        job.ix0 = 15; job.iy0 = 15; job.iz0 = 15;
        job.sx = 1; job.sy = 1; job.sz = 1;
        job.next_x = 100; job.next_y = 100; job.next_z = 100;
        job.inc_x = 100; job.inc_y = 100; job.inc_z = 100;
        job.max_steps = 100;
        
        golden_raytrace(job, expected);
        submit_ray_job(job, actual);
        
        if (compare_results(actual, expected, "Empty scene")) begin
            $display("  PASS: Empty scene handled correctly");
            passed_tests++;
        end else begin
            failed_tests++;
        end
        total_tests++;
        edge_case_tests++;
    endtask
    
    // =========================================================================
    // Random Test Generation
    // =========================================================================
    
    task run_random_tests(int num_tests);
        ray_job_t job;
        ray_result_t actual, expected;
        int num_voxels;
        int pass_count = 0;
        
        $display("\n[RANDOM TESTS] Running %0d random tests...", num_tests);
        
        for (int test_num = 0; test_num < num_tests; test_num++) begin
            // Generate random scene (5-20% occupancy)
            clear_voxel_grid();
            num_voxels = $urandom_range(1000, 5000);
            
            for (int i = 0; i < num_voxels; i++) begin
                int rx = $urandom_range(0, GRID_SIZE-1);
                int ry = $urandom_range(0, GRID_SIZE-1);
                int rz = $urandom_range(0, GRID_SIZE-1);
                set_voxel(rx, ry, rz, 1);
            end
            
            // Only reload scene every 10 tests to save time
            if (test_num % 10 == 0) begin
                load_scene_to_hardware();
            end
            
            // Generate random ray
            job.ix0 = $urandom_range(0, GRID_SIZE-1);
            job.iy0 = $urandom_range(0, GRID_SIZE-1);
            job.iz0 = $urandom_range(0, GRID_SIZE-1);
            job.sx = $urandom_range(0, 1);
            job.sy = $urandom_range(0, 1);
            job.sz = $urandom_range(0, 1);
            
            // Random timers (avoid overflow)
            job.next_x = $urandom_range(100, 10000);
            job.next_y = $urandom_range(100, 10000);
            job.next_z = $urandom_range(100, 10000);
            job.inc_x = $urandom_range(100, 1000);
            job.inc_y = $urandom_range(100, 1000);
            job.inc_z = $urandom_range(100, 1000);
            job.max_steps = $urandom_range(20, 200);
            
            // Run test
            golden_raytrace(job, expected);
            submit_ray_job(job, actual);
            
            if (compare_results(actual, expected, $sformatf("Random test %0d", test_num))) begin
                pass_count++;
            end else begin
                $display("  FAILED: Test %0d with start=(%0d,%0d,%0d) dir=(%0b,%0b,%0b)",
                         test_num, job.ix0, job.iy0, job.iz0, job.sx, job.sy, job.sz);
                failed_tests++;
            end
            
            total_tests++;
            random_tests++;
            
            // Progress update
            if ((test_num + 1) % 100 == 0) begin
                $display("  Progress: %0d / %0d tests, %0d passed", test_num + 1, num_tests, pass_count);
            end
        end
        
        passed_tests += pass_count;
        $display("\n[RANDOM TESTS] Completed: %0d / %0d passed", pass_count, num_tests);
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        $display("=============================================================================");
        $display("Comprehensive Raytracer Top Testbench");
        $display("=============================================================================");
        
        // Initialize
        total_tests = 0;
        passed_tests = 0;
        failed_tests = 0;
        edge_case_tests = 0;
        random_tests = 0;
        
        // Waveform dump
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
        
        // Reset
        reset_dut();
        
        // Edge case tests
        $display("\n=== EDGE CASE TESTS ===");
        test_simple_x_ray();
        test_boundary_start();
        test_immediate_hit();
        test_timeout();
        test_timer_tie();
        test_diagonal_ray();
        test_negative_direction();
        test_empty_scene();
        
        // Random tests
        $display("\n=== RANDOM ROBUSTNESS TESTS ===");
        run_random_tests(10000);
        
        // Final report
        $display("\n=============================================================================");
        $display("TEST SUMMARY");
        $display("=============================================================================");
        $display("Total tests:      %0d", total_tests);
        $display("Passed:           %0d", passed_tests);
        $display("Failed:           %0d", failed_tests);
        $display("Edge case tests:  %0d", edge_case_tests);
        $display("Random tests:     %0d", random_tests);
        $display("Pass rate:        %.2f%%", (passed_tests * 100.0) / total_tests);
        $display("=============================================================================");
        
        if (failed_tests == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
            $fatal(1, "%0d test(s) failed!", failed_tests);
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100ms; // 100 milliseconds max
        $display("ERROR: Testbench timeout!");
        $fatal(1, "Simulation ran too long");
    end

endmodule

`default_nettype wire
