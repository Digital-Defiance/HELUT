// E256-v5 research round. Not fixture-v4. Not the staged E256-v3 fixture-v5.
//
// One 32-byte round of the patched multi-byte rotor machine.
// Encrypt: keyed affine rotor, row shift (0,1,3,4), MixColumns, XOR mask.
// Decrypt: XOR mask, inverse mix, inverse shift, inverse rotor.
// No reflector, no reverse rotor walk, no second plugboard.
// The schedule supplies the rotor. A mask change alone is not a new position.

`default_nettype none

module e256v5_round (
    input  wire          decrypt,
    input  wire [255:0]  st,
    input  wire [255:0]  mask,
    input  wire [255:0]  cin,
    input  wire [255:0]  cout,
    input  wire [2047:0] min_m,
    input  wire [2047:0] mout_m,
    input  wire [2047:0] min_inv,
    input  wire [2047:0] mout_inv,
    output wire [255:0]  st_out
);
  function [7:0] xt;
    input [7:0] v;
    begin
      xt = v[7] ? ((v << 1) ^ 8'h1b) : (v << 1);
    end
  endfunction

  function [7:0] g9;
    input [7:0] v;
    reg [7:0] x2, x4, x8;
    begin
      x2 = xt(v); x4 = xt(x2); x8 = xt(x4);
      g9 = x8 ^ v;
    end
  endfunction
  function [7:0] gb;
    input [7:0] v;
    reg [7:0] x2, x4, x8;
    begin
      x2 = xt(v); x4 = xt(x2); x8 = xt(x4);
      gb = x8 ^ x2 ^ v;
    end
  endfunction
  function [7:0] gd;
    input [7:0] v;
    reg [7:0] x2, x4, x8;
    begin
      x2 = xt(v); x4 = xt(x2); x8 = xt(x4);
      gd = x8 ^ x4 ^ v;
    end
  endfunction
  function [7:0] ge;
    input [7:0] v;
    reg [7:0] x2, x4, x8;
    begin
      x2 = xt(v); x4 = xt(x2); x8 = xt(x4);
      ge = x8 ^ x4 ^ x2;
    end
  endfunction

  function [7:0] matvec;
    input [63:0] rows;
    input [7:0] x;
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1)
        matvec[i] = ^(rows[8 * i +: 8] & x);
    end
  endfunction

  wire [255:0] enc_rot, enc_shf, enc_mix;
  wire [255:0] dec_unmask, dec_mix, dec_shf, dec_rot;

  genvar j, c, r;
  generate
    for (j = 0; j < 32; j = j + 1) begin : g_enc_rot
      wire [7:0] x = st[8 * j +: 8];
      wire [7:0] mixed = matvec(min_m[64 * j +: 64], x) ^ cin[8 * j +: 8];
      wire [7:0] sub;
      e256h_atk_sbox u_sb (.x(mixed), .y(sub));
      assign enc_rot[8 * j +: 8] = matvec(mout_m[64 * j +: 64], sub) ^ cout[8 * j +: 8];
    end
    for (c = 0; c < 8; c = c + 1) begin : g_enc_sh
      for (r = 0; r < 4; r = r + 1) begin : g_enc_row
        localparam integer OFFR = (r == 0) ? 0 : (r == 1) ? 1 : (r == 2) ? 3 : 4;
        localparam integer SRC = 4 * ((c + OFFR) % 8) + r;
        assign enc_shf[8 * (4 * c + r) +: 8] = enc_rot[8 * SRC +: 8];
      end
    end
    for (c = 0; c < 8; c = c + 1) begin : g_enc_mix
      wire [7:0] a0 = enc_shf[8 * (4 * c + 0) +: 8];
      wire [7:0] a1 = enc_shf[8 * (4 * c + 1) +: 8];
      wire [7:0] a2 = enc_shf[8 * (4 * c + 2) +: 8];
      wire [7:0] a3 = enc_shf[8 * (4 * c + 3) +: 8];
      assign enc_mix[8 * (4 * c + 0) +: 8] = xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
      assign enc_mix[8 * (4 * c + 1) +: 8] = a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
      assign enc_mix[8 * (4 * c + 2) +: 8] = a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
      assign enc_mix[8 * (4 * c + 3) +: 8] = xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
    end

    for (c = 0; c < 8; c = c + 1) begin : g_dec_mix
      wire [7:0] b0 = dec_unmask[8 * (4 * c + 0) +: 8];
      wire [7:0] b1 = dec_unmask[8 * (4 * c + 1) +: 8];
      wire [7:0] b2 = dec_unmask[8 * (4 * c + 2) +: 8];
      wire [7:0] b3 = dec_unmask[8 * (4 * c + 3) +: 8];
      assign dec_mix[8 * (4 * c + 0) +: 8] = ge(b0) ^ gb(b1) ^ gd(b2) ^ g9(b3);
      assign dec_mix[8 * (4 * c + 1) +: 8] = g9(b0) ^ ge(b1) ^ gb(b2) ^ gd(b3);
      assign dec_mix[8 * (4 * c + 2) +: 8] = gd(b0) ^ g9(b1) ^ ge(b2) ^ gb(b3);
      assign dec_mix[8 * (4 * c + 3) +: 8] = gb(b0) ^ gd(b1) ^ g9(b2) ^ ge(b3);
    end
    for (c = 0; c < 8; c = c + 1) begin : g_dec_sh
      for (r = 0; r < 4; r = r + 1) begin : g_dec_row
        localparam integer OFFR = (r == 0) ? 0 : (r == 1) ? 1 : (r == 2) ? 3 : 4;
        localparam integer SRC = 4 * ((c + 8 - OFFR) % 8) + r;
        assign dec_shf[8 * (4 * c + r) +: 8] = dec_mix[8 * SRC +: 8];
      end
    end
    for (j = 0; j < 32; j = j + 1) begin : g_dec_rot
      wire [7:0] y = dec_shf[8 * j +: 8] ^ cout[8 * j +: 8];
      wire [7:0] back = matvec(mout_inv[64 * j +: 64], y);
      wire [7:0] sub;
      e256r_inv_sbox u_inv (.x(back), .y(sub));
      assign dec_rot[8 * j +: 8] = matvec(min_inv[64 * j +: 64], sub ^ cin[8 * j +: 8]);
    end
  endgenerate

  assign dec_unmask = st ^ mask;
  assign st_out = decrypt ? dec_rot : (enc_mix ^ mask);
endmodule

`default_nettype wire
