// E256 repaired round — NON-PRODUCTION RESEARCH RTL.
//
// One 256-bit round. Encrypt and decrypt are different paths. There is no
// reflector, no reverse rotor stack, and no second plugboard pass.
// Byte j is at row j%4, column j/4. Row offsets are (0,1,3,4).
//
// NOT a specification, suite, profile, fixture, or production core.

`default_nettype none

module e256r_inv_sbox (
    input  wire [7:0] x,
    output reg  [7:0] y
);
  reg [7:0] tab [0:255];
  initial $readmemh("e256r_inv_sbox.hex", tab);
  always @* y = tab[x];
endmodule

module e256r_round (
    input  wire         decrypt,
    input  wire [255:0] st,
    input  wire [255:0] mask,
    output wire [255:0] st_out
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

  wire [255:0] enc_sub;
  wire [255:0] enc_shf;
  wire [255:0] enc_mix;
  wire [255:0] dec_mix;
  wire [255:0] dec_shf;
  wire [255:0] dec_sub;

  genvar j, c, r;
  generate
    for (j = 0; j < 32; j = j + 1) begin : g_enc_sub
      wire [7:0] y;
      e256h_atk_sbox u_sb (.x(st[8*j +: 8] ^ mask[8*j +: 8]), .y(y));
      assign enc_sub[8*j +: 8] = y;
    end
    for (c = 0; c < 8; c = c + 1) begin : g_enc_sh
      for (r = 0; r < 4; r = r + 1) begin : g_enc_row
        localparam integer OFFR = (r == 0) ? 0 : (r == 1) ? 1 : (r == 2) ? 3 : 4;
        localparam integer SRC = 4 * ((c + OFFR) % 8) + r;
        assign enc_shf[8*(4*c+r) +: 8] = enc_sub[8*SRC +: 8];
      end
    end
    for (c = 0; c < 8; c = c + 1) begin : g_enc_mix
      wire [7:0] a0 = enc_shf[8*(4*c+0) +: 8];
      wire [7:0] a1 = enc_shf[8*(4*c+1) +: 8];
      wire [7:0] a2 = enc_shf[8*(4*c+2) +: 8];
      wire [7:0] a3 = enc_shf[8*(4*c+3) +: 8];
      assign enc_mix[8*(4*c+0) +: 8] = xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
      assign enc_mix[8*(4*c+1) +: 8] = a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
      assign enc_mix[8*(4*c+2) +: 8] = a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
      assign enc_mix[8*(4*c+3) +: 8] = xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
    end

    for (c = 0; c < 8; c = c + 1) begin : g_dec_mix
      wire [7:0] b0 = st[8*(4*c+0) +: 8];
      wire [7:0] b1 = st[8*(4*c+1) +: 8];
      wire [7:0] b2 = st[8*(4*c+2) +: 8];
      wire [7:0] b3 = st[8*(4*c+3) +: 8];
      assign dec_mix[8*(4*c+0) +: 8] = ge(b0) ^ gb(b1) ^ gd(b2) ^ g9(b3);
      assign dec_mix[8*(4*c+1) +: 8] = g9(b0) ^ ge(b1) ^ gb(b2) ^ gd(b3);
      assign dec_mix[8*(4*c+2) +: 8] = gd(b0) ^ g9(b1) ^ ge(b2) ^ gb(b3);
      assign dec_mix[8*(4*c+3) +: 8] = gb(b0) ^ gd(b1) ^ g9(b2) ^ ge(b3);
    end
    for (c = 0; c < 8; c = c + 1) begin : g_dec_sh
      for (r = 0; r < 4; r = r + 1) begin : g_dec_row
        localparam integer OFFR = (r == 0) ? 0 : (r == 1) ? 1 : (r == 2) ? 3 : 4;
        localparam integer SRC = 4 * ((c + 8 - OFFR) % 8) + r;
        assign dec_shf[8*(4*c+r) +: 8] = dec_mix[8*SRC +: 8];
      end
    end
    for (j = 0; j < 32; j = j + 1) begin : g_dec_sub
      wire [7:0] y;
      e256r_inv_sbox u_inv (.x(dec_shf[8*j +: 8]), .y(y));
      assign dec_sub[8*j +: 8] = y ^ mask[8*j +: 8];
    end
  endgenerate

  assign st_out = decrypt ? dec_sub : enc_mix;
endmodule

`default_nettype wire
