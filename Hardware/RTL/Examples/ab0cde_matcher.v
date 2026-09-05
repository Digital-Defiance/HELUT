module ab0cde_matcher(
    input [7:0] char0,
    input [7:0] char1,
    input [7:0] char2,
    input [7:0] char3,
    input [7:0] char4,
    input [7:0] char5,
    output match
);
    // Matches the exact, case-sensitive ASCII demonstration callsign "AB0CDE".
    assign match = (char0 == 8'h41) &&
                   (char1 == 8'h42) &&
                   (char2 == 8'h30) &&
                   (char3 == 8'h43) &&
                   (char4 == 8'h44) &&
                   (char5 == 8'h45);
endmodule
