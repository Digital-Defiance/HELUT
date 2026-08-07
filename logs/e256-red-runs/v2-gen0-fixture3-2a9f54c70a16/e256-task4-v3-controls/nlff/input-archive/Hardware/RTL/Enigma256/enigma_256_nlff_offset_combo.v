`timescale 1ns / 1ps

// Past-NLFF Red Team combo: NLFF step enables + 8-bit offset next-state
// (offset + step, wrap) for all four rotors, plus high byte of Galois next.
// Matches the E256-v2/gen0 native reversible NLFF research profile.
// Densifies the cone past NLFF-only and NLFF+lfsr_next_hi.

module enigma_256_nlff_offset_combo (
    input  wire [63:0] lfsr,
    input  wire [7:0]  offset_r1,
    input  wire [7:0]  offset_r2,
    input  wire [7:0]  offset_r3,
    input  wire [7:0]  offset_r4,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4,
    output wire [7:0]  next_r1,
    output wire [7:0]  next_r2,
    output wire [7:0]  next_r3,
    output wire [7:0]  next_r4,
    output wire [7:0]  lfsr_next_hi
);
    wire [63:0] lfsr_next = {1'b0, lfsr[63:1]} ^ (lfsr[0] ? 64'hD800000000000000 : 64'h0);
    assign lfsr_next_hi = lfsr_next[63:56];

    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
    assign step_r1 = e256_nlff_step_r1;
    assign step_r2 = e256_nlff_step_r2;
    assign step_r3 = e256_nlff_step_r3;
    assign step_r4 = e256_nlff_step_r4;

    assign next_r1 = offset_r1 + {7'b0, step_r1};
    assign next_r2 = offset_r2 + {7'b0, step_r2};
    assign next_r3 = offset_r3 + {7'b0, step_r3};
    assign next_r4 = offset_r4 + {7'b0, step_r4};
endmodule
