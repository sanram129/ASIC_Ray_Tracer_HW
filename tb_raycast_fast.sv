// =============================================================================
// Testbench: tb_raycast_fast
// Description: Fast comprehensive testbench for voxel raycasting accelerator
//              Optimized to avoid full scene clears between tests
//              Tests DDA correctness, edge cases, backpressure
// =============================================================================

`timescale 1ns/1ps

module tb_raycast_fast;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter W = 24;
    parameter FRAC = 16;
    parameter SYNC_READ = 1;
    parameter CLK_PERIOD = 10;
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic        clock;
    logic        reset;
    
    // Scene loading
    logic        load_mode;
    logic        load_valid;
    logic        load_ready;
    logic [14:0] load_addr;
    logic        load_data;
    logic [14:0] load_count;
    logic        load_complete;
    
    // Ray job interface
    logic        job_valid;
    logic        job_ready;
    logic [4:0]  ix0, iy0, iz0;
    logic        sx, sy, sz;
    logic [W-1:0] next_x, next_y, next_z;
    logic [W-1:0] inc_x, inc_y, inc_z;
    logic [9:0]  max_steps;
    
    // Result interface
    logic        res_valid;
    logic        res_ready;
    logic        hit;
    logic [4:0]  hx, hy, hz;
    logic [2:0]  face_id;
    logic [9:0]  steps_taken;
    logic [3:0]  brightness;
    
    // =========================================================================
    // Test Control
    // =========================================================================
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    raycast_top #(
        .W(W),
        .SYNC_READ(SYNC_READ)
    ) dut (
        .clock         (clock),
        .reset         (reset),
        .load_mode     (load_mode),
        .load_valid    (load_valid),
        .load_ready    (load_ready),
        .load_addr     (load_addr),
        .load_data     (load_data),
        .load_count    (load_count),
        .load_complete (load_complete),
        .job_valid     (job_valid),
        .job_ready     (job_ready),
        .ix0           (ix0),
        .iy0           (iy0),
        .iz0           (iz0),
        .sx            (sx),
        .sy            (sy),
        .sz            (sz),
        .next_x        (next_x),
        .next_y        (next_y),
        .next_z        (next_z),
        .inc_x         (inc_x),
        .inc_y         (inc_y),
        .inc_z         (inc_z),
        .max_steps     (max_steps),
        .res_valid     (res_valid),
        .res_ready     (res_ready),
        .hit           (hit),
        .hx            (hx),
        .hy            (hy),
        .hz            (hz),
        .face_id       (face_id),
        .steps_taken   (steps_taken),
        .brightness    (brightness)
    );
    
    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clock = 0;
        forever #(CLK_PERIOD/2) clock = ~clock;
    end
    
    // =========================================================================
    // Helper Functions
    // =========================================================================
    
    // Compute linear address from (x,y,z)
    function automatic logic [14:0] addr_from_xyz(input logic [4:0] x, y, z);
        return {z, y, x};
    endfunction
    
    // Convert face_id to string
    function automatic string face_to_str(input logic [2:0] fid);
        case (fid)
            3'b000: return "+X";
            3'b001: return "-X";
            3'b010: return "+Y";
            3'b011: return "-Y";
            3'b100: return "+Z";
            3'b101: return "-Z";
            default: return "??";
        endcase
    endfunction
    
    // Expected brightness from face_id
    function automatic logic [3:0] expected_brightness(input logic [2:0] fid);
        case (fid)
            3'b000: return 4'd2;  // +X
            3'b001: return 4'd2;  // -X
            3'b010: return 4'd4;  // +Y
            3'b011: return 4'd1;  // -Y
            3'b100: return 4'd3;  // +Z
            3'b101: return 4'd3;  // -Z
            default: return 4'd0;
        endcase
    endfunction
    
    // =========================================================================
    // Scene Loading Tasks
    // =========================================================================
    
    // Load a single voxel (blocking assignment for TB)
    task load_voxel(input logic [4:0] x, y, z, input logic solid);
        logic [14:0] addr;
        addr = addr_from_xyz(x, y, z);
        @(posedge clock);
        load_valid = 1'b1;
        load_addr  = addr;
        load_data  = solid;
        @(posedge clock);
        while (!load_complete) @(posedge clock);
        load_valid = 1'b0;
        @(posedge clock);
    endtask
    
    // =========================================================================
    // Job Submission and Result Checking
    // =========================================================================
    
    // Submit a ray job (simplified axis-aligned helper)
    task submit_ray_axis_aligned(
        input logic [4:0] start_x, start_y, start_z,
        input logic [2:0] axis,  // 0=X, 1=Y, 2=Z
        input logic       dir,   // 1=positive, 0=negative
        input logic [9:0] max_s
    );
        logic [W-1:0] nx, ny, nz;
        logic [W-1:0] ix, iy, iz;
        
        // For axis-aligned rays, set increments to 1.0 in fixed point
        ix = (1 << FRAC);
        iy = (1 << FRAC);
        iz = (1 << FRAC);
        
        // Initial timers: axis being stepped gets 0.5, others get large value
        nx = (axis == 0) ? (1 << (FRAC-1)) : (1 << (FRAC+4));
        ny = (axis == 1) ? (1 << (FRAC-1)) : (1 << (FRAC+4));
        nz = (axis == 2) ? (1 << (FRAC-1)) : (1 << (FRAC+4));
        
        @(posedge clock);
        job_valid  = 1'b1;
        ix0        = start_x;
        iy0        = start_y;
        iz0        = start_z;
        sx         = (axis == 0) ? dir : 1'b1;
        sy         = (axis == 1) ? dir : 1'b1;
        sz         = (axis == 2) ? dir : 1'b1;
        next_x     = nx;
        next_y     = ny;
        next_z     = nz;
        inc_x      = ix;
        inc_y      = iy;
        inc_z      = iz;
        max_steps  = max_s;
        
        @(posedge clock);
        wait(job_ready);
        @(posedge clock);
        job_valid = 1'b0;
    endtask
    
    // Wait for result and check
    task automatic check_result(
        input logic       expect_hit,
        input logic [4:0] expect_x, expect_y, expect_z,
        input logic [2:0] expect_face,
        input string      test_name
    );
        logic [3:0] exp_bright;
        integer timeout_counter;
        
        test_count = test_count + 1;
        
        // Wait for result with timeout
        res_ready = 1'b1;
        @(posedge clock);
        timeout_counter = 0;
        while (!res_valid && timeout_counter < 1000) begin
            @(posedge clock);
            timeout_counter = timeout_counter + 1;
        end
        
        if (timeout_counter >= 1000) begin
            $display("LOG: %0t : ERROR : tb_raycast_fast : dut.res_valid : expected_value: 1 actual_value: 0", $time);
            $display("[FAIL] %s: Timeout waiting for result!", test_name);
            fail_count = fail_count + 1;
            res_ready = 1'b0;
            return;
        end
        
        @(posedge clock);
        
        exp_bright = expected_brightness(expect_face);
        
        // Check results
        if (hit !== expect_hit) begin
            $display("LOG: %0t : ERROR : tb_raycast_fast : dut.hit : expected_value: %0b actual_value: %0b", 
                     $time, expect_hit, hit);
            $display("[FAIL] %s: Hit mismatch (expected=%0b, got=%0b)", test_name, expect_hit, hit);
            fail_count = fail_count + 1;
        end else if (expect_hit) begin
            if (hx !== expect_x || hy !== expect_y || hz !== expect_z) begin
                $display("LOG: %0t : ERROR : tb_raycast_fast : dut.hit_position : expected_value: (%0d,%0d,%0d) actual_value: (%0d,%0d,%0d)", 
                         $time, expect_x, expect_y, expect_z, hx, hy, hz);
                $display("[FAIL] %s: Position mismatch (expected=(%0d,%0d,%0d), got=(%0d,%0d,%0d))", 
                         test_name, expect_x, expect_y, expect_z, hx, hy, hz);
                fail_count = fail_count + 1;
            end else if (face_id !== expect_face) begin
                $display("LOG: %0t : ERROR : tb_raycast_fast : dut.face_id : expected_value: %s actual_value: %s", 
                         $time, face_to_str(expect_face), face_to_str(face_id));
                $display("[FAIL] %s: Face mismatch (expected=%s, got=%s)", 
                         test_name, face_to_str(expect_face), face_to_str(face_id));
                fail_count = fail_count + 1;
            end else if (brightness !== exp_bright) begin
                $display("LOG: %0t : ERROR : tb_raycast_fast : dut.brightness : expected_value: %0d actual_value: %0d", 
                         $time, exp_bright, brightness);
                $display("[FAIL] %s: Brightness mismatch (expected=%0d, got=%0d)", 
                         test_name, exp_bright, brightness);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %s: Hit at (%0d,%0d,%0d), face=%s, brightness=%0d, steps=%0d", 
                         test_name, hx, hy, hz, face_to_str(face_id), brightness, steps_taken);
                pass_count = pass_count + 1;
            end
        end else begin
            // Miss case
            $display("[PASS] %s: Miss (as expected), steps=%0d", test_name, steps_taken);
            pass_count = pass_count + 1;
        end
        
        res_ready = 1'b0;
        @(posedge clock);
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        $display("=================================================================");
        $display("  VOXEL RAYCASTING ACCELERATOR - FAST TESTBENCH");
        $display("=================================================================");
        
        // Initialize signals
        reset      = 1;
        load_mode  = 0;
        load_valid = 0;
        load_addr  = 0;
        load_data  = 0;
        job_valid  = 0;
        ix0 = 0; iy0 = 0; iz0 = 0;
        sx = 0; sy = 0; sz = 0;
        next_x = 0; next_y = 0; next_z = 0;
        inc_x = 0; inc_y = 0; inc_z = 0;
        max_steps = 0;
        res_ready = 0;
        
        // Reset sequence
        repeat(5) @(posedge clock);
        reset = 0;
        repeat(2) @(posedge clock);
        
        // Note: RAM initialized to all zeros (empty scene) by default
        
        // =====================================================================
        // TEST 1: Axis-Aligned Ray +X Direction
        // =====================================================================
        $display("\n[TEST 1] Axis-Aligned Ray: +X Direction");
        load_mode = 1;
        load_voxel(5'd10, 5'd5, 5'd5, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd0, 5'd5, 5'd5, 3'd0, 1'b1, 10'd100);
        check_result(1'b1, 5'd10, 5'd5, 5'd5, 3'b000, "Ray +X to voxel (10,5,5)");
        
        // =====================================================================
        // TEST 2: Axis-Aligned Ray -X Direction
        // =====================================================================
        $display("\n[TEST 2] Axis-Aligned Ray: -X Direction");
        submit_ray_axis_aligned(5'd20, 5'd5, 5'd5, 3'd0, 1'b0, 10'd100);
        check_result(1'b1, 5'd10, 5'd5, 5'd5, 3'b001, "Ray -X to voxel (10,5,5)");
        
        // =====================================================================
        // TEST 3: Axis-Aligned Ray +Y Direction
        // =====================================================================
        $display("\n[TEST 3] Axis-Aligned Ray: +Y Direction");
        load_mode = 1;
        load_voxel(5'd5, 5'd10, 5'd5, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd5, 5'd0, 5'd5, 3'd1, 1'b1, 10'd100);
        check_result(1'b1, 5'd5, 5'd10, 5'd5, 3'b010, "Ray +Y to voxel (5,10,5)");
        
        // =====================================================================
        // TEST 4: Axis-Aligned Ray -Y Direction
        // =====================================================================
        $display("\n[TEST 4] Axis-Aligned Ray: -Y Direction");
        submit_ray_axis_aligned(5'd5, 5'd20, 5'd5, 3'd1, 1'b0, 10'd100);
        check_result(1'b1, 5'd5, 5'd10, 5'd5, 3'b011, "Ray -Y to voxel (5,10,5)");
        
        // =====================================================================
        // TEST 5: Axis-Aligned Ray +Z Direction
        // =====================================================================
        $display("\n[TEST 5] Axis-Aligned Ray: +Z Direction");
        load_mode = 1;
        load_voxel(5'd7, 5'd7, 5'd10, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd7, 5'd7, 5'd0, 3'd2, 1'b1, 10'd100);
        check_result(1'b1, 5'd7, 5'd7, 5'd10, 3'b100, "Ray +Z to voxel (7,7,10)");
        
        // =====================================================================
        // TEST 6: Axis-Aligned Ray -Z Direction
        // =====================================================================
        $display("\n[TEST 6] Axis-Aligned Ray: -Z Direction");
        submit_ray_axis_aligned(5'd7, 5'd7, 5'd20, 3'd2, 1'b0, 10'd100);
        check_result(1'b1, 5'd7, 5'd7, 5'd10, 3'b101, "Ray -Z to voxel (7,7,10)");
        
        // =====================================================================
        // TEST 7: Miss - Ray Exits Bounds (+X)
        // =====================================================================
        $display("\n[TEST 7] Miss - Ray Exits Bounds (+X)");
        submit_ray_axis_aligned(5'd0, 5'd25, 5'd25, 3'd0, 1'b1, 10'd100);
        check_result(1'b0, 5'd0, 5'd0, 5'd0, 3'b000, "Ray +X exits bounds (miss)");
        
        // =====================================================================
        // TEST 8: Miss - Ray Exits Bounds (-X)
        // =====================================================================
        $display("\n[TEST 8] Miss - Ray Exits Bounds (-X)");
        submit_ray_axis_aligned(5'd31, 5'd25, 5'd25, 3'd0, 1'b0, 10'd100);
        check_result(1'b0, 5'd0, 5'd0, 5'd0, 3'b001, "Ray -X exits bounds (miss)");
        
        // =====================================================================
        // TEST 9: Max Steps Termination
        // =====================================================================
        $display("\n[TEST 9] Max Steps Termination");
        load_mode = 1;
        load_voxel(5'd31, 5'd15, 5'd15, 1'b1);  // Far away
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd0, 5'd15, 5'd15, 3'd0, 1'b1, 10'd5);  // Max 5 steps
        check_result(1'b0, 5'd0, 5'd0, 5'd0, 3'b000, "Ray terminated by max_steps");
        
        // =====================================================================
        // TEST 10: Ray Starting at Edge (0,0,0)
        // =====================================================================
        $display("\n[TEST 10] Ray Starting at Edge (0,0,0)");
        load_mode = 1;
        load_voxel(5'd5, 5'd0, 5'd0, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd0, 5'd0, 5'd0, 3'd0, 1'b1, 10'd100);
        check_result(1'b1, 5'd5, 5'd0, 5'd0, 3'b000, "Ray from (0,0,0) +X");
        
        // =====================================================================
        // TEST 11: Ray Starting at Corner (31,31,31)
        // =====================================================================
        $display("\n[TEST 11] Ray Starting at Corner (31,31,31)");
        load_mode = 1;
        load_voxel(5'd25, 5'd31, 5'd31, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd31, 5'd31, 5'd31, 3'd0, 1'b0, 10'd100);
        check_result(1'b1, 5'd25, 5'd31, 5'd31, 3'b001, "Ray from (31,31,31) -X");
        
        // =====================================================================
        // TEST 12: Brightness Verification - All Faces
        // =====================================================================
        $display("\n[TEST 12] Brightness Verification - All Faces");
        load_mode = 1;
        
        // Create a 3x3x3 solid cube at center
        for (int x = 14; x <= 16; x++) begin
            for (int y = 14; y <= 16; y++) begin
                for (int z = 14; z <= 16; z++) begin
                    load_voxel(x[4:0], y[4:0], z[4:0], 1'b1);
                end
            end
        end
        load_mode = 0;
        
        // Test +X face (brightness=2)
        submit_ray_axis_aligned(5'd10, 5'd15, 5'd15, 3'd0, 1'b1, 10'd100);
        check_result(1'b1, 5'd14, 5'd15, 5'd15, 3'b000, "Brightness test: +X face");
        
        // Test -X face (brightness=2)
        submit_ray_axis_aligned(5'd20, 5'd15, 5'd15, 3'd0, 1'b0, 10'd100);
        check_result(1'b1, 5'd16, 5'd15, 5'd15, 3'b001, "Brightness test: -X face");
        
        // Test +Y face (brightness=4)
        submit_ray_axis_aligned(5'd15, 5'd10, 5'd15, 3'd1, 1'b1, 10'd100);
        check_result(1'b1, 5'd15, 5'd14, 5'd15, 3'b010, "Brightness test: +Y face");
        
        // Test -Y face (brightness=1)
        submit_ray_axis_aligned(5'd15, 5'd20, 5'd15, 3'd1, 1'b0, 10'd100);
        check_result(1'b1, 5'd15, 5'd16, 5'd15, 3'b011, "Brightness test: -Y face");
        
        // Test +Z face (brightness=3)
        submit_ray_axis_aligned(5'd15, 5'd15, 5'd10, 3'd2, 1'b1, 10'd100);
        check_result(1'b1, 5'd15, 5'd15, 5'd14, 3'b100, "Brightness test: +Z face");
        
        // Test -Z face (brightness=3)
        submit_ray_axis_aligned(5'd15, 5'd15, 5'd20, 3'd2, 1'b0, 10'd100);
        check_result(1'b1, 5'd15, 5'd15, 5'd16, 3'b101, "Brightness test: -Z face");
        
        // =====================================================================
        // TEST 13: Multiple Consecutive Jobs
        // =====================================================================
        $display("\n[TEST 13] Multiple Consecutive Jobs");
        load_mode = 1;
        load_voxel(5'd10, 5'd10, 5'd10, 1'b1);
        load_voxel(5'd20, 5'd20, 5'd20, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd0, 5'd10, 5'd10, 3'd0, 1'b1, 10'd100);
        check_result(1'b1, 5'd10, 5'd10, 5'd10, 3'b000, "Job 1: Hit (10,10,10)");
        
        submit_ray_axis_aligned(5'd0, 5'd20, 5'd20, 3'd0, 1'b1, 10'd100);
        check_result(1'b1, 5'd20, 5'd20, 5'd20, 3'b000, "Job 2: Hit (20,20,20)");
        
        submit_ray_axis_aligned(5'd0, 5'd18, 5'd18, 3'd0, 1'b1, 10'd100);
        check_result(1'b0, 5'd0, 5'd0, 5'd0, 3'b000, "Job 3: Miss");
        
        // =====================================================================
        // TEST 14: Backpressure - Delayed res_ready
        // =====================================================================
        $display("\n[TEST 14] Backpressure - Delayed res_ready");
        load_mode = 1;
        load_voxel(5'd5, 5'd5, 5'd5, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd0, 5'd5, 5'd5, 3'd0, 1'b1, 10'd100);
        
        // Wait for result but don't assert res_ready immediately
        @(posedge clock);
        wait(res_valid);
        $display("  Result valid, but delaying res_ready...");
        repeat(10) @(posedge clock);  // Delay 10 cycles
        
        res_ready = 1'b1;
        @(posedge clock);
        
        if (hit && hx == 5 && hy == 5 && hz == 5) begin
            $display("[PASS] Backpressure test: Result held stable during delay");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Backpressure test: Result changed during delay");
            fail_count = fail_count + 1;
        end
        test_count = test_count + 1;
        
        res_ready = 1'b0;
        @(posedge clock);
        
        // =====================================================================
        // TEST 15: Starting Inside Solid Voxel
        // =====================================================================
        $display("\n[TEST 15] Starting Inside Solid Voxel");
        load_mode = 1;
        load_voxel(5'd12, 5'd12, 5'd12, 1'b1);
        load_voxel(5'd13, 5'd12, 5'd12, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd12, 5'd12, 5'd12, 3'd0, 1'b1, 10'd100);
        check_result(1'b1, 5'd13, 5'd12, 5'd12, 3'b000, "Starting in solid, hits next");
        
        // =====================================================================
        // TEST 16: Boundary Voxels
        // =====================================================================
        $display("\n[TEST 16] Boundary Voxels");
        load_mode = 1;
        load_voxel(5'd0, 5'd0, 5'd0, 1'b1);
        load_mode = 0;
        
        submit_ray_axis_aligned(5'd10, 5'd0, 5'd0, 3'd0, 1'b0, 10'd100);
        check_result(1'b1, 5'd0, 5'd0, 5'd0, 3'b001, "Hit boundary voxel (0,0,0)");
        
        // =====================================================================
        // Final Report
        // =====================================================================
        $display("\n=================================================================");
        $display("  TEST SUMMARY");
        $display("=================================================================");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("=================================================================");
        
        if (fail_count == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
            $fatal(1, "%0d tests failed!", fail_count);
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #10000000;  // 10ms timeout (much shorter, but should be enough)
        $display("ERROR: Testbench timeout!");
        $fatal(1, "Simulation timeout");
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
