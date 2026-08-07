module multiplier3x3_dut (
    clk, in_0, in_1, in_2, in_3, in_4, in_5, out_8, out_11, out_14, out_17, out_20, out_23
);

    input wire clk;
    input wire in_0;
    input wire in_1;
    input wire in_2;
    input wire in_3;
    input wire in_4;
    input wire in_5;
    output wire out_8;
    output wire out_11;
    output wire out_14;
    output wire out_17;
    output wire out_20;
    output wire out_23;

    // Internal Netlist Wires
    wire [23:0] n;

    // Primary I/O Bindings
    assign n[0] = in_0;
    assign n[1] = in_1;
    assign n[2] = in_2;
    assign n[3] = in_3;
    assign n[4] = in_4;
    assign n[5] = in_5;
    assign out_8 = n[8];
    assign out_11 = n[11];
    assign out_14 = n[14];
    assign out_17 = n[17];
    assign out_20 = n[20];
    assign out_23 = n[23];

    // Adversarially Synthesized Combinational Logic
    LUT6 #(
        .INIT(64'hAA00AA00AA00AA00)
    ) lut_0 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[6])
    );
    LUT6 #(
        .INIT(64'hAA00AA00AA00AA00)
    ) lut_1 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[7])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_2 (
        .I0(n[6]), .I1(n[7]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[8])
    );
    LUT6 #(
        .INIT(64'h66AACC0066AACC00)
    ) lut_3 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[9])
    );
    LUT6 #(
        .INIT(64'h66AACC0066AACC00)
    ) lut_4 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[10])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_5 (
        .I0(n[9]), .I1(n[10]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[11])
    );
    LUT6 #(
        .INIT(64'h1E665AAAB4CCF000)
    ) lut_6 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[12])
    );
    LUT6 #(
        .INIT(64'h1E665AAAB4CCF000)
    ) lut_7 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[13])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_8 (
        .I0(n[12]), .I1(n[13]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[14])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_9 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[15])
    );
    LUT6 #(
        .INIT(64'h54B46CCC38F00000)
    ) lut_10 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[16])
    );
    LUT6 #(
        .INIT(64'hCCCCCCCCCCCCCCCC)
    ) lut_11 (
        .I0(n[15]), .I1(n[16]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[17])
    );
    LUT6 #(
        .INIT(64'h983870F0C0000000)
    ) lut_12 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[18])
    );
    LUT6 #(
        .INIT(64'h983870F0C0000000)
    ) lut_13 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[19])
    );
    LUT6 #(
        .INIT(64'hCCCCCCCCCCCCCCCC)
    ) lut_14 (
        .I0(n[18]), .I1(n[19]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[20])
    );
    LUT6 #(
        .INIT(64'hE0C0800000000000)
    ) lut_15 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[21])
    );
    LUT6 #(
        .INIT(64'hE0C0800000000000)
    ) lut_16 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[22])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_17 (
        .I0(n[21]), .I1(n[22]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[23])
    );

endmodule
