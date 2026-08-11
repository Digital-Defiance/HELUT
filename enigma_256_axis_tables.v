`timescale 1ns / 1ps

// AXI4-Stream → enigma_256_core table burst loader.
// Streams 10×256 = 2560 bytes: wr_sel advances every 256 beats, wr_addr 0…255.
// Use instead of 2560 AXI-Lite WR_DATA commits for message-key swaps.

module enigma_256_axis_tables (
    input  wire        clk,
    input  wire        rst_n,

    // AXIS slave (table payload)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // Core table write port
    output reg         wr_en,
    output reg  [3:0]  wr_sel,
    output reg  [7:0]  wr_addr,
    output reg  [7:0]  wr_data,

    output reg         busy,
    output reg         done
);
    reg [11:0] count; // 0…2559

    assign s_axis_tready = rst_n && !done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en   <= 1'b0;
            wr_sel  <= 4'd0;
            wr_addr <= 8'd0;
            wr_data <= 8'd0;
            count   <= 12'd0;
            busy    <= 1'b0;
            done    <= 1'b0;
        end else begin
            wr_en <= 1'b0;
            if (done) begin
                // idle until reset
            end else if (s_axis_tvalid && s_axis_tready) begin
                busy    <= 1'b1;
                wr_en   <= 1'b1;
                wr_data <= s_axis_tdata;
                wr_sel  <= count[11:8]; // 0…9
                wr_addr <= count[7:0];
                if (count == 12'd2559 || s_axis_tlast) begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    count <= 12'd0;
                end else begin
                    count <= count + 12'd1;
                end
            end
        end
    end
endmodule
