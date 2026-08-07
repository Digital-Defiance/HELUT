module popcount6_dut (
    clk, in_0, in_1, in_2, in_3, in_4, in_5, out_8, out_11, out_14
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

    // Internal Netlist Wires
    wire [14:0] n;

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

    // Adversarially Synthesized Combinational Logic
    LUT6 #(
        .INIT(64'h6996966996696996)
    ) lut_0 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[6])
    );
    LUT6 #(
        .INIT(64'h6996966996696996)
    ) lut_1 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[7])
    );
    LUT6 #(
        .INIT(64'h8888888888888888)
    ) lut_2 (
        .I0(n[6]), .I1(n[7]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[8])
    );
    LUT6 #(
        .INIT(64'h8117177E177E7EE8)
    ) lut_3 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[9])
    );
    LUT6 #(
        .INIT(64'h8117177E177E7EE8)
    ) lut_4 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[10])
    );
    LUT6 #(
        .INIT(64'h8888888888888888)
    ) lut_5 (
        .I0(n[9]), .I1(n[10]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[11])
    );
    LUT6 #(
        .INIT(64'hFEE8E880E8808000)
    ) lut_6 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[12])
    );
    LUT6 #(
        .INIT(64'hFEE8E880E8808000)
    ) lut_7 (
        .I0(n[0]), .I1(n[1]), .I2(n[2]), .I3(n[3]), .I4(n[4]), .I5(n[5]),
        .O(n[13])
    );
    LUT6 #(
        .INIT(64'h8888888888888888)
    ) lut_8 (
        .I0(n[12]), .I1(n[13]), .I2(1'b0), .I3(1'b0), .I4(1'b0), .I5(1'b0),
        .O(n[14])
    );

endmodule
