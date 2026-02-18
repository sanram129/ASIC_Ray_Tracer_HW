// =============================================================================
// Module: voxel_addr_map
// Description: Combinational address mapping for 32x32x32 voxel grid
//              Maps (x,y,z) coordinates to linear memory address
//              Address format: {z[4:0], y[4:0], x[4:0]} = (z<<10)|(y<<5)|x
// =============================================================================

module voxel_addr_map (
    input  logic [4:0] ix,   // X coordinate (0..31)
    input  logic [4:0] iy,   // Y coordinate (0..31)
    input  logic [4:0] iz,   // Z coordinate (0..31)
    output logic [14:0] addr // Linear address (0..32767)
);

    // Direct bit concatenation: MSB=z, LSB=x
    assign addr = {iz, iy, ix};

endmodule
