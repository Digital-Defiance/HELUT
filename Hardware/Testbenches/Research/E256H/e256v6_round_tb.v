// Walks E256-v6 for N blocks. The round count comes from the Python schedule.
`default_nettype none
`timescale 1ns / 1ps

module e256v6_round_tb;
  reg [7:0] nmem [0:1];
  reg [7:0] mem [0:3263];
  reg [255:0] st, scale, want, plain;
  wire [255:0] enc_out, dec_out;
  reg [7:0] sched [0:2399];
  integer i, k, r, n, rounds, base, fail;
  integer s, differ_block, differ_key;

  e256v6_round u (
    .decrypt(1'b0), .st(st), .scale(scale), .st_out(enc_out)
  );
  e256v6_round d (
    .decrypt(1'b1), .st(st), .scale(scale), .st_out(dec_out)
  );

  task load_round;
    input integer at;
    integer t;
    begin
      for (t = 0; t < 32; t = t + 1)
        scale[8 * t +: 8] = mem[at + t];
    end
  endtask

  initial begin
    $readmemh("nvec.hex", nmem);
    $readmemh("vectors.hex", mem);
    n = nmem[0];
    rounds = nmem[1];
    fail = 0;
    base = 0;
    for (k = 0; k < n; k = k + 1) begin
      for (i = 0; i < 32; i = i + 1)
        plain[8 * i +: 8] = mem[base + i];
      st = plain;
      for (r = 0; r < rounds; r = r + 1) begin
        load_round(base + 32 + r * 64);
        for (i = 0; i < 32; i = i + 1)
          want[8 * i +: 8] = mem[base + 32 + r * 64 + 32 + i];
        #1;
        if (enc_out !== want) begin
          $display("FAIL encrypt block %0d round %0d", k, r);
          fail = fail + 1;
        end
        st = enc_out;
      end
      for (r = rounds - 1; r >= 0; r = r - 1) begin
        load_round(base + 32 + r * 64);
        #1;
        st = dec_out;
      end
      if (st !== plain) begin
        $display("FAIL decrypt block %0d", k);
        fail = fail + 1;
      end
      base = base + 32 + rounds * 64;
    end
    if (fail) $fatal(1);
    $readmemh("sched.hex", sched);
    differ_block = 0;
    differ_key = 0;
    begin : sched_check
      integer words, stride;
      words = rounds * 16;
      stride = words * 2;
      for (s = 0; s < words; s = s + 1) begin
        if (sched[2 * s] != sched[stride + 2 * s] || sched[2 * s + 1] != sched[stride + 2 * s + 1])
          differ_block = differ_block + 1;
        if (sched[2 * s] != sched[2 * stride + 2 * s] || sched[2 * s + 1] != sched[2 * stride + 2 * s + 1])
          differ_key = differ_key + 1;
      end
      if (differ_block != words || differ_key != words) begin
        $display("FAIL schedule block %0d key %0d", differ_block, differ_key);
        $fatal(1);
      end
      $display("PASS verilog %0d blocks x %0d rounds  scales %0d/%0d", n, rounds, differ_key, words);
    end
    $finish;
  end
endmodule
