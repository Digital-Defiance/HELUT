// E256-H H4 switching-sequence integrated cores -- NON-PRODUCTION RESEARCH RTL.
//
// Contract: directives/e256-hardware-h4-sequence-preregistration.json
// Design record: directives/e256-hardware-architecture.md section 11
//
// This file adds only the frozen R=12 repeated/per-round selector experiment.
// It reuses the immutable H2 protocol, nonlinear/linear layers, and stationary
// and rotating 13-word effective-mask stores.  It is not a cipher suite,
// production implementation, H4 policy, key schedule, round-count selection,
// security claim, or reset/zeroization claim.  The two externalized controls at
// the end are deliberately invalid accounting fixtures and are never graded
// variants.

`default_nettype none

// Runtime H4 round over the frozen H2 SubBytes and MixColumns primitives.
module e256h_h4_round_direct #(
    parameter integer MUTATE_H4_DIRECTION = 0
) (
    input  wire [255:0] state_i,
    input  wire [255:0] round_key,
    input  wire [11:0]  h4_i,
    output wire [255:0] state_o
);
  wire [255:0] substituted;
  reg  [255:0] shifted;
  wire [255:0] mixed;

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
          0: row_offset = h4_i[2:0];
          1: row_offset = h4_i[5:3];
          2: row_offset = h4_i[8:6];
          default: row_offset = h4_i[11:9];
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

// Stationary-FF mask organization.  Every public wrapper leaves all mutation
// parameters at zero.  SELECTOR_MUTATION is a local control ABI:
//   0 normal w_r; 1 w_(11-r); 2 hold w_0; 3 w_((r+1) mod 12).
module e256h_h4_ff_core #(
    parameter integer SEQUENCE_MODE = 0,
    parameter integer SELECTOR_MUTATION = 0,
    parameter integer MUTATE_H4_DIRECTION = 0,
    parameter integer MUTATE_WRONG_KEY_ADDRESS = 0,
    parameter integer MUTATE_LIVE_SELECTOR = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [143:0] cfg_h4_sequence,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output reg  [255:0] block_o,
    output reg          busy,
    output reg          done
);
  wire         cfg_write;
  wire [3:0]   cfg_index;
  wire         commit_accept;
  wire         start_accept;
  reg  [3:0]   round_index;
  reg  [255:0] state;
  wire [3:0] read_index = busy ?
      ((MUTATE_WRONG_KEY_ADDRESS != 0) ? round_index
                                       : (round_index + 4'd1)) : 4'd0;
  wire [255:0] key_word;
  wire [11:0]  selected_h4;
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
    if (SEQUENCE_MODE != 0) begin : g_sequence_selector
      reg [143:0] selector_latched;
      reg [3:0] selector_index;
      wire [143:0] selector_source =
          (MUTATE_LIVE_SELECTOR != 0) ? cfg_h4_sequence : selector_latched;

      always @(posedge clk) begin
        if (commit_accept) begin
          selector_latched <= cfg_h4_sequence;
        end
      end

      always @* begin
        case (SELECTOR_MUTATION)
          1: selector_index = 4'd11 - round_index;
          2: selector_index = 4'd0;
          3: selector_index = (round_index == 4'd11) ? 4'd0
                                                     : round_index + 4'd1;
          default: selector_index = round_index;
        endcase
      end
      assign selected_h4 = selector_source[12*selector_index +: 12];
    end else begin : g_repeated_selector
      reg [11:0] selector_latched;
      always @(posedge clk) begin
        if (commit_accept) begin
          selector_latched <= cfg_h4_sequence[11:0];
        end
      end
      assign selected_h4 = (MUTATE_LIVE_SELECTOR != 0) ?
                           cfg_h4_sequence[11:0] : selector_latched;
    end
  endgenerate

  e256h_h4_round_direct #(
      .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION)
  ) u_round (
      .state_i(state), .round_key(key_word), .h4_i(selected_h4),
      .state_o(round_next)
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
      if (start_accept) begin
        // E0 applies K_0.  Every accepted block restarts selector indexing.
        state <= block_i ^ key_word;
        round_index <= 4'd0;
        busy <= 1'b1;
      end else if (busy) begin
        // E1..E12 apply K_1..K_12 with w_0..w_11.
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

// Rotating-ring mask organization.  Acceptance plus twelve busy rotations
// restore the thirteen-word bank to K_0 ordering after every valid block.
module e256h_h4_ring_core #(
    parameter integer SEQUENCE_MODE = 0,
    parameter integer SELECTOR_MUTATION = 0,
    parameter integer MUTATE_H4_DIRECTION = 0,
    parameter integer MUTATE_BROKEN_RING_ROTATION = 0,
    parameter integer MUTATE_LIVE_SELECTOR = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [143:0] cfg_h4_sequence,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output reg  [255:0] block_o,
    output reg          busy,
    output reg          done
);
  wire         cfg_write;
  wire [3:0]   cfg_index;
  wire         commit_accept;
  wire         start_accept;
  reg  [3:0]   round_index;
  reg  [255:0] state;
  wire [255:0] key_word;
  wire [11:0]  selected_h4;
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
    if (SEQUENCE_MODE != 0) begin : g_sequence_selector
      reg [143:0] selector_latched;
      reg [3:0] selector_index;
      wire [143:0] selector_source =
          (MUTATE_LIVE_SELECTOR != 0) ? cfg_h4_sequence : selector_latched;

      always @(posedge clk) begin
        if (commit_accept) begin
          selector_latched <= cfg_h4_sequence;
        end
      end

      always @* begin
        case (SELECTOR_MUTATION)
          1: selector_index = 4'd11 - round_index;
          2: selector_index = 4'd0;
          3: selector_index = (round_index == 4'd11) ? 4'd0
                                                     : round_index + 4'd1;
          default: selector_index = round_index;
        endcase
      end
      assign selected_h4 = selector_source[12*selector_index +: 12];
    end else begin : g_repeated_selector
      reg [11:0] selector_latched;
      always @(posedge clk) begin
        if (commit_accept) begin
          selector_latched <= cfg_h4_sequence[11:0];
        end
      end
      assign selected_h4 = (MUTATE_LIVE_SELECTOR != 0) ?
                           cfg_h4_sequence[11:0] : selector_latched;
    end
  endgenerate

  e256h_h4_round_direct #(
      .MUTATE_H4_DIRECTION(MUTATE_H4_DIRECTION)
  ) u_round (
      .state_i(state), .round_key(key_word), .h4_i(selected_h4),
      .state_o(round_next)
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

// Four exact graded tops.  Their common 144-bit port is configuration input;
// the repeated wrappers commit only its low twelve bits.
module e256h_h4_ff_repeated (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [143:0] cfg_h4_sequence, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h4_ff_core #(.SEQUENCE_MODE(0)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4_sequence(cfg_h4_sequence), .key_valid(key_valid),
      .cfg_error(cfg_error), .start(start), .ready(ready), .block_i(block_i),
      .block_o(block_o), .busy(busy), .done(done)
  );
endmodule

module e256h_h4_ff_sequence (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [143:0] cfg_h4_sequence, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h4_ff_core #(.SEQUENCE_MODE(1)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4_sequence(cfg_h4_sequence), .key_valid(key_valid),
      .cfg_error(cfg_error), .start(start), .ready(ready), .block_i(block_i),
      .block_o(block_o), .busy(busy), .done(done)
  );
endmodule

module e256h_h4_ring_repeated (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [143:0] cfg_h4_sequence, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h4_ring_core #(.SEQUENCE_MODE(0)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4_sequence(cfg_h4_sequence), .key_valid(key_valid),
      .cfg_error(cfg_error), .start(start), .ready(ready), .block_i(block_i),
      .block_o(block_o), .busy(busy), .done(done)
  );
endmodule

module e256h_h4_ring_sequence (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [143:0] cfg_h4_sequence, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h4_ring_core #(.SEQUENCE_MODE(1)) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4_sequence(cfg_h4_sequence), .key_valid(key_valid),
      .cfg_error(cfg_error), .start(start), .ready(ready), .block_i(block_i),
      .block_o(block_o), .busy(busy), .done(done)
  );
endmodule

// Parameterized control wrapper.  Mutation codes are local runner/TB ABI:
//   0 none; 1 reverse sequence; 2 hold w0; 3 index+1; 4 reverse H4;
//   5 wrong key address; 6 broken ring acceptance rotation;
//   7 read live selector pins; 8 reverse mask bytes (TB/input-file side).
module e256h_h4_control_core #(
    parameter integer STORAGE = 0,       // 0=ff, 1=ring
    parameter integer SEQUENCE_MODE = 1,
    parameter integer MUTATION = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         cfg_begin,
    input  wire         cfg_valid,
    output wire         cfg_ready,
    input  wire [255:0] cfg_word,
    input  wire         cfg_commit,
    input  wire [143:0] cfg_h4_sequence,
    output wire         key_valid,
    output wire         cfg_error,
    input  wire         start,
    output wire         ready,
    input  wire [255:0] block_i,
    output wire [255:0] block_o,
    output wire         busy,
    output wire         done
);
  localparam integer SELECTOR_CONTROL =
      (MUTATION == 1) ? 1 : (MUTATION == 2) ? 2 :
      (MUTATION == 3) ? 3 : 0;

  generate
    if (STORAGE == 0) begin : g_ff
      e256h_h4_ff_core #(
          .SEQUENCE_MODE(SEQUENCE_MODE),
          .SELECTOR_MUTATION(SELECTOR_CONTROL),
          .MUTATE_H4_DIRECTION(MUTATION == 4),
          .MUTATE_WRONG_KEY_ADDRESS(MUTATION == 5),
          .MUTATE_LIVE_SELECTOR(MUTATION == 7)
      ) u_core (
          .clk(clk), .rst(rst), .cfg_begin(cfg_begin),
          .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_word(cfg_word),
          .cfg_commit(cfg_commit), .cfg_h4_sequence(cfg_h4_sequence),
          .key_valid(key_valid), .cfg_error(cfg_error), .start(start),
          .ready(ready), .block_i(block_i), .block_o(block_o),
          .busy(busy), .done(done)
      );
    end else begin : g_ring
      e256h_h4_ring_core #(
          .SEQUENCE_MODE(SEQUENCE_MODE),
          .SELECTOR_MUTATION(SELECTOR_CONTROL),
          .MUTATE_H4_DIRECTION(MUTATION == 4),
          .MUTATE_BROKEN_RING_ROTATION(MUTATION == 6),
          .MUTATE_LIVE_SELECTOR(MUTATION == 7)
      ) u_core (
          .clk(clk), .rst(rst), .cfg_begin(cfg_begin),
          .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_word(cfg_word),
          .cfg_commit(cfg_commit), .cfg_h4_sequence(cfg_h4_sequence),
          .key_valid(key_valid), .cfg_error(cfg_error), .start(start),
          .ready(ready), .block_i(block_i), .block_o(block_o),
          .busy(busy), .done(done)
      );
    end
  endgenerate
endmodule

// Deliberately invalid: sequence selection reads the 144-bit live port rather
// than committed selector state.  Synthesis must reject this as a graded top.
module e256h_h4_externalized_sequence_control (
    input wire clk, input wire rst, input wire cfg_begin,
    input wire cfg_valid, output wire cfg_ready,
    input wire [255:0] cfg_word, input wire cfg_commit,
    input wire [143:0] cfg_h4_sequence, output wire key_valid,
    output wire cfg_error, input wire start, output wire ready,
    input wire [255:0] block_i, output wire [255:0] block_o,
    output wire busy, output wire done
);
  e256h_h4_ff_core #(
      .SEQUENCE_MODE(1), .MUTATE_LIVE_SELECTOR(1)
  ) u_core (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4_sequence(cfg_h4_sequence), .key_valid(key_valid),
      .cfg_error(cfg_error), .start(start), .ready(ready), .block_i(block_i),
      .block_o(block_o), .busy(busy), .done(done)
  );
endmodule

// Deliberately invalid: the complete mask bank is a wide live input.  Selector
// state is still commit-sampled so only the mask boundary is under test.
module e256h_h4_externalized_mask_control (
    input  wire          clk,
    input  wire          rst,
    input  wire          selector_commit,
    input  wire [143:0]  cfg_h4_sequence,
    input  wire          start,
    input  wire [255:0]  block_i,
    input  wire [3327:0] mask_words,
    output wire          ready,
    output reg  [255:0]  block_o,
    output reg           busy,
    output reg           done
);
  reg [143:0] selector_latched;
  reg [255:0] state;
  reg [3:0] round_index;
  wire [255:0] round_key = mask_words[(round_index+1)*256 +: 256];
  wire [11:0] selected_h4 = selector_latched[12*round_index +: 12];
  wire [255:0] round_next;

  assign ready = !busy;

  always @(posedge clk) begin
    if (selector_commit) begin
      selector_latched <= cfg_h4_sequence;
    end
  end

  e256h_h4_round_direct u_round (
      .state_i(state), .round_key(round_key), .h4_i(selected_h4),
      .state_o(round_next)
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
