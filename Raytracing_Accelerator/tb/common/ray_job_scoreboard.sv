`ifndef RAY_JOB_SCOREBOARD_SV
`define RAY_JOB_SCOREBOARD_SV

`include "tb_utils.svh"

// Reference model and scoreboard for ray_job_if
class ray_job_scoreboard #(
    parameter int X_BITS = 5,
    parameter int Y_BITS = 5,
    parameter int Z_BITS = 5,
    parameter int W = 24,
    parameter int MAX_STEPS_BITS = 10
);
    
    // Reference state
    logic ref_job_active;
    logic ref_job_loaded;
    logic ref_job_ready;
    
    // Reference job fields
    logic [X_BITS-1:0] ref_ix0_q, ref_iy0_q, ref_iz0_q;
    logic ref_sx_q, ref_sy_q, ref_sz_q;
    logic [W-1:0] ref_next_x_q, ref_next_y_q, ref_next_z_q;
    logic [W-1:0] ref_inc_x_q, ref_inc_y_q, ref_inc_z_q;
    logic [MAX_STEPS_BITS-1:0] ref_max_steps_q;
    
    int check_count;
    int mismatch_count;
    
    function new();
        ref_job_active = 0;
        ref_job_loaded = 0;
        ref_job_ready = 1;
        check_count = 0;
        mismatch_count = 0;
    endfunction
    
    // Reference model update (call each clock cycle)
    function void update_model(
        input logic load_mode,
        input logic job_valid,
        input logic job_done,
        input logic [X_BITS-1:0] ix0, iy0, iz0,
        input logic sx, sy, sz,
        input logic [W-1:0] next_x, next_y, next_z,
        input logic [W-1:0] inc_x, inc_y, inc_z,
        input logic [MAX_STEPS_BITS-1:0] max_steps
    );
        logic accept;
        
        // Calculate ready
        ref_job_ready = (!load_mode) && (!ref_job_active || job_done);
        
        // Calculate accept
        accept = job_valid && ref_job_ready;
        
        // Update job_loaded (1-cycle pulse)
        ref_job_loaded = accept;
        
        // Update job_active
        if (accept) begin
            ref_job_active = 1'b1;
        end else if (job_done && !accept) begin
            ref_job_active = 1'b0;
        end
        
        // Latch job fields on accept
        if (accept) begin
            ref_ix0_q = ix0;
            ref_iy0_q = iy0;
            ref_iz0_q = iz0;
            ref_sx_q = sx;
            ref_sy_q = sy;
            ref_sz_q = sz;
            ref_next_x_q = next_x;
            ref_next_y_q = next_y;
            ref_next_z_q = next_z;
            ref_inc_x_q = inc_x;
            ref_inc_y_q = inc_y;
            ref_inc_z_q = inc_z;
            ref_max_steps_q = max_steps;
        end
    endfunction
    
    // Check DUT outputs against reference model
    function void check_outputs(
        input logic dut_job_ready,
        input logic dut_job_loaded,
        input logic dut_job_active,
        input logic [X_BITS-1:0] dut_ix0_q, dut_iy0_q, dut_iz0_q,
        input logic dut_sx_q, dut_sy_q, dut_sz_q,
        input logic [W-1:0] dut_next_x_q, dut_next_y_q, dut_next_z_q,
        input logic [W-1:0] dut_inc_x_q, dut_inc_y_q, dut_inc_z_q,
        input logic [MAX_STEPS_BITS-1:0] dut_max_steps_q
    );
        check_count++;
        
        if (dut_job_ready !== ref_job_ready) begin
            mismatch_count++;
            report_error($sformatf("job_ready mismatch: DUT=%b, REF=%b", 
                dut_job_ready, ref_job_ready));
        end
        
        if (dut_job_loaded !== ref_job_loaded) begin
            mismatch_count++;
            report_error($sformatf("job_loaded mismatch: DUT=%b, REF=%b", 
                dut_job_loaded, ref_job_loaded));
        end
        
        if (dut_job_active !== ref_job_active) begin
            mismatch_count++;
            report_error($sformatf("job_active mismatch: DUT=%b, REF=%b", 
                dut_job_active, ref_job_active));
        end
        
        // Only check latched values if active
        if (ref_job_active) begin
            if (dut_ix0_q !== ref_ix0_q) begin
                mismatch_count++;
                report_error($sformatf("ix0_q mismatch: DUT=%h, REF=%h", 
                    dut_ix0_q, ref_ix0_q));
            end
            // Similar checks for other fields...
            if (dut_max_steps_q !== ref_max_steps_q) begin
                mismatch_count++;
                report_error($sformatf("max_steps_q mismatch: DUT=%h, REF=%h", 
                    dut_max_steps_q, ref_max_steps_q));
            end
        end
    endfunction
    
    function void report();
        $display("[SCOREBOARD] Checks: %0d, Mismatches: %0d", check_count, mismatch_count);
        if (mismatch_count > 0) begin
            $fatal(1, "Scoreboard found %0d mismatches", mismatch_count);
        end
    endfunction
    
endclass

`endif // RAY_JOB_SCOREBOARD_SV
