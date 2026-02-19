`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_integration
// Description: Integration testbench for axis_choose + step_update + bounds_check
//              Verifies correct combined behavior of the voxel traversal system
// =============================================================================

module tb_integration;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int W = 32;
    localparam int COORD_W = 6;
    localparam int MAX_VAL = 31;
    localparam int NUM_RANDOM_TESTS = 10000;
    
    // =========================================================================
    // Test Inputs (driven by testbench)
    // =========================================================================
    logic [4:0]  ix, iy, iz;
    logic        sx, sy, sz;
    logic [31:0] next_x, next_y, next_z;
    logic [31:0] inc_x, inc_y, inc_z;
    
    // =========================================================================
    // axis_choose outputs (connect to step_update)
    // =========================================================================
    logic [2:0] step_mask;
    logic [1:0] primary_sel;
    
    // =========================================================================
    // step_update outputs
    // =========================================================================
    logic [4:0]  ix_next, iy_next, iz_next;
    logic [31:0] next_x_next, next_y_next, next_z_next;
    logic [2:0]  face_mask;
    logic [2:0]  primary_face_id;
    
    // =========================================================================
    // bounds_check inputs (zero-extended from step_update)
    // =========================================================================
    logic [5:0] bounds_ix, bounds_iy, bounds_iz;
    
    // =========================================================================
    // bounds_check output
    // =========================================================================
    logic out_of_bounds;
    
    // =========================================================================
    // Test Control
    // =========================================================================
    int test_count;
    
    // =========================================================================
    // DUT Instantiation: axis_choose
    // =========================================================================
    axis_choose #(.W(W)) u_axis_choose (
        .a(next_x),
        .b(next_y),
        .c(next_z),
        .step_mask(step_mask),
        .primary_sel(primary_sel)
    );
    
    // =========================================================================
    // DUT Instantiation: step_update
    // =========================================================================
    step_update #(.W(W)) u_step_update (
        .ix(ix),
        .iy(iy),
        .iz(iz),
        .sx(sx),
        .sy(sy),
        .sz(sz),
        .next_x(next_x),
        .next_y(next_y),
        .next_z(next_z),
        .inc_x(inc_x),
        .inc_y(inc_y),
        .inc_z(inc_z),
        .step_mask(step_mask),
        .primary_sel(primary_sel),
        .ix_next(ix_next),
        .iy_next(iy_next),
        .iz_next(iz_next),
        .next_x_next(next_x_next),
        .next_y_next(next_y_next),
        .next_z_next(next_z_next),
        .face_mask(face_mask),
        .primary_face_id(primary_face_id)
    );
    
    // =========================================================================
    // Zero-extend updated coordinates for bounds check
    // =========================================================================
    assign bounds_ix = {1'b0, ix_next};
    assign bounds_iy = {1'b0, iy_next};
    assign bounds_iz = {1'b0, iz_next};
    
    // =========================================================================
    // DUT Instantiation: bounds_check
    // =========================================================================
    bounds_check #(
        .COORD_W(COORD_W),
        .MAX_VAL(MAX_VAL)
    ) u_bounds_check (
        .ix(bounds_ix),
        .iy(bounds_iy),
        .iz(bounds_iz),
        .out_of_bounds(out_of_bounds)
    );
    
    // =========================================================================
    // Integration Check Task
    // =========================================================================
    task automatic check_integration(string test_name);
        logic [31:0] min_val;
        logic exp_out_of_bounds;
        logic [4:0] exp_ix_next, exp_iy_next, exp_iz_next;
        logic [31:0] exp_next_x_next, exp_next_y_next, exp_next_z_next;
        logic [2:0] exp_face_id;
        
        // Wait for combinational logic to settle
        #1;
        
        // =====================================================================
        // Check A: axis_choose invariants
        // =====================================================================
        
        // step_mask must never be 000
        if (step_mask === 3'b000) begin
            $display("\nLOG: %0t : ERROR : tb_integration : step_mask : expected_value: non-zero actual_value: 3'b000", $time);
            $fatal(1, "[%s] axis_choose FAIL: step_mask is 3'b000", test_name);
        end
        
        // primary_sel must point to lowest set bit in step_mask
        if (step_mask[0] && primary_sel !== 2'd0) begin
            $display("\nLOG: %0t : ERROR : tb_integration : primary_sel : expected_value: 0 actual_value: %0d", $time, primary_sel);
            $fatal(1, "[%s] axis_choose FAIL: step_mask[0]=1 but primary_sel=%0d (expected 0)", 
                   test_name, primary_sel);
        end
        if (!step_mask[0] && step_mask[1] && primary_sel !== 2'd1) begin
            $display("\nLOG: %0t : ERROR : tb_integration : primary_sel : expected_value: 1 actual_value: %0d", $time, primary_sel);
            $fatal(1, "[%s] axis_choose FAIL: step_mask=3'b%03b but primary_sel=%0d (expected 1)", 
                   test_name, step_mask, primary_sel);
        end
        if (!step_mask[0] && !step_mask[1] && step_mask[2] && primary_sel !== 2'd2) begin
            $display("\nLOG: %0t : ERROR : tb_integration : primary_sel : expected_value: 2 actual_value: %0d", $time, primary_sel);
            $fatal(1, "[%s] axis_choose FAIL: step_mask=3'b%03b but primary_sel=%0d (expected 2)", 
                   test_name, step_mask, primary_sel);
        end
        
        // primary_sel must correspond to a set bit
        if ((primary_sel == 2'd0 && !step_mask[0]) ||
            (primary_sel == 2'd1 && !step_mask[1]) ||
            (primary_sel == 2'd2 && !step_mask[2])) begin
            $display("\nLOG: %0t : ERROR : tb_integration : primary_sel : expected_value: set_bit actual_value: %0d", $time, primary_sel);
            $fatal(1, "[%s] axis_choose FAIL: primary_sel=%0d but step_mask[%0d]=0", 
                   test_name, primary_sel, primary_sel);
        end
        
        // =====================================================================
        // Check B: step_update integration checks
        // =====================================================================
        
        // face_mask must equal step_mask
        if (face_mask !== step_mask) begin
            $display("\nLOG: %0t : ERROR : tb_integration : face_mask : expected_value: 3'b%03b actual_value: 3'b%03b", 
                     $time, step_mask, face_mask);
            $fatal(1, "[%s] step_update FAIL: face_mask (3'b%03b) != step_mask (3'b%03b)", 
                   test_name, face_mask, step_mask);
        end
        
        // Check pass-through and updates for each axis
        // X-axis
        if (!step_mask[0]) begin
            if (ix_next !== ix) begin
                $display("\nLOG: %0t : ERROR : tb_integration : ix_next : expected_value: %0d actual_value: %0d", $time, ix, ix_next);
                $fatal(1, "[%s] step_update FAIL: step_mask[0]=0 but ix_next (%0d) != ix (%0d)", 
                       test_name, ix_next, ix);
            end
            if (next_x_next !== next_x) begin
                $display("\nLOG: %0t : ERROR : tb_integration : next_x_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, next_x, next_x_next);
                $fatal(1, "[%s] step_update FAIL: step_mask[0]=0 but next_x_next (0x%08h) != next_x (0x%08h)", 
                       test_name, next_x_next, next_x);
            end
        end else begin
            // Check timer update
            exp_next_x_next = next_x + inc_x;
            if (next_x_next !== exp_next_x_next) begin
                $display("\nLOG: %0t : ERROR : tb_integration : next_x_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, exp_next_x_next, next_x_next);
                $fatal(1, "[%s] step_update FAIL: next_x_next (0x%08h) != next_x+inc_x (0x%08h)", 
                       test_name, next_x_next, exp_next_x_next);
            end
            // Check coordinate step
            exp_ix_next = sx ? (ix + 5'd1) : (ix - 5'd1);
            if (ix_next !== exp_ix_next) begin
                $display("\nLOG: %0t : ERROR : tb_integration : ix_next : expected_value: %0d actual_value: %0d", 
                         $time, exp_ix_next, ix_next);
                $fatal(1, "[%s] step_update FAIL: ix_next (%0d) != expected (%0d), sx=%0b", 
                       test_name, ix_next, exp_ix_next, sx);
            end
        end
        
        // Y-axis
        if (!step_mask[1]) begin
            if (iy_next !== iy) begin
                $display("\nLOG: %0t : ERROR : tb_integration : iy_next : expected_value: %0d actual_value: %0d", $time, iy, iy_next);
                $fatal(1, "[%s] step_update FAIL: step_mask[1]=0 but iy_next (%0d) != iy (%0d)", 
                       test_name, iy_next, iy);
            end
            if (next_y_next !== next_y) begin
                $display("\nLOG: %0t : ERROR : tb_integration : next_y_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, next_y, next_y_next);
                $fatal(1, "[%s] step_update FAIL: step_mask[1]=0 but next_y_next (0x%08h) != next_y (0x%08h)", 
                       test_name, next_y_next, next_y);
            end
        end else begin
            exp_next_y_next = next_y + inc_y;
            if (next_y_next !== exp_next_y_next) begin
                $display("\nLOG: %0t : ERROR : tb_integration : next_y_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, exp_next_y_next, next_y_next);
                $fatal(1, "[%s] step_update FAIL: next_y_next (0x%08h) != next_y+inc_y (0x%08h)", 
                       test_name, next_y_next, exp_next_y_next);
            end
            exp_iy_next = sy ? (iy + 5'd1) : (iy - 5'd1);
            if (iy_next !== exp_iy_next) begin
                $display("\nLOG: %0t : ERROR : tb_integration : iy_next : expected_value: %0d actual_value: %0d", 
                         $time, exp_iy_next, iy_next);
                $fatal(1, "[%s] step_update FAIL: iy_next (%0d) != expected (%0d), sy=%0b", 
                       test_name, iy_next, exp_iy_next, sy);
            end
        end
        
        // Z-axis
        if (!step_mask[2]) begin
            if (iz_next !== iz) begin
                $display("\nLOG: %0t : ERROR : tb_integration : iz_next : expected_value: %0d actual_value: %0d", $time, iz, iz_next);
                $fatal(1, "[%s] step_update FAIL: step_mask[2]=0 but iz_next (%0d) != iz (%0d)", 
                       test_name, iz_next, iz);
            end
            if (next_z_next !== next_z) begin
                $display("\nLOG: %0t : ERROR : tb_integration : next_z_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, next_z, next_z_next);
                $fatal(1, "[%s] step_update FAIL: step_mask[2]=0 but next_z_next (0x%08h) != next_z (0x%08h)", 
                       test_name, next_z_next, next_z);
            end
        end else begin
            exp_next_z_next = next_z + inc_z;
            if (next_z_next !== exp_next_z_next) begin
                $display("\nLOG: %0t : ERROR : tb_integration : next_z_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, exp_next_z_next, next_z_next);
                $fatal(1, "[%s] step_update FAIL: next_z_next (0x%08h) != next_z+inc_z (0x%08h)", 
                       test_name, next_z_next, exp_next_z_next);
            end
            exp_iz_next = sz ? (iz + 5'd1) : (iz - 5'd1);
            if (iz_next !== exp_iz_next) begin
                $display("\nLOG: %0t : ERROR : tb_integration : iz_next : expected_value: %0d actual_value: %0d", 
                         $time, exp_iz_next, iz_next);
                $fatal(1, "[%s] step_update FAIL: iz_next (%0d) != expected (%0d), sz=%0b", 
                       test_name, iz_next, exp_iz_next, sz);
            end
        end
        
        // Check primary_face_id
        case (primary_sel)
            2'd0: exp_face_id = sx ? 3'd0 : 3'd1;
            2'd1: exp_face_id = sy ? 3'd2 : 3'd3;
            2'd2: exp_face_id = sz ? 3'd4 : 3'd5;
            default: exp_face_id = 3'd0;
        endcase
        
        if (primary_face_id !== exp_face_id) begin
            $display("\nLOG: %0t : ERROR : tb_integration : primary_face_id : expected_value: %0d actual_value: %0d", 
                     $time, exp_face_id, primary_face_id);
            $fatal(1, "[%s] step_update FAIL: primary_face_id (%0d) != expected (%0d) for primary_sel=%0d", 
                   test_name, primary_face_id, exp_face_id, primary_sel);
        end
        
        // =====================================================================
        // Check C: bounds_check integration
        // =====================================================================
        
        // Compute expected out_of_bounds
        exp_out_of_bounds = (bounds_ix > MAX_VAL) || (bounds_iy > MAX_VAL) || (bounds_iz > MAX_VAL);
        
        if (out_of_bounds !== exp_out_of_bounds) begin
            $display("\nLOG: %0t : ERROR : tb_integration : out_of_bounds : expected_value: %0b actual_value: %0b", 
                     $time, exp_out_of_bounds, out_of_bounds);
            $display("bounds_ix=%0d, bounds_iy=%0d, bounds_iz=%0d, MAX_VAL=%0d", 
                     bounds_ix, bounds_iy, bounds_iz, MAX_VAL);
            $fatal(1, "[%s] bounds_check FAIL: out_of_bounds (%0b) != expected (%0b)", 
                   test_name, out_of_bounds, exp_out_of_bounds);
        end
        
        test_count++;
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        
        test_count = 0;
        
        $display("\n=== Starting Integration Directed Tests ===\n");
        
        // =====================================================================
        // Directed Test 1: Strict minimum cases
        // =====================================================================
        $display("Test Group: Strict Minimum Cases");
        
        // X strictly smallest
        ix = 5'd15; iy = 5'd15; iz = 5'd15;
        sx = 1; sy = 1; sz = 1;
        next_x = 32'h1000; next_y = 32'h2000; next_z = 32'h3000;
        inc_x = 32'h100; inc_y = 32'h200; inc_z = 32'h300;
        check_integration("X_strict_min");
        
        // Y strictly smallest
        ix = 5'd10; iy = 5'd20; iz = 5'd5;
        sx = 0; sy = 1; sz = 0;
        next_x = 32'h3000; next_y = 32'h1000; next_z = 32'h2000;
        inc_x = 32'h50; inc_y = 32'h60; inc_z = 32'h70;
        check_integration("Y_strict_min");
        
        // Z strictly smallest
        ix = 5'd25; iy = 5'd28; iz = 5'd30;
        sx = 1; sy = 0; sz = 1;
        next_x = 32'h5000; next_y = 32'h4000; next_z = 32'h1000;
        inc_x = 32'h10; inc_y = 32'h20; inc_z = 32'h30;
        check_integration("Z_strict_min");
        
        // =====================================================================
        // Directed Test 2: Two-way ties
        // =====================================================================
        $display("\nTest Group: Two-Way Ties");
        
        // X==Y < Z
        ix = 5'd0; iy = 5'd0; iz = 5'd0;
        sx = 1; sy = 1; sz = 1;
        next_x = 32'h1000; next_y = 32'h1000; next_z = 32'h2000;
        inc_x = 32'h1; inc_y = 32'h2; inc_z = 32'h3;
        check_integration("XY_tie_min");
        
        // X==Z < Y
        ix = 5'd31; iy = 5'd15; iz = 5'd31;
        sx = 0; sy = 0; sz = 1;
        next_x = 32'h5000; next_y = 32'hA000; next_z = 32'h5000;
        inc_x = 32'h100; inc_y = 32'h100; inc_z = 32'h100;
        check_integration("XZ_tie_min");
        
        // Y==Z < X
        ix = 5'd20; iy = 5'd10; iz = 5'd25;
        sx = 1; sy = 0; sz = 0;
        next_x = 32'hF000; next_y = 32'h3000; next_z = 32'h3000;
        inc_x = 32'h50; inc_y = 32'h60; inc_z = 32'h70;
        check_integration("YZ_tie_min");
        
        // =====================================================================
        // Directed Test 3: Three-way tie
        // =====================================================================
        $display("\nTest Group: Three-Way Tie");
        
        // X==Y==Z, all positive steps
        ix = 5'd16; iy = 5'd16; iz = 5'd16;
        sx = 1; sy = 1; sz = 1;
        next_x = 32'h7777; next_y = 32'h7777; next_z = 32'h7777;
        inc_x = 32'hAAAA; inc_y = 32'hBBBB; inc_z = 32'hCCCC;
        check_integration("XYZ_tie_all_pos");
        
        // X==Y==Z, all negative steps
        ix = 5'd8; iy = 5'd8; iz = 5'd8;
        sx = 0; sy = 0; sz = 0;
        next_x = 32'h5555; next_y = 32'h5555; next_z = 32'h5555;
        inc_x = 32'h1111; inc_y = 32'h2222; inc_z = 32'h3333;
        check_integration("XYZ_tie_all_neg");
        
        // X==Y==Z, mixed steps
        ix = 5'd12; iy = 5'd14; iz = 5'd18;
        sx = 1; sy = 0; sz = 1;
        next_x = 32'hABCD; next_y = 32'hABCD; next_z = 32'hABCD;
        inc_x = 32'hF; inc_y = 32'h10; inc_z = 32'h11;
        check_integration("XYZ_tie_mixed");
        
        // =====================================================================
        // Directed Test 4: Edge coordinate cases
        // =====================================================================
        $display("\nTest Group: Edge Coordinates");
        
        // Wrap from 31 to 0 (positive step)
        ix = 5'd31; iy = 5'd15; iz = 5'd15;
        sx = 1; sy = 0; sz = 0;
        next_x = 32'h1000; next_y = 32'h2000; next_z = 32'h3000;
        inc_x = 32'h100; inc_y = 32'h100; inc_z = 32'h100;
        check_integration("X_wrap_31_to_0");
        
        // Wrap from 0 to 31 (negative step)
        ix = 5'd0; iy = 5'd10; iz = 5'd20;
        sx = 0; sy = 1; sz = 1;
        next_x = 32'h500; next_y = 32'h600; next_z = 32'h700;
        inc_x = 32'h10; inc_y = 32'h20; inc_z = 32'h30;
        check_integration("X_wrap_0_to_31");
        
        // Multiple axes wrapping
        ix = 5'd31; iy = 5'd31; iz = 5'd31;
        sx = 1; sy = 1; sz = 1;
        next_x = 32'h100; next_y = 32'h100; next_z = 32'h100;
        inc_x = 32'h1; inc_y = 32'h2; inc_z = 32'h3;
        check_integration("XYZ_all_wrap");
        
        // =====================================================================
        // Directed Test 5: Timer extremes
        // =====================================================================
        $display("\nTest Group: Timer Extremes");
        
        // Zero timers and increments
        ix = 5'd5; iy = 5'd10; iz = 5'd15;
        sx = 1; sy = 1; sz = 1;
        next_x = 32'h0; next_y = 32'h0; next_z = 32'h0;
        inc_x = 32'h0; inc_y = 32'h0; inc_z = 32'h0;
        check_integration("timers_all_zero");
        
        // Max timers with increment
        ix = 5'd20; iy = 5'd20; iz = 5'd20;
        sx = 0; sy = 0; sz = 0;
        next_x = 32'hFFFFFFFF; next_y = 32'hFFFFFFFF; next_z = 32'hFFFFFFFF;
        inc_x = 32'h1; inc_y = 32'h1; inc_z = 32'h1;
        check_integration("timers_max_overflow");
        
        // Large increments
        ix = 5'd3; iy = 5'd7; iz = 5'd11;
        sx = 1; sy = 0; sz = 1;
        next_x = 32'h1000; next_y = 32'h2000; next_z = 32'h1500;
        inc_x = 32'hFFFFFFF0; inc_y = 32'hFFFFFFF0; inc_z = 32'hFFFFFFF0;
        check_integration("timers_large_inc");
        
        // =====================================================================
        // Directed Test 6: Bounds-triggering scenarios
        // =====================================================================
        $display("\nTest Group: Bounds Scenarios");
        
        // Coordinates stay in bounds after step
        ix = 5'd30; iy = 5'd30; iz = 5'd30;
        sx = 1; sy = 1; sz = 1;
        next_x = 32'h100; next_y = 32'h100; next_z = 32'h100;
        inc_x = 32'h10; inc_y = 32'h20; inc_z = 32'h30;
        check_integration("bounds_stay_in");
        
        // Coordinates at boundary
        ix = 5'd31; iy = 5'd31; iz = 5'd30;
        sx = 0; sy = 0; sz = 0;
        next_x = 32'h200; next_y = 32'h300; next_z = 32'h100;
        inc_x = 32'h5; inc_y = 32'h6; inc_z = 32'h7;
        check_integration("bounds_at_edge");
        
        // =====================================================================
        // Random Tests
        // =====================================================================
        $display("\n=== Starting Random Tests ===");
        $display("Running %0d random test vectors...\n", NUM_RANDOM_TESTS);
        
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            // Randomize coordinates (0..31)
            ix = $urandom() & 5'h1F;
            iy = $urandom() & 5'h1F;
            iz = $urandom() & 5'h1F;
            
            // Randomize signs
            sx = $urandom() & 1'b1;
            sy = $urandom() & 1'b1;
            sz = $urandom() & 1'b1;
            
            // Randomize timers
            next_x = $urandom();
            next_y = $urandom();
            next_z = $urandom();
            
            // Bias to create ties (30% of cases)
            if (($urandom() % 100) < 30) begin
                case ($urandom() % 6)
                    0: next_y = next_x;              // X==Y
                    1: next_z = next_x;              // X==Z
                    2: next_z = next_y;              // Y==Z
                    3: begin next_y = next_x; next_z = next_x; end  // X==Y==Z
                    4: begin next_z = next_y; end    // Y==Z
                    5: begin next_y = next_x; end    // X==Y
                endcase
            end
            
            // Randomize increments
            inc_x = $urandom();
            inc_y = $urandom();
            inc_z = $urandom();
            
            check_integration($sformatf("random_%0d", i));
        end
        
        // =====================================================================
        // Test Complete
        // =====================================================================
        $display("\n=== All Integration Tests Completed Successfully ===");
        $display("PASS: %0d tests", test_count);
        $display("\nTEST PASSED");
        $finish;
    end
    
    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
