// Step Control FSM for DDA Ray-Tracer
// Complete implementation with job loading, bounds checking, solid detection
// SKY130 Process Target

module step_control_fsm #(
    parameter int COORD_WIDTH = 16,     // Voxel coordinate width
    parameter int TIMER_WIDTH = 32,     // Timer value width (fixed-point)
    parameter int STEP_COUNT_WIDTH = 16 // Step counter width
) (
    input  logic                          clock,
    input  logic                          reset,
    
    // Job control
    input  logic                          job_loaded,      // Job parameters loaded and ready
    output logic                          ready,           // Ready for new job
    
    // Job parameters (loaded once at start)
    input  logic [COORD_WIDTH-1:0]        job_init_x,
    input  logic [COORD_WIDTH-1:0]        job_init_y,
    input  logic [COORD_WIDTH-1:0]        job_init_z,
    input  logic                          job_dir_x_pos,
    input  logic                          job_dir_y_pos,
    input  logic                          job_dir_z_pos,
    input  logic [TIMER_WIDTH-1:0]        job_timer_x,
    input  logic [TIMER_WIDTH-1:0]        job_timer_y,
    input  logic [TIMER_WIDTH-1:0]        job_timer_z,
    input  logic [TIMER_WIDTH-1:0]        job_delta_x,
    input  logic [TIMER_WIDTH-1:0]        job_delta_y,
    input  logic [TIMER_WIDTH-1:0]        job_delta_z,
    input  logic [STEP_COUNT_WIDTH-1:0]   max_steps,       // Maximum steps before timeout
    
    // Voxel data from RAM
    input  logic                          solid_bit,       // Current voxel is solid (from RAM)
    input  logic                          solid_valid,     // Solid bit data is valid
    
    // Bounds checking
    input  logic                          out_of_bounds,   // Current voxel is out of bounds
    
    // RAM control signals
    output logic                          ram_read_req,    // Request RAM read
    output logic [COORD_WIDTH-1:0]        ram_addr_x,      // RAM address X
    output logic [COORD_WIDTH-1:0]        ram_addr_y,      // RAM address Y
    output logic [COORD_WIDTH-1:0]        ram_addr_z,      // RAM address Z
    
    // Current state outputs (continuously updated)
    output logic [COORD_WIDTH-1:0]        current_voxel_x,
    output logic [COORD_WIDTH-1:0]        current_voxel_y,
    output logic [COORD_WIDTH-1:0]        current_voxel_z,
    output logic [TIMER_WIDTH-1:0]        current_timer_x,
    output logic [TIMER_WIDTH-1:0]        current_timer_y,
    output logic [TIMER_WIDTH-1:0]        current_timer_z,
    output logic [STEP_COUNT_WIDTH-1:0]   steps_taken,
    
    // Termination outputs
    output logic                          done,            // Ray trace complete
    output logic                          hit,             // Hit solid voxel
    output logic                          timeout,         // Exceeded max_steps
    
    // Result outputs (valid when done=1)
    output logic [COORD_WIDTH-1:0]        hit_voxel_x,
    output logic [COORD_WIDTH-1:0]        hit_voxel_y,
    output logic [COORD_WIDTH-1:0]        hit_voxel_z,
    output logic [2:0]                    face_id          // One-hot: [2]=Z, [1]=Y, [0]=X
);

    // FSM State Definition
    typedef enum logic [2:0] {
        IDLE           = 3'b000,  // Waiting for job
        INIT           = 3'b001,  // Initialize from job
        CHECK_RAM      = 3'b010,  // Request RAM read and wait
        COMPARE        = 3'b011,  // Compare timers, choose axis
        UPDATE         = 3'b100,  // Update voxel and timer
        CHECK_TERM     = 3'b101,  // Check termination conditions
        FINISH         = 3'b110   // Output results
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal state registers
    logic [COORD_WIDTH-1:0]      voxel_x_reg;
    logic [COORD_WIDTH-1:0]      voxel_y_reg;
    logic [COORD_WIDTH-1:0]      voxel_z_reg;
    logic [TIMER_WIDTH-1:0]      timer_x_reg;
    logic [TIMER_WIDTH-1:0]      timer_y_reg;
    logic [TIMER_WIDTH-1:0]      timer_z_reg;
    logic [STEP_COUNT_WIDTH-1:0] step_counter;
    
    // Job parameter registers (loaded once)
    logic                        dir_x_pos_reg;
    logic                        dir_y_pos_reg;
    logic                        dir_z_pos_reg;
    logic [TIMER_WIDTH-1:0]      delta_x_reg;
    logic [TIMER_WIDTH-1:0]      delta_y_reg;
    logic [TIMER_WIDTH-1:0]      delta_z_reg;
    logic [STEP_COUNT_WIDTH-1:0] max_steps_reg;
    
    // Result registers
    logic [COORD_WIDTH-1:0]      hit_x_reg;
    logic [COORD_WIDTH-1:0]      hit_y_reg;
    logic [COORD_WIDTH-1:0]      hit_z_reg;
    logic [2:0]                  face_reg;
    
    // Status flags
    logic                        hit_flag;
    logic                        timeout_flag;
    logic                        bounds_flag;
    
    // Timer comparison results
    logic                        x_is_min;
    logic                        y_is_min;
    logic                        z_is_min;
    
    //----------------------------------------------------------------------
    // State Register
    //----------------------------------------------------------------------
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    //----------------------------------------------------------------------
    // Next State Logic
    //----------------------------------------------------------------------
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (job_loaded) begin
                    next_state = INIT;
                end
            end
            
            INIT: begin
                // Initialize complete, start ray tracing
                next_state = CHECK_RAM;
            end
            
            CHECK_RAM: begin
                // Wait for RAM data to be valid
                if (solid_valid) begin
                    next_state = COMPARE;
                end
            end
            
            COMPARE: begin
                // Timer comparison done
                next_state = UPDATE;
            end
            
            UPDATE: begin
                // Voxel/timer update done
                next_state = CHECK_TERM;
            end
            
            CHECK_TERM: begin
                // Check if we should continue or terminate
                if (hit_flag || timeout_flag || bounds_flag) begin
                    next_state = FINISH;
                end else begin
                    next_state = CHECK_RAM;  // Continue loop
                end
            end
            
            FINISH: begin
                // Hold results for one cycle
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    //----------------------------------------------------------------------
    // Timer Comparison Logic
    //----------------------------------------------------------------------
    always_comb begin
        // Determine which timer has minimum value
        // Priority: X > Y > Z (if equal, X takes precedence)
        x_is_min = (timer_x_reg <= timer_y_reg) && (timer_x_reg <= timer_z_reg);
        y_is_min = (timer_y_reg < timer_x_reg) && (timer_y_reg <= timer_z_reg);
        z_is_min = (timer_z_reg < timer_x_reg) && (timer_z_reg < timer_y_reg);
    end
    
    //----------------------------------------------------------------------
    // Datapath Logic
    //----------------------------------------------------------------------
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            voxel_x_reg     <= '0;
            voxel_y_reg     <= '0;
            voxel_z_reg     <= '0;
            timer_x_reg     <= '0;
            timer_y_reg     <= '0;
            timer_z_reg     <= '0;
            step_counter    <= '0;
            dir_x_pos_reg   <= 1'b1;
            dir_y_pos_reg   <= 1'b1;
            dir_z_pos_reg   <= 1'b1;
            delta_x_reg     <= '0;
            delta_y_reg     <= '0;
            delta_z_reg     <= '0;
            max_steps_reg   <= '0;
            hit_x_reg       <= '0;
            hit_y_reg       <= '0;
            hit_z_reg       <= '0;
            face_reg        <= 3'b000;
            hit_flag        <= 1'b0;
            timeout_flag    <= 1'b0;
            bounds_flag     <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    // Reset flags
                    hit_flag     <= 1'b0;
                    timeout_flag <= 1'b0;
                    bounds_flag  <= 1'b0;
                    step_counter <= '0;
                end
                
                INIT: begin
                    // Load job parameters
                    voxel_x_reg   <= job_init_x;
                    voxel_y_reg   <= job_init_y;
                    voxel_z_reg   <= job_init_z;
                    timer_x_reg   <= job_timer_x;
                    timer_y_reg   <= job_timer_y;
                    timer_z_reg   <= job_timer_z;
                    dir_x_pos_reg <= job_dir_x_pos;
                    dir_y_pos_reg <= job_dir_y_pos;
                    dir_z_pos_reg <= job_dir_z_pos;
                    delta_x_reg   <= job_delta_x;
                    delta_y_reg   <= job_delta_y;
                    delta_z_reg   <= job_delta_z;
                    max_steps_reg <= max_steps;
                    step_counter  <= '0;
                end
                
                CHECK_RAM: begin
                    // Wait for RAM, no register updates
                end
                
                COMPARE: begin
                    // Comparison in combinational logic
                end
                
                UPDATE: begin
                    // Update voxel and timer based on which axis has minimum timer
                    if (x_is_min) begin
                        if (dir_x_pos_reg) begin
                            voxel_x_reg <= voxel_x_reg + 1'b1;
                        end else begin
                            voxel_x_reg <= voxel_x_reg - 1'b1;
                        end
                        timer_x_reg <= timer_x_reg + delta_x_reg;
                        face_reg <= 3'b001;  // X face
                    end else if (y_is_min) begin
                        if (dir_y_pos_reg) begin
                            voxel_y_reg <= voxel_y_reg + 1'b1;
                        end else begin
                            voxel_y_reg <= voxel_y_reg - 1'b1;
                        end
                        timer_y_reg <= timer_y_reg + delta_y_reg;
                        face_reg <= 3'b010;  // Y face
                    end else if (z_is_min) begin
                        if (dir_z_pos_reg) begin
                            voxel_z_reg <= voxel_z_reg + 1'b1;
                        end else begin
                            voxel_z_reg <= voxel_z_reg - 1'b1;
                        end
                        timer_z_reg <= timer_z_reg + delta_z_reg;
                        face_reg <= 3'b100;  // Z face
                    end
                    
                    // Increment step counter
                    step_counter <= step_counter + 1'b1;
                end
                
                CHECK_TERM: begin
                    // Check termination conditions
                    if (solid_bit) begin
                        hit_flag  <= 1'b1;
                        hit_x_reg <= voxel_x_reg;
                        hit_y_reg <= voxel_y_reg;
                        hit_z_reg <= voxel_z_reg;
                    end
                    
                    if (step_counter >= max_steps_reg) begin
                        timeout_flag <= 1'b1;
                    end
                    
                    if (out_of_bounds) begin
                        bounds_flag <= 1'b1;
                    end
                end
                
                FINISH: begin
                    // Hold final values
                end
                
                default: begin
                    // Do nothing
                end
            endcase
        end
    end
    
    //----------------------------------------------------------------------
    // RAM Control Logic
    //----------------------------------------------------------------------
    always_comb begin
        // Request RAM read when checking current voxel
        ram_read_req = (current_state == CHECK_RAM);
        
        // RAM address is always the current voxel position
        ram_addr_x = voxel_x_reg;
        ram_addr_y = voxel_y_reg;
        ram_addr_z = voxel_z_reg;
    end
    
    //----------------------------------------------------------------------
    // Output Logic
    //----------------------------------------------------------------------
    always_comb begin
        // Ready signal
        ready = (current_state == IDLE);
        
        // Termination signals
        done    = (current_state == FINISH);
        hit     = hit_flag;
        timeout = timeout_flag;
        
        // Current state outputs (always visible)
        current_voxel_x = voxel_x_reg;
        current_voxel_y = voxel_y_reg;
        current_voxel_z = voxel_z_reg;
        current_timer_x = timer_x_reg;
        current_timer_y = timer_y_reg;
        current_timer_z = timer_z_reg;
        steps_taken     = step_counter;
        
        // Result outputs (final hit location)
        hit_voxel_x = hit_x_reg;
        hit_voxel_y = hit_y_reg;
        hit_voxel_z = hit_z_reg;
        face_id     = face_reg;
    end

endmodule
