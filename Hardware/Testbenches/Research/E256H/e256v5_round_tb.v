// Walks E256-v5 for N blocks. Parameters come from the Python schedule.
`default_nettype none
`timescale 1ns / 1ps

module e256v5_round_tb;
  reg [7:0] nmem [0:1];
  reg [7:0] mem [0:32383];
  reg [255:0] st, mk, cin, cout, want, plain, pre;
  reg [2047:0] min_m, mout_m, min_inv, mout_inv;
  wire [255:0] enc_out, dec_out;
  integer i, k, r, n, rounds, base, fail;

  e256v5_round u (
    .decrypt(1'b0), .st(st), .mask(mk), .cin(cin), .cout(cout),
    .min_m(min_m), .mout_m(mout_m), .min_inv(min_inv), .mout_inv(mout_inv),
    .st_out(enc_out)
  );
  e256v5_round d (
    .decrypt(1'b1), .st(st), .mask(mk), .cin(cin), .cout(cout),
    .min_m(min_m), .mout_m(mout_m), .min_inv(min_inv), .mout_inv(mout_inv),
    .st_out(dec_out)
  );

  task load_round;
    input integer at;
    integer t;
    begin
      for (t = 0; t < 32; t = t + 1) begin
        cin[8 * t +: 8] = mem[at + t];
        cout[8 * t +: 8] = mem[at + 32 + t];
        mk[8 * t +: 8] = mem[at + 64 + 1024 + t];
      end
      for (t = 0; t < 256; t = t + 1) begin
        min_m[8 * t +: 8] = mem[at + 64 + t];
        mout_m[8 * t +: 8] = mem[at + 64 + 256 + t];
        min_inv[8 * t +: 8] = mem[at + 64 + 512 + t];
        mout_inv[8 * t +: 8] = mem[at + 64 + 768 + t];
      end
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
      for (i = 0; i < 32; i = i + 1) begin
        plain[8 * i +: 8] = mem[base + i];
        pre[8 * i +: 8] = mem[base + 32 + i];
      end
      st = plain ^ pre;
      for (r = 0; r < rounds; r = r + 1) begin
        load_round(base + 64 + r * 1152);
        for (i = 0; i < 32; i = i + 1)
          want[8 * i +: 8] = mem[base + 64 + r * 1152 + 1120 + i];
        #1;
        if (enc_out !== want) begin
          $display("FAIL encrypt block %0d round %0d", k, r);
          fail = fail + 1;
        end
        st = u.st_out;
      end
      for (r = rounds - 1; r >= 0; r = r - 1) begin
        load_round(base + 64 + r * 1152);
        #1;
        st = dec_out;
      end
      st = st ^ pre;
      if (st !== plain) begin
        $display("FAIL decrypt block %0d", k);
        fail = fail + 1;
      end
      base = base + 64 + rounds * 1152;
    end
    if (fail) $fatal(1);
    $display("PASS verilog %0d blocks x %0d rounds", n, rounds);
    $finish;
  end
endmodule
`default_nettype wire
