`timescale 1ns / 1ps

// Past-NLFF Red Team cone: NLFF + offset next-state + frozen reciprocal
// scramble fragment (identity plug → R1…R4 → un-UKW → rev → plug).
// Stand-in bijections — not live BRAM tables. Matches Swift
// `enigma256ScrambleFrag` in Enigma256TensorLUT.swift.

module enigma_256_scramble_frag_combo (
    input  wire [63:0] lfsr,
    input  wire [7:0]  data_in,
    input  wire [7:0]  offset_r1,
    input  wire [7:0]  offset_r2,
    input  wire [7:0]  offset_r3,
    input  wire [7:0]  offset_r4,
    output wire [7:0]  frag_out,
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

    // E256-v2/gen0 native reversible NLFF research profile.
    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
    assign step_r1 = e256_nlff_step_r1;
    assign step_r2 = e256_nlff_step_r2;
    assign step_r3 = e256_nlff_step_r3;
    assign step_r4 = e256_nlff_step_r4;
    wire center_mode = step_r1 ^ step_r2 ^ step_r3 ^ step_r4;

    assign next_r1 = offset_r1 + {7'b0, step_r1};
    assign next_r2 = offset_r2 + {7'b0, step_r2};
    assign next_r3 = offset_r3 + {7'b0, step_r3};
    assign next_r4 = offset_r4 + {7'b0, step_r4};

    // ---- Frozen bijections (must match Swift) ----
    function automatic [7:0] sbox1;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[4:0], x[7:5]}; // rotl 3
            b = a + 8'h3D;
            sbox1 = {b[6:0], b[7]}; // rotl 1
        end
    endfunction
    function automatic [7:0] sbox1_inv;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[0], x[7:1]}; // rotr 1
            b = a - 8'h3D;
            sbox1_inv = {b[2:0], b[7:3]}; // rotr 3
        end
    endfunction

    function automatic [7:0] sbox2;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[2:0], x[7:3]}; // rotl 5
            b = a ^ 8'hA5;
            sbox2 = b + 8'h11;
        end
    endfunction
    function automatic [7:0] sbox2_inv;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = x - 8'h11;
            b = a ^ 8'hA5;
            sbox2_inv = {b[4:0], b[7:5]}; // rotr 5
        end
    endfunction

    function automatic [7:0] sbox3;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[5:0], x[7:6]}; // rotl 2
            b = a ^ 8'hC3;
            sbox3 = b + 8'h27;
        end
    endfunction
    function automatic [7:0] sbox3_inv;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = x - 8'h27;
            b = a ^ 8'hC3;
            sbox3_inv = {b[1:0], b[7:2]}; // rotr 2
        end
    endfunction

    function automatic [7:0] sbox4;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[0], x[7:1]}; // rotl 7 == rotr 1
            b = a + 8'h6E;
            sbox4 = b ^ 8'h39;
        end
    endfunction
    function automatic [7:0] sbox4_inv;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = x ^ 8'h39;
            b = a - 8'h6E;
            sbox4_inv = {b[6:0], b[7]}; // rotr 7 == rotl 1
        end
    endfunction

    // Schema-3 frozen base reflector: adjacent swaps reserve 0 <-> 1.
    function automatic [7:0] base_reflector;
        input [7:0] x;
        begin
            base_reflector = x ^ 8'h01;
        end
    endfunction

    // Identity plug → four forward stages → UKW → four reverse → plug.
    wire [7:0] r1_in  = data_in + offset_r1;
    wire [7:0] r1_out = sbox1(r1_in) - offset_r1;
    wire [7:0] r2_in  = r1_out + offset_r2;
    wire [7:0] r2_out = sbox2(r2_in) - offset_r2;
    wire [7:0] r3_in  = r2_out + offset_r3;
    wire [7:0] r3_out = sbox3(r3_in) - offset_r3;
    wire [7:0] r4_in  = r3_out + offset_r4;
    wire [7:0] r4_out = sbox4(r4_in) - offset_r4;

    wire [7:0] ref_base = base_reflector(r4_out);
    wire       center_reserved = (r4_out[7:1] == 7'b0);
    wire [7:0] ref_out = (center_mode && center_reserved) ? r4_out : ref_base;

    wire [7:0] r4r_in  = ref_out + offset_r4;
    wire [7:0] r4r_out = sbox4_inv(r4r_in) - offset_r4;
    wire [7:0] r3r_in  = r4r_out + offset_r3;
    wire [7:0] r3r_out = sbox3_inv(r3r_in) - offset_r3;
    wire [7:0] r2r_in  = r3r_out + offset_r2;
    wire [7:0] r2r_out = sbox2_inv(r2r_in) - offset_r2;
    wire [7:0] r1r_in  = r2r_out + offset_r1;
    wire [7:0] r1r_out = sbox1_inv(r1r_in) - offset_r1;

    assign frag_out = r1r_out;
endmodule
