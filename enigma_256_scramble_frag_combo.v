`timescale 1ns / 1ps

// Past-NLFF Red Team cone: NLFF + offset next-state + a frozen two-rotor
// scramble fragment (plug identity → R1 → R2) with bit-sliced bijections.
// Not the live BRAM tables — a denser synthesizable stand-in for Red pressure
// beyond step/offset cones. Matches Swift `enigma256FragSbox` / `enigma256FragSbox2`.

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
    wire [63:0] lfsr_next = {lfsr[62:0], 1'b0} ^ (lfsr[63] ? 64'hD800000000000000 : 64'h0);
    assign lfsr_next_hi = lfsr_next[63:56];

    // Gen-5 cubic6 NLFF (live SoftBus folds).
    assign step_r1 = (lfsr[4]  & lfsr[15] & lfsr[17]) ^ (lfsr[23] & lfsr[26]) ^ lfsr[61];
    assign step_r2 = (lfsr[7]  & lfsr[9]  & lfsr[31]) ^ (lfsr[38] & lfsr[50]) ^ lfsr[59];
    assign step_r3 = (lfsr[30] & lfsr[43] & lfsr[46]) ^ (lfsr[49] & lfsr[51]) ^ lfsr[60];
    assign step_r4 = (lfsr[12] & lfsr[29] & lfsr[54]) ^ (lfsr[55] & lfsr[57]) ^ lfsr[62];

    assign next_r1 = offset_r1 + {7'b0, step_r1};
    assign next_r2 = offset_r2 + {7'b0, step_r2};
    assign next_r3 = offset_r3 + {7'b0, step_r3};
    assign next_r4 = offset_r4 + {7'b0, step_r4};

    // Frozen bijections (Red stand-in for BRAM rotors) — must match Swift oracle.
    function automatic [7:0] sbox1;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[4:0], x[7:5]};          // rotl 3
            b = a + 8'h3D;
            sbox1 = {b[6:0], b[7]};        // rotl 1
        end
    endfunction

    function automatic [7:0] sbox2;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[2:0], x[7:3]};          // rotl 5
            b = a ^ 8'hA5;
            sbox2 = b + 8'h11;
        end
    endfunction

    // Identity plugboard → R1 stage → R2 stage (forward only fragment).
    wire [7:0] r1_in  = data_in + offset_r1;
    wire [7:0] r1_out = sbox1(r1_in) - offset_r1;
    wire [7:0] r2_in  = r1_out + offset_r2;
    wire [7:0] r2_out = sbox2(r2_in) - offset_r2;
    assign frag_out = r2_out;
endmodule
