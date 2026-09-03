// Auto-generated E256 TensorLUT derivative; do not hand-edit.
// Compatibility: E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4
// Receipt SHA-256: 5c5bc931a145048037ec420b2c0c47ff310570e963bd45b8262f18a1640f0027
// Source netlist SHA-256: b6e027e8b3d090496444c1814c45d37250533224a4bd9c5537faf4a7024a2eb3
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
    wire [127:0] n;

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
        .INIT(64'hCFFCFCCF30022231)
    ) lut_0 (
        .I0(n[47]), .I1(n[70]), .I2(n[21]), .I3(n[71]), .I4(n[72]), .I5(n[73]),
        .O(n[74])
    );
    LUT6 #(
        .INIT(64'h8787878787878787)
    ) lut_1 (
        .I0(n[24]), .I1(n[21]), .I2(n[25]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[72])
    );
    LUT6 #(
        .INIT(64'h470F1DA51DA5470F)
    ) lut_2 (
        .I0(n[25]), .I1(n[8]), .I2(n[24]), .I3(n[21]), .I4(n[31]), .I5(n[14]),
        .O(n[70])
    );
    LUT6 #(
        .INIT(64'h1DACA28AD8935775)
    ) lut_3 (
        .I0(n[8]), .I1(n[24]), .I2(n[21]), .I3(n[25]), .I4(n[14]), .I5(n[31]),
        .O(n[73])
    );
    LUT6 #(
        .INIT(64'h9999999999999999)
    ) lut_4 (
        .I0(n[8]), .I1(n[14]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[71])
    );
    LUT6 #(
        .INIT(64'hAAFA3C035505C3FC)
    ) lut_5 (
        .I0(n[72]), .I1(n[47]), .I2(n[73]), .I3(n[70]), .I4(n[71]), .I5(n[75]),
        .O(n[76])
    );
    LUT6 #(
        .INIT(64'h63F09C0F00000000)
    ) lut_6 (
        .I0(n[24]), .I1(n[25]), .I2(n[21]), .I3(n[14]), .I4(n[47]), .I5(n[8]),
        .O(n[75])
    );
    LUT6 #(
        .INIT(64'h0440FBBF0440FBBF)
    ) lut_7 (
        .I0(n[13]), .I1(n[55]), .I2(n[38]), .I3(n[34]), .I4(n[3]), .I5(1'b0),
        .O(n[77])
    );
    LUT6 #(
        .INIT(64'h90AC6CA06F53935F)
    ) lut_8 (
        .I0(n[13]), .I1(n[38]), .I2(n[3]), .I3(n[34]), .I4(n[55]), .I5(n[15]),
        .O(n[78])
    );
    LUT6 #(
        .INIT(64'h529BED53E52C9C88)
    ) lut_9 (
        .I0(n[55]), .I1(n[38]), .I2(n[3]), .I3(n[15]), .I4(n[13]), .I5(n[34]),
        .O(n[79])
    );
    LUT6 #(
        .INIT(64'h6996699669966996)
    ) lut_10 (
        .I0(n[80]), .I1(n[81]), .I2(n[29]), .I3(n[63]), .I4(1'b0), .I5(1'b0),
        .O(n[82])
    );
    LUT6 #(
        .INIT(64'h82287DD782287DD7)
    ) lut_11 (
        .I0(n[22]), .I1(n[46]), .I2(n[61]), .I3(n[20]), .I4(n[83]), .I5(1'b0),
        .O(n[80])
    );
    LUT6 #(
        .INIT(64'h7FD5D57F802A2A80)
    ) lut_12 (
        .I0(n[49]), .I1(n[42]), .I2(n[22]), .I3(n[46]), .I4(n[20]), .I5(n[36]),
        .O(n[83])
    );
    LUT6 #(
        .INIT(64'hA2B0B0A2F8EAEAF8)
    ) lut_13 (
        .I0(n[42]), .I1(n[49]), .I2(n[22]), .I3(n[46]), .I4(n[20]), .I5(n[61]),
        .O(n[81])
    );
    LUT6 #(
        .INIT(64'h4FFBB4FFF78FFF78)
    ) lut_14 (
        .I0(n[46]), .I1(n[42]), .I2(n[80]), .I3(n[61]), .I4(n[49]), .I5(n[20]),
        .O(n[84])
    );
    LUT6 #(
        .INIT(64'h20B0A0C0DF4F5F3F)
    ) lut_15 (
        .I0(n[4]), .I1(n[27]), .I2(n[10]), .I3(n[6]), .I4(n[35]), .I5(n[57]),
        .O(n[85])
    );
    LUT6 #(
        .INIT(64'h905FACC35999305F)
    ) lut_16 (
        .I0(n[6]), .I1(n[57]), .I2(n[10]), .I3(n[27]), .I4(n[4]), .I5(n[35]),
        .O(n[86])
    );
    LUT6 #(
        .INIT(64'h7888877787777888)
    ) lut_17 (
        .I0(n[87]), .I1(n[88]), .I2(n[89]), .I3(n[30]), .I4(n[90]), .I5(n[91]),
        .O(n[66])
    );
    LUT6 #(
        .INIT(64'hACFB0F0407FEF840)
    ) lut_18 (
        .I0(n[91]), .I1(n[89]), .I2(n[65]), .I3(n[30]), .I4(n[32]), .I5(n[54]),
        .O(n[87])
    );
    LUT6 #(
        .INIT(64'h4182852AFC3F90FF)
    ) lut_19 (
        .I0(n[65]), .I1(n[32]), .I2(n[54]), .I3(n[43]), .I4(n[30]), .I5(n[33]),
        .O(n[91])
    );
    LUT6 #(
        .INIT(64'h19A5C30F46FA3CF0)
    ) lut_20 (
        .I0(n[30]), .I1(n[65]), .I2(n[54]), .I3(n[33]), .I4(n[32]), .I5(n[43]),
        .O(n[88])
    );
    LUT6 #(
        .INIT(64'hFCB703480348FCB7)
    ) lut_21 (
        .I0(n[92]), .I1(n[93]), .I2(n[94]), .I3(n[95]), .I4(n[96]), .I5(n[97]),
        .O(n[69])
    );
    LUT6 #(
        .INIT(64'h40BF40BF40BF40BF)
    ) lut_22 (
        .I0(n[98]), .I1(n[99]), .I2(n[39]), .I3(n[100]), .I4(1'b0), .I5(1'b0),
        .O(n[93])
    );
    LUT6 #(
        .INIT(64'h807F807F807F807F)
    ) lut_23 (
        .I0(n[39]), .I1(n[16]), .I2(n[5]), .I3(n[58]), .I4(1'b0), .I5(1'b0),
        .O(n[100])
    );
    LUT6 #(
        .INIT(64'h8787878787878787)
    ) lut_24 (
        .I0(n[5]), .I1(n[26]), .I2(n[16]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[98])
    );
    LUT6 #(
        .INIT(64'h01400EB001400EB0)
    ) lut_25 (
        .I0(n[94]), .I1(n[98]), .I2(n[101]), .I3(n[102]), .I4(n[99]), .I5(1'b0),
        .O(n[95])
    );
    LUT6 #(
        .INIT(64'h6666666666666666)
    ) lut_26 (
        .I0(n[103]), .I1(n[104]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[101])
    );
    LUT6 #(
        .INIT(64'h18C0000018C00000)
    ) lut_27 (
        .I0(n[26]), .I1(n[58]), .I2(n[16]), .I3(n[5]), .I4(n[39]), .I5(1'b0),
        .O(n[103])
    );
    LUT6 #(
        .INIT(64'hC355C355C355C355)
    ) lut_28 (
        .I0(n[5]), .I1(n[9]), .I2(n[26]), .I3(n[51]), .I4(1'b0), .I5(1'b0),
        .O(n[104])
    );
    LUT6 #(
        .INIT(64'h10CF10CF10CF10CF)
    ) lut_29 (
        .I0(n[26]), .I1(n[100]), .I2(n[51]), .I3(n[39]), .I4(1'b0), .I5(1'b0),
        .O(n[102])
    );
    LUT6 #(
        .INIT(64'hBE41BE41BE41BE41)
    ) lut_30 (
        .I0(n[98]), .I1(n[103]), .I2(n[104]), .I3(n[105]), .I4(1'b0), .I5(1'b0),
        .O(n[94])
    );
    LUT6 #(
        .INIT(64'h9669966996699669)
    ) lut_31 (
        .I0(n[39]), .I1(n[5]), .I2(n[9]), .I3(n[26]), .I4(1'b0), .I5(1'b0),
        .O(n[105])
    );
    LUT6 #(
        .INIT(64'h4141414141414141)
    ) lut_32 (
        .I0(n[51]), .I1(n[102]), .I2(n[101]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[92])
    );
    LUT6 #(
        .INIT(64'hF807316007F8CBCF)
    ) lut_33 (
        .I0(n[106]), .I1(n[107]), .I2(n[108]), .I3(n[109]), .I4(n[110]), .I5(n[111]),
        .O(n[96])
    );
    LUT6 #(
        .INIT(64'h4B4B4B4B4B4B4B4B)
    ) lut_34 (
        .I0(n[109]), .I1(n[59]), .I2(n[62]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[106])
    );
    LUT6 #(
        .INIT(64'h2A80D57F2A80D57F)
    ) lut_35 (
        .I0(n[59]), .I1(n[60]), .I2(n[62]), .I3(n[37]), .I4(n[28]), .I5(1'b0),
        .O(n[109])
    );
    LUT6 #(
        .INIT(64'h01FE01FE01FE01FE)
    ) lut_36 (
        .I0(n[108]), .I1(n[109]), .I2(n[112]), .I3(n[113]), .I4(1'b0), .I5(1'b0),
        .O(n[110])
    );
    LUT6 #(
        .INIT(64'h8787878787878787)
    ) lut_37 (
        .I0(n[60]), .I1(n[62]), .I2(n[37]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[108])
    );
    LUT6 #(
        .INIT(64'h8F708F708F708F70)
    ) lut_38 (
        .I0(n[59]), .I1(n[56]), .I2(n[60]), .I3(n[64]), .I4(1'b0), .I5(1'b0),
        .O(n[113])
    );
    LUT6 #(
        .INIT(64'h82A0AA0075DF5D7F)
    ) lut_39 (
        .I0(n[59]), .I1(n[60]), .I2(n[37]), .I3(n[62]), .I4(n[64]), .I5(n[56]),
        .O(n[112])
    );
    LUT6 #(
        .INIT(64'h40BF40BF40BF40BF)
    ) lut_40 (
        .I0(n[108]), .I1(n[113]), .I2(n[111]), .I3(n[114]), .I4(1'b0), .I5(1'b0),
        .O(n[107])
    );
    LUT6 #(
        .INIT(64'hC99C5FA0C99C5FA0)
    ) lut_41 (
        .I0(n[62]), .I1(n[37]), .I2(n[59]), .I3(n[60]), .I4(n[28]), .I5(1'b0),
        .O(n[111])
    );
    LUT6 #(
        .INIT(64'h2580CF3F2580CF3F)
    ) lut_42 (
        .I0(n[28]), .I1(n[60]), .I2(n[62]), .I3(n[37]), .I4(n[59]), .I5(1'b0),
        .O(n[114])
    );
    LUT6 #(
        .INIT(64'h28D7D728D72828D7)
    ) lut_43 (
        .I0(n[115]), .I1(n[116]), .I2(n[112]), .I3(n[117]), .I4(n[12]), .I5(n[48]),
        .O(n[97])
    );
    LUT6 #(
        .INIT(64'hF3032733F3032733)
    ) lut_44 (
        .I0(n[109]), .I1(n[114]), .I2(n[113]), .I3(n[111]), .I4(n[108]), .I5(1'b0),
        .O(n[115])
    );
    LUT6 #(
        .INIT(64'hBF4080BF40207F7F)
    ) lut_45 (
        .I0(n[60]), .I1(n[37]), .I2(n[113]), .I3(n[59]), .I4(n[62]), .I5(n[28]),
        .O(n[116])
    );
    LUT6 #(
        .INIT(64'h827D827D827D827D)
    ) lut_46 (
        .I0(n[51]), .I1(n[103]), .I2(n[104]), .I3(n[98]), .I4(1'b0), .I5(1'b0),
        .O(n[117])
    );
    LUT6 #(
        .INIT(64'hAC5FFFFC53AFFFF3)
    ) lut_47 (
        .I0(n[3]), .I1(n[13]), .I2(n[55]), .I3(n[77]), .I4(n[52]), .I5(n[38]),
        .O(n[118])
    );
    LUT6 #(
        .INIT(64'h40BF01FEFBFBEFEF)
    ) lut_48 (
        .I0(n[10]), .I1(n[19]), .I2(n[35]), .I3(n[27]), .I4(n[85]), .I5(n[4]),
        .O(n[119])
    );
    LUT6 #(
        .INIT(64'h9669699696696996)
    ) lut_49 (
        .I0(n[119]), .I1(n[6]), .I2(n[82]), .I3(n[84]), .I4(n[120]), .I5(1'b0),
        .O(n[68])
    );
    LUT6 #(
        .INIT(64'h8BFFDEF017FFBD0F)
    ) lut_50 (
        .I0(n[27]), .I1(n[6]), .I2(n[4]), .I3(n[10]), .I4(n[19]), .I5(n[35]),
        .O(n[121])
    );
    LUT6 #(
        .INIT(64'h9696969696969696)
    ) lut_51 (
        .I0(n[121]), .I1(n[85]), .I2(n[86]), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[120])
    );
    LUT6 #(
        .INIT(64'h023FE10020800C40)
    ) lut_52 (
        .I0(n[65]), .I1(n[30]), .I2(n[32]), .I3(n[54]), .I4(n[33]), .I5(n[43]),
        .O(n[122])
    );
    LUT6 #(
        .INIT(64'h6666666666666666)
    ) lut_53 (
        .I0(n[122]), .I1(n[53]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[89])
    );
    LUT6 #(
        .INIT(64'hBB0FC377443CF088)
    ) lut_54 (
        .I0(n[23]), .I1(n[50]), .I2(n[7]), .I3(n[17]), .I4(n[18]), .I5(n[41]),
        .O(n[123])
    );
    LUT6 #(
        .INIT(64'h20EFEF2020EFEF20)
    ) lut_55 (
        .I0(n[26]), .I1(n[100]), .I2(n[51]), .I3(n[5]), .I4(n[9]), .I5(1'b0),
        .O(n[99])
    );
    LUT6 #(
        .INIT(64'h7887877878878778)
    ) lut_56 (
        .I0(n[8]), .I1(n[74]), .I2(n[2]), .I3(n[44]), .I4(n[76]), .I5(1'b0),
        .O(n[124])
    );
    LUT6 #(
        .INIT(64'hC63C5AE4C9CCCCD8)
    ) lut_57 (
        .I0(n[77]), .I1(n[79]), .I2(n[13]), .I3(n[55]), .I4(n[78]), .I5(n[52]),
        .O(n[125])
    );
    LUT6 #(
        .INIT(64'hB44B4BB4B44B4BB4)
    ) lut_58 (
        .I0(n[78]), .I1(n[118]), .I2(n[124]), .I3(n[8]), .I4(n[125]), .I5(1'b0),
        .O(n[67])
    );
    LUT6 #(
        .INIT(64'h780704C0D7FDAB3A)
    ) lut_59 (
        .I0(n[17]), .I1(n[50]), .I2(n[23]), .I3(n[45]), .I4(n[41]), .I5(n[7]),
        .O(n[126])
    );
    LUT6 #(
        .INIT(64'h55AAAAAA30CF3F3F)
    ) lut_60 (
        .I0(n[126]), .I1(n[23]), .I2(n[17]), .I3(n[123]), .I4(n[45]), .I5(n[18]),
        .O(n[127])
    );
    LUT6 #(
        .INIT(64'h6996699669966996)
    ) lut_61 (
        .I0(n[40]), .I1(n[11]), .I2(n[127]), .I3(n[50]), .I4(1'b0), .I5(1'b0),
        .O(n[90])
    );

endmodule
