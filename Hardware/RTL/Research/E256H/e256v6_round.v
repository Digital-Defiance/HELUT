// E256-v6 research round. Not fixture-v4. Not E256-v5.
//
// One 32-byte round, read as 16 words of 16 bits.
// Encrypt: scale, GF(2^16) inverse, row shift, MixColumns.
// Decrypt: inverse mix, inverse shift, inverse rotor.
// No XOR mask. Polynomial x^16 + x^12 + x^3 + x + 1. No reflector.

`default_nettype none

module e256v6_round (
    input  wire         decrypt,
    input  wire [255:0] st,
    input  wire [255:0] scale,
    output wire [255:0] st_out
);
  function [15:0] gf_mul;
    input [15:0] a;
    input [15:0] b;
    integer i;
    reg [15:0] aa, acc;
    begin
      aa = a;
      acc = 16'h0;
      for (i = 0; i < 16; i = i + 1) begin
        if (b[i])
          acc = acc ^ aa;
        aa = aa[15] ? ({aa[14:0], 1'b0} ^ 16'h100B) : {aa[14:0], 1'b0};
      end
      gf_mul = acc;
    end
  endfunction

  function [15:0] gf_inv;
    input [15:0] x;
    integer b;
    reg [15:0] base, acc, exp;
    begin
      if (x == 16'h0)
        gf_inv = 16'h0;
      else begin
        base = x;
        acc = 16'h1;
        exp = 16'hFFFE;
        for (b = 0; b < 16; b = b + 1) begin
          if (exp[0])
            acc = gf_mul(acc, base);
          base = gf_mul(base, base);
          exp = exp >> 1;
        end
        gf_inv = acc;
      end
    end
  endfunction

  wire [255:0] enc_rot, enc_shf, enc_mix;
  wire [255:0] dec_mix, dec_shf, dec_rot;

  genvar col, row;
  generate
    for (col = 0; col < 4; col = col + 1) begin : g_rot
      for (row = 0; row < 4; row = row + 1) begin : g_word
        localparam integer W = 4 * col + row;
        wire [15:0] x = st[16 * W +: 16];
        wire [15:0] s = scale[16 * W +: 16];
        wire [15:0] inner = gf_mul(s, x);
        assign enc_rot[16 * W +: 16] = gf_inv(inner) ^ 16'h1;
        wire [15:0] y = dec_shf[16 * W +: 16];
        assign dec_rot[16 * W +: 16] = gf_mul(gf_inv(s), gf_inv(y ^ 16'h1));
      end
    end
    for (col = 0; col < 4; col = col + 1) begin : g_sh
      for (row = 0; row < 4; row = row + 1) begin : g_lane
        localparam integer DST = 4 * col + row;
        localparam integer SRC = 4 * ((col + row) % 4) + row;
        localparam integer BACK = 4 * ((col + 4 - row) % 4) + row;
        assign enc_shf[16 * DST +: 16] = enc_rot[16 * SRC +: 16];
        assign dec_shf[16 * DST +: 16] = dec_mix[16 * BACK +: 16];
      end
    end
    for (col = 0; col < 4; col = col + 1) begin : g_mix
      wire [15:0] a = enc_shf[16 * (4 * col + 0) +: 16];
      wire [15:0] b = enc_shf[16 * (4 * col + 1) +: 16];
      wire [15:0] c = enc_shf[16 * (4 * col + 2) +: 16];
      wire [15:0] d = enc_shf[16 * (4 * col + 3) +: 16];
      assign enc_mix[16 * (4 * col + 0) +: 16] = gf_mul(16'h02, a) ^ gf_mul(16'h03, b) ^ c ^ d;
      assign enc_mix[16 * (4 * col + 1) +: 16] = a ^ gf_mul(16'h02, b) ^ gf_mul(16'h03, c) ^ d;
      assign enc_mix[16 * (4 * col + 2) +: 16] = a ^ b ^ gf_mul(16'h02, c) ^ gf_mul(16'h03, d);
      assign enc_mix[16 * (4 * col + 3) +: 16] = gf_mul(16'h03, a) ^ b ^ c ^ gf_mul(16'h02, d);
      wire [15:0] p = st[16 * (4 * col + 0) +: 16];
      wire [15:0] q = st[16 * (4 * col + 1) +: 16];
      wire [15:0] r = st[16 * (4 * col + 2) +: 16];
      wire [15:0] s = st[16 * (4 * col + 3) +: 16];
      assign dec_mix[16 * (4 * col + 0) +: 16] =
        gf_mul(16'h0E, p) ^ gf_mul(16'h0B, q) ^ gf_mul(16'h0D, r) ^ gf_mul(16'h09, s);
      assign dec_mix[16 * (4 * col + 1) +: 16] =
        gf_mul(16'h09, p) ^ gf_mul(16'h0E, q) ^ gf_mul(16'h0B, r) ^ gf_mul(16'h0D, s);
      assign dec_mix[16 * (4 * col + 2) +: 16] =
        gf_mul(16'h0D, p) ^ gf_mul(16'h09, q) ^ gf_mul(16'h0E, r) ^ gf_mul(16'h0B, s);
      assign dec_mix[16 * (4 * col + 3) +: 16] =
        gf_mul(16'h0B, p) ^ gf_mul(16'h0D, q) ^ gf_mul(16'h09, r) ^ gf_mul(16'h0E, s);
    end
  endgenerate

  assign st_out = decrypt ? dec_rot : enc_mix;
endmodule
