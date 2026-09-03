`timescale 1ns / 1ps

// Wider Red Team combo: NLFF step enables + high byte of Galois next-state.
// Matches the E256-v2/gen0 native reversible NLFF research profile.
// Right-shift/LSB feedback puts the 0xD800… contribution in the high byte,
// densifying the cone past NLFF-only.

module enigma_256_nlff_lfsr_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4,
    output wire [7:0]  lfsr_next_hi
);
    wire [63:0] lfsr_next = {1'b0, lfsr[63:1]} ^ (lfsr[0] ? 64'hD800000000000000 : 64'h0);
    assign lfsr_next_hi = lfsr_next[63:56];

    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
    assign step_r1 = e256_nlff_step_r1;
    assign step_r2 = e256_nlff_step_r2;
    assign step_r3 = e256_nlff_step_r3;
    assign step_r4 = e256_nlff_step_r4;
endmodule
