`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Module: raytracer_top
// Description: Complete raytracer system integrating:
//              - ray_job_if: Job input interface
//              - step_control_fsm: FSM for stepping control
//              - voxel_raytracer_core: Pipelined datapath (axis_choose, step_update, 
//                bounds_check, voxel_addr_map, voxel_ram, scene_loader_if)
//
// This top-level module resolves all interface compatibility issues and
// connects the FSM control flow with the pipelined datapath.
// =============================================================================
module raytracer_top #(
    // Coordinate and timer parameters
    parameter int COORD_WIDTH = 16,        // Voxel coordinate width for FSM
    parameter int COORD_W = 6,             // Coordinate width for bounds check
    parameter int TIMER_WIDTH = 32,        // Timer value width (fixed-point)
    parameter int W = 32,                  // Timer width for pipeline
    parameter int MAX_VAL = 31,            // Max coordinate value (0..31)
    
    // Address and step parameters
    parameter int ADDR_BITS = 15,          // Memory address bits (32^3 = 2^15)
    parameter int X_BITS = 5,              // X coordinate bits
    parameter int Y_BITS = 5,              // Y coordinate bits  
    parameter int Z_BITS = 5,              // Z coordinate bits
    parameter int MAX_STEPS_BITS = 10,     // Max steps counter width
    parameter int STEP_COUNT_WIDTH = 16    // Step counter width for FSM
)(
    // Clock and Reset
    input  logic                          clk,
    input  logic                          rst_n,
    
    // =========================================================================
    // Ray Job Input Interface (from CPU/testbench)
    // =========================================================================
    input  logic                          job_valid,
    output logic                          job_ready,
    
    // Ray job parameters (Option B format)
    input  logic [X_BITS-1:0]             job_ix0,
    input  logic [Y_BITS-1:0]             job_iy0,
    input  logic [Z_BITS-1:0]             job_iz0,
    input  logic                          job_sx,
    input  logic                          job_sy,
    input  logic                          job_sz,
    input  logic [W-1:0]                  job_next_x,
    input  logic [W-1:0]                  job_next_y,
    input  logic [W-1:0]                  job_next_z,
    input  logic [W-1:0]                  job_inc_x,
    input  logic [W-1:0]                  job_inc_y,
    input  logic [W-1:0]                  job_inc_z,
    input  logic [MAX_STEPS_BITS-1:0]     job_max_steps,
    
    // =========================================================================
    // Scene Loading Interface (from CPU/testbench)
    // =========================================================================
    input  logic                          load_mode,
    input  logic                          load_valid,
    output logic                          load_ready,
    input  logic [ADDR_BITS-1:0]          load_addr,
    input  logic                          load_data,
    output logic [ADDR_BITS:0]            write_count,
    output logic                          load_complete,
    
    // =========================================================================
    // Ray Tracing Results (to CPU/testbench)
    // =========================================================================
    output logic                          ray_done,
    output logic                          ray_hit,
    output logic                          ray_timeout,
    output logic [COORD_WIDTH-1:0]        hit_voxel_x,
    output logic [COORD_WIDTH-1:0]        hit_voxel_y,
    output logic [COORD_WIDTH-1:0]        hit_voxel_z,
    output logic [2:0]                    hit_face_id,
    output logic [STEP_COUNT_WIDTH-1:0]   steps_taken
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    
    // Ray job interface outputs
    logic                          job_loaded;
    logic                          job_active;
    logic [X_BITS-1:0]             ix0_q;
    logic [Y_BITS-1:0]             iy0_q;
    logic [Z_BITS-1:0]             iz0_q;
    logic                          sx_q, sy_q, sz_q;
    logic [W-1:0]                  next_x_q, next_y_q, next_z_q;
    logic [W-1:0]                  inc_x_q, inc_y_q, inc_z_q;
    logic [MAX_STEPS_BITS-1:0]     max_steps_q;
    
    // FSM to core signals
    logic                          step_valid;
    logic [X_BITS-1:0]             current_ix;
    logic [Y_BITS-1:0]             current_iy;
    logic [Z_BITS-1:0]             current_iz;
    logic [W-1:0]                  current_next_x;
    logic [W-1:0]                  current_next_y;
    logic [W-1:0]                  current_next_z;
    
    // Core to FSM feedback
    logic [X_BITS-1:0]             next_ix;
    logic [Y_BITS-1:0]             next_iy;
    logic [Z_BITS-1:0]             next_iz;
    logic [W-1:0]                  next_next_x;
    logic [W-1:0]                  next_next_y;
    logic [W-1:0]                  next_next_z;
    logic [2:0]                    face_mask;
    logic [2:0]                    primary_face_id;
    logic                          out_of_bounds;
    logic                          voxel_occupied;
    logic                          step_valid_out;
    
    // FSM control signals
    logic                          fsm_ready;
    logic                          fsm_done;
    
    // RAM address mapping
    logic [ADDR_BITS-1:0]          ram_addr;
    logic                          ram_read_req;
    logic [COORD_WIDTH-1:0]        ram_addr_x;
    logic [COORD_WIDTH-1:0]        ram_addr_y;
    logic [COORD_WIDTH-1:0]        ram_addr_z;
    
    // =========================================================================
    // Module Instantiation: ray_job_if
    // =========================================================================
    ray_job_if #(
        .X_BITS(X_BITS),
        .Y_BITS(Y_BITS),
        .Z_BITS(Z_BITS),
        .W(W),
        .MAX_STEPS_BITS(MAX_STEPS_BITS)
    ) u_ray_job_if (
        .clk(clk),
        .rst_n(rst_n),
        
        // Load mode gating
        .load_mode(load_mode),
        
        // Job input handshake
        .job_valid(job_valid),
        .job_ready(job_ready),
        
        // Job fields
        .ix0(job_ix0),
        .iy0(job_iy0),
        .iz0(job_iz0),
        .sx(job_sx),
        .sy(job_sy),
        .sz(job_sz),
        .next_x(job_next_x),
        .next_y(job_next_y),
        .next_z(job_next_z),
        .inc_x(job_inc_x),
        .inc_y(job_inc_y),
        .inc_z(job_inc_z),
        .max_steps(job_max_steps),
        
        // Job done from FSM
        .job_done(fsm_done),
        
        // Registered outputs
        .job_loaded(job_loaded),
        .job_active(job_active),
        .ix0_q(ix0_q),
        .iy0_q(iy0_q),
        .iz0_q(iz0_q),
        .sx_q(sx_q),
        .sy_q(sy_q),
        .sz_q(sz_q),
        .next_x_q(next_x_q),
        .next_y_q(next_y_q),
        .next_z_q(next_z_q),
        .inc_x_q(inc_x_q),
        .inc_y_q(inc_y_q),
        .inc_z_q(inc_z_q),
        .max_steps_q(max_steps_q)
    );
    
    // =========================================================================
    // Module Instantiation: step_control_fsm
    // =========================================================================
    // Note: FSM uses different clock/reset naming (clock/reset vs clk/rst_n)
    //       and different parameter widths
    
    step_control_fsm #(
        .COORD_WIDTH(COORD_WIDTH),
        .TIMER_WIDTH(TIMER_WIDTH),
        .STEP_COUNT_WIDTH(STEP_COUNT_WIDTH)
    ) u_step_control_fsm (
        .clock(clk),                    // Map clk -> clock
        .reset(~rst_n),                 // Map rst_n -> reset (inverted!)
        
        // Job control
        .job_loaded(job_loaded),
        .ready(fsm_ready),
        
        // Job parameters (width conversion: 5-bit -> COORD_WIDTH)
        .job_init_x({{(COORD_WIDTH-X_BITS){1'b0}}, ix0_q}),
        .job_init_y({{(COORD_WIDTH-Y_BITS){1'b0}}, iy0_q}),
        .job_init_z({{(COORD_WIDTH-Z_BITS){1'b0}}, iz0_q}),
        .job_dir_x_pos(sx_q),
        .job_dir_y_pos(sy_q),
        .job_dir_z_pos(sz_q),
        .job_timer_x({{(TIMER_WIDTH-W){1'b0}}, next_x_q}),
        .job_timer_y({{(TIMER_WIDTH-W){1'b0}}, next_y_q}),
        .job_timer_z({{(TIMER_WIDTH-W){1'b0}}, next_z_q}),
        .job_delta_x({{(TIMER_WIDTH-W){1'b0}}, inc_x_q}),
        .job_delta_y({{(TIMER_WIDTH-W){1'b0}}, inc_y_q}),
        .job_delta_z({{(TIMER_WIDTH-W){1'b0}}, inc_z_q}),
        .max_steps({{(STEP_COUNT_WIDTH-MAX_STEPS_BITS){1'b0}}, max_steps_q}),
        
        // Voxel data from RAM (via core pipeline)
        .solid_bit(voxel_occupied),
        .solid_valid(step_valid_out),   // Use pipeline valid as data valid
        
        // Bounds checking
        .out_of_bounds(out_of_bounds),
        
        // RAM control (address mapping handled below)
        .ram_read_req(ram_read_req),
        .ram_addr_x(ram_addr_x),
        .ram_addr_y(ram_addr_y),
        .ram_addr_z(ram_addr_z),
        
        // Current state (for pipeline input)
        .current_voxel_x(current_ix),
        .current_voxel_y(current_iy),
        .current_voxel_z(current_iz),
        .current_timer_x(current_next_x),
        .current_timer_y(current_next_y),
        .current_timer_z(current_next_z),
        .steps_taken(steps_taken),
        
        // Termination outputs
        .done(fsm_done),
        .hit(ray_hit),
        .timeout(ray_timeout),
        
        // Result outputs
        .hit_voxel_x(hit_voxel_x),
        .hit_voxel_y(hit_voxel_y),
        .hit_voxel_z(hit_voxel_z),
        .face_id(hit_face_id)
    );
    
    // Map FSM done to output
    assign ray_done = fsm_done;
    
    // =========================================================================
    // Module Instantiation: voxel_raytracer_core
    // =========================================================================
    // The core contains the full pipeline: axis_choose -> step_update ->
    // bounds_check -> voxel_addr_map -> voxel_ram -> scene_loader_if
    
    voxel_raytracer_core #(
        .W(W),
        .COORD_W(COORD_W),
        .MAX_VAL(MAX_VAL),
        .ADDR_BITS(ADDR_BITS)
    ) u_voxel_raytracer_core (
        .clk(clk),
        .rst_n(rst_n),
        
        // Ray step inputs (from FSM current state, truncated to 5 bits)
        .ix_in(current_ix[X_BITS-1:0]),
        .iy_in(current_iy[Y_BITS-1:0]),
        .iz_in(current_iz[Z_BITS-1:0]),
        .sx_in(sx_q),
        .sy_in(sy_q),
        .sz_in(sz_q),
        .next_x_in(current_next_x[W-1:0]),
        .next_y_in(current_next_y[W-1:0]),
        .next_z_in(current_next_z[W-1:0]),
        .inc_x_in(inc_x_q),
        .inc_y_in(inc_y_q),
        .inc_z_in(inc_z_q),
        .step_valid_in(job_active && fsm_ready),  // Valid when job active and FSM ready
        
        // Scene loading interface (pass through)
        .load_mode(load_mode),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_addr(load_addr),
        .load_data(load_data),
        .write_count(write_count),
        .load_complete(load_complete),
        
        // Ray step outputs (back to FSM - not used in current FSM design)
        .ix_out(next_ix),
        .iy_out(next_iy),
        .iz_out(next_iz),
        .next_x_out(next_next_x),
        .next_y_out(next_next_y),
        .next_z_out(next_next_z),
        .face_mask_out(face_mask),
        .primary_face_id_out(primary_face_id),
        .out_of_bounds_out(out_of_bounds),
        .voxel_occupied_out(voxel_occupied),
        .step_valid_out(step_valid_out)
    );
    
    // =========================================================================
    // Integration Notes:
    // =========================================================================
    // 1. The FSM (step_control_fsm) manages the stepping loop internally
    // 2. The core (voxel_raytracer_core) is a pipelined datapath
    // 3. Currently the FSM doesn't feed back updated positions from the core
    //    This is because the FSM has its own stepping logic
    // 4. The core's outputs (next_ix, next_iy, etc.) could be used to replace
    //    the FSM's internal stepping logic in a future iteration
    // 5. For now, the integration provides:
    //    - Job loading via ray_job_if
    //    - FSM control flow
    //    - Memory access via core's voxel_ram
    //    - Bounds checking and occupancy detection

endmodule

`default_nettype wire
