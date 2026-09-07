module mux8_ref(clk, in_0, in_1, in_2, in_3, in_4, in_5, in_6, in_7, in_8, in_9, in_10, out_25);
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
    output out_25;
        wire [7:0] data = {in_7, in_6, in_5, in_4, in_3, in_2, in_1, in_0};
        wire [2:0] select = {in_10, in_9, in_8};
        assign out_25 = data[select];
endmodule