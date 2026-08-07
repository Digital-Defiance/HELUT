module decision_tree(
    input [3:0] feature_a,
    input [3:0] feature_b,
    output is_high_risk
);
    // Exact, non-linear threshold logic
    assign is_high_risk = (feature_a > 4'd10) ? ((feature_b < 4'd5) ? 1'b1 : 1'b0) : 1'b0;
endmodule
