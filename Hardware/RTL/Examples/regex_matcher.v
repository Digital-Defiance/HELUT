module regex_matcher(
    input [7:0] char0,
    input [7:0] char1,
    input [7:0] char2,
    output match
);
    // Matches exact ASCII sequence "DEF"
    assign match = (char0 == 8'h44) && (char1 == 8'h45) && (char2 == 8'h46);
endmodule
