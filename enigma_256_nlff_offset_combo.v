`timescale 1ns / 1ps

// Past-NLFF Red Team combo: NLFF step enables + 8-bit offset next-state
// (offset + step, wrap) for all four rotors, plus high byte of Galois next.
// Matches live gen-5 cubic6 leaves in SoftBus / enigma_256_core.
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
    wire [63:0] lfsr_next = {lfsr[62:0], 1'b0} ^ (lfsr[63] ? 64'hD800000000000000 : 64'h0);
    assign lfsr_next_hi = lfsr_next[63:56];

    assign step_r1 = (lfsr[4]  & lfsr[15] & lfsr[17]) ^ (lfsr[23] & lfsr[26]) ^ lfsr[61];
    assign step_r2 = (lfsr[7]  & lfsr[9]  & lfsr[31]) ^ (lfsr[38] & lfsr[50]) ^ lfsr[59];
    assign step_r3 = (lfsr[30] & lfsr[43] & lfsr[46]) ^ (lfsr[49] & lfsr[51]) ^ lfsr[60];
    assign step_r4 = (lfsr[12] & lfsr[29] & lfsr[54]) ^ (lfsr[55] & lfsr[57]) ^ lfsr[62];

    assign next_r1 = offset_r1 + {7'b0, step_r1};
    assign next_r2 = offset_r2 + {7'b0, step_r2};
    assign next_r3 = offset_r3 + {7'b0, step_r3};
    assign next_r4 = offset_r4 + {7'b0, step_r4};
endmodule
