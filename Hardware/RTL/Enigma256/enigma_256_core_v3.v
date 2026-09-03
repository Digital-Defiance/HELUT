`timescale 1ns / 1ps

// Incompatible E256-v3/gen0 research-core boundary.
// profile_sha256=0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16
//
// The frozen byte transform/NLFF is shared with the preserved hand-authored
// v2 core. V3 changes the host derivation/profile contract and, critically,
// rejects an externally supplied all-zero LFSR before it reaches active state.
// Standard AEAD remains mandatory for real data.
module enigma_256_core_v3 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        wr_en,
    input  wire [3:0]  wr_sel,
    input  wire [7:0]  wr_addr,
    input  wire [7:0]  wr_data,

    input  wire        load_state,
    input  wire [63:0] init_lfsr,
    input  wire [7:0]  init_r1_pos,
    input  wire [7:0]  init_r2_pos,
    input  wire [7:0]  init_r3_pos,
    input  wire [7:0]  init_r4_pos,
    input  wire [63:0] init_byte_counter,

    input  wire [7:0]  data_in,
    input  wire [7:0]  center_mask,
    input  wire [63:0] absolute_byte_counter,
    input  wire        valid_in,
    output wire [7:0]  data_out,
    output wire        valid_out,
    output wire        schedule_error,
    output reg         configuration_error
);
    wire valid_state_load = load_state && (init_lfsr != 64'd0);
    reg configuration_armed;
    wire core_valid_in = valid_in && configuration_armed &&
                         !configuration_error && !load_state;
    wire [7:0] core_data_out;
    wire core_valid_out;
    wire core_schedule_error;

    // A valid load atomically arms traffic. Reset, malformed state, or payload
    // attempted while unarmed leaves the wrapped core quiescent until a later
    // valid load. The prior state may remain physically present, but it cannot
    // process or authenticate another beat through this boundary.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            configuration_error <= 1'b0;
            configuration_armed <= 1'b0;
        end else if (load_state) begin
            if (init_lfsr == 64'd0) begin
                configuration_error <= 1'b1;
                configuration_armed <= 1'b0;
            end else begin
                configuration_error <= 1'b0;
                configuration_armed <= 1'b1;
            end
        end else if (valid_in && !configuration_armed) begin
            configuration_error <= 1'b1;
        end
    end

    assign data_out = core_data_out;
    assign valid_out = core_valid_out && configuration_armed && !configuration_error;
    assign schedule_error = core_schedule_error;

    enigma_256_core core (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_sel(wr_sel),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .load_state(valid_state_load),
        .init_lfsr(init_lfsr),
        .init_r1_pos(init_r1_pos),
        .init_r2_pos(init_r2_pos),
        .init_r3_pos(init_r3_pos),
        .init_r4_pos(init_r4_pos),
        .init_byte_counter(init_byte_counter),
        .data_in(data_in),
        .center_mask(center_mask),
        .absolute_byte_counter(absolute_byte_counter),
        .valid_in(core_valid_in),
        .data_out(core_data_out),
        .valid_out(core_valid_out),
        .schedule_error(core_schedule_error)
    );
endmodule
