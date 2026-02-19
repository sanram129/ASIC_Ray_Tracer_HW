`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_bounds_check
// Description: Self-checking testbench for bounds_check module
//              Tests voxel coordinate bounds checking logic
// =============================================================================

module tb_bounds_check;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int COORD_W6 = 6;
    localparam int COORD_W5 = 5;
    localparam int MAX_VAL = 31;
    localparam int NUM_RANDOM_TESTS = 10000;
    
    // =========================================================================
    // DUT Signals - COORD_W=6 instance
    // =========================================================================
    logic [COORD_W6-1:0] ix_6, iy_6, iz_6;
    logic out_of_bounds_6;
    
    // =========================================================================
    // DUT Signals - COORD_W=5 instance
    // =========================================================================
    logic [COORD_W5-1:0] ix_5, iy_5, iz_5;
    logic out_of_bounds_5;
    
    // =========================================================================
    // Test Control
    // =========================================================================
    int test_count;
    int test_count_5bit;
    
    // =========================================================================
    // DUT Instantiation - COORD_W=6, MAX_VAL=31
    // =========================================================================
    bounds_check #(
        .COORD_W(COORD_W6),
        .MAX_VAL(MAX_VAL)
    ) dut_6 (
        .ix(ix_6),
        .iy(iy_6),
        .iz(iz_6),
        .out_of_bounds(out_of_bounds_6)
    );
    
    // =========================================================================
    // DUT Instantiation - COORD_W=5, MAX_VAL=31 (always in-bounds)
    // =========================================================================
    bounds_check #(
        .COORD_W(COORD_W5),
        .MAX_VAL(MAX_VAL)
    ) dut_5 (
        .ix(ix_5),
        .iy(iy_5),
        .iz(iz_5),
        .out_of_bounds(out_of_bounds_5)
    );
    
    // =========================================================================
    // Check Task - COORD_W=6
    // =========================================================================
    task automatic check_bounds_6(
        input logic [COORD_W6-1:0] in_ix,
        input logic [COORD_W6-1:0] in_iy,
        input logic [COORD_W6-1:0] in_iz,
        input string test_name
    );
        logic expected;
        
        // Apply inputs
        ix_6 = in_ix;
        iy_6 = in_iy;
        iz_6 = in_iz;
        
        // Wait for combinational logic to settle
        #1;
        
        // Compute expected result
        expected = (in_ix > MAX_VAL) || (in_iy > MAX_VAL) || (in_iz > MAX_VAL);
        
        // Check result
        if (out_of_bounds_6 !== expected) begin
            $display("\nLOG: %0t : ERROR : tb_bounds_check : dut_6.out_of_bounds : expected_value: %0b actual_value: %0b", 
                     $time, expected, out_of_bounds_6);
            $display("Test: %s", test_name);
            $display("Inputs: ix=%0d, iy=%0d, iz=%0d", in_ix, in_iy, in_iz);
            $display("MAX_VAL=%0d, COORD_W=%0d", MAX_VAL, COORD_W6);
            $fatal(1, "[%s] MISMATCH: ix=%0d, iy=%0d, iz=%0d | Expected out_of_bounds=%0b, Got=%0b", 
                   test_name, in_ix, in_iy, in_iz, expected, out_of_bounds_6);
        end
        
        test_count++;
    endtask
    
    // =========================================================================
    // Check Task - COORD_W=5 (should always be in-bounds)
    // =========================================================================
    task automatic check_bounds_5(
        input logic [COORD_W5-1:0] in_ix,
        input logic [COORD_W5-1:0] in_iy,
        input logic [COORD_W5-1:0] in_iz,
        input string test_name
    );
        logic expected;
        
        // Apply inputs
        ix_5 = in_ix;
        iy_5 = in_iy;
        iz_5 = in_iz;
        
        // Wait for combinational logic to settle
        #1;
        
        // For COORD_W=5, all values 0..31 are in range, so always expect 0
        expected = 1'b0;
        
        // Check result
        if (out_of_bounds_5 !== expected) begin
            $display("\nLOG: %0t : ERROR : tb_bounds_check : dut_5.out_of_bounds : expected_value: %0b actual_value: %0b", 
                     $time, expected, out_of_bounds_5);
            $display("Test: %s", test_name);
            $display("Inputs: ix=%0d, iy=%0d, iz=%0d", in_ix, in_iy, in_iz);
            $display("MAX_VAL=%0d, COORD_W=%0d", MAX_VAL, COORD_W5);
            $fatal(1, "[%s] MISMATCH (5-bit): ix=%0d, iy=%0d, iz=%0d | Expected out_of_bounds=%0b, Got=%0b", 
                   test_name, in_ix, in_iy, in_iz, expected, out_of_bounds_5);
        end
        
        test_count_5bit++;
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        
        test_count = 0;
        test_count_5bit = 0;
        
        $display("\n=== Starting Directed Tests (COORD_W=6, MAX_VAL=31) ===\n");
        
        // =====================================================================
        // Directed Test 1: All in-bounds edge cases
        // =====================================================================
        $display("Test Group: All In-Bounds Edge Cases");
        
        // All zeros
        check_bounds_6(6'd0, 6'd0, 6'd0, "all_zeros");
        
        // All at MAX_VAL
        check_bounds_6(6'd31, 6'd31, 6'd31, "all_max_val");
        
        // Mixed in-bounds values
        check_bounds_6(6'd31, 6'd0, 6'd15, "mixed_in_bounds_1");
        check_bounds_6(6'd15, 6'd31, 6'd0, "mixed_in_bounds_2");
        check_bounds_6(6'd0, 6'd15, 6'd31, "mixed_in_bounds_3");
        check_bounds_6(6'd10, 6'd20, 6'd30, "mixed_in_bounds_4");
        
        // =====================================================================
        // Directed Test 2: Single-axis out-of-bounds
        // =====================================================================
        $display("\nTest Group: Single-Axis Out-of-Bounds");
        
        // X-axis out-of-bounds
        check_bounds_6(6'd32, 6'd0, 6'd0, "x_out_32");
        check_bounds_6(6'd33, 6'd15, 6'd15, "x_out_33");
        check_bounds_6(6'd50, 6'd31, 6'd31, "x_out_50");
        
        // Y-axis out-of-bounds
        check_bounds_6(6'd0, 6'd32, 6'd0, "y_out_32");
        check_bounds_6(6'd15, 6'd33, 6'd15, "y_out_33");
        check_bounds_6(6'd31, 6'd50, 6'd31, "y_out_50");
        
        // Z-axis out-of-bounds
        check_bounds_6(6'd0, 6'd0, 6'd32, "z_out_32");
        check_bounds_6(6'd15, 6'd15, 6'd33, "z_out_33");
        check_bounds_6(6'd31, 6'd31, 6'd50, "z_out_50");
        
        // =====================================================================
        // Directed Test 3: High extremes (63)
        // =====================================================================
        $display("\nTest Group: High Extremes");
        
        check_bounds_6(6'd63, 6'd0, 6'd0, "x_extreme_63");
        check_bounds_6(6'd0, 6'd63, 6'd0, "y_extreme_63");
        check_bounds_6(6'd0, 6'd0, 6'd63, "z_extreme_63");
        
        // =====================================================================
        // Directed Test 4: Multiple axes out-of-bounds
        // =====================================================================
        $display("\nTest Group: Multiple Axes Out-of-Bounds");
        
        check_bounds_6(6'd32, 6'd32, 6'd0, "xy_out");
        check_bounds_6(6'd32, 6'd0, 6'd32, "xz_out");
        check_bounds_6(6'd0, 6'd32, 6'd32, "yz_out");
        check_bounds_6(6'd63, 6'd63, 6'd63, "all_out_max");
        check_bounds_6(6'd32, 6'd32, 6'd32, "all_out_32");
        check_bounds_6(6'd40, 6'd50, 6'd60, "all_out_mixed");
        
        // =====================================================================
        // Directed Test 5: Boundary neighbor checks
        // =====================================================================
        $display("\nTest Group: Boundary Neighbors");
        
        check_bounds_6(6'd30, 6'd31, 6'd31, "30_31_31_in");
        check_bounds_6(6'd31, 6'd30, 6'd31, "31_30_31_in");
        check_bounds_6(6'd31, 6'd31, 6'd30, "31_31_30_in");
        
        check_bounds_6(6'd31, 6'd31, 6'd32, "31_31_32_out");
        check_bounds_6(6'd31, 6'd32, 6'd31, "31_32_31_out");
        check_bounds_6(6'd32, 6'd31, 6'd31, "32_31_31_out");
        
        // Additional boundary tests
        check_bounds_6(6'd30, 6'd30, 6'd30, "30_30_30_in");
        check_bounds_6(6'd32, 6'd32, 6'd32, "32_32_32_out");
        
        // =====================================================================
        // Random Tests (COORD_W=6)
        // =====================================================================
        $display("\n=== Starting Random Tests (COORD_W=6) ===");
        $display("Running %0d random test vectors...\n", NUM_RANDOM_TESTS);
        
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [COORD_W6-1:0] rand_ix, rand_iy, rand_iz;
            
            // Bias 30% of tests to boundary values
            if (($urandom() % 100) < 30) begin
                // Pick boundary values: 0, 31, 32, 63
                rand_ix = pick_boundary_value();
                rand_iy = pick_boundary_value();
                rand_iz = pick_boundary_value();
            end else begin
                // Random values in full 6-bit range
                rand_ix = $urandom_range(0, 63);
                rand_iy = $urandom_range(0, 63);
                rand_iz = $urandom_range(0, 63);
            end
            
            check_bounds_6(rand_ix, rand_iy, rand_iz, $sformatf("random_%0d", i));
        end
        
        // =====================================================================
        // COORD_W=5 Tests (should always be in-bounds)
        // =====================================================================
        $display("\n=== Starting COORD_W=5 Tests (Always In-Bounds) ===\n");
        
        // Edge cases
        check_bounds_5(5'd0, 5'd0, 5'd0, "5bit_all_zeros");
        check_bounds_5(5'd31, 5'd31, 5'd31, "5bit_all_max");
        check_bounds_5(5'd15, 5'd15, 5'd15, "5bit_mid");
        
        // Random samples
        $display("Running representative random tests for COORD_W=5...\n");
        for (int i = 0; i < 1000; i++) begin
            logic [COORD_W5-1:0] rand_ix_5, rand_iy_5, rand_iz_5;
            
            rand_ix_5 = $urandom() & 5'h1F;  // Mask to 5 bits
            rand_iy_5 = $urandom() & 5'h1F;
            rand_iz_5 = $urandom() & 5'h1F;
            
            check_bounds_5(rand_ix_5, rand_iy_5, rand_iz_5, $sformatf("5bit_random_%0d", i));
        end
        
        // =====================================================================
        // Test Complete
        // =====================================================================
        $display("\n=== All Tests Completed Successfully ===");
        $display("PASS: %0d tests (COORD_W=6)", test_count);
        $display("PASS: %0d tests (COORD_W=5)", test_count_5bit);
        $display("TOTAL PASS: %0d tests", test_count + test_count_5bit);
        $display("\nTEST PASSED");
        $finish;
    end
    
    // =========================================================================
    // Helper Function: Pick Boundary Value
    // =========================================================================
    function automatic logic [COORD_W6-1:0] pick_boundary_value();
        int choice;
        choice = $urandom() % 4;
        case (choice)
            0: return 6'd0;
            1: return 6'd31;
            2: return 6'd32;
            3: return 6'd63;
        endcase
    endfunction
    
    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
