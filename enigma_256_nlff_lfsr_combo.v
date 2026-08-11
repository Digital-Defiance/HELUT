`timescale 1ns / 1ps

// Wider Red Team combo: NLFF step enables + high byte of Galois next-state.
// Matches live gen-5 cubic6 leaves in SoftBus / enigma_256_core.
// Low byte of lfsr_next is a trivial shift (no feedback taps); high byte
// includes the 0xD800… feedback and densifies the cone past NLFF-only.

module enigma_256_nlff_lfsr_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4,
    output wire [7:0]  lfsr_next_hi
);
    wire [63:0] lfsr_next = {lfsr[62:0], 1'b0} ^ (lfsr[63] ? 64'hD800000000000000 : 64'h0);
    assign lfsr_next_hi = lfsr_next[63:56];

    assign step_r1 = (lfsr[4]  & lfsr[15] & lfsr[17]) ^ (lfsr[23] & lfsr[26]) ^ lfsr[61];
    assign step_r2 = (lfsr[7]  & lfsr[9]  & lfsr[31]) ^ (lfsr[38] & lfsr[50]) ^ lfsr[59];
    assign step_r3 = (lfsr[30] & lfsr[43] & lfsr[46]) ^ (lfsr[49] & lfsr[51]) ^ lfsr[60];
    assign step_r4 = (lfsr[12] & lfsr[29] & lfsr[54]) ^ (lfsr[55] & lfsr[57]) ^ lfsr[62];
endmodule
