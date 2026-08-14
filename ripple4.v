// 4-bit ripple-carry adder (M2 baseline bottleneck).
module ripple4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] s,
    output wire       cout
);
    wire [4:0] c;
    assign c[0] = 1'b0;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : fa
            assign s[i] = a[i] ^ b[i] ^ c[i];
            assign c[i+1] = (a[i] & b[i]) | (c[i] & (a[i] ^ b[i]));
        end
    endgenerate
    assign cout = c[4];
endmodule
