`timescale 1ns/1ps

// Professional ASIC Verification Testbench for ray_job_if
// Features: Scoreboard, Assertions, Coverage, Self-checking

module tb_ray_job_if;

`include "tb_utils.svh"
`include "ray_job_scoreboard.sv"

// Parameters
localparam int X_BITS = 5;
localparam int Y_BITS = 5;
localparam int Z_BITS = 5;
localparam int W = 24;
localparam int MAX_STEPS_BITS = 10;

// Clock and Reset
logic clk;
logic rst_n;

// DUT Signals
logic load_mode;
logic job_valid;
logic job_ready;

logic [X_BITS-1:0] ix0, iy0, iz0;
logic sx, sy, sz;
logic [W-1:0] next_x, next_y, next_z;
logic [W-1:0] inc_x, inc_y, inc_z;
logic [MAX_STEPS_BITS-1:0] max_steps;

logic job_done;
logic job_loaded;
logic job_active;

logic [X_BITS-1:0] ix0_q, iy0_q, iz0_q;
logic sx_q, sy_q, sz_q;
logic [W-1:0] next_x_q, next_y_q, next_z_q;
logic [W-1:0] inc_x_q, inc_y_q, inc_z_q;
logic [MAX_STEPS_BITS-1:0] max_steps_q;

// Scoreboard
ray_job_scoreboard #(
    .X_BITS(X_BITS),
    .Y_BITS(Y_BITS),
    .Z_BITS(Z_BITS),
    .W(W),
    .MAX_STEPS_BITS(MAX_STEPS_BITS)
) scoreboard;

// DUT Instantiation
ray_job_if #(
    .X_BITS(X_BITS),
    .Y_BITS(Y_BITS),
    .Z_BITS(Z_BITS),
    .W(W),
    .MAX_STEPS_BITS(MAX_STEPS_BITS)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .load_mode(load_mode),
    .job_valid(job_valid),
    .job_ready(job_ready),
    .ix0(ix0), .iy0(iy0), .iz0(iz0),
    .sx(sx), .sy(sy), .sz(sz),
    .next_x(next_x), .next_y(next_y), .next_z(next_z),
    .inc_x(inc_x), .inc_y(inc_y), .inc_z(inc_z),
    .max_steps(max_steps),
    .job_done(job_done),
    .job_loaded(job_loaded),
    .job_active(job_active),
    .ix0_q(ix0_q), .iy0_q(iy0_q), .iz0_q(iz0_q),
    .sx_q(sx_q), .sy_q(sy_q), .sz_q(sz_q),
    .next_x_q(next_x_q), .next_y_q(next_y_q), .next_z_q(next_z_q),
    .inc_x_q(inc_x_q), .inc_y_q(inc_y_q), .inc_z_q(inc_z_q),
    .max_steps_q(max_steps_q)
);

// ============================================================================
// ASSERTIONS
// ============================================================================

// Assertion: job_loaded is single-cycle pulse
property p_job_loaded_pulse;
    @(posedge clk) disable iff (!rst_n)
    job_loaded |=> !job_loaded;
endproperty
assert property (p_job_loaded_pulse) 
    else $fatal(1, "job_loaded must be single-cycle pulse");

// Assertion: Readiness formula
property p_ready_formula;
    @(posedge clk) disable iff (!rst_n)
    job_ready == ((!load_mode) && (!job_active || job_done));
endproperty
assert property (p_ready_formula)
    else $fatal(1, "job_ready formula violated");

// Assertion: No accept during load_mode
property p_no_accept_in_load_mode;
    @(posedge clk) disable iff (!rst_n)
    load_mode |-> !job_loaded;
endproperty
assert property (p_no_accept_in_load_mode)
    else $fatal(1, "Job accepted during load_mode");

// Assertion: job_loaded implies accept
property p_loaded_implies_accept;
    @(posedge clk) disable iff (!rst_n)
    job_loaded |-> (job_valid && job_ready);
endproperty
assert property (p_loaded_implies_accept)
    else $fatal(1, "job_loaded without valid accept");

// ============================================================================
// COVERAGE
// ============================================================================

covergroup cg_ray_job_interface @(posedge clk);
    option.per_instance = 1;
    
    cp_job_valid: coverpoint job_valid {
        bins valid = {1};
        bins invalid = {0};
    }
    
    cp_job_ready: coverpoint job_ready;
    
    cp_load_mode: coverpoint load_mode {
        bins normal = {0};
        bins loading = {1};
    }
    
    cp_job_active: coverpoint job_active;
    
    cp_job_done: coverpoint job_done;
    
    // Cross coverage: critical scenarios
    cx_accept: cross cp_job_valid, cp_job_ready, cp_load_mode {
        ignore_bins blocked = binsof(cp_load_mode.loading);
    }
    
    cx_handoff: cross cp_job_active, cp_job_done, cp_job_valid {
        bins handoff_scenario = binsof(cp_job_active) intersect {1} &&
                                binsof(cp_job_done) intersect {1} &&
                                binsof(cp_job_valid) intersect {1};
    }
    
endgroup

cg_ray_job_interface cov_inst;

// ============================================================================
// TEST STIMULUS
// ============================================================================

// Initialize scoreboard
initial begin
    scoreboard = new();
end

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// Scoreboard checking (every cycle after reset)
always @(posedge clk) begin
    if (rst_n) begin
        // Update reference model
        scoreboard.update_model(
            load_mode, job_valid, job_done,
            ix0, iy0, iz0, sx, sy, sz,
            next_x, next_y, next_z,
            inc_x, inc_y, inc_z,
            max_steps
        );
        
        // Check DUT outputs
        scoreboard.check_outputs(
            job_ready, job_loaded, job_active,
            ix0_q, iy0_q, iz0_q, sx_q, sy_q, sz_q,
            next_x_q, next_y_q, next_z_q,
            inc_x_q, inc_y_q, inc_z_q,
            max_steps_q
        );
    end
end

// Main test sequence
initial begin
    // Initialize coverage
    cov_inst = new();
    
    // Handle +SEED plusarg
    if ($value$plusargs("SEED=%d", global_seed)) begin
        $display("[INFO] Using seed from plusarg: %0d", global_seed);
    end
    
    // Initialize signals
    load_mode = 0;
    job_valid = 0;
    job_done = 0;
    ix0 = 0; iy0 = 0; iz0 = 0;
    sx = 0; sy = 0; sz = 0;
    next_x = 0; next_y = 0; next_z = 0;
    inc_x = 0; inc_y = 0; inc_z = 0;
    max_steps = 0;
    
    // Reset
    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    
    $display("========================================");
    $display("Starting ray_job_if Verification");
    $display("========================================");
    
    // ========================================================================
    // DIRECTED TESTS
    // ========================================================================
    
    test_accept_when_idle();
    test_reject_during_load_mode();
    test_job_completion();
    test_handoff();
    test_backpressure();
    
    // ========================================================================
    // CONSTRAINED RANDOM TESTS
    // ========================================================================
    
    test_random_stimulus(1000);
    
    // ========================================================================
    // FINAL REPORT
    // ========================================================================
    
    repeat(10) @(posedge clk);
    
    $display("========================================");
    $display("Coverage Report:");
    $display("  Coverage: %.2f%%", cov_inst.get_coverage());
    $display("========================================");
    
    scoreboard.report();
    final_report();
    
    $finish;
end

// ============================================================================
// DIRECTED TEST TASKS
// ============================================================================

task test_accept_when_idle();
    $display("[TEST] Accept when idle");
    @(posedge clk);
    
    // Drive valid job
    job_valid = 1;
    ix0 = 5'd10;
    iy0 = 5'd15;
    iz0 = 5'd20;
    sx = 1; sy = 0; sz = 1;
    max_steps = 10'd100;
    
    @(posedge clk);
    if (!job_loaded) $fatal(1, "Job not loaded when idle and valid");
    
    job_valid = 0;
    @(posedge clk);
    
    if (ix0_q != 5'd10) $fatal(1, "ix0_q not latched correctly");
    
    // Complete the job
    repeat(5) @(posedge clk);
    job_done = 1;
    @(posedge clk);
    job_done = 0;
    
    report_pass("Accept when idle");
endtask

task test_reject_during_load_mode();
    $display("[TEST] Reject during load_mode");
    @(posedge clk);
    
    load_mode = 1;
    job_valid = 1;
    ix0 = 5'd5;
    
    @(posedge clk);
    if (job_loaded) $fatal(1, "Job accepted during load_mode");
    
    load_mode = 0;
    job_valid = 0;
    @(posedge clk);
    
    report_pass("Reject during load_mode");
endtask

task test_job_completion();
    $display("[TEST] Job completion");
    @(posedge clk);
    
    // Accept job
    job_valid = 1;
    ix0 = 5'd7;
    @(posedge clk);
    job_valid = 0;
    
    // Run active for N cycles
    repeat(10) @(posedge clk);
    if (!job_active) $fatal(1, "Job should be active");
    
    // Complete
    job_done = 1;
    @(posedge clk);
    job_done = 0;
    @(posedge clk);
    
    if (job_active) $fatal(1, "Job should be idle after completion");
    
    report_pass("Job completion");
endtask

task test_handoff();
    $display("[TEST] Handoff scenario");
    @(posedge clk);
    
    // Accept first job
    job_valid = 1;
    ix0 = 5'd1;
    @(posedge clk);
    
    // Run for a bit
    repeat(3) @(posedge clk);
    
    // Signal done and present new job same cycle
    job_done = 1;
    job_valid = 1;
    ix0 = 5'd2;
    
    @(posedge clk);
    if (!job_loaded) $fatal(1, "Handoff job not accepted");
    if (!job_active) $fatal(1, "Should remain active during handoff");
    
    job_done = 0;
    job_valid = 0;
    
    // Cleanup
    repeat(5) @(posedge clk);
    job_done = 1;
    @(posedge clk);
    job_done = 0;
    
    report_pass("Handoff scenario");
endtask

task test_backpressure();
    $display("[TEST] Backpressure");
    @(posedge clk);
    
    // Accept job
    job_valid = 1;
    ix0 = 5'd3;
    @(posedge clk);
    
    // Keep valid high but should only accept once
    int accept_count = 0;
    for (int i = 0; i < 10; i++) begin
        if (job_loaded) accept_count++;
        @(posedge clk);
    end
    
    if (accept_count != 1) $fatal(1, "Multiple accepts with backpressure");
    
    job_valid = 0;
    repeat(5) @(posedge clk);
    job_done = 1;
    @(posedge clk);
    job_done = 0;
    
    report_pass("Backpressure");
endtask

task test_random_stimulus(int num_cycles);
    $display("[TEST] Random stimulus for %0d cycles", num_cycles);
    
    for (int i = 0; i < num_cycles; i++) begin
        // Randomize inputs
        load_mode = ($urandom % 10) < 1;  // 10% load_mode
        job_valid = ($urandom % 2);
        
        if ($urandom % 100 < 5 && job_active) begin  // 5% chance if active
            job_done = 1;
        end else begin
            job_done = 0;
        end
        
        // Randomize job fields
        ix0 = $urandom;
        iy0 = $urandom;
        iz0 = $urandom;
        sx = $urandom;
        sy = $urandom;
        sz = $urandom;
        next_x = $urandom;
        next_y = $urandom;
        next_z = $urandom;
        inc_x = $urandom;
        inc_y = $urandom;
        inc_z = $urandom;
        max_steps = $urandom;
        
        @(posedge clk);
    end
    
    // Cleanup
    load_mode = 0;
    job_valid = 0;
    job_done = 0;
    
    if (job_active) begin
        repeat(5) @(posedge clk);
        job_done = 1;
        @(posedge clk);
        job_done = 0;
    end
    
    report_pass("Random stimulus");
endtask

// Dump waveforms
initial begin
    $dumpfile("tb_ray_job_if.fst");
    $dumpvars(0, tb_ray_job_if);
end

endmodule
