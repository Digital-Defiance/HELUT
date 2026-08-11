`timescale 1ns / 1ps

// Combinational NLFF only — TensorLUT-friendly (no DFFs).
// Blue generation 3 formula=cubic6 — SoftBus field on Apple Silicon.

module enigma_256_nlff_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    assign step_r1 = (lfsr[0] & lfsr[13] & lfsr[27]) ^ (lfsr[5] & lfsr[41]) ^ lfsr[62];
    assign step_r2 = (lfsr[1] & lfsr[18] & lfsr[33]) ^ (lfsr[9] & lfsr[44]) ^ lfsr[58];
    assign step_r3 = (lfsr[2] & lfsr[21] & lfsr[36]) ^ (lfsr[11] & lfsr[48]) ^ lfsr[55];
    assign step_r4 = (lfsr[3] & lfsr[24] & lfsr[39]) ^ (lfsr[14] & lfsr[51]) ^ lfsr[60];
endmodule
