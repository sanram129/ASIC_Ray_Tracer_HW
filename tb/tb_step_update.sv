`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_step_update
// Description: Self-checking testbench for step_update voxel stepping module
//              Tests all invariants and edge cases
// =============================================================================

module tb_step_update;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int W32 = 32;
    localparam int W8  = 8;
    localparam int NUM_RANDOM_TESTS = 10000;
    
    // =========================================================================
    // DUT Signals - W=32 instance
    // =========================================================================
    logic [4:0]     ix_32, iy_32, iz_32;
    logic           sx_32, sy_32, sz_32;
    logic [W32-1:0] next_x_32, next_y_32, next_z_32;
    logic [W32-1:0] inc_x_32, inc_y_32, inc_z_32;
    logic [2:0]     step_mask_32;
    logic [1:0]     primary_sel_32;
    
    logic [4:0]     ix_next_32, iy_next_32, iz_next_32;
    logic [W32-1:0] next_x_next_32, next_y_next_32, next_z_next_32;
    logic [2:0]     face_mask_32;
    logic [2:0]     primary_face_id_32;
    
    // =========================================================================
    // Test Control
    // =========================================================================
    int test_count;
    
    // =========================================================================
    // DUT Instantiation - W=32
    // =========================================================================
    step_update #(.W(W32)) dut_32 (
        .ix(ix_32),
        .iy(iy_32),
        .iz(iz_32),
        .sx(sx_32),
        .sy(sy_32),
        .sz(sz_32),
        .next_x(next_x_32),
        .next_y(next_y_32),
        .next_z(next_z_32),
        .inc_x(inc_x_32),
        .inc_y(inc_y_32),
        .inc_z(inc_z_32),
        .step_mask(step_mask_32),
        .primary_sel(primary_sel_32),
        .ix_next(ix_next_32),
        .iy_next(iy_next_32),
        .iz_next(iz_next_32),
        .next_x_next(next_x_next_32),
        .next_y_next(next_y_next_32),
        .next_z_next(next_z_next_32),
        .face_mask(face_mask_32),
        .primary_face_id(primary_face_id_32)
    );
    
    // =========================================================================
    // Helper Function: Display Test Vector
    // =========================================================================
    function automatic void display_vector(string test_name);
        $display("\n=== Test: %s ===", test_name);
        $display("Inputs:");
        $display("  ix=%0d, iy=%0d, iz=%0d", ix_32, iy_32, iz_32);
        $display("  sx=%0b, sy=%0b, sz=%0b", sx_32, sy_32, sz_32);
        $display("  next_x=0x%08h, next_y=0x%08h, next_z=0x%08h", next_x_32, next_y_32, next_z_32);
        $display("  inc_x=0x%08h, inc_y=0x%08h, inc_z=0x%08h", inc_x_32, inc_y_32, inc_z_32);
        $display("  step_mask=3'b%03b, primary_sel=%0d", step_mask_32, primary_sel_32);
        $display("Outputs:");
        $display("  ix_next=%0d, iy_next=%0d, iz_next=%0d", ix_next_32, iy_next_32, iz_next_32);
        $display("  next_x_next=0x%08h, next_y_next=0x%08h, next_z_next=0x%08h", 
                 next_x_next_32, next_y_next_32, next_z_next_32);
        $display("  face_mask=3'b%03b, primary_face_id=%0d", face_mask_32, primary_face_id_32);
    endfunction
    
    // =========================================================================
    // Invariant Checking Task
    // =========================================================================
    task automatic check_invariants(string test_name);
        logic [W32-1:0] exp_next_x_next, exp_next_y_next, exp_next_z_next;
        logic [4:0] exp_ix_next, exp_iy_next, exp_iz_next;
        logic [2:0] exp_primary_face_id;
        
        // Wait for combinational logic to settle
        #1;
        
        // =====================================================================
        // Invariant A: face_mask must equal step_mask exactly
        // =====================================================================
        if (face_mask_32 !== step_mask_32) begin
            display_vector(test_name);
            $display("LOG: %0t : ERROR : tb_step_update : dut_32.face_mask : expected_value: 3'b%03b actual_value: 3'b%03b", 
                     $time, step_mask_32, face_mask_32);
            $fatal(1, "[%s] INVARIANT A FAILED: face_mask (3'b%03b) != step_mask (3'b%03b)", 
                   test_name, face_mask_32, step_mask_32);
        end
        
        // =====================================================================
        // Invariant B: If step_mask[i]==0, outputs pass through unchanged
        // =====================================================================
        
        // X-axis pass-through check
        if (step_mask_32[0] == 0) begin
            if (ix_next_32 !== ix_32) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.ix_next : expected_value: %0d actual_value: %0d", 
                         $time, ix_32, ix_next_32);
                $fatal(1, "[%s] INVARIANT B FAILED: step_mask[0]==0 but ix_next (%0d) != ix (%0d)", 
                       test_name, ix_next_32, ix_32);
            end
            if (next_x_next_32 !== next_x_32) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.next_x_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, next_x_32, next_x_next_32);
                $fatal(1, "[%s] INVARIANT B FAILED: step_mask[0]==0 but next_x_next (0x%08h) != next_x (0x%08h)", 
                       test_name, next_x_next_32, next_x_32);
            end
        end
        
        // Y-axis pass-through check
        if (step_mask_32[1] == 0) begin
            if (iy_next_32 !== iy_32) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.iy_next : expected_value: %0d actual_value: %0d", 
                         $time, iy_32, iy_next_32);
                $fatal(1, "[%s] INVARIANT B FAILED: step_mask[1]==0 but iy_next (%0d) != iy (%0d)", 
                       test_name, iy_next_32, iy_32);
            end
            if (next_y_next_32 !== next_y_32) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.next_y_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, next_y_32, next_y_next_32);
                $fatal(1, "[%s] INVARIANT B FAILED: step_mask[1]==0 but next_y_next (0x%08h) != next_y (0x%08h)", 
                       test_name, next_y_next_32, next_y_32);
            end
        end
        
        // Z-axis pass-through check
        if (step_mask_32[2] == 0) begin
            if (iz_next_32 !== iz_32) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.iz_next : expected_value: %0d actual_value: %0d", 
                         $time, iz_32, iz_next_32);
                $fatal(1, "[%s] INVARIANT B FAILED: step_mask[2]==0 but iz_next (%0d) != iz (%0d)", 
                       test_name, iz_next_32, iz_32);
            end
            if (next_z_next_32 !== next_z_32) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.next_z_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, next_z_32, next_z_next_32);
                $fatal(1, "[%s] INVARIANT B FAILED: step_mask[2]==0 but next_z_next (0x%08h) != next_z (0x%08h)", 
                       test_name, next_z_next_32, next_z_32);
            end
        end
        
        // =====================================================================
        // Invariant C: If step_mask[i]==1, timer updates by exactly increment
        // =====================================================================
        
        // X-timer update check
        if (step_mask_32[0] == 1) begin
            exp_next_x_next = next_x_32 + inc_x_32;
            if (next_x_next_32 !== exp_next_x_next) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.next_x_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, exp_next_x_next, next_x_next_32);
                $fatal(1, "[%s] INVARIANT C FAILED: step_mask[0]==1 but next_x_next (0x%08h) != next_x+inc_x (0x%08h)", 
                       test_name, next_x_next_32, exp_next_x_next);
            end
            
            // Check index update (±1 step based on sign)
            exp_ix_next = sx_32 ? (ix_32 + 5'd1) : (ix_32 - 5'd1);
            if (ix_next_32 !== exp_ix_next) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.ix_next : expected_value: %0d actual_value: %0d", 
                         $time, exp_ix_next, ix_next_32);
                $fatal(1, "[%s] INVARIANT C FAILED: step_mask[0]==1 but ix_next (%0d) != expected (%0d), sx=%0b", 
                       test_name, ix_next_32, exp_ix_next, sx_32);
            end
        end
        
        // Y-timer update check
        if (step_mask_32[1] == 1) begin
            exp_next_y_next = next_y_32 + inc_y_32;
            if (next_y_next_32 !== exp_next_y_next) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.next_y_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, exp_next_y_next, next_y_next_32);
                $fatal(1, "[%s] INVARIANT C FAILED: step_mask[1]==1 but next_y_next (0x%08h) != next_y+inc_y (0x%08h)", 
                       test_name, next_y_next_32, exp_next_y_next);
            end
            
            // Check index update (±1 step based on sign)
            exp_iy_next = sy_32 ? (iy_32 + 5'd1) : (iy_32 - 5'd1);
            if (iy_next_32 !== exp_iy_next) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.iy_next : expected_value: %0d actual_value: %0d", 
                         $time, exp_iy_next, iy_next_32);
                $fatal(1, "[%s] INVARIANT C FAILED: step_mask[1]==1 but iy_next (%0d) != expected (%0d), sy=%0b", 
                       test_name, iy_next_32, exp_iy_next, sy_32);
            end
        end
        
        // Z-timer update check
        if (step_mask_32[2] == 1) begin
            exp_next_z_next = next_z_32 + inc_z_32;
            if (next_z_next_32 !== exp_next_z_next) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.next_z_next : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, exp_next_z_next, next_z_next_32);
                $fatal(1, "[%s] INVARIANT C FAILED: step_mask[2]==1 but next_z_next (0x%08h) != next_z+inc_z (0x%08h)", 
                       test_name, next_z_next_32, exp_next_z_next);
            end
            
            // Check index update (±1 step based on sign)
            exp_iz_next = sz_32 ? (iz_32 + 5'd1) : (iz_32 - 5'd1);
            if (iz_next_32 !== exp_iz_next) begin
                display_vector(test_name);
                $display("LOG: %0t : ERROR : tb_step_update : dut_32.iz_next : expected_value: %0d actual_value: %0d", 
                         $time, exp_iz_next, iz_next_32);
                $fatal(1, "[%s] INVARIANT C FAILED: step_mask[2]==1 but iz_next (%0d) != expected (%0d), sz=%0b", 
                       test_name, iz_next_32, exp_iz_next, sz_32);
            end
        end
        
        // =====================================================================
        // Invariant D: primary_face_id must match primary_sel and sign bit
        // =====================================================================
        case (primary_sel_32)
            2'd0: exp_primary_face_id = sx_32 ? 3'd0 : 3'd1;  // X-axis: X+ or X-
            2'd1: exp_primary_face_id = sy_32 ? 3'd2 : 3'd3;  // Y-axis: Y+ or Y-
            2'd2: exp_primary_face_id = sz_32 ? 3'd4 : 3'd5;  // Z-axis: Z+ or Z-
            2'd3: begin
                // Invalid but allowed - print warning
                $display("LOG: %0t : WARNING : tb_step_update : primary_sel=3 (invalid but testing default behavior)", $time);
                exp_primary_face_id = 3'd0;  // DUT default
            end
        endcase
        
        if (primary_face_id_32 !== exp_primary_face_id) begin
            display_vector(test_name);
            $display("LOG: %0t : ERROR : tb_step_update : dut_32.primary_face_id : expected_value: %0d actual_value: %0d", 
                     $time, exp_primary_face_id, primary_face_id_32);
            $fatal(1, "[%s] INVARIANT D FAILED: primary_sel=%0d, sign=%0b, expected face_id=%0d, got=%0d", 
                   test_name, primary_sel_32, 
                   (primary_sel_32==0) ? sx_32 : (primary_sel_32==1) ? sy_32 : sz_32,
                   exp_primary_face_id, primary_face_id_32);
        end
        
        test_count++;
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        
        test_count = 0;
        
        $display("\n=== Starting Directed Tests ===\n");
        
        // =====================================================================
        // Directed Test 1: step_mask = 000 (no stepping, all pass-through)
        // =====================================================================
        $display("Test Group: step_mask=000 (Pass-through)");
        
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 1; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b000;
        primary_sel_32 = 2'd0;
        check_invariants("step_mask_000_test1");
        
        ix_32 = 5'd0; iy_32 = 5'd31; iz_32 = 5'd16;
        sx_32 = 0; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'hFFFFFFFF; next_y_32 = 32'h0; next_z_32 = 32'hAAAAAAAA;
        inc_x_32 = 32'h1; inc_y_32 = 32'h1; inc_z_32 = 32'h1;
        step_mask_32 = 3'b000;
        primary_sel_32 = 2'd1;
        check_invariants("step_mask_000_test2");
        
        // =====================================================================
        // Directed Test 2: Single-axis steps
        // =====================================================================
        $display("\nTest Group: Single-axis Steps");
        
        // X-axis only, positive direction (sx=1)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 1; sy_32 = 0; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b001;
        primary_sel_32 = 2'd0;
        check_invariants("single_X_positive");
        
        // X-axis only, negative direction (sx=0)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 0; sy_32 = 1; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b001;
        primary_sel_32 = 2'd0;
        check_invariants("single_X_negative");
        
        // Y-axis only, positive direction (sy=1)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 0; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b010;
        primary_sel_32 = 2'd1;
        check_invariants("single_Y_positive");
        
        // Y-axis only, negative direction (sy=0)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 1; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b010;
        primary_sel_32 = 2'd1;
        check_invariants("single_Y_negative");
        
        // Z-axis only, positive direction (sz=1)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 0; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b100;
        primary_sel_32 = 2'd2;
        check_invariants("single_Z_positive");
        
        // Z-axis only, negative direction (sz=0)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 1; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b100;
        primary_sel_32 = 2'd2;
        check_invariants("single_Z_negative");
        
        // =====================================================================
        // Directed Test 3: Two-axis steps (diagonal)
        // =====================================================================
        $display("\nTest Group: Two-axis Steps (Diagonal)");
        
        // X+Y step, both positive
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 1; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b011;
        primary_sel_32 = 2'd0;
        check_invariants("diagonal_XY_pos_pos");
        
        // X+Y step, mixed signs
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 1; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b011;
        primary_sel_32 = 2'd0;
        check_invariants("diagonal_XY_pos_neg");
        
        // X+Z step, both negative
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 0; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b101;
        primary_sel_32 = 2'd0;
        check_invariants("diagonal_XZ_neg_neg");
        
        // Y+Z step, mixed signs
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 0; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b110;
        primary_sel_32 = 2'd1;
        check_invariants("diagonal_YZ_pos_neg");
        
        // =====================================================================
        // Directed Test 4: Three-axis step
        // =====================================================================
        $display("\nTest Group: Three-axis Step");
        
        // All positive
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 1; sy_32 = 1; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b111;
        primary_sel_32 = 2'd0;
        check_invariants("three_axis_all_pos");
        
        // All negative
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 0; sy_32 = 0; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b111;
        primary_sel_32 = 2'd1;
        check_invariants("three_axis_all_neg");
        
        // Mixed signs
        ix_32 = 5'd5; iy_32 = 5'd10; iz_32 = 5'd15;
        sx_32 = 1; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b111;
        primary_sel_32 = 2'd2;
        check_invariants("three_axis_mixed");
        
        // =====================================================================
        // Directed Test 5: Edge coordinate values (wrap behavior)
        // =====================================================================
        $display("\nTest Group: Edge Coordinates (Wrap Behavior)");
        
        // ix=0, sx=0 (subtract 1 wraps to 31)
        ix_32 = 5'd0; iy_32 = 5'd15; iz_32 = 5'd15;
        sx_32 = 0; sy_32 = 1; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b001;
        primary_sel_32 = 2'd0;
        check_invariants("edge_ix_0_neg_wrap");
        
        // ix=31, sx=1 (add 1 wraps to 0)
        ix_32 = 5'd31; iy_32 = 5'd15; iz_32 = 5'd15;
        sx_32 = 1; sy_32 = 0; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b001;
        primary_sel_32 = 2'd0;
        check_invariants("edge_ix_31_pos_wrap");
        
        // iy=0, sy=0 (wrap)
        ix_32 = 5'd15; iy_32 = 5'd0; iz_32 = 5'd15;
        sx_32 = 1; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b010;
        primary_sel_32 = 2'd1;
        check_invariants("edge_iy_0_neg_wrap");
        
        // iy=31, sy=1 (wrap)
        ix_32 = 5'd15; iy_32 = 5'd31; iz_32 = 5'd15;
        sx_32 = 0; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b010;
        primary_sel_32 = 2'd1;
        check_invariants("edge_iy_31_pos_wrap");
        
        // iz=0, sz=0 (wrap)
        ix_32 = 5'd15; iy_32 = 5'd15; iz_32 = 5'd0;
        sx_32 = 1; sy_32 = 1; sz_32 = 0;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b100;
        primary_sel_32 = 2'd2;
        check_invariants("edge_iz_0_neg_wrap");
        
        // iz=31, sz=1 (wrap)
        ix_32 = 5'd15; iy_32 = 5'd15; iz_32 = 5'd31;
        sx_32 = 0; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'h100; inc_y_32 = 32'h200; inc_z_32 = 32'h300;
        step_mask_32 = 3'b100;
        primary_sel_32 = 2'd2;
        check_invariants("edge_iz_31_pos_wrap");
        
        // =====================================================================
        // Directed Test 6: Timer extremes
        // =====================================================================
        $display("\nTest Group: Timer Extremes");
        
        // All timers and increments zero
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 1; sy_32 = 1; sz_32 = 1;
        next_x_32 = 32'h0; next_y_32 = 32'h0; next_z_32 = 32'h0;
        inc_x_32 = 32'h0; inc_y_32 = 32'h0; inc_z_32 = 32'h0;
        step_mask_32 = 3'b111;
        primary_sel_32 = 2'd0;
        check_invariants("timer_all_zero");
        
        // Max timers, increment by 1 (overflow wrap)
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 0; sy_32 = 0; sz_32 = 0;
        next_x_32 = 32'hFFFFFFFF; next_y_32 = 32'hFFFFFFFF; next_z_32 = 32'hFFFFFFFF;
        inc_x_32 = 32'h1; inc_y_32 = 32'h1; inc_z_32 = 32'h1;
        step_mask_32 = 3'b111;
        primary_sel_32 = 2'd1;
        check_invariants("timer_max_overflow");
        
        // Max increment
        ix_32 = 5'd10; iy_32 = 5'd15; iz_32 = 5'd20;
        sx_32 = 1; sy_32 = 0; sz_32 = 1;
        next_x_32 = 32'h1000; next_y_32 = 32'h2000; next_z_32 = 32'h3000;
        inc_x_32 = 32'hFFFFFFFF; inc_y_32 = 32'hFFFFFFFF; inc_z_32 = 32'hFFFFFFFF;
        step_mask_32 = 3'b101;
        primary_sel_32 = 2'd2;
        check_invariants("timer_max_increment");
        
        // =====================================================================
        // Random Tests
        // =====================================================================
        $display("\n=== Starting Random Tests ===");
        $display("Running %0d random test vectors...\n", NUM_RANDOM_TESTS);
        
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            // Randomize coordinates (0..31)
            ix_32 = $urandom() & 5'h1F;
            iy_32 = $urandom() & 5'h1F;
            iz_32 = $urandom() & 5'h1F;
            
            // Randomize signs
            sx_32 = $urandom() & 1'b1;
            sy_32 = $urandom() & 1'b1;
            sz_32 = $urandom() & 1'b1;
            
            // Randomize timers and increments
            next_x_32 = $urandom();
            next_y_32 = $urandom();
            next_z_32 = $urandom();
            inc_x_32 = $urandom();
            inc_y_32 = $urandom();
            inc_z_32 = $urandom();
            
            // Randomize step_mask (0..7)
            step_mask_32 = $urandom() & 3'b111;
            
            // Mostly valid primary_sel (0..2), occasionally 3
            if (($urandom() % 100) < 95) begin
                primary_sel_32 = $urandom() % 3;
            end else begin
                primary_sel_32 = 2'd3;  // Test invalid case
            end
            
            check_invariants($sformatf("random_%0d", i));
        end
        
        // =====================================================================
        // Test Complete
        // =====================================================================
        $display("\n=== All Tests Completed Successfully ===");
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
