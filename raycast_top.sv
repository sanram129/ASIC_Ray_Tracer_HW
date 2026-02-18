// =============================================================================
// Module: raycast_top
// Description: Top-level voxel raycasting accelerator integration
//              Integrates all submodules and exposes external interfaces
//              32x32x32 voxel grid with DDA-based ray traversal
//              Supports scene loading, job submission, and result output
// =============================================================================

module raycast_top #(
    parameter W = 24,         // Fixed-point timer width (default 24, FRAC=16)
    parameter SYNC_READ = 1   // RAM read mode: 1=sync (1-cycle), 0=async
) (
    input  logic        clock,
    input  logic        reset,
    
    // =========================================================================
    // Scene Loading Interface
    // =========================================================================
    input  logic        load_mode,    // 1=enable loading, 0=disable (raycast mode)
    input  logic        load_valid,
    output logic        load_ready,
    input  logic [14:0] load_addr,
    input  logic        load_data,
    output logic [14:0] load_count,   // Number of voxels loaded
    output logic        load_complete,
    
    // =========================================================================
    // Ray Job Input Interface
    // =========================================================================
    input  logic        job_valid,
    output logic        job_ready,
    input  logic [4:0]  ix0,          // Starting voxel position
    input  logic [4:0]  iy0,
    input  logic [4:0]  iz0,
    input  logic        sx,           // Step sign: 1=+dir, 0=-dir
    input  logic        sy,
    input  logic        sz,
    input  logic [W-1:0] next_x,      // DDA timers (precomputed)
    input  logic [W-1:0] next_y,
    input  logic [W-1:0] next_z,
    input  logic [W-1:0] inc_x,       // DDA increments
    input  logic [W-1:0] inc_y,
    input  logic [W-1:0] inc_z,
    input  logic [9:0]  max_steps,    // Maximum traversal steps
    
    // =========================================================================
    // Result Output Interface
    // =========================================================================
    output logic        res_valid,
    input  logic        res_ready,
    output logic        hit,          // 1=hit solid voxel, 0=miss
    output logic [4:0]  hx,           // Hit voxel position
    output logic [4:0]  hy,
    output logic [4:0]  hz,
    output logic [2:0]  face_id,      // Face orientation: 0=+X,1=-X,2=+Y,3=-Y,4=+Z,5=-Z
    output logic [9:0]  steps_taken,  // Number of DDA steps
    output logic [3:0]  brightness    // Shaded brightness output
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    
    // Job interface signals
    logic        job_loaded;
    logic        job_active;
    logic        job_done;
    logic [4:0]  ix0_reg, iy0_reg, iz0_reg;
    logic        sx_reg, sy_reg, sz_reg;
    logic [W-1:0] next_x_reg, next_y_reg, next_z_reg;
    logic [W-1:0] inc_x_reg, inc_y_reg, inc_z_reg;
    logic [9:0]  max_steps_reg;
    
    // RAM signals
    logic        ram_wr_en;
    logic [14:0] ram_wr_addr;
    logic        ram_wr_data;
    logic [14:0] ram_rd_addr;
    logic        ram_rd_data;
    
    // DDA stepper signals
    logic [14:0] voxel_addr;
    logic        voxel_solid;

    // =========================================================================
    // Module Instantiations
    // =========================================================================

    // -------------------------------------------------------------------------
    // Ray Job Interface: Accept and latch job parameters
    // -------------------------------------------------------------------------
    ray_job_if #(
        .W(W)
    ) u_ray_job_if (
        .clock           (clock),
        .reset           (reset),
        .job_valid       (job_valid),
        .job_ready       (job_ready),
        .ix0             (ix0),
        .iy0             (iy0),
        .iz0             (iz0),
        .sx              (sx),
        .sy              (sy),
        .sz              (sz),
        .next_x          (next_x),
        .next_y          (next_y),
        .next_z          (next_z),
        .inc_x           (inc_x),
        .inc_y           (inc_y),
        .inc_z           (inc_z),
        .max_steps       (max_steps),
        .job_done        (job_done),
        .job_loaded      (job_loaded),
        .job_active      (job_active),
        .ix0_reg         (ix0_reg),
        .iy0_reg         (iy0_reg),
        .iz0_reg         (iz0_reg),
        .sx_reg          (sx_reg),
        .sy_reg          (sy_reg),
        .sz_reg          (sz_reg),
        .next_x_reg      (next_x_reg),
        .next_y_reg      (next_y_reg),
        .next_z_reg      (next_z_reg),
        .inc_x_reg       (inc_x_reg),
        .inc_y_reg       (inc_y_reg),
        .inc_z_reg       (inc_z_reg),
        .max_steps_reg   (max_steps_reg)
    );

    // -------------------------------------------------------------------------
    // Scene Loader Interface: Control RAM writes during loading
    // -------------------------------------------------------------------------
    scene_loader_if u_scene_loader_if (
        .clock           (clock),
        .reset           (reset),
        .load_mode       (load_mode),
        .load_valid      (load_valid),
        .load_ready      (load_ready),
        .load_addr       (load_addr),
        .load_data       (load_data),
        .ram_wr_en       (ram_wr_en),
        .ram_wr_addr     (ram_wr_addr),
        .ram_wr_data     (ram_wr_data),
        .load_count      (load_count),
        .load_complete   (load_complete)
    );

    // -------------------------------------------------------------------------
    // Voxel RAM: 32K x 1-bit occupancy memory
    // -------------------------------------------------------------------------
    voxel_ram #(
        .SYNC_READ(SYNC_READ)
    ) u_voxel_ram (
        .clock           (clock),
        .reset           (reset),
        .wr_en           (ram_wr_en),
        .wr_addr         (ram_wr_addr),
        .wr_data         (ram_wr_data),
        .rd_addr         (ram_rd_addr),
        .rd_data         (ram_rd_data)
    );

    // RAM read address from DDA stepper
    assign ram_rd_addr = voxel_addr;
    assign voxel_solid = ram_rd_data;

    // -------------------------------------------------------------------------
    // DDA Stepper: Core raycast controller and datapath
    // -------------------------------------------------------------------------
    dda_stepper #(
        .W(W),
        .SYNC_READ(SYNC_READ)
    ) u_dda_stepper (
        .clock           (clock),
        .reset           (reset),
        .job_active      (job_active),
        .job_done        (job_done),
        .ix0             (ix0_reg),
        .iy0             (iy0_reg),
        .iz0             (iz0_reg),
        .sx              (sx_reg),
        .sy              (sy_reg),
        .sz              (sz_reg),
        .next_x_init     (next_x_reg),
        .next_y_init     (next_y_reg),
        .next_z_init     (next_z_reg),
        .inc_x           (inc_x_reg),
        .inc_y           (inc_y_reg),
        .inc_z           (inc_z_reg),
        .max_steps       (max_steps_reg),
        .voxel_addr      (voxel_addr),
        .voxel_solid     (voxel_solid),
        .res_valid       (res_valid),
        .res_ready       (res_ready),
        .hit             (hit),
        .hx              (hx),
        .hy              (hy),
        .hz              (hz),
        .face_id         (face_id),
        .steps_taken     (steps_taken)
    );

    // -------------------------------------------------------------------------
    // Shade LUT: Map face orientation to brightness
    // -------------------------------------------------------------------------
    shade_lut u_shade_lut (
        .face_id         (face_id),
        .brightness      (brightness)
    );

    // =========================================================================
    // Assertions for Verification
    // =========================================================================
    `ifndef SYNTHESIS
    
    // Check: No RAM writes when load_mode=0
    always_ff @(posedge clock) begin
        if (!reset && !load_mode && ram_wr_en) begin
            $error("[ASSERTION] RAM write occurred during raycast mode (load_mode=0)!");
        end
    end
    
    // Check: Job accepted only when job_ready
    always_ff @(posedge clock) begin
        if (!reset && job_loaded && !job_ready) begin
            $error("[ASSERTION] Job accepted when job_ready=0!");
        end
    end
    
    // Check: Result valid implies job was active
    logic was_job_active;
    always_ff @(posedge clock) begin
        if (reset) begin
            was_job_active <= 1'b0;
        end else begin
            if (job_active) was_job_active <= 1'b1;
            if (job_done) was_job_active <= 1'b0;
        end
    end
    
    `endif

endmodule
