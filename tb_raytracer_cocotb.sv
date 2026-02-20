`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// Module: tb_raytracer_cocotb
// Description: Thin cocotb top-level wrapper for raytracer_top.
//              All ports mirror raytracer_top exactly so cocotb can drive
//              and observe every signal directly.
//              Clock (clk) is driven by cocotb's Clock utility.
// =============================================================================
module tb_raytracer_cocotb #(
    parameter int COORD_WIDTH     = 16,
    parameter int COORD_W         = 6,
    parameter int TIMER_WIDTH     = 32,
    parameter int W               = 32,
    parameter int MAX_VAL         = 31,
    parameter int ADDR_BITS       = 15,
    parameter int X_BITS          = 5,
    parameter int Y_BITS          = 5,
    parameter int Z_BITS          = 5,
    parameter int MAX_STEPS_BITS  = 10,
    parameter int STEP_COUNT_WIDTH = 16
)(
    // =========================================================================
    // Clock & Reset (driven by cocotb)
    // =========================================================================
    input  logic                          clk,
    input  logic                          rst_n,

    // =========================================================================
    // Ray Job Input Interface
    // =========================================================================
    input  logic                          job_valid,
    output logic                          job_ready,

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
    // Scene Loading Interface
    // =========================================================================
    input  logic                          load_mode,
    input  logic                          load_valid,
    output logic                          load_ready,
    input  logic [ADDR_BITS-1:0]          load_addr,
    input  logic                          load_data,
    output logic [ADDR_BITS:0]            write_count,
    output logic                          load_complete,

    // =========================================================================
    // Ray Tracing Results
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
    // DUT Instantiation
    // =========================================================================
    raytracer_top #(
        .COORD_WIDTH    (COORD_WIDTH),
        .COORD_W        (COORD_W),
        .TIMER_WIDTH    (TIMER_WIDTH),
        .W              (W),
        .MAX_VAL        (MAX_VAL),
        .ADDR_BITS      (ADDR_BITS),
        .X_BITS         (X_BITS),
        .Y_BITS         (Y_BITS),
        .Z_BITS         (Z_BITS),
        .MAX_STEPS_BITS (MAX_STEPS_BITS),
        .STEP_COUNT_WIDTH(STEP_COUNT_WIDTH)
    ) u_raytracer_top (
        .clk            (clk),
        .rst_n          (rst_n),

        .job_valid      (job_valid),
        .job_ready      (job_ready),
        .job_ix0        (job_ix0),
        .job_iy0        (job_iy0),
        .job_iz0        (job_iz0),
        .job_sx         (job_sx),
        .job_sy         (job_sy),
        .job_sz         (job_sz),
        .job_next_x     (job_next_x),
        .job_next_y     (job_next_y),
        .job_next_z     (job_next_z),
        .job_inc_x      (job_inc_x),
        .job_inc_y      (job_inc_y),
        .job_inc_z      (job_inc_z),
        .job_max_steps  (job_max_steps),

        .load_mode      (load_mode),
        .load_valid     (load_valid),
        .load_ready     (load_ready),
        .load_addr      (load_addr),
        .load_data      (load_data),
        .write_count    (write_count),
        .load_complete  (load_complete),

        .ray_done       (ray_done),
        .ray_hit        (ray_hit),
        .ray_timeout    (ray_timeout),
        .hit_voxel_x    (hit_voxel_x),
        .hit_voxel_y    (hit_voxel_y),
        .hit_voxel_z    (hit_voxel_z),
        .hit_face_id    (hit_face_id),
        .steps_taken    (steps_taken)
    );

endmodule

`default_nettype wire
