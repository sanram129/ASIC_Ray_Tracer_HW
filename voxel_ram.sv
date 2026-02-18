// =============================================================================
// Module: voxel_ram
// Description: 32K x 1-bit voxel occupancy memory
//              - 1 read port (sync or async via parameter)
//              - 1 write port (sync)
//              - Total size: 32768 bits (4 KB)
//              - Later replaceable with SKY130 SRAM macro
// =============================================================================

module voxel_ram #(
    parameter SYNC_READ = 1  // 1=synchronous read (1-cycle latency), 0=async
) (
    input  logic        clock,
    input  logic        reset,
    
    // Write port
    input  logic        wr_en,
    input  logic [14:0] wr_addr,
    input  logic        wr_data,
    
    // Read port
    input  logic [14:0] rd_addr,
    output logic        rd_data
);

    // Memory array: 32K x 1 bit
    logic mem [0:32767];

    // Synchronous write
    always_ff @(posedge clock) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    // Read port: sync or async based on parameter
    generate
        if (SYNC_READ) begin : gen_sync_read
            // Synchronous read (1-cycle latency)
            always_ff @(posedge clock) begin
                if (reset) begin
                    rd_data <= 1'b0;
                end else begin
                    rd_data <= mem[rd_addr];
                end
            end
        end else begin : gen_async_read
            // Asynchronous (combinational) read
            assign rd_data = mem[rd_addr];
        end
    endgenerate

endmodule
