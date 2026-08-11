module enigma_256_tensorlut_baseline (
    clk, in_2, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, in_11, in_12, in_13, in_14, in_15, in_16, in_17, in_18, in_19, in_20, in_21, in_22, in_23, in_24, in_25, in_26, in_27, in_28, in_29, in_30, in_31, in_32, in_33, in_34, in_35, in_36, in_37, in_38, in_39, in_40, in_41, in_42, in_43, in_44, in_45, in_46, in_47, in_48, in_49, in_50, in_51, in_52, in_53, in_54, in_55, in_56, in_57, in_58, in_59, in_60, in_61, in_62, in_63, in_64, in_65, out_66, out_67, out_68, out_69
);

    input wire clk;
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
    input wire in_16;
    input wire in_17;
    input wire in_18;
    input wire in_19;
    input wire in_20;
    input wire in_21;
    input wire in_22;
    input wire in_23;
    input wire in_24;
    input wire in_25;
    input wire in_26;
    input wire in_27;
    input wire in_28;
    input wire in_29;
    input wire in_30;
    input wire in_31;
    input wire in_32;
    input wire in_33;
    input wire in_34;
    input wire in_35;
    input wire in_36;
    input wire in_37;
    input wire in_38;
    input wire in_39;
    input wire in_40;
    input wire in_41;
    input wire in_42;
    input wire in_43;
    input wire in_44;
    input wire in_45;
    input wire in_46;
    input wire in_47;
    input wire in_48;
    input wire in_49;
    input wire in_50;
    input wire in_51;
    input wire in_52;
    input wire in_53;
    input wire in_54;
    input wire in_55;
    input wire in_56;
    input wire in_57;
    input wire in_58;
    input wire in_59;
    input wire in_60;
    input wire in_61;
    input wire in_62;
    input wire in_63;
    input wire in_64;
    input wire in_65;
    output wire out_66;
    output wire out_67;
    output wire out_68;
    output wire out_69;

    // Internal Netlist Wires
    wire [73:0] n;

    // Primary I/O Bindings
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
    assign n[16] = in_16;
    assign n[17] = in_17;
    assign n[18] = in_18;
    assign n[19] = in_19;
    assign n[20] = in_20;
    assign n[21] = in_21;
    assign n[22] = in_22;
    assign n[23] = in_23;
    assign n[24] = in_24;
    assign n[25] = in_25;
    assign n[26] = in_26;
    assign n[27] = in_27;
    assign n[28] = in_28;
    assign n[29] = in_29;
    assign n[30] = in_30;
    assign n[31] = in_31;
    assign n[32] = in_32;
    assign n[33] = in_33;
    assign n[34] = in_34;
    assign n[35] = in_35;
    assign n[36] = in_36;
    assign n[37] = in_37;
    assign n[38] = in_38;
    assign n[39] = in_39;
    assign n[40] = in_40;
    assign n[41] = in_41;
    assign n[42] = in_42;
    assign n[43] = in_43;
    assign n[44] = in_44;
    assign n[45] = in_45;
    assign n[46] = in_46;
    assign n[47] = in_47;
    assign n[48] = in_48;
    assign n[49] = in_49;
    assign n[50] = in_50;
    assign n[51] = in_51;
    assign n[52] = in_52;
    assign n[53] = in_53;
    assign n[54] = in_54;
    assign n[55] = in_55;
    assign n[56] = in_56;
    assign n[57] = in_57;
    assign n[58] = in_58;
    assign n[59] = in_59;
    assign n[60] = in_60;
    assign n[61] = in_61;
    assign n[62] = in_62;
    assign n[63] = in_63;
    assign n[64] = in_64;
    assign n[65] = in_65;
    assign out_66 = n[66];
    assign out_67 = n[67];
    assign out_68 = n[68];
    assign out_69 = n[69];

    // Adversarially Synthesized Combinational Logic
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_0 (
        .I0(n[70]), .I1(n[71]), .I2(n[72]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[69])
    );
    LUT6 #(
        .INIT(64'h807F7F7F7F808080)
    ) lut_1 (
        .I0(n[29]), .I1(n[2]), .I2(n[15]), .I3(n[7]), .I4(n[43]), .I5(n[64]),
        .O(n[70])
    );
    LUT6 #(
        .INIT(64'h807F7F7F7F808080)
    ) lut_2 (
        .I0(n[35]), .I1(n[3]), .I2(n[20]), .I3(n[11]), .I4(n[46]), .I5(n[60]),
        .O(n[71])
    );
    LUT6 #(
        .INIT(64'h807F7F7F7F808080)
    ) lut_3 (
        .I0(n[41]), .I1(n[5]), .I2(n[26]), .I3(n[16]), .I4(n[53]), .I5(n[62]),
        .O(n[72])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_4 (
        .I0(n[70]), .I1(n[72]), .I2(n[73]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[68])
    );
    LUT6 #(
        .INIT(64'h807F7F7F7F808080)
    ) lut_5 (
        .I0(n[38]), .I1(n[4]), .I2(n[23]), .I3(n[13]), .I4(n[50]), .I5(n[57]),
        .O(n[73])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_6 (
        .I0(n[72]), .I1(n[73]), .I2(n[71]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[67])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_7 (
        .I0(n[71]), .I1(n[73]), .I2(n[70]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[66])
    );

endmodule
