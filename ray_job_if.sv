// =============================================================================
// Module: ray_job_if
// Description: Ray job acceptance interface with valid/ready handshake
//              Latches job parameters and provides job_active signal
//              Supports backpressure: won't accept new job until current completes
// =============================================================================

module ray_job_if #(
    parameter W = 24  // Fixed-point timer width
) (
    input  logic        clock,
    input  logic        reset,
    
    // Job input interface (valid/ready handshake)
    input  logic        job_valid,
    output logic        job_ready,
    input  logic [4:0]  ix0,
    input  logic [4:0]  iy0,
    input  logic [4:0]  iz0,
    input  logic        sx,           // Sign bit: 1=+dir, 0=-dir
    input  logic        sy,
    input  logic        sz,
    input  logic [W-1:0] next_x,
    input  logic [W-1:0] next_y,
    input  logic [W-1:0] next_z,
    input  logic [W-1:0] inc_x,
    input  logic [W-1:0] inc_y,
    input  logic [W-1:0] inc_z,
    input  logic [9:0]  max_steps,
    
    // Control from DDA stepper
    input  logic        job_done,     // Pulse when job completes
    
    // Latched outputs
    output logic        job_loaded,   // Pulse when job accepted
    output logic        job_active,   // High while processing
    output logic [4:0]  ix0_reg,
    output logic [4:0]  iy0_reg,
    output logic [4:0]  iz0_reg,
    output logic        sx_reg,
    output logic        sy_reg,
    output logic        sz_reg,
    output logic [W-1:0] next_x_reg,
    output logic [W-1:0] next_y_reg,
    output logic [W-1:0] next_z_reg,
    output logic [W-1:0] inc_x_reg,
    output logic [W-1:0] inc_y_reg,
    output logic [W-1:0] inc_z_reg,
    output logic [9:0]  max_steps_reg
);

    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        ACTIVE      = 2'b01,
        COMPLETING  = 2'b10
    } state_t;

    state_t state, state_next;

    // State machine
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
                if (job_valid) begin
                    state_next = ACTIVE;
                end
            end
            
            ACTIVE: begin
                if (job_done) begin
                    state_next = COMPLETING;
                end
            end
            
            COMPLETING: begin
                state_next = IDLE;
            end
            
            default: state_next = IDLE;
        endcase
    end

    // Outputs
    assign job_ready  = (state == IDLE);
    assign job_loaded = (state == IDLE) && job_valid;
    assign job_active = (state == ACTIVE);

    // Latch job parameters when accepted
    always_ff @(posedge clock) begin
        if (reset) begin
            ix0_reg       <= 5'd0;
            iy0_reg       <= 5'd0;
            iz0_reg       <= 5'd0;
            sx_reg        <= 1'b0;
            sy_reg        <= 1'b0;
            sz_reg        <= 1'b0;
            next_x_reg    <= '0;
            next_y_reg    <= '0;
            next_z_reg    <= '0;
            inc_x_reg     <= '0;
            inc_y_reg     <= '0;
            inc_z_reg     <= '0;
            max_steps_reg <= 10'd0;
        end else if (job_loaded) begin
            ix0_reg       <= ix0;
            iy0_reg       <= iy0;
            iz0_reg       <= iz0;
            sx_reg        <= sx;
            sy_reg        <= sy;
            sz_reg        <= sz;
            next_x_reg    <= next_x;
            next_y_reg    <= next_y;
            next_z_reg    <= next_z;
            inc_x_reg     <= inc_x;
            inc_y_reg     <= inc_y;
            inc_z_reg     <= inc_z;
            max_steps_reg <= max_steps;
        end
    end

endmodule
