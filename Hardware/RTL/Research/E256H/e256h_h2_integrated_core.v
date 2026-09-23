// E256-H collapsed-schedule H2 integrated core -- NON-PRODUCTION RESEARCH RTL.
//
// Contract: directives/e256-hardware-h2-preregistration.json
// Design record: directives/e256-hardware-architecture.md section 10
//
// This file implements a fixed-R=12 cost-measurement fixture.  It is not a
// cipher suite, profile, protocol, production implementation, security claim,
// or round-count selection.  It contains no XOF and accepts only the thirteen
// already-collapsed effective masks K_0..K_12.  The generic-memory variants are
// H1-ineligible comparators, not BRAM/SRAM/ROM recommendations.  No reset or
// zeroization property is claimed for any effective-mask store.
//
// The semantic AES S-box is implemented below as an explicit combinational
// LUT6 netlist generated from the frozen e256h_atk_sbox truth table by the
// pinned Yosys/ABC toolchain.  The predecessor source remains pinned and
// unmodified; it is not instantiated because `memory -nomap` would preserve
// its case statement as a ROM.  Byte j is word[8*j +: 8], with index
// 4*column+row.  Forward H4 takes source column (column+offset[row]) mod 8.

`default_nettype none

// ---------------------------------------------------------------------------
// Tableless AES S-box.  Every variable right shift below is a 4/5/6-input LUT
// truth table, not an inferred memory.  Exhaustive simulation must reproduce
// AES_SBOX_SHA256 before any H2 measurement is accepted.
module e256h_h2_sbox (
    input  wire [7:0] x,
    output wire [7:0] y
);
  wire _00_;
  wire _01_;
  wire _02_;
  wire _03_;
  wire _04_;
  wire _05_;
  wire _06_;
  wire _07_;
  wire _08_;
  wire _09_;
  wire _10_;
  wire _11_;
  wire _12_;
  wire _13_;
  wire _14_;
  wire _15_;
  wire _16_;
  wire _17_;
  wire _18_;
  wire _19_;
  wire _20_;
  wire _21_;
  wire _22_;
  wire _23_;
  wire _24_;
  wire _25_;
  wire _26_;
  wire _27_;
  wire _28_;
  wire _29_;
  wire _30_;
  wire _31_;
  wire _32_;
  wire _33_;
  wire _34_;
  wire _35_;
  wire _36_;
  wire _37_;
  wire _38_;
  wire _39_;
  wire _40_;

  assign y[6] = 64'hccccaaaa00ff0f0f >> {x[7:6], _00_, _01_, _02_, _03_};
  assign _00_ = 64'h1711ceb0f8e330dd >> {x[4], x[2], x[5], x[1:0], x[3]};
  assign _01_ = 64'h7c1047e08fc0f578 >> {x[1], x[2], x[5], x[3], x[4], x[0]};
  assign _02_ = 64'h09a41c10c89b35da >> {x[1:0], x[4:2], x[5]};
  assign _03_ = 64'h6669f503fdc547ad >> {x[2], x[5], x[3], x[0], x[4], x[1]};
  assign y[5] = 32'd861270256 >> {x[7], x[5], _04_, _08_, _09_};
  assign _04_ = 16'hf0ee >> {x[6], _05_, _07_, _06_};
  assign _05_ = 64'h61c7a32cdafc4c22 >> {x[2], x[0], x[4], x[5], x[3], x[1]};
  assign _06_ = 64'hbec5414800000000 >> {x[4:2], x[0], x[1], x[5]};
  assign _07_ = 64'h1055555105455555 >> {x[1:0], x[2], x[3], x[5:4]};
  assign _08_ = 64'hb8d55470a7ee34ae >> {x[1:0], x[4], x[6], x[2], x[3]};
  assign _09_ = 64'hfa44cf80bda3f93d >> {x[6], x[0], x[2:1], x[3], x[4]};
  assign y[4] = 64'haaaacccc00ff0f0f >> {x[7:6], _10_, _11_, _12_, _13_};
  assign _10_ = 64'h00a38deeb2563c13 >> {x[2], x[5:4], x[1], x[3], x[0]};
  assign _11_ = 64'h4dc31f8c3a1cdc0d >> {x[3], x[0], x[1], x[2], x[4], x[5]};
  assign _12_ = 64'h0c319eebca8cad00 >> {x[1], x[5], x[2], x[4], x[0], x[3]};
  assign _13_ = 64'he0eb2362cf2a541f >> {x[5], x[3], x[1], x[2], x[4], x[0]};
  assign y[3] = 64'h00ff00ff0f0f1111 >> {x[7:6], _14_, _18_, _20_, _19_};
  assign _14_ = 16'heef0 >> {x[6], _15_, _17_, _16_};
  assign _15_ = 64'h122d3be30953d266 >> {x[5:4], x[0], x[2:1], x[3]};
  assign _16_ = 64'h00000000075dcac4 >> {x[5], x[1], x[2], x[3], x[4], x[0]};
  assign _17_ = 64'h8a1c3c8100000000 >> {x[5], x[3], x[0], x[1], x[4], x[2]};
  assign _18_ = 64'hb91b03c8c73107b4 >> {x[2], x[5:3], x[0], x[1]};
  assign _19_ = 64'h00000000f0aecb13 >> {x[5], x[0], x[1], x[2], x[4:3]};
  assign _20_ = 64'h88aaa0a8aaaa0aaa >> {x[0], x[1], x[2], x[4:3], x[5]};
  assign y[2] = 64'hcccc55550f0f00ff >> {x[7:6], _21_, _22_, _23_, _24_};
  assign _21_ = 64'h64e45c33f95a803d >> {x[2:1], x[5:3], x[0]};
  assign _22_ = 64'hc3b5107bafceff3f >> {x[0], x[1], x[2], x[3], x[5:4]};
  assign _23_ = 64'h8bbce148f43b7af8 >> {x[5], x[2], x[4], x[1], x[3], x[0]};
  assign _24_ = 64'haf848cb1832350f0 >> {x[1], x[4], x[2], x[5], x[3], x[0]};
  assign y[1] = 32'd3433754864 >> {x[7:6], _25_, _29_, _30_};
  assign _25_ = 16'hee0f >> {x[6], _28_, _26_, _27_};
  assign _26_ = 64'h00000000c32d2ebe >> {x[5], x[2:1], x[4], x[0], x[3]};
  assign _27_ = 64'h9f35a03c00000000 >> {x[5], x[1], x[3], x[0], x[2], x[4]};
  assign _28_ = 64'hb760334680accf82 >> {x[5], x[1], x[3:2], x[4], x[0]};
  assign _29_ = 64'he9079e4444c0eaa9 >> {x[3], x[5], x[1], x[4], x[2], x[0]};
  assign _30_ = 64'h2e8a1783f31650ec >> {x[2], x[3], x[0], x[5], x[1], x[4]};
  assign y[0] = 32'd4126994672 >> {x[6], x[7], _31_, _35_, _36_};
  assign _31_ = 64'h0000f0f00000ccaa >> {x[7:5], _34_, _32_, _33_};
  assign _32_ = 32'd2906543053 >> {x[3], x[0], x[4], x[1], x[2]};
  assign _33_ = 32'd1463435073 >> {x[0], x[1], x[3], x[4], x[2]};
  assign _34_ = 64'h0de08f1c44748827 >> {x[0], x[5], x[3], x[4], x[2:1]};
  assign _35_ = 64'h2cf5d1f29589f0b3 >> {x[5], x[2], x[3], x[0], x[1], x[4]};
  assign _36_ = 64'hd701ca34f5521d57 >> {x[5], x[1], x[2], x[0], x[4:3]};
  assign _37_ = 64'hd3ec2545950fc226 >> {x[1], x[4:3], x[5], x[0], x[2]};
  assign _38_ = 64'h2d689cf3f94da2aa >> {x[2], x[5], x[1], x[3], x[0], x[4]};
  assign _39_ = 64'h117b631fca173531 >> {x[2], x[3], x[1], x[4], x[0], x[5]};
  assign _40_ = 64'h942dbfbde3d13d0a >> {x[1], x[4], x[2], x[3], x[5], x[0]};
  assign y[7] = 64'h00ff33330f0faaaa >> {x[7:6], _37_, _39_, _40_, _38_};
endmodule

// Shared 32-lane nonlinear layer.
module e256h_h2_subbytes (
    input  wire [255:0] state_i,
    output wire [255:0] state_o
);
  genvar lane;
  generate
    for (lane = 0; lane < 32; lane = lane + 1) begin : g_sbox
      e256h_h2_sbox u_sbox (
          .x(state_i[8*lane +: 8]),
          .y(state_o[8*lane +: 8])
      );
    end
  endgenerate
endmodule

// Shared eight-column AES MixColumns layer over x^8+x^4+x^3+x+1 (0x11b).
module e256h_h2_mixcolumns (
    input  wire [255:0] state_i,
    output wire [255:0] state_o
);
  function [7:0] xt(input [7:0] value);
    xt = value[7] ? ((value << 1) ^ 8'h1b) : (value << 1);
  endfunction

  genvar column;
  generate
    for (column = 0; column < 8; column = column + 1) begin : g_column
      wire [7:0] a0 = state_i[8*(4*column+0) +: 8];
      wire [7:0] a1 = state_i[8*(4*column+1) +: 8];
      wire [7:0] a2 = state_i[8*(4*column+2) +: 8];
      wire [7:0] a3 = state_i[8*(4*column+3) +: 8];
      assign state_o[8*(4*column+0) +: 8] =
          xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
      assign state_o[8*(4*column+1) +: 8] =
          a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
      assign state_o[8*(4*column+2) +: 8] =
          a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
      assign state_o[8*(4*column+3) +: 8] =
          xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
    end
  endgenerate
endmodule

// Fixed-H4 round: compile-time tuple (0,1,3,4), then shared MixColumns.
// MUTATE_H4_DIRECTION is a compile-time control hook and is zero in every
// graded wrapper.  It exists only for e256h_h2_control_core.
module e256h_h2_round_fixed #(
    parameter integer MUTATE_H4_DIRECTION = 0
) (
    input  wire [255:0] state_i,
    input  wire [255:0] round_key,
    output wire [255:0] state_o
);
  wire [255:0] substituted;
  wire [255:0] shifted;
  wire [255:0] mixed;

  e256h_h2_subbytes u_subbytes (
      .state_i(state_i),
      .state_o(substituted)
  );

  genvar column;
  genvar row;
  generate
    for (column = 0; column < 8; column = column + 1) begin : g_shift_column
      for (row = 0; row < 4; row = row + 1) begin : g_shift_row
        localparam integer OFFSET =
            (row == 0) ? 0 : (row == 1) ? 1 : (row == 2) ? 3 : 4;
        localparam integer SOURCE_COLUMN =
            (MUTATE_H4_DIRECTION != 0) ? ((column + 8 - OFFSET) % 8)
                                       : ((column + OFFSET) % 8);
        localparam integer SOURCE = 4 * SOURCE_COLUMN + row;
        assign shifted[8*(4*column+row) +: 8] =
            substituted[8*SOURCE +: 8];
      end
    end
  endgenerate

  e256h_h2_mixcolumns u_mixcolumns (
      .state_i(shifted),
      .state_o(mixed)
  );

  assign state_o = mixed ^ round_key;
endmodule

// Runtime-direct H4 round.  One latched tuple is repeated for all rounds and
// blocks until the next successful configuration commit.  The interface is
// selector-general; no on-chip catalog or certification filter is implied.
module e256h_h2_round_direct #(
    parameter integer MUTATE_H4_DIRECTION = 0,
    parameter integer MUTATE_IGNORE_SELECTOR = 0
) (
    input  wire [255:0] state_i,
    input  wire [255:0] round_key,
    input  wire [11:0]  h4_i,
    output wire [255:0] state_o
);
  wire [255:0] substituted;
  reg  [255:0] shifted;
  wire [255:0] mixed;
  wire [11:0] selected_h4 =
      (MUTATE_IGNORE_SELECTOR != 0) ? 12'h8c8 : h4_i;

  integer column;
  integer row;
  integer source_column;
  reg [2:0] row_offset;

  e256h_h2_subbytes u_subbytes (
      .state_i(state_i),
      .state_o(substituted)
  );

  always @* begin
    shifted = 256'd0;
    row_offset = 3'd0;
    source_column = 0;
    for (column = 0; column < 8; column = column + 1) begin
      for (row = 0; row < 4; row = row + 1) begin
        case (row)
          0: row_offset = selected_h4[2:0];
          1: row_offset = selected_h4[5:3];
          2: row_offset = selected_h4[8:6];
          default: row_offset = selected_h4[11:9];
        endcase
        if (MUTATE_H4_DIRECTION != 0) begin
          source_column = (column + 8 - row_offset) % 8;
        end else begin
          source_column = (column + row_offset) % 8;
        end
        shifted[8*(4*column+row) +: 8] =
            substituted[8*(4*source_column+row) +: 8];
      end
    end
  end

  e256h_h2_mixcolumns u_mixcolumns (
      .state_i(shifted),
      .state_o(mixed)
  );

  assign state_o = mixed ^ round_key;
endmodule

// ---------------------------------------------------------------------------
// Common narrow configuration protocol.  cfg_error is sticky until reset or a
// clean idle cfg_begin.  Pulses sharing a beat are rejected; the frozen normal
// sequence is one begin beat, thirteen accepted word beats, then one commit.
module e256h_h2_protocol (
    input  wire         clk,
    input  wire         rst,
    input  wire         busy,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire         cfg_commit,
    input  wire         start,
    output reg          key_valid,
    output reg          cfg_error,
    output wire         ready,
    output wire         cfg_write,
    output wire [3:0]   cfg_index,
    output wire         commit_accept,
    output wire         start_accept
);
  reg       cfg_active;
  reg [3:0] cfg_count;

  assign cfg_ready = !busy && cfg_active && (cfg_count < 4'd13) &&
                     !cfg_begin && !cfg_commit && !start;
  assign cfg_write = cfg_valid && cfg_ready;
  assign cfg_index = cfg_count;
  assign commit_accept = !busy && cfg_active && cfg_commit &&
                         (cfg_count == 4'd13) && !cfg_begin &&
                         !cfg_valid && !start;
  assign ready = !busy && key_valid && !cfg_active &&
                 !cfg_begin && !cfg_valid && !cfg_commit;
  assign start_accept = start && ready;

  always @(posedge clk) begin
    if (rst) begin
      cfg_active <= 1'b0;
      cfg_count <= 4'd0;
      key_valid <= 1'b0;
      cfg_error <= 1'b0;
    end else if (!busy && cfg_begin && !cfg_valid &&
                 !cfg_commit && !start) begin
      // A clean begin is the recovery boundary and invalidates the old key.
      cfg_active <= 1'b1;
      cfg_count <= 4'd0;
      key_valid <= 1'b0;
      cfg_error <= 1'b0;
    end else if (busy) begin
      // Configuration activity while a block is active is rejected without
      // changing the in-flight configuration.
      if (cfg_begin || cfg_valid || cfg_commit) begin
        cfg_error <= 1'b1;
      end
    end else begin
      if (cfg_begin) begin
        // Simultaneous begin/data/commit/start is not a legal protocol beat.
        cfg_active <= 1'b0;
        cfg_count <= 4'd0;
        key_valid <= 1'b0;
        cfg_error <= 1'b1;
      end else begin
        if (cfg_valid) begin
          if (cfg_write) begin
            cfg_count <= cfg_count + 4'd1;
          end else begin
            // Includes a fourteenth word and data outside a begin/commit span.
            cfg_active <= 1'b0;
            key_valid <= 1'b0;
            cfg_error <= 1'b1;
          end
        end
        if (cfg_commit) begin
          if (commit_accept) begin
            cfg_active <= 1'b0;
            key_valid <= 1'b1;
          end else begin
            // Includes early commit and commit after an invalid/closed span.
            cfg_active <= 1'b0;
            key_valid <= 1'b0;
            cfg_error <= 1'b1;
          end
        end
        if (start && !key_valid) begin
          cfg_error <= 1'b1;
        end
      end
    end
  end
endmodule

// ---------------------------------------------------------------------------
// Integrated storage organizations.  None of these arrays/vectors is reset.
module e256h_h2_ff_store (
    input  wire         clk,
    input  wire         write_enable,
    input  wire [3:0]   write_index,
    input  wire [255:0] write_word,
    input  wire [3:0]   read_index,
    output wire [255:0] read_word
);
  reg [3327:0] words;

  always @(posedge clk) begin
    if (write_enable) begin
      words[write_index*256 +: 256] <= write_word;
    end
  end

  assign read_word = words[read_index*256 +: 256];
endmodule

module e256h_h2_ring_store #(
    parameter integer MUTATE_BROKEN_ACCEPT_ROTATION = 0
) (
    input  wire         clk,
    input  wire         write_enable,
    input  wire [3:0]   write_index,
    input  wire [255:0] write_word,
    input  wire         advance_accept,
    input  wire         advance_round,
    output wire [255:0] current_word
);
  reg [3327:0] words;

  always @(posedge clk) begin
    if (write_enable) begin
      words[write_index*256 +: 256] <= write_word;
    end else if (advance_round) begin
      // K_(r+1) moves into the low/current word.  The thirteenth total
      // rotation restores K_0 after the final round.
      words <= {words[255:0], words[3327:256]};
    end else if (advance_accept &&
                 (MUTATE_BROKEN_ACCEPT_ROTATION == 0)) begin
      words <= {words[255:0], words[3327:256]};
    end
  end

  assign current_word = words[255:0];
endmodule

module e256h_h2_mem_store (
    input  wire         clk,
    input  wire         write_enable,
    input  wire [3:0]   write_index,
    input  wire [255:0] write_word,
    input  wire         read_enable,
    input  wire [3:0]   read_index,
    output reg  [255:0] read_word
);
  // Generic one-cycle synchronous memory addressed only by public protocol
  // state.  It is deliberately H1-ineligible and has no reset initialization.
  reg [255:0] words [0:12];

  always @(posedge clk) begin
    if (write_enable) begin
      words[write_index] <= write_word;
    end
    if (read_enable) begin
      read_word <= words[read_index];
    end
  end
endmodule

// ---------------------------------------------------------------------------
// Stationary-FF integrated core.  Compile-time mutation parameters are zero in
// all six public wrappers and nonzero only through the control wrapper.
module e256h_h2_ff_core #(
    parameter integer DIRECT_H4 = 0,
    parameter integer MUTATE_WRONG_KEY_ADDRESS = 0,
    parameter integer MUTATE_H4_DIRECTION = 0,
    parameter integer MUTATE_IGNORE_SELECTOR = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [11:0]  cfg_h4,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output reg  [255:0] block_o,
    output reg          busy,
    output reg          done
);
  wire       cfg_write;
  wire [3:0] cfg_index;
  wire       commit_accept;
  wire       start_accept;
  reg  [3:0] round_index;
  reg  [255:0] state;
  wire [3:0] read_index = busy ?
      ((MUTATE_WRONG_KEY_ADDRESS != 0) ? round_index
                                       : (round_index + 4'd1)) : 4'd0;
  wire [255:0] key_word;
  wire [255:0] round_next;

  e256h_h2_protocol u_protocol (
      .clk(clk), .rst(rst), .busy(busy),
      .cfg_begin(cfg_begin), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
      .cfg_commit(cfg_commit), .start(start), .key_valid(key_valid),
      .cfg_error(cfg_error), .ready(ready), .cfg_write(cfg_write),
      .cfg_index(cfg_index), .commit_accept(commit_accept),
      .start_accept(start_accept)
  );

  e256h_h2_ff_store u_store (
      .clk(clk), .write_enable(cfg_write), .write_index(cfg_index),
      .write_word(cfg_word), .read_index(read_index), .read_word(key_word)
  );

  generate
    if (DIRECT_H4 != 0) begin : g_direct_h4
      // Not reset: key_valid gates use, and no selector-zeroization claim is
      // made.  Exactly twelve bits are sampled on a successful commit.
      reg [11:0] h4_latched;
      always @(posedge clk) begin
        if (commit_accept) begin
          h4_latched <= cfg_h4;
        end
      end
      e256h_h2_round_direct #(
          .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION),
          .MUTATE_IGNORE_SELECTOR(MUTATE_IGNORE_SELECTOR)
      ) u_round (
          .state_i(state), .round_key(key_word), .h4_i(h4_latched),
          .state_o(round_next)
      );
    end else begin : g_fixed_h4
      e256h_h2_round_fixed #(
          .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION)
      ) u_round (
          .state_i(state), .round_key(key_word), .state_o(round_next)
      );
    end
  endgenerate

  always @(posedge clk) begin
    if (rst) begin
      state <= 256'd0;
      round_index <= 4'd0;
      block_o <= 256'd0;
      busy <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start_accept) begin
        // E0 applies K_0.
        state <= block_i ^ key_word;
        round_index <= 4'd0;
        busy <= 1'b1;
      end else if (busy) begin
        // E1..E12 apply K_1..K_12.
        state <= round_next;
        if (round_index == 4'd11) begin
          block_o <= round_next;
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          round_index <= round_index + 4'd1;
        end
      end
    end
  end
endmodule

// Rotating-FF integrated core.  Acceptance plus twelve round rotations return
// the thirteen-word bank to K_0 ordering before the next block.
module e256h_h2_ring_core #(
    parameter integer DIRECT_H4 = 0,
    parameter integer MUTATE_H4_DIRECTION = 0,
    parameter integer MUTATE_IGNORE_SELECTOR = 0,
    parameter integer MUTATE_BROKEN_RING_ROTATION = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [11:0]  cfg_h4,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output reg  [255:0] block_o,
    output reg          busy,
    output reg          done
);
  wire       cfg_write;
  wire [3:0] cfg_index;
  wire       commit_accept;
  wire       start_accept;
  reg  [3:0] round_index;
  reg  [255:0] state;
  wire [255:0] key_word;
  wire [255:0] round_next;

  e256h_h2_protocol u_protocol (
      .clk(clk), .rst(rst), .busy(busy),
      .cfg_begin(cfg_begin), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
      .cfg_commit(cfg_commit), .start(start), .key_valid(key_valid),
      .cfg_error(cfg_error), .ready(ready), .cfg_write(cfg_write),
      .cfg_index(cfg_index), .commit_accept(commit_accept),
      .start_accept(start_accept)
  );

  e256h_h2_ring_store #(
      .MUTATE_BROKEN_ACCEPT_ROTATION(MUTATE_BROKEN_RING_ROTATION)
  ) u_store (
      .clk(clk), .write_enable(cfg_write), .write_index(cfg_index),
      .write_word(cfg_word), .advance_accept(start_accept),
      .advance_round(busy), .current_word(key_word)
  );

  generate
    if (DIRECT_H4 != 0) begin : g_direct_h4
      reg [11:0] h4_latched;
      always @(posedge clk) begin
        if (commit_accept) begin
          h4_latched <= cfg_h4;
        end
      end
      e256h_h2_round_direct #(
          .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION),
          .MUTATE_IGNORE_SELECTOR(MUTATE_IGNORE_SELECTOR)
      ) u_round (
          .state_i(state), .round_key(key_word), .h4_i(h4_latched),
          .state_o(round_next)
      );
    end else begin : g_fixed_h4
      e256h_h2_round_fixed #(
          .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION)
      ) u_round (
          .state_i(state), .round_key(key_word), .state_o(round_next)
      );
    end
  endgenerate

  always @(posedge clk) begin
    if (rst) begin
      state <= 256'd0;
      round_index <= 4'd0;
      block_o <= 256'd0;
      busy <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start_accept) begin
        state <= block_i ^ key_word;
        round_index <= 4'd0;
        busy <= 1'b1;
      end else if (busy) begin
        state <= round_next;
        if (round_index == 4'd11) begin
          block_o <= round_next;
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          round_index <= round_index + 4'd1;
        end
      end
    end
  end
endmodule

// Generic synchronous-memory comparator.  E0 requests K_0, E1 captures K_0
// and requests K_1, E2 applies K_0, and E3..E14 execute the twelve rounds.
module e256h_h2_mem_core #(
    parameter integer DIRECT_H4 = 0,
    parameter integer MUTATE_WRONG_KEY_ADDRESS = 0,
    parameter integer MUTATE_H4_DIRECTION = 0,
    parameter integer MUTATE_IGNORE_SELECTOR = 0,
    parameter integer MUTATE_STALE_MEMORY_READ = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [11:0]  cfg_h4,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output reg  [255:0] block_o,
    output reg          busy,
    output reg          done
);
  localparam [1:0] PHASE_FETCH_K0 = 2'd0;
  localparam [1:0] PHASE_APPLY_K0 = 2'd1;
  localparam [1:0] PHASE_ROUND = 2'd2;

  wire       cfg_write;
  wire [3:0] cfg_index;
  wire       commit_accept;
  wire       start_accept;
  reg  [1:0] phase;
  reg  [3:0] round_index;
  reg  [255:0] state;
  reg  [255:0] block_hold;
  reg  [255:0] key_hold;
  reg  [255:0] stale_key;
  wire [255:0] memory_word;
  wire [255:0] selected_round_key =
      (MUTATE_STALE_MEMORY_READ != 0) ? stale_key : key_hold;
  wire [255:0] round_next;

  wire memory_read_enable = start_accept ||
      (busy && (phase == PHASE_FETCH_K0)) ||
      (busy && (phase == PHASE_APPLY_K0)) ||
      (busy && (phase == PHASE_ROUND) && (round_index < 4'd10));

  reg [3:0] memory_read_index;
  always @* begin
    memory_read_index = 4'd0;
    if (start_accept) begin
      memory_read_index = 4'd0;
    end else if (phase == PHASE_FETCH_K0) begin
      memory_read_index = (MUTATE_WRONG_KEY_ADDRESS != 0) ? 4'd0 : 4'd1;
    end else if (phase == PHASE_APPLY_K0) begin
      memory_read_index = (MUTATE_WRONG_KEY_ADDRESS != 0) ? 4'd1 : 4'd2;
    end else if (phase == PHASE_ROUND) begin
      memory_read_index = (MUTATE_WRONG_KEY_ADDRESS != 0) ?
          (round_index + 4'd2) : (round_index + 4'd3);
    end
  end

  e256h_h2_protocol u_protocol (
      .clk(clk), .rst(rst), .busy(busy),
      .cfg_begin(cfg_begin), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
      .cfg_commit(cfg_commit), .start(start), .key_valid(key_valid),
      .cfg_error(cfg_error), .ready(ready), .cfg_write(cfg_write),
      .cfg_index(cfg_index), .commit_accept(commit_accept),
      .start_accept(start_accept)
  );

  e256h_h2_mem_store u_store (
      .clk(clk), .write_enable(cfg_write), .write_index(cfg_index),
      .write_word(cfg_word), .read_enable(memory_read_enable),
      .read_index(memory_read_index), .read_word(memory_word)
  );

  generate
    if (DIRECT_H4 != 0) begin : g_direct_h4
      reg [11:0] h4_latched;
      always @(posedge clk) begin
        if (commit_accept) begin
          h4_latched <= cfg_h4;
        end
      end
      e256h_h2_round_direct #(
          .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION),
          .MUTATE_IGNORE_SELECTOR(MUTATE_IGNORE_SELECTOR)
      ) u_round (
          .state_i(state), .round_key(selected_round_key),
          .h4_i(h4_latched), .state_o(round_next)
      );
    end else begin : g_fixed_h4
      e256h_h2_round_fixed #(
          .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION)
      ) u_round (
          .state_i(state), .round_key(selected_round_key),
          .state_o(round_next)
      );
    end
  endgenerate

  always @(posedge clk) begin
    if (rst) begin
      phase <= PHASE_FETCH_K0;
      round_index <= 4'd0;
      state <= 256'd0;
      block_hold <= 256'd0;
      block_o <= 256'd0;
      busy <= 1'b0;
      done <= 1'b0;
      // key_hold, stale_key, memory_word, and the memory array are not reset.
    end else begin
      done <= 1'b0;
      if (start_accept) begin
        // E0: request K_0 and retain the input block.
        block_hold <= block_i;
        phase <= PHASE_FETCH_K0;
        round_index <= 4'd0;
        busy <= 1'b1;
      end else if (busy) begin
        case (phase)
          PHASE_FETCH_K0: begin
            // E1: capture K_0; memory concurrently requests K_1.
            key_hold <= memory_word;
            stale_key <= memory_word;
            phase <= PHASE_APPLY_K0;
          end
          PHASE_APPLY_K0: begin
            // E2: apply K_0 and retain prefetched K_1.
            state <= block_hold ^ key_hold;
            stale_key <= key_hold;
            key_hold <= memory_word;
            round_index <= 4'd0;
            phase <= PHASE_ROUND;
          end
          default: begin
            // E3..E14: rounds 0..11.  stale_key is deliberately one
            // synchronous fetch behind when the planted mutation is enabled.
            state <= round_next;
            stale_key <= key_hold;
            key_hold <= memory_word;
            if (round_index == 4'd11) begin
              block_o <= round_next;
              busy <= 1'b0;
              done <= 1'b1;
            end else begin
              round_index <= round_index + 4'd1;
            end
          end
        endcase
      end
    end
  end
endmodule

// ---------------------------------------------------------------------------
// Six exact graded wrapper tops.  All mutation hooks are tied off here.
module e256h_h2_ff_fixed (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [11:0] cfg_h4, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h2_ff_core #(.DIRECT_H4(0)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
  );
endmodule

module e256h_h2_ff_direct (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [11:0] cfg_h4, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h2_ff_core #(.DIRECT_H4(1)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
  );
endmodule

module e256h_h2_ring_fixed (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [11:0] cfg_h4, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h2_ring_core #(.DIRECT_H4(0)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
  );
endmodule

module e256h_h2_ring_direct (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [11:0] cfg_h4, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h2_ring_core #(.DIRECT_H4(1)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
  );
endmodule

module e256h_h2_mem_fixed (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [11:0] cfg_h4, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h2_mem_core #(.DIRECT_H4(0)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
  );
endmodule

module e256h_h2_mem_direct (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [11:0] cfg_h4, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h2_mem_core #(.DIRECT_H4(1)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
  );
endmodule

// ---------------------------------------------------------------------------
// Parameterized mutation wrapper used only by the control testbench.
// Mutation codes are a local harness ABI because the frozen documents name the
// mutations but do not assign numbers:
//   0 none                         4 broken ring acceptance rotation
//   1 wrong round-key address      5 stale synchronous-memory read
//   2 wrong H4 shift direction     6 wrong-key-order input file (TB-side)
//   3 ignore runtime H4 selector   7 reverse-word-bytes input file (TB-side)
// Codes 6 and 7 intentionally leave RTL unchanged; the runner supplies the
// mutated mask file so the independent loader/packing path is graded.
module e256h_h2_control_core #(
    parameter integer STORAGE = 0,       // 0=ff, 1=ring, 2=mem
    parameter integer DIRECT_H4 = 1,
    parameter integer MUTATION = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [11:0]  cfg_h4,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output wire [255:0] block_o,
    output wire         busy,
    output wire         done
);
  generate
    if (STORAGE == 0) begin : g_ff
      e256h_h2_ff_core #(
          .DIRECT_H4(DIRECT_H4),
          .MUTATE_WRONG_KEY_ADDRESS(MUTATION == 1),
          .MUTATE_H4_DIRECTION(MUTATION == 2),
          .MUTATE_IGNORE_SELECTOR(MUTATION == 3)
      ) u_core (
          .clk(clk), .rst(rst), .cfg_begin(cfg_begin),
          .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_word(cfg_word),
          .cfg_commit(cfg_commit), .cfg_h4(cfg_h4), .key_valid(key_valid),
          .cfg_error(cfg_error), .start(start), .ready(ready),
          .block_i(block_i), .block_o(block_o), .busy(busy), .done(done)
      );
    end else if (STORAGE == 1) begin : g_ring
      e256h_h2_ring_core #(
          .DIRECT_H4(DIRECT_H4),
          .MUTATE_H4_DIRECTION(MUTATION == 2),
          .MUTATE_IGNORE_SELECTOR(MUTATION == 3),
          .MUTATE_BROKEN_RING_ROTATION(MUTATION == 4)
      ) u_core (
          .clk(clk), .rst(rst), .cfg_begin(cfg_begin),
          .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_word(cfg_word),
          .cfg_commit(cfg_commit), .cfg_h4(cfg_h4), .key_valid(key_valid),
          .cfg_error(cfg_error), .start(start), .ready(ready),
          .block_i(block_i), .block_o(block_o), .busy(busy), .done(done)
      );
    end else begin : g_mem
      e256h_h2_mem_core #(
          .DIRECT_H4(DIRECT_H4),
          .MUTATE_WRONG_KEY_ADDRESS(MUTATION == 1),
          .MUTATE_H4_DIRECTION(MUTATION == 2),
          .MUTATE_IGNORE_SELECTOR(MUTATION == 3),
          .MUTATE_STALE_MEMORY_READ(MUTATION == 5)
      ) u_core (
          .clk(clk), .rst(rst), .cfg_begin(cfg_begin),
          .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_word(cfg_word),
          .cfg_commit(cfg_commit), .cfg_h4(cfg_h4), .key_valid(key_valid),
          .cfg_error(cfg_error), .start(start), .ready(ready),
          .block_i(block_i), .block_o(block_o), .busy(busy), .done(done)
      );
    end
  endgenerate
endmodule

// Deliberately rejected H2 accounting control.  The complete 3,328-bit mask
// schedule is a live external port, so this module has no integrated keyed
// store and MUST NOT be reported as an H2 system result.
module e256h_h2_externalized_storage_control (
    input  wire          clk,
    input  wire          rst,
    input  wire          start,
    input  wire [255:0]  block_i,
    input  wire [3327:0] mask_words,
    output wire          ready,
    output reg  [255:0]  block_o,
    output reg           busy,
    output reg           done
);
  reg [255:0] state;
  reg [3:0] round_index;
  wire [255:0] round_key = mask_words[(round_index+1)*256 +: 256];
  wire [255:0] round_next;

  assign ready = !busy;

  e256h_h2_round_fixed u_round (
      .state_i(state), .round_key(round_key), .state_o(round_next)
  );

  always @(posedge clk) begin
    if (rst) begin
      state <= 256'd0;
      round_index <= 4'd0;
      block_o <= 256'd0;
      busy <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start && ready) begin
        state <= block_i ^ mask_words[0 +: 256];
        round_index <= 4'd0;
        busy <= 1'b1;
      end else if (busy) begin
        state <= round_next;
        if (round_index == 4'd11) begin
          block_o <= round_next;
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          round_index <= round_index + 4'd1;
        end
      end
    end
  end
endmodule

`default_nettype wire
