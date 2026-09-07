module decision6_ref(clk, in_0, in_1, in_2, in_3, in_4, in_5, out_8);
    input clk;
    input in_0;
    input in_1;
    input in_2;
    input in_3;
    input in_4;
    input in_5;
    output out_8;
    assign out_8 = in_0 ? (in_1 ? in_2 : in_3) : (in_4 ? in_5 : in_2);
endmodule