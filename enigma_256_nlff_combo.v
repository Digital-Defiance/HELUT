`timescale 1ns / 1ps

// Combinational NLFF only — TensorLUT-friendly (no DFFs).
// Blue generation 1 — SoftBus field on Apple Silicon.

module enigma_256_nlff_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    assign step_r1 = (lfsr[2] & lfsr[8]) ^ lfsr[21];
    assign step_r2 = (lfsr[0] & lfsr[6]) ^ lfsr[15];
    assign step_r3 = (lfsr[3] & lfsr[4]) ^ lfsr[12];
    assign step_r4 = (lfsr[11] & lfsr[17]) ^ lfsr[23];
endmodule
