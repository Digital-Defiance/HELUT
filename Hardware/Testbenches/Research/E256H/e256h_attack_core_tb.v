// Drives the E256-H hardware attack lane and dumps results for grading.
//
// Contract: directives/e256-hardware-attack-preregistration.json
// Driven by: Scripts/e256_hardware_attack_gate.py, which writes the material
// file and independently recomputes every expected value.
//
// Arm 1 (integral): for each defect mode and round count, sweep a Lambda-set
// over the active lane and report the XOR accumulator plus its zero-byte count.
// Arm 2 (truncated differential): for each defect mode and round count, count
// active output bytes for a one-byte input difference.

`default_nettype none
`timescale 1ns / 1ps

module e256h_attack_core_tb;

  localparam integer MAXR = 8;

  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [7:0] material [0:1183];

  reg [MAXR*256-1:0]     p_in_all;
  reg [MAXR*256-1:0]     p_out_all;
  reg [(MAXR+1)*256-1:0] mask_all;

  reg  [3:0] rounds;
  reg  [1:0] defect;
  reg  [4:0] active_lane;

  reg          int_start;
  wire [255:0] int_acc;
  wire [5:0]   int_balanced;
  wire         int_done;

  reg          sgl_start;
  reg  [255:0] sgl_block;
  wire [255:0] sgl_result;
  wire         sgl_done;

  integer fd;
  integer i;
  integer j;
  integer r;
  integer d;
  integer active_count;
  reg [255:0] base_ct;
  reg [255:0] diff_ct;

  // Measured cycle cost of each attack run.
  integer cycle_counter = 0;
  integer cycle_mark;
  integer integral_cycles;
  always @(posedge clk) cycle_counter = cycle_counter + 1;

  e256h_atk_integral #(.MAXR(MAXR)) u_integral (
      .clk(clk), .rst(rst), .start(int_start),
      .rounds(rounds), .defect(defect), .active_lane(active_lane),
      .p_in_all(p_in_all), .p_out_all(p_out_all), .mask_all(mask_all),
      .accumulator(int_acc), .balanced_bytes(int_balanced), .done(int_done)
  );

  e256h_atk_single #(.MAXR(MAXR)) u_single (
      .clk(clk), .rst(rst), .start(sgl_start),
      .block(sgl_block), .rounds(rounds), .defect(defect),
      .p_in_all(p_in_all), .p_out_all(p_out_all), .mask_all(mask_all),
      .result(sgl_result), .done(sgl_done)
  );

  // Stimulus changes on negedge so every control input is stable across the
  // posedge the DUT samples. Driving start on posedge races the DUT.
  task run_integral;
    begin
      @(negedge clk);
      int_start = 1'b1;
      @(negedge clk);
      int_start = 1'b0;
      wait (int_done == 1'b1);
      @(negedge clk);
    end
  endtask

  task run_single(input [255:0] block, output [255:0] out);
    begin
      @(negedge clk);
      sgl_block = block;
      sgl_start = 1'b1;
      @(negedge clk);
      sgl_start = 1'b0;
      wait (sgl_done == 1'b1);
      out = sgl_result;
      @(negedge clk);
    end
  endtask

  initial begin
    $readmemh("build/e256h-attack/material.hex", material);

    for (i = 0; i < MAXR; i = i + 1) begin
      for (j = 0; j < 32; j = j + 1) begin
        p_in_all[(i*32+j)*8 +: 8]  = material[(i*32+j)*2];
        p_out_all[(i*32+j)*8 +: 8] = material[(i*32+j)*2 + 1];
      end
    end
    for (i = 0; i < MAXR + 1; i = i + 1) begin
      for (j = 0; j < 32; j = j + 1) begin
        mask_all[(i*32+j)*8 +: 8] = material[768 + i*32 + j];
      end
    end

    int_start = 1'b0;
    sgl_start = 1'b0;
    active_lane = 5'd0;
    rounds = 4'd1;
    defect = 2'd0;

    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    fd = $fopen("build/e256h-attack/results.txt", "w");

    for (d = 0; d < 3; d = d + 1) begin
      defect = d[1:0];
      for (r = 1; r <= MAXR; r = r + 1) begin
        rounds = r[3:0];

        cycle_mark = cycle_counter;
        run_integral;
        integral_cycles = cycle_counter - cycle_mark;
        $fwrite(fd, "integral %0d %0d %0d %064x %0d\n",
                d, r, int_balanced, int_acc, integral_cycles);

        run_single(256'd0, base_ct);
        run_single(256'd1, diff_ct);
        active_count = 0;
        for (i = 0; i < 32; i = i + 1) begin
          if (base_ct[8*i +: 8] !== diff_ct[8*i +: 8]) begin
            active_count = active_count + 1;
          end
        end
        $fwrite(fd, "truncated %0d %0d %0d %064x %064x\n",
                d, r, active_count, base_ct, diff_ct);
      end
    end

    $fclose(fd);
    $display("E256H_ATTACK_TB DONE");
    $finish;
  end

endmodule

`default_nettype wire
