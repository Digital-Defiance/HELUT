`timescale 1ns / 1ps

// AXI4-Lite slave wrapping enigma_256_core (ENIGMA256_REGMAP.md).
// Combinational ready when response channel is free (single outstanding txn).

module enigma_256_axi (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);
    wire unused_wstrb = |s_axi_wstrb;

    reg [3:0]  reg_wr_sel;
    reg [7:0]  reg_wr_addr;
    reg [7:0]  reg_wr_data;
    reg [63:0] reg_init_lfsr;
    reg [7:0]  reg_r1, reg_r2, reg_r3, reg_r4;
    reg [7:0]  reg_data_in;
    reg [7:0]  latched_data_out;
    reg        latched_valid;
    reg        busy;

    reg        core_wr_en;
    reg        core_load_state;
    reg        core_valid_in;
    // Delayed stream: data_in must be stable the cycle valid_in is seen by core.
    reg        pend_stream;
    reg [7:0]  pend_stream_data;

    wire [7:0] core_data_out;
    wire       core_valid_out;

    enigma_256_core u_core (
        .clk(aclk),
        .rst_n(aresetn),
        .wr_en(core_wr_en),
        .wr_sel(reg_wr_sel),
        .wr_addr(reg_wr_addr),
        .wr_data(reg_wr_data),
        .load_state(core_load_state),
        .init_lfsr(reg_init_lfsr),
        .init_r1_pos(reg_r1),
        .init_r2_pos(reg_r2),
        .init_r3_pos(reg_r3),
        .init_r4_pos(reg_r4),
        .data_in(reg_data_in),
        .valid_in(core_valid_in),
        .data_out(core_data_out),
        .valid_out(core_valid_out)
    );

    assign s_axi_awready = !s_axi_bvalid;
    assign s_axi_wready  = !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    wire wr_hs = s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready;
    wire rd_hs = s_axi_arvalid && s_axi_arready;

    function automatic [31:0] read_mux;
        input [7:0] addr;
        begin
            case (addr)
                8'h00: read_mux = {23'd0, busy, 8'd0};
                8'h04: read_mux = {28'd0, reg_wr_sel};
                8'h08: read_mux = {24'd0, reg_wr_addr};
                8'h0C: read_mux = {24'd0, reg_wr_data};
                8'h10: read_mux = reg_init_lfsr[31:0];
                8'h14: read_mux = reg_init_lfsr[63:32];
                8'h18: read_mux = {24'd0, reg_r1};
                8'h1C: read_mux = {24'd0, reg_r2};
                8'h20: read_mux = {24'd0, reg_r3};
                8'h24: read_mux = {24'd0, reg_r4};
                8'h28: read_mux = {24'd0, reg_data_in};
                8'h2C: read_mux = {24'd0, latched_data_out};
                8'h30: read_mux = {30'd0, busy, latched_valid};
                default: read_mux = 32'h0;
            endcase
        end
    endfunction

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'h0;
            reg_wr_sel <= 4'd0;
            reg_wr_addr <= 8'd0;
            reg_wr_data <= 8'd0;
            reg_init_lfsr <= 64'd1;
            reg_r1 <= 8'd0; reg_r2 <= 8'd0; reg_r3 <= 8'd0; reg_r4 <= 8'd0;
            reg_data_in <= 8'd0;
            latched_data_out <= 8'd0;
            latched_valid <= 1'b0;
            busy <= 1'b0;
            core_wr_en <= 1'b0;
            core_load_state <= 1'b0;
            core_valid_in <= 1'b0;
            pend_stream <= 1'b0;
            pend_stream_data <= 8'd0;
        end else begin
            core_wr_en <= 1'b0;
            core_load_state <= 1'b0;
            core_valid_in <= 1'b0;

            if (core_valid_out) begin
                latched_data_out <= core_data_out;
                latched_valid <= 1'b1;
                busy <= 1'b0;
            end

            // Deferred stream beat (data registered previous cycle).
            if (pend_stream) begin
                reg_data_in <= pend_stream_data;
                core_valid_in <= 1'b1;
                pend_stream <= 1'b0;
            end

            if (wr_hs) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                case (s_axi_awaddr)
                    8'h00: begin
                        if (s_axi_wdata[0])
                            core_load_state <= 1'b1;
                        if (s_axi_wdata[8]) begin
                            latched_valid <= 1'b0;
                            latched_data_out <= 8'd0;
                        end
                    end
                    8'h04: reg_wr_sel  <= s_axi_wdata[3:0];
                    8'h08: reg_wr_addr <= s_axi_wdata[7:0];
                    8'h0C: begin
                        reg_wr_data <= s_axi_wdata[7:0];
                        core_wr_en <= 1'b1;
                    end
                    8'h10: reg_init_lfsr[31:0]  <= s_axi_wdata;
                    8'h14: reg_init_lfsr[63:32] <= s_axi_wdata;
                    8'h18: reg_r1 <= s_axi_wdata[7:0];
                    8'h1C: reg_r2 <= s_axi_wdata[7:0];
                    8'h20: reg_r3 <= s_axi_wdata[7:0];
                    8'h24: reg_r4 <= s_axi_wdata[7:0];
                    8'h28: begin
                        pend_stream_data <= s_axi_wdata[7:0];
                        pend_stream <= 1'b1;
                        latched_valid <= 1'b0;
                        busy <= 1'b1;
                    end
                    default: ;
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (rd_hs) begin
                s_axi_rdata  <= read_mux(s_axi_araddr);
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
