module enigma_256_step_cone_tensorlut (
    clk, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, in_11, in_12, in_13, in_14, in_15, in_16, in_17, in_18, in_19, in_20, in_21, in_22, in_23, in_24, in_25, in_26, in_27, in_28, in_29, in_30, in_31, in_32, in_33, in_34, in_35, in_36, in_37, in_38, in_39, in_40, in_41, in_42, in_43, in_44, in_45, in_46, in_47, in_48, in_49, in_50, in_51, in_52, in_53, in_54, in_55, in_56, in_57, in_58, in_59, in_60, in_61, in_62, in_63, in_64, in_65, in_66, in_67, in_68, in_69, out_134, out_135, out_136, out_137
);

    input wire clk;
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
    input wire in_66;
    input wire in_67;
    input wire in_68;
    input wire in_69;
    output wire out_134;
    output wire out_135;
    output wire out_136;
    output wire out_137;

    // Internal Netlist Wires
    wire [226:0] n;
    reg [226:0] n_reg;

    // Primary I/O Bindings
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
    assign n[66] = in_66;
    assign n[67] = in_67;
    assign n[68] = in_68;
    assign n[69] = in_69;
    assign out_134 = n[134];
    assign out_135 = n[135];
    assign out_136 = n[136];
    assign out_137 = n[137];

    // Adversarially Synthesized Combinational Logic
    LUT6 #(
        .INIT(64'hAAAA3C00AAAA3C00)
    ) lut_0 (
        .I0(n[64]), .I1(n[133]), .I2(n[128]), .I3(n[69]), .I4(n[4]), .I5(1'b0),
        .O(n[138])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_1 (
        .I0(n[69]), .I1(n[124]), .I2(n[60]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[139])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_2 (
        .I0(n[69]), .I1(n[122]), .I2(n[58]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[140])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_3 (
        .I0(n[69]), .I1(n[120]), .I2(n[56]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[141])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_4 (
        .I0(n[69]), .I1(n[118]), .I2(n[54]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[142])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_5 (
        .I0(n[69]), .I1(n[116]), .I2(n[52]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[143])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_6 (
        .I0(n[69]), .I1(n[114]), .I2(n[50]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[144])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_7 (
        .I0(n[69]), .I1(n[112]), .I2(n[48]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[145])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_8 (
        .I0(n[69]), .I1(n[110]), .I2(n[46]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[146])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_9 (
        .I0(n[69]), .I1(n[108]), .I2(n[44]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[147])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_10 (
        .I0(n[69]), .I1(n[106]), .I2(n[42]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[148])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_11 (
        .I0(n[69]), .I1(n[104]), .I2(n[40]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[149])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_12 (
        .I0(n[69]), .I1(n[102]), .I2(n[38]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[150])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_13 (
        .I0(n[69]), .I1(n[100]), .I2(n[36]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[151])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_14 (
        .I0(n[69]), .I1(n[98]), .I2(n[34]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[152])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_15 (
        .I0(n[69]), .I1(n[96]), .I2(n[32]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[153])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_16 (
        .I0(n[69]), .I1(n[94]), .I2(n[30]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[154])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_17 (
        .I0(n[69]), .I1(n[92]), .I2(n[28]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[155])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_18 (
        .I0(n[69]), .I1(n[90]), .I2(n[26]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[156])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_19 (
        .I0(n[69]), .I1(n[88]), .I2(n[24]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[157])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_20 (
        .I0(n[69]), .I1(n[86]), .I2(n[22]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[158])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_21 (
        .I0(n[69]), .I1(n[84]), .I2(n[20]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[159])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_22 (
        .I0(n[69]), .I1(n[82]), .I2(n[18]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[160])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_23 (
        .I0(n[69]), .I1(n[80]), .I2(n[16]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[161])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_24 (
        .I0(n[69]), .I1(n[78]), .I2(n[14]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[162])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_25 (
        .I0(n[69]), .I1(n[76]), .I2(n[12]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[163])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_26 (
        .I0(n[69]), .I1(n[74]), .I2(n[10]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[164])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_27 (
        .I0(n[69]), .I1(n[72]), .I2(n[8]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[165])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_28 (
        .I0(n[69]), .I1(n[70]), .I2(n[6]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[166])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_29 (
        .I0(n[69]), .I1(n[130]), .I2(n[66]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[167])
    );
    LUT6 #(
        .INIT(64'hAAAA3C00AAAA3C00)
    ) lut_30 (
        .I0(n[65]), .I1(n[133]), .I2(n[129]), .I3(n[69]), .I4(n[4]), .I5(1'b0),
        .O(n[168])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_31 (
        .I0(n[69]), .I1(n[127]), .I2(n[63]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[169])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_32 (
        .I0(n[69]), .I1(n[126]), .I2(n[62]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[170])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_33 (
        .I0(n[69]), .I1(n[125]), .I2(n[61]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[171])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_34 (
        .I0(n[69]), .I1(n[123]), .I2(n[59]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[172])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_35 (
        .I0(n[69]), .I1(n[121]), .I2(n[57]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[173])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_36 (
        .I0(n[69]), .I1(n[119]), .I2(n[55]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[174])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_37 (
        .I0(n[69]), .I1(n[117]), .I2(n[53]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[175])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_38 (
        .I0(n[69]), .I1(n[115]), .I2(n[51]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[176])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_39 (
        .I0(n[69]), .I1(n[113]), .I2(n[49]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[177])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_40 (
        .I0(n[69]), .I1(n[111]), .I2(n[47]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[178])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_41 (
        .I0(n[69]), .I1(n[109]), .I2(n[45]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[179])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_42 (
        .I0(n[69]), .I1(n[107]), .I2(n[43]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[180])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_43 (
        .I0(n[69]), .I1(n[105]), .I2(n[41]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[181])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_44 (
        .I0(n[69]), .I1(n[103]), .I2(n[39]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[182])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_45 (
        .I0(n[69]), .I1(n[101]), .I2(n[37]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[183])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_46 (
        .I0(n[69]), .I1(n[99]), .I2(n[35]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[184])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_47 (
        .I0(n[69]), .I1(n[97]), .I2(n[33]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[185])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_48 (
        .I0(n[69]), .I1(n[95]), .I2(n[31]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[186])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_49 (
        .I0(n[69]), .I1(n[93]), .I2(n[29]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[187])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_50 (
        .I0(n[69]), .I1(n[91]), .I2(n[27]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[188])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_51 (
        .I0(n[69]), .I1(n[89]), .I2(n[25]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[189])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_52 (
        .I0(n[69]), .I1(n[87]), .I2(n[23]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[190])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_53 (
        .I0(n[69]), .I1(n[85]), .I2(n[21]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[191])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_54 (
        .I0(n[69]), .I1(n[83]), .I2(n[19]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[192])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_55 (
        .I0(n[69]), .I1(n[81]), .I2(n[17]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[193])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_56 (
        .I0(n[69]), .I1(n[79]), .I2(n[15]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[194])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_57 (
        .I0(n[69]), .I1(n[77]), .I2(n[13]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[195])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_58 (
        .I0(n[69]), .I1(n[75]), .I2(n[11]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[196])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_59 (
        .I0(n[69]), .I1(n[73]), .I2(n[9]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[197])
    );
    LUT6 #(
        .INIT(64'hF088F088F088F088)
    ) lut_60 (
        .I0(n[69]), .I1(n[71]), .I2(n[7]), .I3(n[4]), .I4(1'b0), .I5(1'b0),
        .O(n[198])
    );
    LUT6 #(
        .INIT(64'hFFFF800000000000)
    ) lut_61 (
        .I0(n[199]), .I1(n[200]), .I2(n[201]), .I3(n[202]), .I4(n[5]), .I5(n[4]),
        .O(n[203])
    );
    LUT6 #(
        .INIT(64'h8000800080008000)
    ) lut_62 (
        .I0(n[204]), .I1(n[205]), .I2(n[206]), .I3(n[207]), .I4(1'b0), .I5(1'b0),
        .O(n[200])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_63 (
        .I0(n[47]), .I1(n[46]), .I2(n[45]), .I3(n[44]), .I4(1'b0), .I5(1'b0),
        .O(n[204])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_64 (
        .I0(n[51]), .I1(n[50]), .I2(n[49]), .I3(n[48]), .I4(1'b0), .I5(1'b0),
        .O(n[205])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_65 (
        .I0(n[43]), .I1(n[42]), .I2(n[41]), .I3(n[40]), .I4(1'b0), .I5(1'b0),
        .O(n[206])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_66 (
        .I0(n[39]), .I1(n[38]), .I2(n[37]), .I3(n[36]), .I4(1'b0), .I5(1'b0),
        .O(n[207])
    );
    LUT6 #(
        .INIT(64'h8000800080008000)
    ) lut_67 (
        .I0(n[208]), .I1(n[209]), .I2(n[210]), .I3(n[211]), .I4(1'b0), .I5(1'b0),
        .O(n[201])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_68 (
        .I0(n[67]), .I1(n[66]), .I2(n[65]), .I3(n[64]), .I4(1'b0), .I5(1'b0),
        .O(n[208])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_69 (
        .I0(n[63]), .I1(n[62]), .I2(n[61]), .I3(n[60]), .I4(1'b0), .I5(1'b0),
        .O(n[209])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_70 (
        .I0(n[55]), .I1(n[54]), .I2(n[53]), .I3(n[52]), .I4(1'b0), .I5(1'b0),
        .O(n[210])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_71 (
        .I0(n[59]), .I1(n[58]), .I2(n[57]), .I3(n[56]), .I4(1'b0), .I5(1'b0),
        .O(n[211])
    );
    LUT6 #(
        .INIT(64'h8000800080008000)
    ) lut_72 (
        .I0(n[212]), .I1(n[213]), .I2(n[214]), .I3(n[215]), .I4(1'b0), .I5(1'b0),
        .O(n[202])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_73 (
        .I0(n[19]), .I1(n[18]), .I2(n[17]), .I3(n[16]), .I4(1'b0), .I5(1'b0),
        .O(n[212])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_74 (
        .I0(n[15]), .I1(n[14]), .I2(n[13]), .I3(n[12]), .I4(1'b0), .I5(1'b0),
        .O(n[213])
    );
    LUT6 #(
        .INIT(64'h0101010101010101)
    ) lut_75 (
        .I0(n[7]), .I1(n[6]), .I2(n[68]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[214])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_76 (
        .I0(n[11]), .I1(n[10]), .I2(n[9]), .I3(n[8]), .I4(1'b0), .I5(1'b0),
        .O(n[215])
    );
    LUT6 #(
        .INIT(64'h8000800080008000)
    ) lut_77 (
        .I0(n[216]), .I1(n[217]), .I2(n[218]), .I3(n[219]), .I4(1'b0), .I5(1'b0),
        .O(n[199])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_78 (
        .I0(n[31]), .I1(n[30]), .I2(n[29]), .I3(n[28]), .I4(1'b0), .I5(1'b0),
        .O(n[216])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_79 (
        .I0(n[35]), .I1(n[34]), .I2(n[33]), .I3(n[32]), .I4(1'b0), .I5(1'b0),
        .O(n[217])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_80 (
        .I0(n[27]), .I1(n[26]), .I2(n[25]), .I3(n[24]), .I4(1'b0), .I5(1'b0),
        .O(n[218])
    );
    LUT6 #(
        .INIT(64'h0001000100010001)
    ) lut_81 (
        .I0(n[23]), .I1(n[22]), .I2(n[21]), .I3(n[20]), .I4(1'b0), .I5(1'b0),
        .O(n[219])
    );
    LUT6 #(
        .INIT(64'hEEEEEEEEEEEEEEEE)
    ) lut_82 (
        .I0(n[69]), .I1(n[4]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[220])
    );
    LUT6 #(
        .INIT(64'hAAAA3C00AAAA3C00)
    ) lut_83 (
        .I0(n[68]), .I1(n[133]), .I2(n[132]), .I3(n[69]), .I4(n[4]), .I5(1'b0),
        .O(n[221])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_84 (
        .I0(n[117]), .I1(n[124]), .I2(n[131]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[137])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_85 (
        .I0(n[101]), .I1(n[108]), .I2(n[115]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[136])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_86 (
        .I0(n[85]), .I1(n[92]), .I2(n[99]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[135])
    );
    LUT6 #(
        .INIT(64'h7878787878787878)
    ) lut_87 (
        .I0(n[77]), .I1(n[70]), .I2(n[82]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[134])
    );
    LUT6 #(
        .INIT(64'hAAAA3C00AAAA3C00)
    ) lut_88 (
        .I0(n[67]), .I1(n[131]), .I2(n[133]), .I3(n[69]), .I4(n[4]), .I5(1'b0),
        .O(n[222])
    );

    // Sequential State Updates
    always @(posedge clk) begin
        n_reg[70] <= (n[3] ? 1'b0 : (n[220] ? n[203] : n_reg[70]));
        n_reg[71] <= (n[3] ? 1'b0 : (n[220] ? n[166] : n_reg[71]));
        n_reg[72] <= (n[3] ? 1'b0 : (n[220] ? n[198] : n_reg[72]));
        n_reg[73] <= (n[3] ? 1'b0 : (n[220] ? n[165] : n_reg[73]));
        n_reg[74] <= (n[3] ? 1'b0 : (n[220] ? n[197] : n_reg[74]));
        n_reg[75] <= (n[3] ? 1'b0 : (n[220] ? n[164] : n_reg[75]));
        n_reg[76] <= (n[3] ? 1'b0 : (n[220] ? n[196] : n_reg[76]));
        n_reg[77] <= (n[3] ? 1'b0 : (n[220] ? n[163] : n_reg[77]));
        n_reg[78] <= (n[3] ? 1'b0 : (n[220] ? n[195] : n_reg[78]));
        n_reg[79] <= (n[3] ? 1'b0 : (n[220] ? n[162] : n_reg[79]));
        n_reg[80] <= (n[3] ? 1'b0 : (n[220] ? n[194] : n_reg[80]));
        n_reg[81] <= (n[3] ? 1'b0 : (n[220] ? n[161] : n_reg[81]));
        n_reg[82] <= (n[3] ? 1'b0 : (n[220] ? n[193] : n_reg[82]));
        n_reg[83] <= (n[3] ? 1'b0 : (n[220] ? n[160] : n_reg[83]));
        n_reg[84] <= (n[3] ? 1'b0 : (n[220] ? n[192] : n_reg[84]));
        n_reg[85] <= (n[3] ? 1'b0 : (n[220] ? n[159] : n_reg[85]));
        n_reg[86] <= (n[3] ? 1'b0 : (n[220] ? n[191] : n_reg[86]));
        n_reg[87] <= (n[3] ? 1'b0 : (n[220] ? n[158] : n_reg[87]));
        n_reg[88] <= (n[3] ? 1'b0 : (n[220] ? n[190] : n_reg[88]));
        n_reg[89] <= (n[3] ? 1'b0 : (n[220] ? n[157] : n_reg[89]));
        n_reg[90] <= (n[3] ? 1'b0 : (n[220] ? n[189] : n_reg[90]));
        n_reg[91] <= (n[3] ? 1'b0 : (n[220] ? n[156] : n_reg[91]));
        n_reg[92] <= (n[3] ? 1'b0 : (n[220] ? n[188] : n_reg[92]));
        n_reg[93] <= (n[3] ? 1'b0 : (n[220] ? n[155] : n_reg[93]));
        n_reg[94] <= (n[3] ? 1'b0 : (n[220] ? n[187] : n_reg[94]));
        n_reg[95] <= (n[3] ? 1'b0 : (n[220] ? n[154] : n_reg[95]));
        n_reg[96] <= (n[3] ? 1'b0 : (n[220] ? n[186] : n_reg[96]));
        n_reg[97] <= (n[3] ? 1'b0 : (n[220] ? n[153] : n_reg[97]));
        n_reg[98] <= (n[3] ? 1'b0 : (n[220] ? n[185] : n_reg[98]));
        n_reg[99] <= (n[3] ? 1'b0 : (n[220] ? n[152] : n_reg[99]));
        n_reg[100] <= (n[3] ? 1'b0 : (n[220] ? n[184] : n_reg[100]));
        n_reg[101] <= (n[3] ? 1'b0 : (n[220] ? n[151] : n_reg[101]));
        n_reg[102] <= (n[3] ? 1'b0 : (n[220] ? n[183] : n_reg[102]));
        n_reg[103] <= (n[3] ? 1'b0 : (n[220] ? n[150] : n_reg[103]));
        n_reg[104] <= (n[3] ? 1'b0 : (n[220] ? n[182] : n_reg[104]));
        n_reg[105] <= (n[3] ? 1'b0 : (n[220] ? n[149] : n_reg[105]));
        n_reg[106] <= (n[3] ? 1'b0 : (n[220] ? n[181] : n_reg[106]));
        n_reg[107] <= (n[3] ? 1'b0 : (n[220] ? n[148] : n_reg[107]));
        n_reg[108] <= (n[3] ? 1'b0 : (n[220] ? n[180] : n_reg[108]));
        n_reg[109] <= (n[3] ? 1'b0 : (n[220] ? n[147] : n_reg[109]));
        n_reg[110] <= (n[3] ? 1'b0 : (n[220] ? n[179] : n_reg[110]));
        n_reg[111] <= (n[3] ? 1'b0 : (n[220] ? n[146] : n_reg[111]));
        n_reg[112] <= (n[3] ? 1'b0 : (n[220] ? n[178] : n_reg[112]));
        n_reg[113] <= (n[3] ? 1'b0 : (n[220] ? n[145] : n_reg[113]));
        n_reg[114] <= (n[3] ? 1'b0 : (n[220] ? n[177] : n_reg[114]));
        n_reg[115] <= (n[3] ? 1'b0 : (n[220] ? n[144] : n_reg[115]));
        n_reg[116] <= (n[3] ? 1'b0 : (n[220] ? n[176] : n_reg[116]));
        n_reg[117] <= (n[3] ? 1'b0 : (n[220] ? n[143] : n_reg[117]));
        n_reg[118] <= (n[3] ? 1'b0 : (n[220] ? n[175] : n_reg[118]));
        n_reg[119] <= (n[3] ? 1'b0 : (n[220] ? n[142] : n_reg[119]));
        n_reg[120] <= (n[3] ? 1'b0 : (n[220] ? n[174] : n_reg[120]));
        n_reg[121] <= (n[3] ? 1'b0 : (n[220] ? n[141] : n_reg[121]));
        n_reg[122] <= (n[3] ? 1'b0 : (n[220] ? n[173] : n_reg[122]));
        n_reg[123] <= (n[3] ? 1'b0 : (n[220] ? n[140] : n_reg[123]));
        n_reg[124] <= (n[3] ? 1'b0 : (n[220] ? n[172] : n_reg[124]));
        n_reg[125] <= (n[3] ? 1'b0 : (n[220] ? n[139] : n_reg[125]));
        n_reg[126] <= (n[3] ? 1'b0 : (n[220] ? n[171] : n_reg[126]));
        n_reg[127] <= (n[3] ? 1'b0 : (n[220] ? n[170] : n_reg[127]));
        n_reg[128] <= (n[3] ? 1'b0 : (n[220] ? n[169] : n_reg[128]));
        n_reg[129] <= (n[3] ? 1'b0 : (n[220] ? n[138] : n_reg[129]));
        n_reg[130] <= (n[3] ? 1'b0 : (n[220] ? n[168] : n_reg[130]));
        n_reg[131] <= (n[3] ? 1'b0 : (n[220] ? n[167] : n_reg[131]));
        n_reg[132] <= (n[3] ? 1'b0 : (n[220] ? n[222] : n_reg[132]));
        n_reg[133] <= (n[3] ? 1'b0 : (n[220] ? n[221] : n_reg[133]));
    end

    // DFF to Wire bindings
    assign n[70] = n_reg[70];
    assign n[71] = n_reg[71];
    assign n[72] = n_reg[72];
    assign n[73] = n_reg[73];
    assign n[74] = n_reg[74];
    assign n[75] = n_reg[75];
    assign n[76] = n_reg[76];
    assign n[77] = n_reg[77];
    assign n[78] = n_reg[78];
    assign n[79] = n_reg[79];
    assign n[80] = n_reg[80];
    assign n[81] = n_reg[81];
    assign n[82] = n_reg[82];
    assign n[83] = n_reg[83];
    assign n[84] = n_reg[84];
    assign n[85] = n_reg[85];
    assign n[86] = n_reg[86];
    assign n[87] = n_reg[87];
    assign n[88] = n_reg[88];
    assign n[89] = n_reg[89];
    assign n[90] = n_reg[90];
    assign n[91] = n_reg[91];
    assign n[92] = n_reg[92];
    assign n[93] = n_reg[93];
    assign n[94] = n_reg[94];
    assign n[95] = n_reg[95];
    assign n[96] = n_reg[96];
    assign n[97] = n_reg[97];
    assign n[98] = n_reg[98];
    assign n[99] = n_reg[99];
    assign n[100] = n_reg[100];
    assign n[101] = n_reg[101];
    assign n[102] = n_reg[102];
    assign n[103] = n_reg[103];
    assign n[104] = n_reg[104];
    assign n[105] = n_reg[105];
    assign n[106] = n_reg[106];
    assign n[107] = n_reg[107];
    assign n[108] = n_reg[108];
    assign n[109] = n_reg[109];
    assign n[110] = n_reg[110];
    assign n[111] = n_reg[111];
    assign n[112] = n_reg[112];
    assign n[113] = n_reg[113];
    assign n[114] = n_reg[114];
    assign n[115] = n_reg[115];
    assign n[116] = n_reg[116];
    assign n[117] = n_reg[117];
    assign n[118] = n_reg[118];
    assign n[119] = n_reg[119];
    assign n[120] = n_reg[120];
    assign n[121] = n_reg[121];
    assign n[122] = n_reg[122];
    assign n[123] = n_reg[123];
    assign n[124] = n_reg[124];
    assign n[125] = n_reg[125];
    assign n[126] = n_reg[126];
    assign n[127] = n_reg[127];
    assign n[128] = n_reg[128];
    assign n[129] = n_reg[129];
    assign n[130] = n_reg[130];
    assign n[131] = n_reg[131];
    assign n[132] = n_reg[132];
    assign n[133] = n_reg[133];
endmodule
