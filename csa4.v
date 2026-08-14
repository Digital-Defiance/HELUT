// 4-bit carry-save + CPA (M2 CSA candidate vs ripple4).
module csa4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [3:0] c,
    output wire [3:0] s,
    output wire [4:0] carry
);
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : csa
            assign s[i] = a[i] ^ b[i] ^ c[i];
            assign carry[i+1] = (a[i] & b[i]) | (b[i] & c[i]) | (a[i] & c[i]);
        end
    endgenerate
    assign carry[0] = 1'b0;
endmodule
