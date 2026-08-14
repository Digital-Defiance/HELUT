`timescale 1ns / 1ps

// Frozen 1-byte / 1-round E256 SoftBus scramble (offsets = 0, identity plug).
// Algebra matches `enigma256ScrambleFrag` / scramble_frag_combo sboxes + UKW.
// Not live BRAM day-key tables. Not a full machine / NLFF step.

module e256_round1 (
    input  wire [7:0] pt,
    output wire [7:0] ct
);
    function automatic [7:0] sbox1;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[4:0], x[7:5]};
            b = a + 8'h3D;
            sbox1 = {b[6:0], b[7]};
        end
    endfunction
    function automatic [7:0] sbox1_inv;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[0], x[7:1]};
            b = a - 8'h3D;
            sbox1_inv = {b[2:0], b[7:3]};
        end
    endfunction
    function automatic [7:0] sbox2;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[2:0], x[7:3]};
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
            sbox2_inv = {b[4:0], b[7:5]};
        end
    endfunction
    function automatic [7:0] sbox3;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[5:0], x[7:6]};
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
            sbox3_inv = {b[1:0], b[7:2]};
        end
    endfunction
    function automatic [7:0] sbox4;
        input [7:0] x;
        reg [7:0] a, b;
        begin
            a = {x[0], x[7:1]};
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
            sbox4_inv = {b[6:0], b[7]};
        end
    endfunction
    function automatic [7:0] ukw;
        input [7:0] x;
        begin
            ukw = {x[3:0], x[7:4]} ^ 8'h55;
        end
    endfunction

    wire [7:0] r1 = sbox1(pt);
    wire [7:0] r2 = sbox2(r1);
    wire [7:0] r3 = sbox3(r2);
    wire [7:0] r4 = sbox4(r3);
    wire [7:0] rf = ukw(r4);
    wire [7:0] i4 = sbox4_inv(rf);
    wire [7:0] i3 = sbox3_inv(i4);
    wire [7:0] i2 = sbox2_inv(i3);
    assign ct = sbox1_inv(i2);
endmodule
