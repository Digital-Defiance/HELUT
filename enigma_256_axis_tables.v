`timescale 1ns / 1ps

// AXI4-Stream → enigma_256_core table burst loader.
// Streams 10×256 = 2560 bytes: wr_sel advances every 256 beats, wr_addr 0…255.
// Pulse `arm` (or reset) to clear `done` before each new burst.

module enigma_256_axis_tables (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        arm,

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
    output reg         done,
    output reg  [11:0] byte_count
);
    assign s_axis_tready = rst_n && !done && !arm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en      <= 1'b0;
            wr_sel     <= 4'd0;
            wr_addr    <= 8'd0;
            wr_data    <= 8'd0;
            byte_count <= 12'd0;
            busy       <= 1'b0;
            done       <= 1'b0;
        end else begin
            wr_en <= 1'b0;
            if (arm) begin
                done       <= 1'b0;
                busy       <= 1'b0;
                byte_count <= 12'd0;
            end else if (done) begin
                // hold until next arm
            end else if (s_axis_tvalid && s_axis_tready) begin
                busy       <= 1'b1;
                wr_en      <= 1'b1;
                wr_data    <= s_axis_tdata;
                wr_sel     <= byte_count[11:8]; // 0…9
                wr_addr    <= byte_count[7:0];
                if (byte_count == 12'd2559 || s_axis_tlast) begin
                    done       <= 1'b1;
                    busy       <= 1'b0;
                    byte_count <= byte_count + 12'd1;
                end else begin
                    byte_count <= byte_count + 12'd1;
                end
            end
        end
    end
endmodule
