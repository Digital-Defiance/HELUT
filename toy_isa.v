// Toy ISA for Phase 0.9 M1 remainder: host-clocked ACC, NOP / ADD imm.
// Not PicoRV32. Not a real instruction set.

module toy_isa (
    input  wire       clk,
    input  wire [1:0] op,   // 2'b01 = ADD, else NOP
    input  wire [3:0] imm,
    output reg  [3:0] acc
);
    always @(posedge clk) begin
        if (op == 2'b01)
            acc <= acc + imm;
        else
            acc <= acc;
    end
endmodule
