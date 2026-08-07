module mux8_dut (
    clk, in_0, in_1, in_2, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, out_25
);

    input wire clk;
    input wire in_0;
    input wire in_1;
    input wire in_2;
    input wire in_3;
    input wire in_4;
    input wire in_5;
    input wire in_6;
    input wire in_7;
    input wire in_8;
    input wire in_9;
    input wire in_10;
    output wire out_25;

    // Internal Netlist Wires
    wire [25:0] n;

    // Primary I/O Bindings
    assign n[0] = in_0;
    assign n[1] = in_1;
    assign n[2] = in_2;
    assign n[3] = in_3;
    assign n[4] = in_4;
    assign n[5] = in_5;
    assign n[6] = in_6;
    assign n[7] = in_7;
    assign n[8] = in_8;
    assign n[9] = in_9;
    assign n[10] = in_10;
    assign out_25 = n[25];

    // Adversarially Synthesized Combinational Logic
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_0 (
        .I0(n[0]), .I1(n[1]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[11])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_1 (
        .I0(n[2]), .I1(n[3]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[12])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_2 (
        .I0(n[4]), .I1(n[5]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[13])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_3 (
        .I0(n[6]), .I1(n[7]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[14])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_4 (
        .I0(n[11]), .I1(n[12]), .I2(n[9]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[15])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_5 (
        .I0(n[13]), .I1(n[14]), .I2(n[9]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[16])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_6 (
        .I0(n[15]), .I1(n[16]), .I2(n[10]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[17])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_7 (
        .I0(n[0]), .I1(n[1]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[18])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_8 (
        .I0(n[2]), .I1(n[3]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[19])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_9 (
        .I0(n[4]), .I1(n[5]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[20])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_10 (
        .I0(n[6]), .I1(n[7]), .I2(n[8]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[21])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_11 (
        .I0(n[18]), .I1(n[19]), .I2(n[9]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[22])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_12 (
        .I0(n[20]), .I1(n[21]), .I2(n[9]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[23])
    );
    LUT6 #(
        .INIT(64'hCACACACACACACACA)
    ) lut_13 (
        .I0(n[22]), .I1(n[23]), .I2(n[10]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[24])
    );
    LUT6 #(
        .INIT(64'h8888888888888888)
    ) lut_14 (
        .I0(n[17]), .I1(n[24]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[25])
    );

endmodule
