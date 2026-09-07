module ripple_adder (
    clk, in_0, in_1, in_2, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, in_11, in_12, in_13, in_14, in_15, out_24, out_25, out_26, out_27, out_28, out_29, out_30, out_31, out_23
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
    output wire out_24;
    output wire out_25;
    output wire out_26;
    output wire out_27;
    output wire out_28;
    output wire out_29;
    output wire out_30;
    output wire out_31;
    output wire out_23;

    // Internal Netlist Wires
    wire [31:0] n;

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
    assign out_24 = n[24];
    assign out_25 = n[25];
    assign out_26 = n[26];
    assign out_27 = n[27];
    assign out_28 = n[28];
    assign out_29 = n[29];
    assign out_30 = n[30];
    assign out_31 = n[31];
    assign out_23 = n[23];

    // Adversarially Synthesized Combinational Logic
    LUT6 #(.INIT(64'h6666666666666666)) lut_0 (.I0(n[0]), .I1(n[8]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[24]));
    LUT6 #(.INIT(64'h8888888888888888)) lut_1 (.I0(n[0]), .I1(n[8]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[16]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_2 (.I0(n[1]), .I1(n[9]), .I2(n[16]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[25]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_3 (.I0(n[1]), .I1(n[9]), .I2(n[16]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[17]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_4 (.I0(n[2]), .I1(n[10]), .I2(n[17]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[26]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_5 (.I0(n[2]), .I1(n[10]), .I2(n[17]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[18]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_6 (.I0(n[3]), .I1(n[11]), .I2(n[18]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[27]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_7 (.I0(n[3]), .I1(n[11]), .I2(n[18]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[19]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_8 (.I0(n[4]), .I1(n[12]), .I2(n[19]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[28]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_9 (.I0(n[4]), .I1(n[12]), .I2(n[19]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[20]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_10 (.I0(n[5]), .I1(n[13]), .I2(n[20]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[29]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_11 (.I0(n[5]), .I1(n[13]), .I2(n[20]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[21]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_12 (.I0(n[6]), .I1(n[14]), .I2(n[21]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[30]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_13 (.I0(n[6]), .I1(n[14]), .I2(n[21]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[22]));
    LUT6 #(.INIT(64'h9696969696969696)) lut_14 (.I0(n[7]), .I1(n[15]), .I2(n[22]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[31]));
    LUT6 #(.INIT(64'hE8E8E8E8E8E8E8E8)) lut_15 (.I0(n[7]), .I1(n[15]), .I2(n[22]), .I3(1'b0), .I4(1'b0), .I5(1'b0), .O(n[23]));

endmodule
