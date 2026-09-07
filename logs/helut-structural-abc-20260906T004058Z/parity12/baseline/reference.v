module parity12_ref(clk, in_0, in_1, in_2, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, in_11, out_18);
    input clk;
    input in_0;
    input in_1;
    input in_2;
    input in_3;
    input in_4;
    input in_5;
    input in_6;
    input in_7;
    input in_8;
    input in_9;
    input in_10;
    input in_11;
    output out_18;
    assign out_18 = in_0 ^ in_1 ^ in_2 ^ in_3 ^ in_4 ^ in_5 ^ in_6 ^ in_7 ^ in_8 ^ in_9 ^ in_10 ^ in_11;
endmodule