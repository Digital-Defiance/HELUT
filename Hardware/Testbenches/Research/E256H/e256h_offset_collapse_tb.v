// Sequential E256-H H3 XOR-offset collapse comparison testbench.
//
// Contract: directives/e256-hardware-offset-collapse-preregistration.json
// Runner:   Scripts/e256_hardware_offset_collapse_gate.py
//
// The testbench instantiates the unchanged frozen e256h_atk_single twice.  The
// original side receives the frozen offsets and masks.  The canonical side
// receives zero offsets and a separately rebuilt fixed-R K_0..K_R schedule for
// every R=1..8.  Eight deterministic blocks produce exactly 64 result rows.
// All changing stimulus and start pulses are driven on negedge.

`default_nettype none
`timescale 1ns / 1ps

module e256h_offset_collapse_tb;

  localparam integer MAXR = 8;
  localparam integer MATERIAL_BYTES = 1184;
  localparam integer MASK_BASE = 768;
  localparam integer BLOCK_COUNT = 8;

  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [7:0] material [0:MATERIAL_BYTES-1];
  reg [7:0] block_bytes [0:BLOCK_COUNT*32-1];

  reg [MAXR*256-1:0]     original_p_in_all;
  reg [MAXR*256-1:0]     original_p_out_all;
  reg [(MAXR+1)*256-1:0] original_mask_all;
  reg [MAXR*256-1:0]     canonical_p_in_all;
  reg [MAXR*256-1:0]     canonical_p_out_all;
  reg [(MAXR+1)*256-1:0] canonical_mask_all;

  reg         start;
  reg [255:0] block;
  reg [3:0]   rounds;
  wire [255:0] original_result;
  wire [255:0] canonical_result;
  wire         original_done;
  wire         canonical_done;

  integer fd;
  integer i;
  integer j;
  integer r;
  integer block_index;
  reg [255:0] selected_block;

  function automatic [7:0] xt(input [7:0] value);
    xt = value[7] ? ((value << 1) ^ 8'h1b) : (value << 1);
  endfunction

  // Complete fixed-H4 L_w: forward +offset RowShift, then MixColumns.
  function automatic [255:0] linear_layer(input [255:0] value);
    reg [255:0] shifted;
    reg [7:0] a0;
    reg [7:0] a1;
    reg [7:0] a2;
    reg [7:0] a3;
    integer column;
    integer row;
    integer offset;
    integer source;
    begin
      shifted = 256'd0;
      linear_layer = 256'd0;
      for (column = 0; column < 8; column = column + 1) begin
        for (row = 0; row < 4; row = row + 1) begin
          offset = (row == 0) ? 0 : (row == 1) ? 1 : (row == 2) ? 3 : 4;
          source = 4 * ((column + offset) % 8) + row;
          shifted[8*(4*column+row) +: 8] = value[8*source +: 8];
        end
      end
      for (column = 0; column < 8; column = column + 1) begin
        a0 = shifted[8*(4*column+0) +: 8];
        a1 = shifted[8*(4*column+1) +: 8];
        a2 = shifted[8*(4*column+2) +: 8];
        a3 = shifted[8*(4*column+3) +: 8];
        linear_layer[8*(4*column+0) +: 8] =
            xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
        linear_layer[8*(4*column+1) +: 8] =
            a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
        linear_layer[8*(4*column+2) +: 8] =
            a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
        linear_layer[8*(4*column+3) +: 8] =
            xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
      end
    end
  endfunction

  e256h_atk_single #(.MAXR(MAXR)) u_original (
      .clk(clk),
      .rst(rst),
      .start(start),
      .block(block),
      .rounds(rounds),
      .defect(2'd0),
      .p_in_all(original_p_in_all),
      .p_out_all(original_p_out_all),
      .mask_all(original_mask_all),
      .result(original_result),
      .done(original_done)
  );

  e256h_atk_single #(.MAXR(MAXR)) u_canonical (
      .clk(clk),
      .rst(rst),
      .start(start),
      .block(block),
      .rounds(rounds),
      .defect(2'd0),
      .p_in_all(canonical_p_in_all),
      .p_out_all(canonical_p_out_all),
      .mask_all(canonical_mask_all),
      .result(canonical_result),
      .done(canonical_done)
  );

  task automatic rebuild_fixed_round_keys(input integer fixed_rounds);
    integer key_index;
    begin
      canonical_mask_all = {(MAXR+1)*256{1'b0}};
      // K_0 = M_0 XOR A_0.
      canonical_mask_all[0 +: 256] =
          original_mask_all[0 +: 256] ^ original_p_in_all[0 +: 256];
      // Interior K_r includes A_r.  This loop is deliberately fixed-R.
      for (key_index = 1; key_index < fixed_rounds; key_index = key_index + 1) begin
        canonical_mask_all[key_index*256 +: 256] =
            linear_layer(original_p_out_all[(key_index-1)*256 +: 256]) ^
            original_mask_all[key_index*256 +: 256] ^
            original_p_in_all[key_index*256 +: 256];
      end
      // Terminal K_R excludes A_R.
      canonical_mask_all[fixed_rounds*256 +: 256] =
          linear_layer(original_p_out_all[(fixed_rounds-1)*256 +: 256]) ^
          original_mask_all[fixed_rounds*256 +: 256];
    end
  endtask

  task automatic run_pair(input [255:0] block_value);
    begin
      @(negedge clk);
      block = block_value;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      wait (original_done == 1'b1 && canonical_done == 1'b1);
      // Capture on negedge after both nonblocking result assignments settle.
      @(negedge clk);
    end
  endtask

  initial begin
    $readmemh("build/e256h-offset-collapse/material.hex", material);
    $readmemh("build/e256h-offset-collapse/blocks.hex", block_bytes);

    original_p_in_all = {MAXR*256{1'b0}};
    original_p_out_all = {MAXR*256{1'b0}};
    original_mask_all = {(MAXR+1)*256{1'b0}};
    canonical_p_in_all = {MAXR*256{1'b0}};
    canonical_p_out_all = {MAXR*256{1'b0}};
    canonical_mask_all = {(MAXR+1)*256{1'b0}};

    // Raw attack material layout: interleaved A/B, then masks at byte 768.
    for (i = 0; i < MAXR; i = i + 1) begin
      for (j = 0; j < 32; j = j + 1) begin
        original_p_in_all[(i*32+j)*8 +: 8] = material[(i*32+j)*2];
        original_p_out_all[(i*32+j)*8 +: 8] = material[(i*32+j)*2 + 1];
      end
    end
    for (i = 0; i < MAXR + 1; i = i + 1) begin
      for (j = 0; j < 32; j = j + 1) begin
        original_mask_all[(i*32+j)*8 +: 8] = material[MASK_BASE + i*32 + j];
      end
    end

    start = 1'b0;
    block = 256'd0;
    rounds = 4'd1;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    fd = $fopen("build/e256h-offset-collapse/results.txt", "w");
    if (fd == 0) begin
      $fatal(1, "could not open offset-collapse results file");
    end

    for (r = 1; r <= MAXR; r = r + 1) begin
      @(negedge clk);
      rounds = r[3:0];
      rebuild_fixed_round_keys(r);

      for (block_index = 0; block_index < BLOCK_COUNT;
           block_index = block_index + 1) begin
        selected_block = 256'd0;
        for (j = 0; j < 32; j = j + 1) begin
          selected_block[8*j +: 8] = block_bytes[block_index*32+j];
        end
        run_pair(selected_block);
        $fwrite(fd, "rtl %0d %0d %064x %064x\n",
                r, block_index, original_result, canonical_result);
      end
    end

    $fclose(fd);
    $display("E256H_OFFSET_COLLAPSE_TB DONE");
    $finish;
  end

endmodule

`default_nettype wire
