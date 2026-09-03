`timescale 1ns / 1ps

// Isolated LFSR + NLFF stepping cone for TensorLUT Red Team.
// Matches enigma_256_core.v stepping (no BRAM / no scrambler).
// Deliberate adversarial surface: recover linear vs NLFF-hardened step enables.

module enigma_256_step_cone (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_state,
    input  wire [63:0] init_lfsr,
    input  wire        step,          // clock LFSR one beat (like valid_in)
    output reg  [63:0] lfsr,
    output wire        step_r1,
    output wire        step_r2,
    output wire        step_r3,
    output wire        step_r4
);
    // Right-shift Galois convention: LSB selects the 0xD800… feedback mask.
    wire [63:0] lfsr_next = {1'b0, lfsr[63:1]} ^ (lfsr[0] ? 64'hD800000000000000 : 64'h0);

    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
    assign step_r1 = e256_nlff_step_r1;
    assign step_r2 = e256_nlff_step_r2;
    assign step_r3 = e256_nlff_step_r3;
    assign step_r4 = e256_nlff_step_r4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 64'd1;
        end else if (load_state) begin
            lfsr <= (init_lfsr == 64'd0) ? 64'd1 : init_lfsr;
        end else if (step) begin
            lfsr <= lfsr_next;
        end
    end
endmodule
