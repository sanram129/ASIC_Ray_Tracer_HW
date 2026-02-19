`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_axis_choose
// Description: Self-checking testbench for axis_choose module
//              Tests multi-select minimum detection with exact tie handling
// =============================================================================

module tb_axis_choose;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int W32 = 32;
    localparam int W8  = 8;
    localparam int NUM_RANDOM_TESTS = 10000;
    
    // =========================================================================
    // DUT Signals - W=32 instance
    // =========================================================================
    logic [W32-1:0] a_32, b_32, c_32;
    logic [2:0]     step_mask_32;
    logic [1:0]     primary_sel_32;
    
    // =========================================================================
    // DUT Signals - W=8 instance
    // =========================================================================
    logic [W8-1:0]  a_8, b_8, c_8;
    logic [2:0]     step_mask_8;
    logic [1:0]     primary_sel_8;
    
    // =========================================================================
    // Test Control
    // =========================================================================
    int test_count;
    int test_count_w8;
    
    // =========================================================================
    // DUT Instantiation - W=32
    // =========================================================================
    axis_choose #(.W(W32)) dut_32 (
        .a(a_32),
        .b(b_32),
        .c(c_32),
        .step_mask(step_mask_32),
        .primary_sel(primary_sel_32)
    );
    
    // =========================================================================
    // DUT Instantiation - W=8
    // =========================================================================
    axis_choose #(.W(W8)) dut_8 (
        .a(a_8),
        .b(b_8),
        .c(c_8),
        .step_mask(step_mask_8),
        .primary_sel(primary_sel_8)
    );
    
    // =========================================================================
    // Reference Model Function - Compute Expected Outputs
    // =========================================================================
    function automatic void compute_expected(
        input  logic [W32-1:0] in_a, in_b, in_c,
        output logic [W32-1:0] exp_min_val,
        output logic [2:0]     exp_mask,
        output logic [1:0]     exp_psel
    );
        // Find minimum value
        if (in_a <= in_b && in_a <= in_c) begin
            exp_min_val = in_a;
        end
        else if (in_b <= in_c) begin
            exp_min_val = in_b;
        end
        else begin
            exp_min_val = in_c;
        end
        
        // Generate mask - set bit for each input equal to minimum
        exp_mask[0] = (in_a == exp_min_val);
        exp_mask[1] = (in_b == exp_min_val);
        exp_mask[2] = (in_c == exp_min_val);
        
        // Generate primary_sel - lowest index set bit (priority a > b > c)
        if (exp_mask[0]) begin
            exp_psel = 2'd0;
        end
        else if (exp_mask[1]) begin
            exp_psel = 2'd1;
        end
        else begin
            exp_psel = 2'd2;
        end
    endfunction
    
    // =========================================================================
    // Check Task - Verify DUT outputs against expected values (W=32)
    // =========================================================================
    task automatic check_outputs_32(
        input logic [W32-1:0] in_a, in_b, in_c,
        input string test_name
    );
        logic [W32-1:0] exp_min_val;
        logic [2:0]     exp_mask;
        logic [1:0]     exp_psel;
        
        // Compute expected values
        compute_expected(in_a, in_b, in_c, exp_min_val, exp_mask, exp_psel);
        
        // Wait for combinational logic to settle
        #1;
        
        // Check invariant: step_mask should never be 0
        if (step_mask_32 === 3'b000) begin
            $display("LOG: %0t : ERROR : tb_axis_choose : dut_32.step_mask : expected_value: non-zero actual_value: 3'b000", $time);
            $fatal(1, "[%s] FATAL: step_mask is 3'b000 (should always have at least one bit set)", test_name);
        end
        
        // Check step_mask
        if (step_mask_32 !== exp_mask) begin
            $display("LOG: %0t : ERROR : tb_axis_choose : dut_32.step_mask : expected_value: 3'b%03b actual_value: 3'b%03b", 
                     $time, exp_mask, step_mask_32);
            $fatal(1, "[%s] MISMATCH: a=%0d, b=%0d, c=%0d | Expected mask=3'b%03b, Got mask=3'b%03b", 
                   test_name, in_a, in_b, in_c, exp_mask, step_mask_32);
        end
        
        // Check primary_sel
        if (primary_sel_32 !== exp_psel) begin
            $display("LOG: %0t : ERROR : tb_axis_choose : dut_32.primary_sel : expected_value: 2'd%0d actual_value: 2'd%0d", 
                     $time, exp_psel, primary_sel_32);
            $fatal(1, "[%s] MISMATCH: a=%0d, b=%0d, c=%0d | Expected primary_sel=2'd%0d, Got primary_sel=2'd%0d", 
                   test_name, in_a, in_b, in_c, exp_psel, primary_sel_32);
        end
        
        test_count++;
    endtask
    
    // =========================================================================
    // Check Task - Verify DUT outputs against expected values (W=8)
    // =========================================================================
    task automatic check_outputs_8(
        input logic [W8-1:0] in_a, in_b, in_c,
        input string test_name
    );
        logic [W32-1:0] exp_min_val;
        logic [2:0]     exp_mask;
        logic [1:0]     exp_psel;
        logic [W32-1:0] in_a_ext, in_b_ext, in_c_ext;
        
        // Zero-extend to 32-bit for reference model
        in_a_ext = {{(W32-W8){1'b0}}, in_a};
        in_b_ext = {{(W32-W8){1'b0}}, in_b};
        in_c_ext = {{(W32-W8){1'b0}}, in_c};
        
        // Compute expected values
        compute_expected(in_a_ext, in_b_ext, in_c_ext, exp_min_val, exp_mask, exp_psel);
        
        // Wait for combinational logic to settle
        #1;
        
        // Check invariant: step_mask should never be 0
        if (step_mask_8 === 3'b000) begin
            $display("LOG: %0t : ERROR : tb_axis_choose : dut_8.step_mask : expected_value: non-zero actual_value: 3'b000", $time);
            $fatal(1, "[%s] FATAL: step_mask is 3'b000 (W=8 instance)", test_name);
        end
        
        // Check step_mask
        if (step_mask_8 !== exp_mask) begin
            $display("LOG: %0t : ERROR : tb_axis_choose : dut_8.step_mask : expected_value: 3'b%03b actual_value: 3'b%03b", 
                     $time, exp_mask, step_mask_8);
            $fatal(1, "[%s] MISMATCH (W=8): a=%0d, b=%0d, c=%0d | Expected mask=3'b%03b, Got mask=3'b%03b", 
                   test_name, in_a, in_b, in_c, exp_mask, step_mask_8);
        end
        
        // Check primary_sel
        if (primary_sel_8 !== exp_psel) begin
            $display("LOG: %0t : ERROR : tb_axis_choose : dut_8.primary_sel : expected_value: 2'd%0d actual_value: 2'd%0d", 
                     $time, exp_psel, primary_sel_8);
            $fatal(1, "[%s] MISMATCH (W=8): a=%0d, b=%0d, c=%0d | Expected primary_sel=2'd%0d, Got primary_sel=2'd%0d", 
                   test_name, in_a, in_b, in_c, exp_psel, primary_sel_8);
        end
        
        test_count_w8++;
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        
        test_count = 0;
        test_count_w8 = 0;
        
        $display("\n=== Starting Directed Tests (W=32) ===\n");
        
        // =====================================================================
        // Directed Test 1: Strict ordering cases - all different values
        // =====================================================================
        $display("Test Group: Strict Ordering (all different)");
        
        // a < b < c (a is minimum)
        a_32 = 10; b_32 = 20; c_32 = 30;
        check_outputs_32(a_32, b_32, c_32, "a<b<c");
        
        // a < c < b (a is minimum)
        a_32 = 10; b_32 = 30; c_32 = 20;
        check_outputs_32(a_32, b_32, c_32, "a<c<b");
        
        // b < a < c (b is minimum)
        a_32 = 20; b_32 = 10; c_32 = 30;
        check_outputs_32(a_32, b_32, c_32, "b<a<c");
        
        // b < c < a (b is minimum)
        a_32 = 30; b_32 = 10; c_32 = 20;
        check_outputs_32(a_32, b_32, c_32, "b<c<a");
        
        // c < a < b (c is minimum)
        a_32 = 20; b_32 = 30; c_32 = 10;
        check_outputs_32(a_32, b_32, c_32, "c<a<b");
        
        // c < b < a (c is minimum)
        a_32 = 30; b_32 = 20; c_32 = 10;
        check_outputs_32(a_32, b_32, c_32, "c<b<a");
        
        // =====================================================================
        // Directed Test 2: Pairwise ties at minimum
        // =====================================================================
        $display("Test Group: Pairwise Ties at Minimum");
        
        // a == b < c (both a and b are minimum)
        a_32 = 15; b_32 = 15; c_32 = 25;
        check_outputs_32(a_32, b_32, c_32, "a==b<c");
        
        // a == c < b (both a and c are minimum)
        a_32 = 15; b_32 = 25; c_32 = 15;
        check_outputs_32(a_32, b_32, c_32, "a==c<b");
        
        // b == c < a (both b and c are minimum)
        a_32 = 25; b_32 = 15; c_32 = 15;
        check_outputs_32(a_32, b_32, c_32, "b==c<a");
        
        // =====================================================================
        // Directed Test 3: Triple tie (all equal)
        // =====================================================================
        $display("Test Group: Triple Tie (all equal)");
        
        // a == b == c (all are minimum)
        a_32 = 100; b_32 = 100; c_32 = 100;
        check_outputs_32(a_32, b_32, c_32, "a==b==c");
        
        a_32 = 0; b_32 = 0; c_32 = 0;
        check_outputs_32(a_32, b_32, c_32, "all_zeros");
        
        a_32 = 32'hFFFFFFFF; b_32 = 32'hFFFFFFFF; c_32 = 32'hFFFFFFFF;
        check_outputs_32(a_32, b_32, c_32, "all_max");
        
        // =====================================================================
        // Directed Test 4: Ties NOT at minimum
        // =====================================================================
        $display("Test Group: Ties NOT at Minimum");
        
        // a == b > c (c is minimum alone)
        a_32 = 50; b_32 = 50; c_32 = 10;
        check_outputs_32(a_32, b_32, c_32, "a==b>c");
        
        // a == c > b (b is minimum alone)
        a_32 = 50; b_32 = 10; c_32 = 50;
        check_outputs_32(a_32, b_32, c_32, "a==c>b");
        
        // b == c > a (a is minimum alone)
        a_32 = 10; b_32 = 50; c_32 = 50;
        check_outputs_32(a_32, b_32, c_32, "b==c>a");
        
        // =====================================================================
        // Directed Test 5: Extreme values
        // =====================================================================
        $display("Test Group: Extreme Values");
        
        // All zeros
        a_32 = 0; b_32 = 0; c_32 = 0;
        check_outputs_32(a_32, b_32, c_32, "extreme_all_zeros");
        
        // All max
        a_32 = 32'hFFFFFFFF; b_32 = 32'hFFFFFFFF; c_32 = 32'hFFFFFFFF;
        check_outputs_32(a_32, b_32, c_32, "extreme_all_max");
        
        // Zero vs. max
        a_32 = 0; b_32 = 32'hFFFFFFFF; c_32 = 32'hFFFFFFFF;
        check_outputs_32(a_32, b_32, c_32, "extreme_zero_vs_max_1");
        
        a_32 = 32'hFFFFFFFF; b_32 = 0; c_32 = 32'hFFFFFFFF;
        check_outputs_32(a_32, b_32, c_32, "extreme_zero_vs_max_2");
        
        a_32 = 32'hFFFFFFFF; b_32 = 32'hFFFFFFFF; c_32 = 0;
        check_outputs_32(a_32, b_32, c_32, "extreme_zero_vs_max_3");
        
        // Mix of 0, 1, and max
        a_32 = 0; b_32 = 1; c_32 = 32'hFFFFFFFF;
        check_outputs_32(a_32, b_32, c_32, "extreme_0_1_max");
        
        a_32 = 1; b_32 = 0; c_32 = 32'hFFFFFFFF;
        check_outputs_32(a_32, b_32, c_32, "extreme_1_0_max");
        
        // Powers of 2
        a_32 = 32'h00000001; b_32 = 32'h00000002; c_32 = 32'h00000004;
        check_outputs_32(a_32, b_32, c_32, "powers_of_2");
        
        // Large values near max
        a_32 = 32'hFFFFFFFE; b_32 = 32'hFFFFFFFF; c_32 = 32'hFFFFFFFD;
        check_outputs_32(a_32, b_32, c_32, "near_max_values");
        
        // =====================================================================
        // Random Tests with Tie Biasing (W=32)
        // =====================================================================
        $display("\n=== Starting Random Tests (W=32) ===");
        $display("Running %0d random test vectors...\n", NUM_RANDOM_TESTS);
        
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            // Generate random values
            a_32 = $urandom();
            b_32 = $urandom();
            c_32 = $urandom();
            
            // Bias some cases to create ties intentionally (about 30% of cases)
            case ($urandom() % 10)
                0, 1: b_32 = a_32;              // Tie: b = a
                2, 3: c_32 = a_32;              // Tie: c = a
                4:    c_32 = b_32;              // Tie: c = b
                5:    begin b_32 = a_32; c_32 = a_32; end  // Triple tie
                default: ; // Keep random values
            endcase
            
            check_outputs_32(a_32, b_32, c_32, $sformatf("random_%0d", i));
        end
        
        // =====================================================================
        // Parameterization Test (W=8)
        // =====================================================================
        $display("\n=== Starting Parameterization Tests (W=8) ===\n");
        
        // Basic tests with 8-bit width
        a_8 = 8'd10; b_8 = 8'd20; c_8 = 8'd30;
        check_outputs_8(a_8, b_8, c_8, "W8_a<b<c");
        
        a_8 = 8'd30; b_8 = 8'd20; c_8 = 8'd10;
        check_outputs_8(a_8, b_8, c_8, "W8_c<b<a");
        
        // Ties
        a_8 = 8'd15; b_8 = 8'd15; c_8 = 8'd25;
        check_outputs_8(a_8, b_8, c_8, "W8_a==b<c");
        
        a_8 = 8'd100; b_8 = 8'd100; c_8 = 8'd100;
        check_outputs_8(a_8, b_8, c_8, "W8_all_equal");
        
        // Extreme 8-bit values
        a_8 = 8'd0; b_8 = 8'd0; c_8 = 8'd0;
        check_outputs_8(a_8, b_8, c_8, "W8_all_zeros");
        
        a_8 = 8'hFF; b_8 = 8'hFF; c_8 = 8'hFF;
        check_outputs_8(a_8, b_8, c_8, "W8_all_max");
        
        a_8 = 8'd0; b_8 = 8'd255; c_8 = 8'd128;
        check_outputs_8(a_8, b_8, c_8, "W8_zero_min");
        
        // Random W=8 tests
        for (int i = 0; i < 1000; i++) begin
            a_8 = $urandom() & 8'hFF;
            b_8 = $urandom() & 8'hFF;
            c_8 = $urandom() & 8'hFF;
            
            // Bias ties
            case ($urandom() % 10)
                0, 1: b_8 = a_8;
                2, 3: c_8 = a_8;
                4:    c_8 = b_8;
                5:    begin b_8 = a_8; c_8 = a_8; end
                default: ;
            endcase
            
            check_outputs_8(a_8, b_8, c_8, $sformatf("W8_random_%0d", i));
        end
        
        // =====================================================================
        // Test Complete
        // =====================================================================
        $display("\n=== All Tests Completed Successfully ===");
        $display("PASS: %0d tests (W=32)", test_count);
        $display("PASS: %0d tests (W=8)", test_count_w8);
        $display("TOTAL PASS: %0d tests", test_count + test_count_w8);
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
