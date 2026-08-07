// E256-H hardware attack lane — NON-PRODUCTION RESEARCH RTL.
//
// Implements constraint H8 of directives/e256-hardware-architecture.md: every
// attack arm must exist as a netlist, and planted positive controls must be
// recovered by the same hardware search before any negative result is
// reportable.
//
// Contract: directives/e256-hardware-attack-preregistration.json
// Runner:   Scripts/e256_hardware_attack_gate.py
//
// Two attack arms share one round datapath:
//   * e256h_atk_integral - Lambda-set balance (integral) distinguisher. Feeds
//     256 plaintexts differing only in one active lane and XOR-accumulates the
//     ciphertexts. All-zero accumulator bytes indicate a surviving balance
//     property.
//   * e256h_atk_single - one-block evaluator, used by the truncated
//     differential arm to count active output bytes.
//
// Defect injection uses the SAME netlist via the `defect` port, so planted
// controls traverse the candidate's own datapath rather than a copy:
//   defect 0 = candidate, 1 = identity rotors, 2 = no diffusion.
//
// NOT a specification, suite, profile, fixture, or production core. No timing,
// power, or side-channel property is claimed. A bounded search that finds no
// break is NOT a security result.

`default_nettype none

// ---------------------------------------------------------------------------
module e256h_atk_sbox (
    input  wire [7:0] x,
    output reg  [7:0] y
);
  always @* begin
    case (x)
      8'h00: y=8'h63; 8'h01: y=8'h7c; 8'h02: y=8'h77; 8'h03: y=8'h7b;
      8'h04: y=8'hf2; 8'h05: y=8'h6b; 8'h06: y=8'h6f; 8'h07: y=8'hc5;
      8'h08: y=8'h30; 8'h09: y=8'h01; 8'h0a: y=8'h67; 8'h0b: y=8'h2b;
      8'h0c: y=8'hfe; 8'h0d: y=8'hd7; 8'h0e: y=8'hab; 8'h0f: y=8'h76;
      8'h10: y=8'hca; 8'h11: y=8'h82; 8'h12: y=8'hc9; 8'h13: y=8'h7d;
      8'h14: y=8'hfa; 8'h15: y=8'h59; 8'h16: y=8'h47; 8'h17: y=8'hf0;
      8'h18: y=8'had; 8'h19: y=8'hd4; 8'h1a: y=8'ha2; 8'h1b: y=8'haf;
      8'h1c: y=8'h9c; 8'h1d: y=8'ha4; 8'h1e: y=8'h72; 8'h1f: y=8'hc0;
      8'h20: y=8'hb7; 8'h21: y=8'hfd; 8'h22: y=8'h93; 8'h23: y=8'h26;
      8'h24: y=8'h36; 8'h25: y=8'h3f; 8'h26: y=8'hf7; 8'h27: y=8'hcc;
      8'h28: y=8'h34; 8'h29: y=8'ha5; 8'h2a: y=8'he5; 8'h2b: y=8'hf1;
      8'h2c: y=8'h71; 8'h2d: y=8'hd8; 8'h2e: y=8'h31; 8'h2f: y=8'h15;
      8'h30: y=8'h04; 8'h31: y=8'hc7; 8'h32: y=8'h23; 8'h33: y=8'hc3;
      8'h34: y=8'h18; 8'h35: y=8'h96; 8'h36: y=8'h05; 8'h37: y=8'h9a;
      8'h38: y=8'h07; 8'h39: y=8'h12; 8'h3a: y=8'h80; 8'h3b: y=8'he2;
      8'h3c: y=8'heb; 8'h3d: y=8'h27; 8'h3e: y=8'hb2; 8'h3f: y=8'h75;
      8'h40: y=8'h09; 8'h41: y=8'h83; 8'h42: y=8'h2c; 8'h43: y=8'h1a;
      8'h44: y=8'h1b; 8'h45: y=8'h6e; 8'h46: y=8'h5a; 8'h47: y=8'ha0;
      8'h48: y=8'h52; 8'h49: y=8'h3b; 8'h4a: y=8'hd6; 8'h4b: y=8'hb3;
      8'h4c: y=8'h29; 8'h4d: y=8'he3; 8'h4e: y=8'h2f; 8'h4f: y=8'h84;
      8'h50: y=8'h53; 8'h51: y=8'hd1; 8'h52: y=8'h00; 8'h53: y=8'hed;
      8'h54: y=8'h20; 8'h55: y=8'hfc; 8'h56: y=8'hb1; 8'h57: y=8'h5b;
      8'h58: y=8'h6a; 8'h59: y=8'hcb; 8'h5a: y=8'hbe; 8'h5b: y=8'h39;
      8'h5c: y=8'h4a; 8'h5d: y=8'h4c; 8'h5e: y=8'h58; 8'h5f: y=8'hcf;
      8'h60: y=8'hd0; 8'h61: y=8'hef; 8'h62: y=8'haa; 8'h63: y=8'hfb;
      8'h64: y=8'h43; 8'h65: y=8'h4d; 8'h66: y=8'h33; 8'h67: y=8'h85;
      8'h68: y=8'h45; 8'h69: y=8'hf9; 8'h6a: y=8'h02; 8'h6b: y=8'h7f;
      8'h6c: y=8'h50; 8'h6d: y=8'h3c; 8'h6e: y=8'h9f; 8'h6f: y=8'ha8;
      8'h70: y=8'h51; 8'h71: y=8'ha3; 8'h72: y=8'h40; 8'h73: y=8'h8f;
      8'h74: y=8'h92; 8'h75: y=8'h9d; 8'h76: y=8'h38; 8'h77: y=8'hf5;
      8'h78: y=8'hbc; 8'h79: y=8'hb6; 8'h7a: y=8'hda; 8'h7b: y=8'h21;
      8'h7c: y=8'h10; 8'h7d: y=8'hff; 8'h7e: y=8'hf3; 8'h7f: y=8'hd2;
      8'h80: y=8'hcd; 8'h81: y=8'h0c; 8'h82: y=8'h13; 8'h83: y=8'hec;
      8'h84: y=8'h5f; 8'h85: y=8'h97; 8'h86: y=8'h44; 8'h87: y=8'h17;
      8'h88: y=8'hc4; 8'h89: y=8'ha7; 8'h8a: y=8'h7e; 8'h8b: y=8'h3d;
      8'h8c: y=8'h64; 8'h8d: y=8'h5d; 8'h8e: y=8'h19; 8'h8f: y=8'h73;
      8'h90: y=8'h60; 8'h91: y=8'h81; 8'h92: y=8'h4f; 8'h93: y=8'hdc;
      8'h94: y=8'h22; 8'h95: y=8'h2a; 8'h96: y=8'h90; 8'h97: y=8'h88;
      8'h98: y=8'h46; 8'h99: y=8'hee; 8'h9a: y=8'hb8; 8'h9b: y=8'h14;
      8'h9c: y=8'hde; 8'h9d: y=8'h5e; 8'h9e: y=8'h0b; 8'h9f: y=8'hdb;
      8'ha0: y=8'he0; 8'ha1: y=8'h32; 8'ha2: y=8'h3a; 8'ha3: y=8'h0a;
      8'ha4: y=8'h49; 8'ha5: y=8'h06; 8'ha6: y=8'h24; 8'ha7: y=8'h5c;
      8'ha8: y=8'hc2; 8'ha9: y=8'hd3; 8'haa: y=8'hac; 8'hab: y=8'h62;
      8'hac: y=8'h91; 8'had: y=8'h95; 8'hae: y=8'he4; 8'haf: y=8'h79;
      8'hb0: y=8'he7; 8'hb1: y=8'hc8; 8'hb2: y=8'h37; 8'hb3: y=8'h6d;
      8'hb4: y=8'h8d; 8'hb5: y=8'hd5; 8'hb6: y=8'h4e; 8'hb7: y=8'ha9;
      8'hb8: y=8'h6c; 8'hb9: y=8'h56; 8'hba: y=8'hf4; 8'hbb: y=8'hea;
      8'hbc: y=8'h65; 8'hbd: y=8'h7a; 8'hbe: y=8'hae; 8'hbf: y=8'h08;
      8'hc0: y=8'hba; 8'hc1: y=8'h78; 8'hc2: y=8'h25; 8'hc3: y=8'h2e;
      8'hc4: y=8'h1c; 8'hc5: y=8'ha6; 8'hc6: y=8'hb4; 8'hc7: y=8'hc6;
      8'hc8: y=8'he8; 8'hc9: y=8'hdd; 8'hca: y=8'h74; 8'hcb: y=8'h1f;
      8'hcc: y=8'h4b; 8'hcd: y=8'hbd; 8'hce: y=8'h8b; 8'hcf: y=8'h8a;
      8'hd0: y=8'h70; 8'hd1: y=8'h3e; 8'hd2: y=8'hb5; 8'hd3: y=8'h66;
      8'hd4: y=8'h48; 8'hd5: y=8'h03; 8'hd6: y=8'hf6; 8'hd7: y=8'h0e;
      8'hd8: y=8'h61; 8'hd9: y=8'h35; 8'hda: y=8'h57; 8'hdb: y=8'hb9;
      8'hdc: y=8'h86; 8'hdd: y=8'hc1; 8'hde: y=8'h1d; 8'hdf: y=8'h9e;
      8'he0: y=8'he1; 8'he1: y=8'hf8; 8'he2: y=8'h98; 8'he3: y=8'h11;
      8'he4: y=8'h69; 8'he5: y=8'hd9; 8'he6: y=8'h8e; 8'he7: y=8'h94;
      8'he8: y=8'h9b; 8'he9: y=8'h1e; 8'hea: y=8'h87; 8'heb: y=8'he9;
      8'hec: y=8'hce; 8'hed: y=8'h55; 8'hee: y=8'h28; 8'hef: y=8'hdf;
      8'hf0: y=8'h8c; 8'hf1: y=8'ha1; 8'hf2: y=8'h89; 8'hf3: y=8'h0d;
      8'hf4: y=8'hbf; 8'hf5: y=8'he6; 8'hf6: y=8'h42; 8'hf7: y=8'h68;
      8'hf8: y=8'h41; 8'hf9: y=8'h99; 8'hfa: y=8'h2d; 8'hfb: y=8'h0f;
      8'hfc: y=8'hb0; 8'hfd: y=8'h54; 8'hfe: y=8'hbb; 8'hff: y=8'h16;
      default: y=8'h00;
    endcase
  end
endmodule

// ---------------------------------------------------------------------------
// One E256-H round on the 256-bit state. Byte j sits at row j mod 4 and
// column j div 4, i.e. index 4*column+row. Certified row offsets (0,1,3,4).
module e256h_atk_round #(
    parameter integer OFF0 = 0,
    parameter integer OFF1 = 1,
    parameter integer OFF2 = 3,
    parameter integer OFF3 = 4
) (
    input  wire [255:0] st,
    input  wire [255:0] p_in,
    input  wire [255:0] p_out,
    input  wire [255:0] mask,
    input  wire [1:0]   defect,
    output wire [255:0] st_out
);
  function [7:0] xt(input [7:0] v);
    xt = v[7] ? ((v << 1) ^ 8'h1b) : (v << 1);
  endfunction

  wire [255:0] sub;
  wire [255:0] shf;
  wire [255:0] mix;

  genvar j;
  generate
    for (j = 0; j < 32; j = j + 1) begin : g_rotor
      wire [7:0] lane = st[8*j +: 8];
      wire [7:0] sval;
      e256h_atk_sbox u_sb (.x(lane ^ p_in[8*j +: 8]), .y(sval));
      assign sub[8*j +: 8] =
          (defect == 2'd1) ? lane : (sval ^ p_out[8*j +: 8]);
    end
  endgenerate

  genvar c, r;
  generate
    for (c = 0; c < 8; c = c + 1) begin : g_shift_col
      for (r = 0; r < 4; r = r + 1) begin : g_shift_row
        localparam integer OFFR =
            (r == 0) ? OFF0 : (r == 1) ? OFF1 : (r == 2) ? OFF2 : OFF3;
        localparam integer SRC = 4 * ((c + OFFR) % 8) + r;
        assign shf[8*(4*c+r) +: 8] =
            (defect == 2'd2) ? sub[8*(4*c+r) +: 8] : sub[8*SRC +: 8];
      end
    end
  endgenerate

  generate
    for (c = 0; c < 8; c = c + 1) begin : g_mix_col
      wire [7:0] a0 = shf[8*(4*c+0) +: 8];
      wire [7:0] a1 = shf[8*(4*c+1) +: 8];
      wire [7:0] a2 = shf[8*(4*c+2) +: 8];
      wire [7:0] a3 = shf[8*(4*c+3) +: 8];
      wire [7:0] m0 = xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
      wire [7:0] m1 = a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
      wire [7:0] m2 = a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
      wire [7:0] m3 = xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
      assign mix[8*(4*c+0) +: 8] = (defect == 2'd2) ? a0 : m0;
      assign mix[8*(4*c+1) +: 8] = (defect == 2'd2) ? a1 : m1;
      assign mix[8*(4*c+2) +: 8] = (defect == 2'd2) ? a2 : m2;
      assign mix[8*(4*c+3) +: 8] = (defect == 2'd2) ? a3 : m3;
    end
  endgenerate

  assign st_out = mix ^ mask;
endmodule

// ---------------------------------------------------------------------------
// Single-block evaluator. Runs `rounds` rounds, one round per cycle.
module e256h_atk_single #(
    parameter integer MAXR = 8
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire [255:0]            block,
    input  wire [3:0]              rounds,
    input  wire [1:0]              defect,
    input  wire [MAXR*256-1:0]     p_in_all,
    input  wire [MAXR*256-1:0]     p_out_all,
    input  wire [(MAXR+1)*256-1:0] mask_all,
    output reg  [255:0]            result,
    output reg                     done
);
  reg  [255:0] state;
  reg  [3:0]   round_index;
  reg          busy;
  wire [255:0] next_state;

  e256h_atk_round u_round (
      .st(state),
      .p_in(p_in_all[round_index*256 +: 256]),
      .p_out(p_out_all[round_index*256 +: 256]),
      .mask(mask_all[(round_index+1)*256 +: 256]),
      .defect(defect),
      .st_out(next_state)
  );

  always @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0;
      done <= 1'b0;
      state <= 256'd0;
      round_index <= 4'd0;
      result <= 256'd0;
    end else if (start && !busy) begin
      state <= block ^ mask_all[0 +: 256];
      round_index <= 4'd0;
      busy <= 1'b1;
      done <= 1'b0;
    end else if (busy) begin
      if (round_index == rounds) begin
        result <= state;
        busy <= 1'b0;
        done <= 1'b1;
      end else begin
        state <= next_state;
        round_index <= round_index + 4'd1;
      end
    end else begin
      done <= 1'b0;
    end
  end
endmodule

// ---------------------------------------------------------------------------
// Integral (Lambda-set balance) distinguisher. Sweeps the active lane over all
// 256 values, runs `rounds` rounds per plaintext, and XOR-accumulates the
// ciphertexts. Zero accumulator bytes indicate a surviving balance property.
module e256h_atk_integral #(
    parameter integer MAXR = 8
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire [3:0]              rounds,
    input  wire [1:0]              defect,
    input  wire [4:0]              active_lane,
    input  wire [MAXR*256-1:0]     p_in_all,
    input  wire [MAXR*256-1:0]     p_out_all,
    input  wire [(MAXR+1)*256-1:0] mask_all,
    output reg  [255:0]            accumulator,
    output reg  [5:0]              balanced_bytes,
    output reg                     done
);
  localparam [2:0] S_IDLE = 3'd0;
  localparam [2:0] S_LOAD = 3'd1;
  localparam [2:0] S_RUN  = 3'd2;
  localparam [2:0] S_ACC  = 3'd3;
  localparam [2:0] S_DONE = 3'd4;

  reg  [2:0]   fsm;
  reg  [255:0] state;
  reg  [3:0]   round_index;
  reg  [8:0]   plaintext_index;
  wire [255:0] next_state;
  wire [255:0] loaded;

  function [5:0] count_zero_bytes(input [255:0] value);
    integer index;
    begin
      count_zero_bytes = 6'd0;
      for (index = 0; index < 32; index = index + 1) begin
        if (value[8*index +: 8] == 8'd0) begin
          count_zero_bytes = count_zero_bytes + 6'd1;
        end
      end
    end
  endfunction

  e256h_atk_round u_round (
      .st(state),
      .p_in(p_in_all[round_index*256 +: 256]),
      .p_out(p_out_all[round_index*256 +: 256]),
      .mask(mask_all[(round_index+1)*256 +: 256]),
      .defect(defect),
      .st_out(next_state)
  );

  // Lambda-set plaintext: all lanes zero except the active lane, which sweeps
  // 0..255. The pre-round mask is applied on load.
  assign loaded =
      (256'd0 | ({248'd0, plaintext_index[7:0]} << (8 * active_lane)))
      ^ mask_all[0 +: 256];

  always @(posedge clk) begin
    if (rst) begin
      fsm <= S_IDLE;
      done <= 1'b0;
      accumulator <= 256'd0;
      balanced_bytes <= 6'd0;
      plaintext_index <= 9'd0;
      round_index <= 4'd0;
      state <= 256'd0;
    end else begin
      case (fsm)
        S_IDLE: begin
          done <= 1'b0;
          if (start) begin
            accumulator <= 256'd0;
            plaintext_index <= 9'd0;
            fsm <= S_LOAD;
          end
        end
        S_LOAD: begin
          state <= loaded;
          round_index <= 4'd0;
          fsm <= (rounds == 4'd0) ? S_ACC : S_RUN;
        end
        S_RUN: begin
          state <= next_state;
          round_index <= round_index + 4'd1;
          if (round_index + 4'd1 == rounds) begin
            fsm <= S_ACC;
          end
        end
        S_ACC: begin
          accumulator <= accumulator ^ state;
          if (plaintext_index == 9'd255) begin
            fsm <= S_DONE;
          end else begin
            plaintext_index <= plaintext_index + 9'd1;
            fsm <= S_LOAD;
          end
        end
        S_DONE: begin
          balanced_bytes <= count_zero_bytes(accumulator);
          done <= 1'b1;
          fsm <= S_IDLE;
        end
        default: fsm <= S_IDLE;
      endcase
    end
  end
endmodule

`default_nettype wire
