`ifndef TB_UTILS_SVH
`define TB_UTILS_SVH

// Common testbench utilities and definitions

// Clock generation task
task automatic gen_clock(ref logic clk, input int half_period_ns = 5);
    clk = 0;
    forever #(half_period_ns) clk = ~clk;
endtask

// Reset generation task
task automatic apply_reset(ref logic rst_n, ref logic clk, input int cycles = 10);
    rst_n = 0;
    repeat(cycles) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
endtask

// Randomization seed control
int global_seed = 42;  // Default deterministic seed

function automatic void set_seed(int seed);
    global_seed = seed;
    $display("[INFO] Setting random seed to %0d", seed);
endfunction

// Error counting
int error_count = 0;
int test_count = 0;

function automatic void report_error(string msg);
    error_count++;
    $error("[ERROR #%0d] %s", error_count, msg);
endfunction

function automatic void report_pass(string test_name);
    test_count++;
    $display("[PASS] Test %0d: %s", test_count, test_name);
endfunction

function automatic void final_report();
    $display("========================================");
    $display("FINAL TEST REPORT");
    $display("========================================");
    $display("Tests Run:    %0d", test_count);
    $display("Errors Found: %0d", error_count);
    if (error_count == 0) begin
        $display("STATUS: ALL TESTS PASSED");
        $display("========================================");
    end else begin
        $fatal(1, "VERIFICATION FAILED with %0d errors", error_count);
    end
endfunction

`endif // TB_UTILS_SVH
