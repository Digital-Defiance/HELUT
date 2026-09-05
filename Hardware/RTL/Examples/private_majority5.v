// Five-voter private majority, written for the HELUT concept series (Episode 12).
//
// Five ballot bits enter; one decision bit leaves. Under encrypted evaluation,
// the evaluator learns only whether the proposal passed, not the five ballots.
//
// This demonstrates the shape of a private computation. It is not a complete
// multiparty voting protocol: the SING harness owns the key and decrypts the
// result in-process to compare it with the clear golden model.
module private_majority5 (
    input  wire [4:0] votes,
    output wire       proposal_passes
);
    wire [2:0] yes_count;

    assign yes_count = {2'b0, votes[0]} +
                       {2'b0, votes[1]} +
                       {2'b0, votes[2]} +
                       {2'b0, votes[3]} +
                       {2'b0, votes[4]};

    assign proposal_passes = (yes_count >= 3'd3);
endmodule
