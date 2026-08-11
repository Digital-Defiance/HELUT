`timescale 1ns / 1ps

// Combinational NLFF only — TensorLUT-friendly (no DFFs).
// Blue generation 2 — SoftBus field on Apple Silicon.

module enigma_256_nlff_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    assign step_r1 = (lfsr[46] & lfsr[49]) ^ lfsr[55];
    assign step_r2 = (lfsr[36] & lfsr[39]) ^ lfsr[41];
    assign step_r3 = (lfsr[50] & lfsr[54]) ^ lfsr[60];
    assign step_r4 = (lfsr[44] & lfsr[52]) ^ lfsr[56];
endmodule
