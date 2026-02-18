// =============================================================================
// Module: scene_loader_if
// Description: Scene loader interface for voxel RAM initialization
//              Controls write access to voxel memory during load mode
//              Prevents RAM writes when load_mode=0 (during raycast operation)
//              Provides optional load completion counter
// =============================================================================

module scene_loader_if (
    input  logic        clock,
    input  logic        reset,
    
    // Load interface (valid/ready handshake)
    input  logic        load_mode,    // 1=loading enabled, 0=loading disabled
    input  logic        load_valid,
    output logic        load_ready,
    input  logic [14:0] load_addr,
    input  logic        load_data,
    
    // RAM write interface
    output logic        ram_wr_en,
    output logic [14:0] ram_wr_addr,
    output logic        ram_wr_data,
    
    // Status
    output logic [14:0] load_count,   // Number of voxels loaded
    output logic        load_complete // Pulse after each successful write
);

    // Load handshake: ready when in load mode
    assign load_ready = load_mode;
    
    // Gate writes: only allow when load_mode=1 and valid transaction
    assign ram_wr_en   = load_mode && load_valid && load_ready;
    assign ram_wr_addr = load_addr;
    assign ram_wr_data = load_data;
    
    // Generate completion pulse
    assign load_complete = ram_wr_en;
    
    // Count loaded voxels
    always_ff @(posedge clock) begin
        if (reset) begin
            load_count <= 15'd0;
        end else if (ram_wr_en) begin
            load_count <= load_count + 15'd1;
        end
    end

    // Assertions for verification
    `ifndef SYNTHESIS
    // Check: No writes when load_mode is disabled
    always_ff @(posedge clock) begin
        if (!reset && !load_mode && ram_wr_en) begin
            $error("ASSERTION FAILED: RAM write occurred when load_mode=0!");
        end
    end
    `endif

endmodule
