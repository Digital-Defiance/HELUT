`timescale 1ns / 1ps

// Combinational NLFF only — TensorLUT-friendly (no DFFs).
// Blue generation 5 formula=cubic6 — SoftBus field on Apple Silicon.

module enigma_256_nlff_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    assign step_r1 = (lfsr[4] & lfsr[15] & lfsr[17]) ^ (lfsr[23] & lfsr[26]) ^ lfsr[61];
    assign step_r2 = (lfsr[7] & lfsr[9] & lfsr[31]) ^ (lfsr[38] & lfsr[50]) ^ lfsr[59];
    assign step_r3 = (lfsr[30] & lfsr[43] & lfsr[46]) ^ (lfsr[49] & lfsr[51]) ^ lfsr[60];
    assign step_r4 = (lfsr[12] & lfsr[29] & lfsr[54]) ^ (lfsr[55] & lfsr[57]) ^ lfsr[62];
endmodule
