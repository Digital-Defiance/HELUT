`timescale 1ns / 1ps

// E256-v2/gen0 native reversible NLFF — combinational TensorLUT cone.
// Bounded research profile; see logs/e256-v2-gen0-nlff-search.json.
module enigma_256_nlff_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
    assign step_r1 = e256_nlff_step_r1;
    assign step_r2 = e256_nlff_step_r2;
    assign step_r3 = e256_nlff_step_r3;
    assign step_r4 = e256_nlff_step_r4;
endmodule
