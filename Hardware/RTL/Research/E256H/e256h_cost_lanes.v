// E256-H rotor-lane cost model — NON-PRODUCTION RESEARCH RTL.
//
// Purpose: measure the marginal LUT6 cost of four rotor keying schemes for one
// byte lane, holding the S-box description constant, so that constraint H3 in
// directives/e256-hardware-architecture.md is decided by synthesis rather than
// by hand estimate.
//
// Contract: directives/e256-hardware-cost-preregistration.json
// Runner:   Scripts/e256_hardware_cost_gate.py
//
// This is NOT a specification, suite, profile, fixture, or production core. It
// is combinational, unregistered, and deliberately minimal. No timing, power,
// or side-channel property is claimed. Constant latency is not side-channel
// resistance.
//
// Every S-box-bearing variant instantiates the SAME e256h_aes_sbox truth-table
// description, so differences between variants are keying overhead only. The
// absolute S-box cost reflects a truth table optimized by ABC and must not be
// compared against published tower-field gate-equivalent figures.

`default_nettype none

// ---------------------------------------------------------------------------
// Shared AES S-box, truth-table description.
// SHA-256 of the 256 table bytes in input order:
//   c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2
module e256h_aes_sbox (
    input  wire [7:0] x,
    output reg  [7:0] y
);
  always @* begin
    case (x)
      8'h00: y = 8'h63; 8'h01: y = 8'h7c; 8'h02: y = 8'h77; 8'h03: y = 8'h7b;
      8'h04: y = 8'hf2; 8'h05: y = 8'h6b; 8'h06: y = 8'h6f; 8'h07: y = 8'hc5;
      8'h08: y = 8'h30; 8'h09: y = 8'h01; 8'h0a: y = 8'h67; 8'h0b: y = 8'h2b;
      8'h0c: y = 8'hfe; 8'h0d: y = 8'hd7; 8'h0e: y = 8'hab; 8'h0f: y = 8'h76;
      8'h10: y = 8'hca; 8'h11: y = 8'h82; 8'h12: y = 8'hc9; 8'h13: y = 8'h7d;
      8'h14: y = 8'hfa; 8'h15: y = 8'h59; 8'h16: y = 8'h47; 8'h17: y = 8'hf0;
      8'h18: y = 8'had; 8'h19: y = 8'hd4; 8'h1a: y = 8'ha2; 8'h1b: y = 8'haf;
      8'h1c: y = 8'h9c; 8'h1d: y = 8'ha4; 8'h1e: y = 8'h72; 8'h1f: y = 8'hc0;
      8'h20: y = 8'hb7; 8'h21: y = 8'hfd; 8'h22: y = 8'h93; 8'h23: y = 8'h26;
      8'h24: y = 8'h36; 8'h25: y = 8'h3f; 8'h26: y = 8'hf7; 8'h27: y = 8'hcc;
      8'h28: y = 8'h34; 8'h29: y = 8'ha5; 8'h2a: y = 8'he5; 8'h2b: y = 8'hf1;
      8'h2c: y = 8'h71; 8'h2d: y = 8'hd8; 8'h2e: y = 8'h31; 8'h2f: y = 8'h15;
      8'h30: y = 8'h04; 8'h31: y = 8'hc7; 8'h32: y = 8'h23; 8'h33: y = 8'hc3;
      8'h34: y = 8'h18; 8'h35: y = 8'h96; 8'h36: y = 8'h05; 8'h37: y = 8'h9a;
      8'h38: y = 8'h07; 8'h39: y = 8'h12; 8'h3a: y = 8'h80; 8'h3b: y = 8'he2;
      8'h3c: y = 8'heb; 8'h3d: y = 8'h27; 8'h3e: y = 8'hb2; 8'h3f: y = 8'h75;
      8'h40: y = 8'h09; 8'h41: y = 8'h83; 8'h42: y = 8'h2c; 8'h43: y = 8'h1a;
      8'h44: y = 8'h1b; 8'h45: y = 8'h6e; 8'h46: y = 8'h5a; 8'h47: y = 8'ha0;
      8'h48: y = 8'h52; 8'h49: y = 8'h3b; 8'h4a: y = 8'hd6; 8'h4b: y = 8'hb3;
      8'h4c: y = 8'h29; 8'h4d: y = 8'he3; 8'h4e: y = 8'h2f; 8'h4f: y = 8'h84;
      8'h50: y = 8'h53; 8'h51: y = 8'hd1; 8'h52: y = 8'h00; 8'h53: y = 8'hed;
      8'h54: y = 8'h20; 8'h55: y = 8'hfc; 8'h56: y = 8'hb1; 8'h57: y = 8'h5b;
      8'h58: y = 8'h6a; 8'h59: y = 8'hcb; 8'h5a: y = 8'hbe; 8'h5b: y = 8'h39;
      8'h5c: y = 8'h4a; 8'h5d: y = 8'h4c; 8'h5e: y = 8'h58; 8'h5f: y = 8'hcf;
      8'h60: y = 8'hd0; 8'h61: y = 8'hef; 8'h62: y = 8'haa; 8'h63: y = 8'hfb;
      8'h64: y = 8'h43; 8'h65: y = 8'h4d; 8'h66: y = 8'h33; 8'h67: y = 8'h85;
      8'h68: y = 8'h45; 8'h69: y = 8'hf9; 8'h6a: y = 8'h02; 8'h6b: y = 8'h7f;
      8'h6c: y = 8'h50; 8'h6d: y = 8'h3c; 8'h6e: y = 8'h9f; 8'h6f: y = 8'ha8;
      8'h70: y = 8'h51; 8'h71: y = 8'ha3; 8'h72: y = 8'h40; 8'h73: y = 8'h8f;
      8'h74: y = 8'h92; 8'h75: y = 8'h9d; 8'h76: y = 8'h38; 8'h77: y = 8'hf5;
      8'h78: y = 8'hbc; 8'h79: y = 8'hb6; 8'h7a: y = 8'hda; 8'h7b: y = 8'h21;
      8'h7c: y = 8'h10; 8'h7d: y = 8'hff; 8'h7e: y = 8'hf3; 8'h7f: y = 8'hd2;
      8'h80: y = 8'hcd; 8'h81: y = 8'h0c; 8'h82: y = 8'h13; 8'h83: y = 8'hec;
      8'h84: y = 8'h5f; 8'h85: y = 8'h97; 8'h86: y = 8'h44; 8'h87: y = 8'h17;
      8'h88: y = 8'hc4; 8'h89: y = 8'ha7; 8'h8a: y = 8'h7e; 8'h8b: y = 8'h3d;
      8'h8c: y = 8'h64; 8'h8d: y = 8'h5d; 8'h8e: y = 8'h19; 8'h8f: y = 8'h73;
      8'h90: y = 8'h60; 8'h91: y = 8'h81; 8'h92: y = 8'h4f; 8'h93: y = 8'hdc;
      8'h94: y = 8'h22; 8'h95: y = 8'h2a; 8'h96: y = 8'h90; 8'h97: y = 8'h88;
      8'h98: y = 8'h46; 8'h99: y = 8'hee; 8'h9a: y = 8'hb8; 8'h9b: y = 8'h14;
      8'h9c: y = 8'hde; 8'h9d: y = 8'h5e; 8'h9e: y = 8'h0b; 8'h9f: y = 8'hdb;
      8'ha0: y = 8'he0; 8'ha1: y = 8'h32; 8'ha2: y = 8'h3a; 8'ha3: y = 8'h0a;
      8'ha4: y = 8'h49; 8'ha5: y = 8'h06; 8'ha6: y = 8'h24; 8'ha7: y = 8'h5c;
      8'ha8: y = 8'hc2; 8'ha9: y = 8'hd3; 8'haa: y = 8'hac; 8'hab: y = 8'h62;
      8'hac: y = 8'h91; 8'had: y = 8'h95; 8'hae: y = 8'he4; 8'haf: y = 8'h79;
      8'hb0: y = 8'he7; 8'hb1: y = 8'hc8; 8'hb2: y = 8'h37; 8'hb3: y = 8'h6d;
      8'hb4: y = 8'h8d; 8'hb5: y = 8'hd5; 8'hb6: y = 8'h4e; 8'hb7: y = 8'ha9;
      8'hb8: y = 8'h6c; 8'hb9: y = 8'h56; 8'hba: y = 8'hf4; 8'hbb: y = 8'hea;
      8'hbc: y = 8'h65; 8'hbd: y = 8'h7a; 8'hbe: y = 8'hae; 8'hbf: y = 8'h08;
      8'hc0: y = 8'hba; 8'hc1: y = 8'h78; 8'hc2: y = 8'h25; 8'hc3: y = 8'h2e;
      8'hc4: y = 8'h1c; 8'hc5: y = 8'ha6; 8'hc6: y = 8'hb4; 8'hc7: y = 8'hc6;
      8'hc8: y = 8'he8; 8'hc9: y = 8'hdd; 8'hca: y = 8'h74; 8'hcb: y = 8'h1f;
      8'hcc: y = 8'h4b; 8'hcd: y = 8'hbd; 8'hce: y = 8'h8b; 8'hcf: y = 8'h8a;
      8'hd0: y = 8'h70; 8'hd1: y = 8'h3e; 8'hd2: y = 8'hb5; 8'hd3: y = 8'h66;
      8'hd4: y = 8'h48; 8'hd5: y = 8'h03; 8'hd6: y = 8'hf6; 8'hd7: y = 8'h0e;
      8'hd8: y = 8'h61; 8'hd9: y = 8'h35; 8'hda: y = 8'h57; 8'hdb: y = 8'hb9;
      8'hdc: y = 8'h86; 8'hdd: y = 8'hc1; 8'hde: y = 8'h1d; 8'hdf: y = 8'h9e;
      8'he0: y = 8'he1; 8'he1: y = 8'hf8; 8'he2: y = 8'h98; 8'he3: y = 8'h11;
      8'he4: y = 8'h69; 8'he5: y = 8'hd9; 8'he6: y = 8'h8e; 8'he7: y = 8'h94;
      8'he8: y = 8'h9b; 8'he9: y = 8'h1e; 8'hea: y = 8'h87; 8'heb: y = 8'he9;
      8'hec: y = 8'hce; 8'hed: y = 8'h55; 8'hee: y = 8'h28; 8'hef: y = 8'hdf;
      8'hf0: y = 8'h8c; 8'hf1: y = 8'ha1; 8'hf2: y = 8'h89; 8'hf3: y = 8'h0d;
      8'hf4: y = 8'hbf; 8'hf5: y = 8'he6; 8'hf6: y = 8'h42; 8'hf7: y = 8'h68;
      8'hf8: y = 8'h41; 8'hf9: y = 8'h99; 8'hfa: y = 8'h2d; 8'hfb: y = 8'h0f;
      8'hfc: y = 8'hb0; 8'hfd: y = 8'h54; 8'hfe: y = 8'hbb; 8'hff: y = 8'h16;
      default: y = 8'h00;
    endcase
  end
endmodule

// ---------------------------------------------------------------------------
// Calibration control: wire-through. Must map to zero LUT6 cells (P1).
module e256h_cost_identity (
    input  wire [7:0] x,
    output wire [7:0] y
);
  assign y = x;
endmodule

// ---------------------------------------------------------------------------
// Calibration control: eight independent 2-input XORs. At most 8 LUT6 (P2).
module e256h_cost_xor_only (
    input  wire [7:0] x,
    input  wire [7:0] p_in,
    output wire [7:0] y
);
  assign y = x ^ p_in;
endmodule

// ---------------------------------------------------------------------------
// Baseline: unkeyed fixed S-box lane.
module e256h_cost_fixed (
    input  wire [7:0] x,
    output wire [7:0] y
);
  e256h_aes_sbox sbox (.x(x), .y(y));
endmodule

// ---------------------------------------------------------------------------
// H3 candidate: rotor as fixed wiring entered at a keyed position.
// R_p(x) = SBOX(x XOR p_in) XOR p_out. Exactly the affine lane with both
// matrices set to identity, so DDT/LAT/degree are preserved by construction.
module e256h_cost_offset (
    input  wire [7:0] x,
    input  wire [7:0] p_in,
    input  wire [7:0] p_out,
    output wire [7:0] y
);
  wire [7:0] s;
  e256h_aes_sbox sbox (.x(x ^ p_in), .y(s));
  assign y = s ^ p_out;
endmodule

// ---------------------------------------------------------------------------
// Metric-stability control: logically identical to e256h_cost_offset, written
// per bit with explicit loops. Must synthesize to the same LUT6 count and
// depth (P3), otherwise the metric is description noise.
module e256h_cost_offset_alt (
    input  wire [7:0] x,
    input  wire [7:0] p_in,
    input  wire [7:0] p_out,
    output wire [7:0] y
);
  reg [7:0] pre;
  reg [7:0] post;
  wire [7:0] s;
  integer i;
  integer j;

  always @* begin
    for (i = 0; i < 8; i = i + 1) begin
      pre[i] = x[i] ^ p_in[i];
    end
  end

  e256h_aes_sbox sbox (.x(pre), .y(s));

  always @* begin
    for (j = 0; j < 8; j = j + 1) begin
      post[j] = s[j] ^ p_out[j];
    end
  end

  assign y = post;
endmodule

// ---------------------------------------------------------------------------
// Incumbent (the E256-062 shape): runtime-programmable GF(2) affine wrappers.
// y = L_out(SBOX(L_in(x) XOR c_in)) XOR c_out.
// Row r of each matrix occupies bits [8*r+7 : 8*r]; output bit r is
// parity(row_r AND operand), matching the frozen model convention.
module e256h_cost_affine (
    input  wire [7:0]  x,
    input  wire [63:0] l_in,
    input  wire [63:0] l_out,
    input  wire [7:0]  c_in,
    input  wire [7:0]  c_out,
    output wire [7:0]  y
);
  wire [7:0] pre;
  wire [7:0] s;
  wire [7:0] post;

  genvar r;
  generate
    for (r = 0; r < 8; r = r + 1) begin : g_in
      assign pre[r] = ^(l_in[8*r +: 8] & x);
    end
  endgenerate

  e256h_aes_sbox sbox (.x(pre ^ c_in), .y(s));

  generate
    for (r = 0; r < 8; r = r + 1) begin : g_out
      assign post[r] = ^(l_out[8*r +: 8] & s);
    end
  endgenerate

  assign y = post ^ c_out;
endmodule

// ---------------------------------------------------------------------------
// H1-violation comparator: the identical rotor function realized as a
// runtime-loaded 256-entry lookup. Byte x occupies tbl[8*x+7 : 8*x].
// Included to price secret-table rotors in logic; H1 forbids this shape in a
// datapath because it reintroduces secret-indexed storage.
module e256h_cost_table (
    input  wire [7:0]    x,
    input  wire [2047:0] tbl,
    output wire [7:0]    y
);
  assign y = tbl[8*x +: 8];
endmodule

`default_nettype wire
