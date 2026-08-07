`timescale 1ns / 1ps

// Self-checking testbench for enigma_256_core vs a fixture-v4 golden bundle.
// The bundle directory is both an include root for tb_params.vh and the
// runtime +HEXDIR used for tables, payload, and traces.

module enigma_256_tb;
`include "tb_params.vh"

    reg         clk = 0;
    reg         rst_n = 0;
    always #5 clk = ~clk;

    reg         wr_en = 0;
    reg  [3:0]  wr_sel = 0;
    reg  [7:0]  wr_addr = 0;
    reg  [7:0]  wr_data = 0;

    reg         load_state = 0;
    reg  [63:0] init_lfsr = 64'h1;
    reg  [7:0]  init_r1_pos = 0, init_r2_pos = 0, init_r3_pos = 0, init_r4_pos = 0;
    reg  [63:0] init_byte_counter = 0;

    reg  [7:0]  data_in = 0;
    reg  [7:0]  center_mask = 0;
    reg  [63:0] absolute_byte_counter = 0;
    reg         valid_in = 0;
    wire [7:0]  data_out;
    wire        valid_out;
    wire        schedule_error;

    enigma_256_core dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .load_state(load_state),
        .init_lfsr(init_lfsr),
        .init_r1_pos(init_r1_pos), .init_r2_pos(init_r2_pos),
        .init_r3_pos(init_r3_pos), .init_r4_pos(init_r4_pos),
        .init_byte_counter(init_byte_counter),
        .data_in(data_in), .center_mask(center_mask),
        .absolute_byte_counter(absolute_byte_counter), .valid_in(valid_in),
        .data_out(data_out), .valid_out(valid_out),
        .schedule_error(schedule_error)
    );

    reg [7:0] table_mem [0:8][0:255];
    reg [7:0] plain_mem [0:ENIGMA256_N-1];
    reg [7:0] cipher_mem [0:ENIGMA256_N-1];
    reg [63:0] trace_lfsr_before [0:ENIGMA256_N-1];
    reg [63:0] trace_lfsr_after [0:ENIGMA256_N-1];
    reg [31:0] trace_offsets_before [0:ENIGMA256_N-1];
    reg [31:0] trace_offsets_after [0:ENIGMA256_N-1];
    reg [3:0] trace_step_mask [0:ENIGMA256_N-1];
    reg [63:0] trace_byte_counter_before [0:ENIGMA256_N-1];
    reg [63:0] trace_byte_counter_after [0:ENIGMA256_N-1];
    reg [7:0] trace_center_mask [0:ENIGMA256_N-1];
    reg [7:0] trace_center_input [0:ENIGMA256_N-1];
    reg [7:0] trace_center_output [0:ENIGMA256_N-1];

    integer i, t, errors, n_bytes, code, fd;
    reg [7:0] byte_v;
    string hexdir;
    string path;

    initial begin
        if (!$value$plusargs("HEXDIR=%s", hexdir))
            hexdir = "Fixtures/enigma256_golden";

        init_lfsr   = ENIGMA256_LFSR;
        init_r1_pos = ENIGMA256_R1;
        init_r2_pos = ENIGMA256_R2;
        init_r3_pos = ENIGMA256_R3;
        init_r4_pos = ENIGMA256_R4;
        n_bytes     = ENIGMA256_N;

        path = {hexdir, "/tables/plugboard.hex"}; load_table(0);
        path = {hexdir, "/tables/r1_fwd.hex"};    load_table(1);
        path = {hexdir, "/tables/r1_rev.hex"};    load_table(2);
        path = {hexdir, "/tables/r2_fwd.hex"};    load_table(3);
        path = {hexdir, "/tables/r2_rev.hex"};    load_table(4);
        path = {hexdir, "/tables/r3_fwd.hex"};    load_table(5);
        path = {hexdir, "/tables/r3_rev.hex"};    load_table(6);
        path = {hexdir, "/tables/r4_fwd.hex"};    load_table(7);
        path = {hexdir, "/tables/r4_rev.hex"};    load_table(8);

        path = {hexdir, "/plaintext.hex"};  load_plain();
        path = {hexdir, "/ciphertext.hex"}; load_cipher();
        $readmemh({hexdir, "/trace/lfsr_before.hex"}, trace_lfsr_before, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/lfsr_after.hex"}, trace_lfsr_after, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/offsets_before.hex"}, trace_offsets_before, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/offsets_after.hex"}, trace_offsets_after, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/step_mask.hex"}, trace_step_mask, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/byte_counter_before.hex"}, trace_byte_counter_before, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/byte_counter_after.hex"}, trace_byte_counter_after, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/center_mask.hex"}, trace_center_mask, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/center_input.hex"}, trace_center_input, 0, n_bytes - 1);
        $readmemh({hexdir, "/trace/center_output.hex"}, trace_center_output, 0, n_bytes - 1);
        init_byte_counter = trace_byte_counter_before[0];

        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (t = 0; t < 9; t = t + 1) begin
            for (i = 0; i < 256; i = i + 1) begin
                @(negedge clk);
                wr_en   = 1'b1;
                wr_sel  = t[3:0];
                wr_addr = i[7:0];
                wr_data = table_mem[t][i];
            end
        end
        @(negedge clk);
        wr_en = 1'b0;

        @(negedge clk);
        load_state = 1'b1;
        @(negedge clk);
        load_state = 1'b0;
        @(posedge clk);

        errors = 0;
        for (i = 0; i < n_bytes; i = i + 1) begin
            @(negedge clk);
            data_in              = plain_mem[i];
            center_mask          = trace_center_mask[i];
            absolute_byte_counter = trace_byte_counter_before[i];
            valid_in             = 1'b1;
            #1;
            if (dut.lfsr !== trace_lfsr_before[i]) begin
                $display("FAIL beat %0d pre-lfsr got %016x want %016x", i, dut.lfsr, trace_lfsr_before[i]);
                errors = errors + 1;
            end
            if ({dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4} !== trace_offsets_before[i]) begin
                $display("FAIL beat %0d pre-offsets got %08x want %08x", i,
                         {dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4}, trace_offsets_before[i]);
                errors = errors + 1;
            end
            if ({dut.step_r4, dut.step_r3, dut.step_r2, dut.step_r1} !== trace_step_mask[i]) begin
                $display("FAIL beat %0d step mask got %x want %x", i,
                         {dut.step_r4, dut.step_r3, dut.step_r2, dut.step_r1}, trace_step_mask[i]);
                errors = errors + 1;
            end
            if (dut.expected_byte_counter !== trace_byte_counter_before[i]) begin
                $display("FAIL beat %0d pre-counter got %016x want %016x", i,
                         dut.expected_byte_counter, trace_byte_counter_before[i]);
                errors = errors + 1;
            end
            if (dut.r4_out_fwd !== trace_center_input[i] ||
                dut.center_out !== trace_center_output[i] ||
                dut.center_out !== (dut.r4_out_fwd ^ center_mask)) begin
                $display("FAIL beat %0d center got %02x xor %02x -> %02x want %02x -> %02x", i,
                         dut.r4_out_fwd, center_mask, dut.center_out,
                         trace_center_input[i], trace_center_output[i]);
                errors = errors + 1;
            end
            @(posedge clk);
            #1;
            if (!valid_out) begin
                $display("FAIL: valid_out low at beat %0d", i);
                errors = errors + 1;
            end else if (data_out !== cipher_mem[i]) begin
                $display("FAIL beat %0d: got %02x want %02x", i, data_out, cipher_mem[i]);
                errors = errors + 1;
            end
            if (schedule_error) begin
                $display("FAIL beat %0d: unexpected schedule_error", i);
                errors = errors + 1;
            end
            if (dut.lfsr !== trace_lfsr_after[i]) begin
                $display("FAIL beat %0d post-lfsr got %016x want %016x", i, dut.lfsr, trace_lfsr_after[i]);
                errors = errors + 1;
            end
            if ({dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4} !== trace_offsets_after[i]) begin
                $display("FAIL beat %0d post-offsets got %08x want %08x", i,
                         {dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4}, trace_offsets_after[i]);
                errors = errors + 1;
            end
            if (dut.expected_byte_counter !== trace_byte_counter_after[i]) begin
                $display("FAIL beat %0d post-counter got %016x want %016x", i,
                         dut.expected_byte_counter, trace_byte_counter_after[i]);
                errors = errors + 1;
            end
        end
        @(negedge clk);
        valid_in = 1'b0;

        if (errors == 0)
            $display("PASS: enigma_256_core matched %0d fixture-v4 bytes and state transitions", n_bytes);
        else
            $display("FAIL: %0d mismatches", errors);
        $finish(errors == 0 ? 0 : 1);
    end

    task load_table;
        input integer sel;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("FATAL: cannot open %s", path);
                $finish(1);
            end
            for (i = 0; i < 256; i = i + 1) begin
                code = $fscanf(fd, "%h\n", byte_v);
                if (code != 1) begin
                    $display("FATAL: short hex in %s at %0d", path, i);
                    $finish(1);
                end
                table_mem[sel][i] = byte_v;
            end
            $fclose(fd);
        end
    endtask

    task load_plain;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin $display("FATAL: %s", path); $finish(1); end
            for (i = 0; i < n_bytes; i = i + 1) begin
                code = $fscanf(fd, "%h\n", byte_v);
                if (code != 1) begin $display("FATAL: PT short"); $finish(1); end
                plain_mem[i] = byte_v;
            end
            $fclose(fd);
        end
    endtask

    task load_cipher;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin $display("FATAL: %s", path); $finish(1); end
            for (i = 0; i < n_bytes; i = i + 1) begin
                code = $fscanf(fd, "%h\n", byte_v);
                if (code != 1) begin $display("FATAL: CT short"); $finish(1); end
                cipher_mem[i] = byte_v;
            end
            $fclose(fd);
        end
    endtask
endmodule
