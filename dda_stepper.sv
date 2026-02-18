// =============================================================================
// Module: dda_stepper
// Description: Core 3D DDA (Digital Differential Analyzer) controller
//              Traverses voxel grid using precomputed DDA parameters
//              Handles synchronous RAM read latency via FSM
//              Detects hits, determines face orientation, counts steps
//              Supports output backpressure via res_valid/res_ready
//
// Algorithm:
//   1. Find minimum of (next_x, next_y, next_z)
//   2. Step along that axis (increment index, add increment to timer)
//   3. Check bounds (out-of-bounds = miss)
//   4. Query RAM for voxel occupancy
//   5. If solid: hit! Record face_id and stop
//   6. If empty: continue to next step
//   7. Stop on hit, OOB, or max_steps reached
// =============================================================================

module dda_stepper #(
    parameter W = 24,         // Fixed-point timer width
    parameter SYNC_READ = 1   // RAM read latency: 1=sync, 0=async
) (
    input  logic        clock,
    input  logic        reset,
    
    // Job control
    input  logic        job_active,   // High when job is running
    output logic        job_done,     // Pulse when job completes
    
    // Job parameters (latched)
    input  logic [4:0]  ix0,
    input  logic [4:0]  iy0,
    input  logic [4:0]  iz0,
    input  logic        sx,           // Sign: 1=+dir, 0=-dir
    input  logic        sy,
    input  logic        sz,
    input  logic [W-1:0] next_x_init,
    input  logic [W-1:0] next_y_init,
    input  logic [W-1:0] next_z_init,
    input  logic [W-1:0] inc_x,
    input  logic [W-1:0] inc_y,
    input  logic [W-1:0] inc_z,
    input  logic [9:0]  max_steps,
    
    // RAM interface
    output logic [14:0] voxel_addr,
    input  logic        voxel_solid,  // 1=solid, 0=empty
    
    // Result interface (valid/ready handshake)
    output logic        res_valid,
    input  logic        res_ready,
    output logic        hit,
    output logic [4:0]  hx,
    output logic [4:0]  hy,
    output logic [4:0]  hz,
    output logic [2:0]  face_id,      // 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
    output logic [9:0]  steps_taken
);

    // =========================================================================
    // FSM States
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        INIT         = 3'b001,  // Initialize position and timers
        SELECT_AXIS  = 3'b010,  // Find min(next_x, next_y, next_z)
        STEP         = 3'b011,  // Step along selected axis
        WAIT_RAM     = 3'b100,  // Wait for RAM read (SYNC_READ only)
        CHECK_HIT    = 3'b101,  // Check voxel occupancy
        RESULT       = 3'b110   // Present result, wait for res_ready
    } state_t;

    state_t state, state_next;

    // =========================================================================
    // Datapath Registers
    // =========================================================================
    logic [4:0]  ix_reg, iy_reg, iz_reg;          // Current voxel position
    logic [W-1:0] next_x_reg, next_y_reg, next_z_reg; // DDA timers
    logic [9:0]  step_count;                       // Steps taken
    logic [2:0]  selected_axis;                    // 0=X, 1=Y, 2=Z
    logic        selected_sign;                    // Sign of selected axis
    logic        is_hit;                           // Hit flag
    logic        is_oob;                           // Out-of-bounds flag
    logic        is_max_steps;                     // Max steps reached

    // Result holding registers
    logic [4:0]  hx_reg, hy_reg, hz_reg;
    logic [2:0]  face_id_reg;
    logic [9:0]  steps_taken_reg;
    logic        hit_reg;

    // =========================================================================
    // Comparator Logic: Find min(next_x, next_y, next_z)
    // =========================================================================
    logic x_lt_y, x_lt_z, y_lt_z;
    logic [2:0] axis_select;
    
    assign x_lt_y = (next_x_reg < next_y_reg);
    assign x_lt_z = (next_x_reg < next_z_reg);
    assign y_lt_z = (next_y_reg < next_z_reg);
    
    // Priority: if tied, select X > Y > Z
    always_comb begin
        if (x_lt_y && x_lt_z) begin
            axis_select = 3'd0;  // X is minimum
        end else if (y_lt_z) begin
            axis_select = 3'd1;  // Y is minimum
        end else begin
            axis_select = 3'd2;  // Z is minimum
        end
    end

    // =========================================================================
    // Bounds Checking
    // =========================================================================
    logic [5:0] next_ix, next_iy, next_iz;  // 6-bit for overflow detection
    
    always_comb begin
        // Compute next position based on selected axis
        next_ix = {1'b0, ix_reg};
        next_iy = {1'b0, iy_reg};
        next_iz = {1'b0, iz_reg};
        
        case (selected_axis)
            3'd0: next_ix = sx ? ({1'b0, ix_reg} + 6'd1) : ({1'b0, ix_reg} - 6'd1);
            3'd1: next_iy = sy ? ({1'b0, iy_reg} + 6'd1) : ({1'b0, iy_reg} - 6'd1);
            3'd2: next_iz = sz ? ({1'b0, iz_reg} + 6'd1) : ({1'b0, iz_reg} - 6'd1);
            default: begin
                next_ix = {1'b0, ix_reg};
                next_iy = {1'b0, iy_reg};
                next_iz = {1'b0, iz_reg};
            end
        endcase
        
        // Check for out-of-bounds (overflow or underflow)
        is_oob = (next_ix[5] || next_ix > 6'd31) ||
                 (next_iy[5] || next_iy > 6'd31) ||
                 (next_iz[5] || next_iz > 6'd31);
    end

    // =========================================================================
    // Face ID Determination
    // =========================================================================
    always_comb begin
        case (selected_axis)
            3'd0: face_id_reg = sx ? 3'b000 : 3'b001;  // X: 0=+X, 1=-X
            3'd1: face_id_reg = sy ? 3'b010 : 3'b011;  // Y: 2=+Y, 3=-Y
            3'd2: face_id_reg = sz ? 3'b100 : 3'b101;  // Z: 4=+Z, 5=-Z
            default: face_id_reg = 3'b111;
        endcase
    end

    // =========================================================================
    // Address Mapping (inline)
    // =========================================================================
    assign voxel_addr = {iz_reg, iy_reg, ix_reg};

    // =========================================================================
    // Max Steps Check
    // =========================================================================
    assign is_max_steps = (step_count >= max_steps);

    // =========================================================================
    // State Machine
    // =========================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end

    always_comb begin
        state_next = state;
        
        case (state)
            IDLE: begin
                if (job_active) begin
                    state_next = INIT;
                end
            end
            
            INIT: begin
                state_next = SELECT_AXIS;
            end
            
            SELECT_AXIS: begin
                state_next = STEP;
            end
            
            STEP: begin
                if (is_oob || is_max_steps) begin
                    // Miss: OOB or max steps
                    state_next = RESULT;
                end else if (SYNC_READ) begin
                    // Wait for RAM read latency
                    state_next = WAIT_RAM;
                end else begin
                    // Async read: check immediately
                    state_next = CHECK_HIT;
                end
            end
            
            WAIT_RAM: begin
                // Wait 1 cycle for synchronous RAM
                state_next = CHECK_HIT;
            end
            
            CHECK_HIT: begin
                if (voxel_solid) begin
                    // Hit! Go to result
                    state_next = RESULT;
                end else begin
                    // Empty voxel, continue
                    state_next = SELECT_AXIS;
                end
            end
            
            RESULT: begin
                if (res_ready) begin
                    state_next = IDLE;
                end
                // Stay in RESULT until handshake completes
            end
            
            default: state_next = IDLE;
        endcase
    end

    // =========================================================================
    // Datapath Updates
    // =========================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            ix_reg         <= 5'd0;
            iy_reg         <= 5'd0;
            iz_reg         <= 5'd0;
            next_x_reg     <= '0;
            next_y_reg     <= '0;
            next_z_reg     <= '0;
            step_count     <= 10'd0;
            selected_axis  <= 3'd0;
            selected_sign  <= 1'b0;
            is_hit         <= 1'b0;
            hx_reg         <= 5'd0;
            hy_reg         <= 5'd0;
            hz_reg         <= 5'd0;
            steps_taken_reg <= 10'd0;
            hit_reg        <= 1'b0;
        end else begin
            case (state)
                INIT: begin
                    // Load initial position and timers
                    ix_reg     <= ix0;
                    iy_reg     <= iy0;
                    iz_reg     <= iz0;
                    next_x_reg <= next_x_init;
                    next_y_reg <= next_y_init;
                    next_z_reg <= next_z_init;
                    step_count <= 10'd0;
                    is_hit     <= 1'b0;
                end
                
                SELECT_AXIS: begin
                    // Select axis with minimum timer
                    selected_axis <= axis_select;
                    case (axis_select)
                        3'd0: selected_sign <= sx;
                        3'd1: selected_sign <= sy;
                        3'd2: selected_sign <= sz;
                        default: selected_sign <= 1'b0;
                    endcase
                end
                
                STEP: begin
                    if (!is_oob && !is_max_steps) begin
                        // Step along selected axis
                        case (selected_axis)
                            3'd0: begin
                                ix_reg <= sx ? (ix_reg + 5'd1) : (ix_reg - 5'd1);
                                next_x_reg <= next_x_reg + inc_x;
                            end
                            3'd1: begin
                                iy_reg <= sy ? (iy_reg + 5'd1) : (iy_reg - 5'd1);
                                next_y_reg <= next_y_reg + inc_y;
                            end
                            3'd2: begin
                                iz_reg <= sz ? (iz_reg + 5'd1) : (iz_reg - 5'd1);
                                next_z_reg <= next_z_reg + inc_z;
                            end
                            default: begin
                                // Should not happen
                            end
                        endcase
                        step_count <= step_count + 10'd1;
                    end
                end
                
                CHECK_HIT: begin
                    if (voxel_solid) begin
                        // Hit detected!
                        is_hit          <= 1'b1;
                        hx_reg          <= ix_reg;
                        hy_reg          <= iy_reg;
                        hz_reg          <= iz_reg;
                        steps_taken_reg <= step_count;
                        hit_reg         <= 1'b1;
                    end
                end
                
                RESULT: begin
                    if (state_next == IDLE) begin
                        // Capture miss case
                        if (!is_hit) begin
                            hx_reg          <= ix_reg;
                            hy_reg          <= iy_reg;
                            hz_reg          <= iz_reg;
                            steps_taken_reg <= step_count;
                            hit_reg         <= 1'b0;
                        end
                    end
                end
                
                default: begin
                    // Stay in current state
                end
            endcase
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign res_valid    = (state == RESULT);
    assign job_done     = (state == RESULT) && res_ready;
    assign hit          = hit_reg;
    assign hx           = hx_reg;
    assign hy           = hy_reg;
    assign hz           = hz_reg;
    assign face_id      = face_id_reg;
    assign steps_taken  = steps_taken_reg;

endmodule
