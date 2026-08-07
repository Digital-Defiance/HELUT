`timescale 1ns / 1ps

// E256-v3/gen0 native reversible NLFF combinational oracle.
// profile_sha256=0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16
module enigma_256_nlff_v3_combo (
    input  wire [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v3.vh"
    assign step_r1 = e256_nlff_step_r1;
    assign step_r2 = e256_nlff_step_r2;
    assign step_r3 = e256_nlff_step_r3;
    assign step_r4 = e256_nlff_step_r4;
endmodule
