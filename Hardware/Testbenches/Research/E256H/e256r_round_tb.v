// Walks the frozen experimental machine. Masks come from the Python schedule.
`default_nettype none
`timescale 1ns / 1ps

module e256r_round_tb;
  reg [7:0] nmem [0:1];
  reg [7:0] mem [0:4607];
  reg [255:0] st, mk, want, plain;
  wire [255:0] cipher, back;
  integer i, k, r, n, rounds, base, fail, steps;

  e256r_round u_enc (.decrypt(1'b0), .st(st), .mask(mk), .st_out(cipher));
  e256r_round u_dec (.decrypt(1'b1), .st(st), .mask(mk), .st_out(back));

  initial begin
    $readmemh("nvec.hex", nmem);
    $readmemh("vectors.hex", mem);
    n = nmem[0];
    rounds = nmem[1];
    fail = 0;
    steps = 0;
    base = 0;
    for (k = 0; k < n; k = k + 1) begin
      for (i = 0; i < 32; i = i + 1)
        plain[8*i +: 8] = mem[base + i];
      st = plain;
      for (r = 0; r < rounds; r = r + 1) begin
        for (i = 0; i < 32; i = i + 1) begin
          mk[8*i +: 8] = mem[base + 32 + r*32 + i];
          want[8*i +: 8] = mem[base + 32 + rounds*32 + r*32 + i];
        end
        #1;
        if (cipher !== want) begin
          $display("FAIL encrypt block %0d round %0d", k, r);
          fail = fail + 1;
        end
        st = cipher;
        steps = steps + 1;
      end
      for (r = rounds - 1; r >= 0; r = r - 1) begin
        for (i = 0; i < 32; i = i + 1)
          mk[8*i +: 8] = mem[base + 32 + r*32 + i];
        #1;
        st = back;
      end
      if (st !== plain) begin
        $display("FAIL decrypt block %0d", k);
        fail = fail + 1;
      end
      base = base + 32 * (1 + 2 * rounds);
    end
    if (fail) $fatal(1);
    $display("PASS verilog %0d blocks x %0d rounds match python and decrypt", n, rounds);
    $finish;
  end
endmodule
`default_nettype wire
