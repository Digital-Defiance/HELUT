`timescale 1ns / 1ps

module enigma_256_v3_fixture_tb;
    parameter FIXTURE = "Fixtures/Staging/Enigma256/E256-v3-gen0-0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16-fixture-v5";

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg wr_en = 1'b0;
    reg [3:0] wr_sel = 4'd0;
    reg [7:0] wr_addr = 8'd0;
    reg [7:0] wr_data = 8'd0;
    reg load_state = 1'b0;
    reg [63:0] init_lfsr = 64'hf4945e1ad9283950;
    reg [7:0] init_r1_pos = 8'h48;
    reg [7:0] init_r2_pos = 8'hb1;
    reg [7:0] init_r3_pos = 8'h0c;
    reg [7:0] init_r4_pos = 8'hb8;
    reg [63:0] init_byte_counter = 64'd0;
    reg [7:0] data_in = 8'd0;
    reg [7:0] center_mask = 8'd0;
    reg [63:0] absolute_byte_counter = 64'd0;
    reg valid_in = 1'b0;
    wire [7:0] data_out;
    wire valid_out;
    wire schedule_error;
    wire configuration_error;

    enigma_256_core_v3 dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .load_state(load_state), .init_lfsr(init_lfsr),
        .init_r1_pos(init_r1_pos), .init_r2_pos(init_r2_pos),
        .init_r3_pos(init_r3_pos), .init_r4_pos(init_r4_pos),
        .init_byte_counter(init_byte_counter),
        .data_in(data_in), .center_mask(center_mask),
        .absolute_byte_counter(absolute_byte_counter), .valid_in(valid_in),
        .data_out(data_out), .valid_out(valid_out),
        .schedule_error(schedule_error),
        .configuration_error(configuration_error)
    );

    task load_table;
        input [3:0] selector;
        input string filename;
        integer file_handle;
        integer address;
        integer value;
        begin
            file_handle = $fopen(filename, "rb");
            if (file_handle == 0) begin
                $display("FAIL cannot open table %s", filename);
                $fatal(1);
            end
            for (address = 0; address < 256; address = address + 1) begin
                value = $fgetc(file_handle);
                if (value < 0) begin
                    $display("FAIL short table %s at %0d", filename, address);
                    $fatal(1);
                end
                @(negedge clk);
                wr_sel = selector;
                wr_addr = address[7:0];
                wr_data = value[7:0];
                wr_en = 1'b1;
                @(posedge clk); #1;
                wr_en = 1'b0;
            end
            value = $fgetc(file_handle);
            if (value >= 0) begin
                $display("FAIL long table %s", filename);
                $fatal(1);
            end
            $fclose(file_handle);
        end
    endtask

    integer trace_file;
    integer scan_count;
    integer byte_index;
    reg [8*256-1:0] header;
    reg [7:0] expected_input;
    reg [7:0] expected_output;
    reg [63:0] expected_counter_before;
    reg [63:0] expected_lfsr_before;
    reg [31:0] expected_positions_before;
    reg [7:0] expected_step_mask;
    reg [7:0] expected_center_mask;
    reg [7:0] expected_center_input;
    reg [7:0] expected_center_output;
    reg [63:0] expected_counter_after;
    reg [63:0] expected_lfsr_after;
    reg [31:0] expected_positions_after;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        load_table(4'd0, {FIXTURE, "/artifacts/tables/plugboard.bin"});
        load_table(4'd1, {FIXTURE, "/artifacts/tables/r1_fwd.bin"});
        load_table(4'd2, {FIXTURE, "/artifacts/tables/r1_rev.bin"});
        load_table(4'd3, {FIXTURE, "/artifacts/tables/r2_fwd.bin"});
        load_table(4'd4, {FIXTURE, "/artifacts/tables/r2_rev.bin"});
        load_table(4'd5, {FIXTURE, "/artifacts/tables/r3_fwd.bin"});
        load_table(4'd6, {FIXTURE, "/artifacts/tables/r3_rev.bin"});
        load_table(4'd7, {FIXTURE, "/artifacts/tables/r4_fwd.bin"});
        load_table(4'd8, {FIXTURE, "/artifacts/tables/r4_rev.bin"});

        @(negedge clk);
        load_state = 1'b1;
        @(posedge clk); #1;
        load_state = 1'b0;
        if (configuration_error) begin
            $display("FAIL fixture-v5 nonzero state rejected");
            $fatal(1);
        end

        trace_file = $fopen({FIXTURE, "/artifacts/stream-trace.csv"}, "r");
        if (trace_file == 0) begin
            $display("FAIL cannot open fixture-v5 stream trace");
            $fatal(1);
        end
        scan_count = $fgets(header, trace_file);
        if (scan_count == 0) begin
            $display("FAIL missing fixture-v5 trace header");
            $fatal(1);
        end

        byte_index = 0;
        while (!$feof(trace_file)) begin
            scan_count = $fscanf(
                trace_file,
                "%d,%h,%h,%h,%h,%h,%h,%h,%h,%h,%h,%h,%h\n",
                byte_index,
                expected_input,
                expected_output,
                expected_counter_before,
                expected_lfsr_before,
                expected_positions_before,
                expected_step_mask,
                expected_center_mask,
                expected_center_input,
                expected_center_output,
                expected_counter_after,
                expected_lfsr_after,
                expected_positions_after
            );
            if (scan_count == -1)
                break;
            if (scan_count != 13) begin
                $display("FAIL malformed fixture-v5 trace row %0d fields=%0d", byte_index, scan_count);
                $fatal(1);
            end
            if (dut.core.lfsr !== expected_lfsr_before ||
                {dut.core.offset_r1, dut.core.offset_r2, dut.core.offset_r3, dut.core.offset_r4} !== expected_positions_before ||
                dut.core.expected_byte_counter !== expected_counter_before) begin
                $display("FAIL pre-state mismatch at byte %0d", byte_index);
                $fatal(1);
            end

            @(negedge clk);
            data_in = expected_input;
            center_mask = expected_center_mask;
            absolute_byte_counter = expected_counter_before;
            valid_in = 1'b1;
            #1;
            if (dut.core.center_out !== expected_center_output ||
                dut.core.r4_out_fwd !== expected_center_input) begin
                $display("FAIL center trace mismatch at byte %0d", byte_index);
                $fatal(1);
            end
            if ({dut.core.step_r4, dut.core.step_r3, dut.core.step_r2, dut.core.step_r1} !== expected_step_mask[3:0]) begin
                $display("FAIL step mask mismatch at byte %0d", byte_index);
                $fatal(1);
            end
            @(posedge clk); #1;
            valid_in = 1'b0;

            if (!valid_out || schedule_error) begin
                $display("FAIL fixture-v5 beat rejected at byte %0d", byte_index);
                $fatal(1);
            end
            if (data_out !== expected_output) begin
                $display("FAIL output mismatch at byte %0d got=%02x expected=%02x",
                         byte_index, data_out, expected_output);
                $fatal(1);
            end
            if (dut.core.lfsr !== expected_lfsr_after ||
                {dut.core.offset_r1, dut.core.offset_r2, dut.core.offset_r3, dut.core.offset_r4} !== expected_positions_after ||
                dut.core.expected_byte_counter !== expected_counter_after) begin
                $display("FAIL post-state mismatch at byte %0d", byte_index);
                $fatal(1);
            end
        end
        $fclose(trace_file);

        if (byte_index != 1023 || dut.core.expected_byte_counter != 64'd1024) begin
            $display("FAIL fixture-v5 did not consume exactly 1024 beats last=%0d counter=%0d",
                     byte_index, dut.core.expected_byte_counter);
            $fatal(1);
        end
        $display("PASS E256-v3 fixture-v5 direct RTL parity 1024/1024 beats");
        $finish;
    end
endmodule
