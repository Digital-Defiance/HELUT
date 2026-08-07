// E256-H H3 XOR-offset collapse SAT lemma — NON-PRODUCTION RESEARCH RTL.
//
// Contract: directives/e256-hardware-offset-collapse-preregistration.json
// Runner:   Scripts/e256_hardware_offset_collapse_gate.py
//
// This combinational cone proves the compositional linear identity
//
//   L(U XOR B) XOR M == L(U) XOR L(B) XOR M
//
// for arbitrary U, B, and M under the fixed certified H4 tuple (0,1,3,4).
// The original and canonical sides use independently instantiated complete
// forward-H4 linear-layer paths.  The nonlinear boundary is outside this SAT
// cone: the unchanged dual e256h_atk_single sequencing test remains the
// integration link to the frozen AES S-box bank and round implementation.
//
// Four explicit tops freeze the correct and planted-mutation modes at
// elaboration time.  This is not a production core, suite, profile, fixture,
// or security claim.

`default_nettype none

// Complete H4 linear layer L_w for the fixed certified tuple (0,1,3,4).
module e256h_offset_collapse_linear #(
    parameter integer OFF0 = 0,
    parameter integer OFF1 = 1,
    parameter integer OFF2 = 3,
    parameter integer OFF3 = 4
) (
    input  wire [255:0] value,
    output wire [255:0] transformed
);
  function [7:0] xt(input [7:0] v);
    xt = v[7] ? ((v << 1) ^ 8'h1b) : (v << 1);
  endfunction

  wire [255:0] shifted;

  genvar c, r;
  generate
    for (c = 0; c < 8; c = c + 1) begin : g_shift_col
      for (r = 0; r < 4; r = r + 1) begin : g_shift_row
        localparam integer OFFR =
            (r == 0) ? OFF0 : (r == 1) ? OFF1 : (r == 2) ? OFF2 : OFF3;
        localparam integer SRC = 4 * ((c + OFFR) % 8) + r;
        assign shifted[8*(4*c+r) +: 8] = value[8*SRC +: 8];
      end
    end
  endgenerate

  generate
    for (c = 0; c < 8; c = c + 1) begin : g_mix_col
      wire [7:0] a0 = shifted[8*(4*c+0) +: 8];
      wire [7:0] a1 = shifted[8*(4*c+1) +: 8];
      wire [7:0] a2 = shifted[8*(4*c+2) +: 8];
      wire [7:0] a3 = shifted[8*(4*c+3) +: 8];
      assign transformed[8*(4*c+0) +: 8] =
          xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3;
      assign transformed[8*(4*c+1) +: 8] =
          a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3;
      assign transformed[8*(4*c+2) +: 8] =
          a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3;
      assign transformed[8*(4*c+3) +: 8] =
          xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3);
    end
  endgenerate
endmodule

// MODE 0: correct transport,       L(U) XOR L(B) XOR M
// MODE 1: omit_output_transport,   L(U) XOR M
// MODE 2: raw_output_offset,       L(U) XOR B XOR M
// MODE 3: wrong_transport_source,  L(U) XOR L(A) XOR M
module e256h_offset_collapse_miter #(
    parameter integer MODE = 0
) (
    input  wire [255:0] U,
    input  wire [255:0] A,
    input  wire [255:0] B,
    input  wire [255:0] M,
    output wire [255:0] original_out,
    output wire [255:0] canonical_out,
    output wire         mismatch
);
  wire [255:0] original_linear;
  wire [255:0] canonical_linear_U;
  wire [255:0] canonical_linear_B;
  wire [255:0] canonical_linear_A;
  wire [255:0] canonical_transport;

  // The original side has its own complete L(U XOR B) path.
  e256h_offset_collapse_linear u_original_linear (
      .value(U ^ B),
      .transformed(original_linear)
  );

  // The canonical side uses separate complete L(U), L(B), and L(A) paths.
  e256h_offset_collapse_linear u_canonical_linear_U (
      .value(U),
      .transformed(canonical_linear_U)
  );

  e256h_offset_collapse_linear u_canonical_linear_B (
      .value(B),
      .transformed(canonical_linear_B)
  );

  e256h_offset_collapse_linear u_canonical_linear_A (
      .value(A),
      .transformed(canonical_linear_A)
  );

  assign canonical_transport =
      (MODE == 1) ? 256'd0 :
      (MODE == 2) ? B :
      (MODE == 3) ? canonical_linear_A :
                    canonical_linear_B;

  assign original_out = original_linear ^ M;
  assign canonical_out = canonical_linear_U ^ canonical_transport ^ M;
  assign mismatch = |(original_out ^ canonical_out);
endmodule

module e256h_offset_collapse_correct (
    input  wire [255:0] U,
    input  wire [255:0] B,
    input  wire [255:0] M,
    output wire [255:0] original_out,
    output wire [255:0] canonical_out,
    output wire         mismatch
);
  e256h_offset_collapse_miter #(.MODE(0)) u_miter (
      .U(U),
      .A(256'd0),
      .B(B),
      .M(M),
      .original_out(original_out),
      .canonical_out(canonical_out),
      .mismatch(mismatch)
  );
endmodule

module e256h_offset_collapse_omit_output_transport (
    input  wire [255:0] U,
    input  wire [255:0] B,
    input  wire [255:0] M,
    output wire [255:0] original_out,
    output wire [255:0] canonical_out,
    output wire         mismatch
);
  e256h_offset_collapse_miter #(.MODE(1)) u_miter (
      .U(U),
      .A(256'd0),
      .B(B),
      .M(M),
      .original_out(original_out),
      .canonical_out(canonical_out),
      .mismatch(mismatch)
  );
endmodule

module e256h_offset_collapse_raw_output_offset (
    input  wire [255:0] U,
    input  wire [255:0] B,
    input  wire [255:0] M,
    output wire [255:0] original_out,
    output wire [255:0] canonical_out,
    output wire         mismatch
);
  e256h_offset_collapse_miter #(.MODE(2)) u_miter (
      .U(U),
      .A(256'd0),
      .B(B),
      .M(M),
      .original_out(original_out),
      .canonical_out(canonical_out),
      .mismatch(mismatch)
  );
endmodule

module e256h_offset_collapse_wrong_transport_source (
    input  wire [255:0] U,
    input  wire [255:0] A,
    input  wire [255:0] B,
    input  wire [255:0] M,
    output wire [255:0] original_out,
    output wire [255:0] canonical_out,
    output wire         mismatch
);
  e256h_offset_collapse_miter #(.MODE(3)) u_miter (
      .U(U),
      .A(A),
      .B(B),
      .M(M),
      .original_out(original_out),
      .canonical_out(canonical_out),
      .mismatch(mismatch)
  );
endmodule

`default_nettype wire
