module adder8_dut (
    clk, in_0, in_1, in_2, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, in_11, in_12, in_13, in_14, in_15, out_48, out_49, out_50, out_51, out_52, out_53, out_54, out_55, out_56
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
    input wire in_11;
    input wire in_12;
    input wire in_13;
    input wire in_14;
    input wire in_15;
    output wire out_48;
    output wire out_49;
    output wire out_50;
    output wire out_51;
    output wire out_52;
    output wire out_53;
    output wire out_54;
    output wire out_55;
    output wire out_56;

    // Internal Netlist Wires
    wire [56:0] n;

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
    assign n[11] = in_11;
    assign n[12] = in_12;
    assign n[13] = in_13;
    assign n[14] = in_14;
    assign n[15] = in_15;
    assign out_48 = n[48];
    assign out_49 = n[49];
    assign out_50 = n[50];
    assign out_51 = n[51];
    assign out_52 = n[52];
    assign out_53 = n[53];
    assign out_54 = n[54];
    assign out_55 = n[55];
    assign out_56 = n[56];

    // Adversarially Synthesized Combinational Logic
    LUT6 #(
        .INIT(64'h6666666666666666)
    ) lut_0 (
        .I0(n[0]), .I1(n[8]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[16])
    );
    LUT6 #(
        .INIT(64'h8888888888888888)
    ) lut_1 (
        .I0(n[0]), .I1(n[8]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[17])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_2 (
        .I0(n[1]), .I1(n[9]), .I2(n[17]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[18])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_3 (
        .I0(n[1]), .I1(n[9]), .I2(n[17]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[19])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_4 (
        .I0(n[2]), .I1(n[10]), .I2(n[19]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[20])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_5 (
        .I0(n[2]), .I1(n[10]), .I2(n[19]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[21])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_6 (
        .I0(n[3]), .I1(n[11]), .I2(n[21]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[22])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_7 (
        .I0(n[3]), .I1(n[11]), .I2(n[21]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[23])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_8 (
        .I0(n[4]), .I1(n[12]), .I2(n[23]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[24])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_9 (
        .I0(n[4]), .I1(n[12]), .I2(n[23]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[25])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_10 (
        .I0(n[5]), .I1(n[13]), .I2(n[25]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[26])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_11 (
        .I0(n[5]), .I1(n[13]), .I2(n[25]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[27])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_12 (
        .I0(n[6]), .I1(n[14]), .I2(n[27]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[28])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_13 (
        .I0(n[6]), .I1(n[14]), .I2(n[27]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[29])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_14 (
        .I0(n[7]), .I1(n[15]), .I2(n[29]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[30])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_15 (
        .I0(n[7]), .I1(n[15]), .I2(n[29]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[31])
    );
    LUT6 #(
        .INIT(64'h6666666666666666)
    ) lut_16 (
        .I0(n[0]), .I1(n[8]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[32])
    );
    LUT6 #(
        .INIT(64'h8888888888888888)
    ) lut_17 (
        .I0(n[0]), .I1(n[8]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[33])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_18 (
        .I0(n[1]), .I1(n[9]), .I2(n[33]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[34])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_19 (
        .I0(n[1]), .I1(n[9]), .I2(n[33]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[35])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_20 (
        .I0(n[2]), .I1(n[10]), .I2(n[35]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[36])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_21 (
        .I0(n[2]), .I1(n[10]), .I2(n[35]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[37])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_22 (
        .I0(n[3]), .I1(n[11]), .I2(n[37]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[38])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_23 (
        .I0(n[3]), .I1(n[11]), .I2(n[37]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[39])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_24 (
        .I0(n[4]), .I1(n[12]), .I2(n[39]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[40])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_25 (
        .I0(n[4]), .I1(n[12]), .I2(n[39]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[41])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_26 (
        .I0(n[5]), .I1(n[13]), .I2(n[41]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[42])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_27 (
        .I0(n[5]), .I1(n[13]), .I2(n[41]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[43])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_28 (
        .I0(n[6]), .I1(n[14]), .I2(n[43]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[44])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_29 (
        .I0(n[6]), .I1(n[14]), .I2(n[43]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[45])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_30 (
        .I0(n[7]), .I1(n[15]), .I2(n[45]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[46])
    );
    LUT6 #(
        .INIT(64'hE8E8E8E8E8E8E8E8)
    ) lut_31 (
        .I0(n[7]), .I1(n[15]), .I2(n[45]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[47])
    );
    LUT6 #(
        .INIT(64'hCCCCCCCCCCCCCCCC)
    ) lut_32 (
        .I0(n[16]), .I1(n[32]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[48])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_33 (
        .I0(n[18]), .I1(n[34]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[49])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_34 (
        .I0(n[20]), .I1(n[36]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[50])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_35 (
        .I0(n[22]), .I1(n[38]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[51])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_36 (
        .I0(n[24]), .I1(n[40]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[52])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_37 (
        .I0(n[26]), .I1(n[42]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[53])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_38 (
        .I0(n[28]), .I1(n[44]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[54])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_39 (
        .I0(n[30]), .I1(n[46]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[55])
    );
    LUT6 #(
        .INIT(64'hAAAAAAAAAAAAAAAA)
    ) lut_40 (
        .I0(n[31]), .I1(n[47]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[56])
    );

endmodule
