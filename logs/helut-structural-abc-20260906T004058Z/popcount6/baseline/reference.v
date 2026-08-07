module popcount6_ref(clk, in_0, in_1, in_2, in_3, in_4, in_5, out_8, out_11, out_14);
    input clk;
    input in_0;
    input in_1;
    input in_2;
    input in_3;
    input in_4;
    input in_5;
    output out_8;
    output out_11;
    output out_14;
        wire [2:0] count = {2'b00, in_0} + {2'b00, in_1} + {2'b00, in_2}
            + {2'b00, in_3} + {2'b00, in_4} + {2'b00, in_5};
        assign out_8 = count[0];
        assign out_11 = count[1];
        assign out_14 = count[2];
endmodule