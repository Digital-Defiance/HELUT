`timescale 1ns / 1ps

// Combinational NLFF only — TensorLUT-friendly (no DFFs).
// Matches enigma_256_core / enigma_256_step_cone step enables.

module enigma_256_nlff_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    assign step_r1 = (lfsr[0]  & lfsr[7])  ^ lfsr[12];
    assign step_r2 = (lfsr[15] & lfsr[22]) ^ lfsr[29];
    assign step_r3 = (lfsr[31] & lfsr[38]) ^ lfsr[45];
    assign step_r4 = (lfsr[47] & lfsr[54]) ^ lfsr[61];
endmodule
