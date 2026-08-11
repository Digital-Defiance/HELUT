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
    wire [63:0] lfsr_next = {lfsr[62:0], 1'b0} ^ (lfsr[63] ? 64'hD800000000000000 : 64'h0);

    assign step_r1 = (lfsr[0] & lfsr[13] & lfsr[27]) ^ (lfsr[5] & lfsr[41]) ^ lfsr[62];
    assign step_r2 = (lfsr[1] & lfsr[18] & lfsr[33]) ^ (lfsr[9] & lfsr[44]) ^ lfsr[58];
    assign step_r3 = (lfsr[2] & lfsr[21] & lfsr[36]) ^ (lfsr[11] & lfsr[48]) ^ lfsr[55];
    assign step_r4 = (lfsr[3] & lfsr[24] & lfsr[39]) ^ (lfsr[14] & lfsr[51]) ^ lfsr[60];

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
