`timescale 1ns / 1ps

// Enigma 256 cryptographic datapath (Blue Team cipher core).
// Matches Sources/HELUTCore/Enigma256.swift SoftBus oracle (Apple Silicon field).
// NLFF folds track Enigma256Generation — TensorLUT melts the NLFF cone, not the BRAMs.
//
// Load sequence (software control plane):
//   1. wr_en strobes fill plugboard and four rotor forward/reverse BRAM pairs
//   2. load_state captures LFSR seed, Grundstellung, and absolute byte counter
//   3. valid_in presents plaintext/ciphertext, center mask, and matching counter
//
// Hardening:
//   - NLFF on LFSR step enables (no raw bit taps → Berlekamp–Massey)
//   - Side-channel: BRAM address leakage is mitigated at the AXI wrapper via
//     optional stream jitter (DPA alignment break). Full dual-rail / masked
//     LUTs are a high-assurance synthesis option outside this reciprocal core.

module enigma_256_core (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Table load (AXI-friendly BRAM write port) ----
    // wr_sel: 0=plugboard, 1=r1_fwd, 2=r1_rev, 3=r2_fwd, 4=r2_rev,
    //         5=r3_fwd, 6=r3_rev, 7=r4_fwd, 8=r4_rev
    input  wire        wr_en,
    input  wire [3:0]  wr_sel,
    input  wire [7:0]  wr_addr,
    input  wire [7:0]  wr_data,

    // ---- Message-key / session load ----
    input  wire        load_state,
    input  wire [63:0] init_lfsr,
    input  wire [7:0]  init_r1_pos,
    input  wire [7:0]  init_r2_pos,
    input  wire [7:0]  init_r3_pos,
    input  wire [7:0]  init_r4_pos,
    input  wire [63:0] init_byte_counter,

    // ---- Streaming datapath ----
    input  wire [7:0]  data_in,
    input  wire [7:0]  center_mask,
    input  wire [63:0] absolute_byte_counter,
    input  wire        valid_in,
    output reg  [7:0]  data_out,
    output reg         valid_out,
    output reg         schedule_error
);

    // =========================================================================
    // 1. STATE MEMORY (HKDF day-key / active-slot tables)
    // =========================================================================
    reg [7:0] plugboard  [0:255];
    reg [7:0] r1_fwd     [0:255]; reg [7:0] r1_rev [0:255];
    reg [7:0] r2_fwd     [0:255]; reg [7:0] r2_rev [0:255];
    reg [7:0] r3_fwd     [0:255]; reg [7:0] r3_rev [0:255];
    reg [7:0] r4_fwd     [0:255]; reg [7:0] r4_rev [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            plugboard[i] = i[7:0];
            r1_fwd[i] = i[7:0]; r1_rev[i] = i[7:0];
            r2_fwd[i] = i[7:0]; r2_rev[i] = i[7:0];
            r3_fwd[i] = i[7:0]; r3_rev[i] = i[7:0];
            r4_fwd[i] = i[7:0]; r4_rev[i] = i[7:0];
        end
    end

    always @(posedge clk) begin
        if (wr_en) begin
            case (wr_sel)
                4'd0: plugboard[wr_addr] <= wr_data;
                4'd1: r1_fwd[wr_addr]    <= wr_data;
                4'd2: r1_rev[wr_addr]    <= wr_data;
                4'd3: r2_fwd[wr_addr]    <= wr_data;
                4'd4: r2_rev[wr_addr]    <= wr_data;
                4'd5: r3_fwd[wr_addr]    <= wr_data;
                4'd6: r3_rev[wr_addr]    <= wr_data;
                4'd7: r4_fwd[wr_addr]    <= wr_data;
                4'd8: r4_rev[wr_addr]    <= wr_data;
                default: /* ignore */ ;
            endcase
        end
    end

    // =========================================================================
    // 2. STEPPING ENGINE (64-bit Galois LFSR + NLFF)
    // Primitive taps 64,63,61,60: right shift with LSB feedback mask 0xD800…
    // =========================================================================
    reg  [63:0] lfsr;
    wire [63:0] lfsr_next = {1'b0, lfsr[63:1]} ^ (lfsr[0] ? 64'hD800000000000000 : 64'h0);

    reg [7:0] offset_r1, offset_r2, offset_r3, offset_r4;
    // Trace-visible schedule state. The value names the only counter accepted
    // on the next valid beat and never wraps through UInt64.max.
    reg [63:0] expected_byte_counter;

    // E256-v2/gen0 native reversible NLFF. The included gate network is
    // generated from the accepted bounded-search receipt.
    `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
    wire step_r1 = e256_nlff_step_r1;
    wire step_r2 = e256_nlff_step_r2;
    wire step_r3 = e256_nlff_step_r3;
    wire step_r4 = e256_nlff_step_r4;

    // =========================================================================
    // 3. CRYPTOGRAPHIC DATAPATH (combinational; sampled on an accepted beat)
    // =========================================================================
    wire [7:0] pb_in      = plugboard[data_in];

    wire [7:0] r1_in_fwd  = pb_in + offset_r1;
    wire [7:0] r1_out_fwd = r1_fwd[r1_in_fwd] - offset_r1;

    wire [7:0] r2_in_fwd  = r1_out_fwd + offset_r2;
    wire [7:0] r2_out_fwd = r2_fwd[r2_in_fwd] - offset_r2;

    wire [7:0] r3_in_fwd  = r2_out_fwd + offset_r3;
    wire [7:0] r3_out_fwd = r3_fwd[r3_in_fwd] - offset_r3;

    wire [7:0] r4_in_fwd  = r3_out_fwd + offset_r4;
    wire [7:0] r4_out_fwd = r4_fwd[r4_in_fwd] - offset_r4;

    // Trace-visible fixture-v4 center involution.
    wire [7:0] center_out = r4_out_fwd ^ center_mask;

    wire [7:0] r4_in_rev  = center_out + offset_r4;
    wire [7:0] r4_out_rev = r4_rev[r4_in_rev] - offset_r4;

    wire [7:0] r3_in_rev  = r4_out_rev + offset_r3;
    wire [7:0] r3_out_rev = r3_rev[r3_in_rev] - offset_r3;

    wire [7:0] r2_in_rev  = r3_out_rev + offset_r2;
    wire [7:0] r2_out_rev = r2_rev[r2_in_rev] - offset_r2;

    wire [7:0] r1_in_rev  = r2_out_rev + offset_r1;
    wire [7:0] r1_out_rev = r1_rev[r1_in_rev] - offset_r1;

    wire [7:0] scramble_out = plugboard[r1_out_rev];
    wire counter_matches = (absolute_byte_counter == expected_byte_counter);
    wire counter_available = (expected_byte_counter != 64'hffffffffffffffff);
    wire accept_byte = valid_in && counter_matches && counter_available;

    // =========================================================================
    // 4. SEQUENTIAL: load / schedule gate / step / registered I/O
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr                  <= 64'd1;
            offset_r1             <= 8'd0;
            offset_r2             <= 8'd0;
            offset_r3             <= 8'd0;
            offset_r4             <= 8'd0;
            expected_byte_counter <= 64'd0;
            data_out              <= 8'd0;
            valid_out             <= 1'b0;
            schedule_error        <= 1'b0;
        end else if (load_state) begin
            lfsr                  <= (init_lfsr == 64'd0) ? 64'd1 : init_lfsr;
            offset_r1             <= init_r1_pos;
            offset_r2             <= init_r2_pos;
            offset_r3             <= init_r3_pos;
            offset_r4             <= init_r4_pos;
            expected_byte_counter <= init_byte_counter;
            data_out              <= 8'd0;
            valid_out             <= 1'b0;
            schedule_error        <= 1'b0;
        end else if (accept_byte) begin
            // Emit under current state, then step and consume exactly one counter.
            data_out              <= scramble_out;
            valid_out             <= 1'b1;
            lfsr                  <= lfsr_next;
            offset_r1             <= offset_r1 + step_r1;
            offset_r2             <= offset_r2 + step_r2;
            offset_r3             <= offset_r3 + step_r3;
            offset_r4             <= offset_r4 + step_r4;
            expected_byte_counter <= expected_byte_counter + 64'd1;
        end else if (valid_in) begin
            // Counter mismatch or UInt64 exhaustion: reject without state motion.
            valid_out      <= 1'b0;
            schedule_error <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
