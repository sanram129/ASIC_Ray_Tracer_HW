// =============================================================================
// Module: shade_lut
// Description: Maps face orientation to brightness multiplier (MVP shading)
//              Simple combinational LUT for per-face constant shading
//
// Face encoding:
//   3'b000 = +X face (brightness 2)
//   3'b001 = -X face (brightness 2)
//   3'b010 = +Y face (brightness 4, top/up)
//   3'b011 = -Y face (brightness 1, bottom/down)
//   3'b100 = +Z face (brightness 3)
//   3'b101 = -Z face (brightness 3)
//   3'b110, 3'b111 = reserved (brightness 0)
// =============================================================================

module shade_lut (
    input  logic [2:0] face_id,      // Which face was hit
    output logic [3:0] brightness    // Brightness multiplier (0..15)
);

    always_comb begin
        case (face_id)
            3'b000:  brightness = 4'd2;  // +X
            3'b001:  brightness = 4'd2;  // -X
            3'b010:  brightness = 4'd4;  // +Y (up, brightest)
            3'b011:  brightness = 4'd1;  // -Y (down, darkest)
            3'b100:  brightness = 4'd3;  // +Z
            3'b101:  brightness = 4'd3;  // -Z
            default: brightness = 4'd0;  // Invalid/miss
        endcase
    end

endmodule
