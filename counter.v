module stateful_counter(
    input clk,
    input en,
    output reg [3:0] count
);
    always @(posedge clk) begin
        if (en)
            count <= count + 4'd1;
    end
endmodule
