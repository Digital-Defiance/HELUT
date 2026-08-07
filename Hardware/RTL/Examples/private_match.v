// Private equality primitive, written for the HELUT concept series (Episode 12).
//
// Two byte-wide values enter; a single bit leaves. Under encrypted evaluation
// neither input is ever revealed, and the only value decrypted is the answer.
//
// The 8-bit width is a demonstration choice, not a security parameter: a party
// holding the key could exhaust 256 values trivially. The point is the shape of
// the computation — a comparison performed without seeing either operand.
module private_match (
    input  wire [7:0] entered,
    input  wire [7:0] expected,
    output wire       match
);
    assign match = (entered == expected);
endmodule
