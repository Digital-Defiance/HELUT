`timescale 1ns / 1ps

// Directed fixture-v4 center and absolute-byte schedule checks. Identity outer
// tables expose center_out directly while retaining the real LFSR/step state.
module enigma_256_center_tb;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg wr_en = 0;
    reg [3:0] wr_sel = 0;
    reg [7:0] wr_addr = 0;
    reg [7:0] wr_data = 0;
    reg load_state = 0;
    reg [63:0] init_lfsr = 1;
    reg [7:0] init_r1_pos = 0, init_r2_pos = 0, init_r3_pos = 0, init_r4_pos = 0;
    reg [63:0] init_byte_counter = 0;
    reg [7:0] data_in = 0;
    reg [7:0] center_mask = 0;
    reg [63:0] absolute_byte_counter = 0;
    reg valid_in = 0;
    wire [7:0] data_out;
    wire valid_out;
    wire schedule_error;

    integer table_index, address_index, errors;

    enigma_256_core dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .load_state(load_state), .init_lfsr(init_lfsr),
        .init_r1_pos(init_r1_pos), .init_r2_pos(init_r2_pos),
        .init_r3_pos(init_r3_pos), .init_r4_pos(init_r4_pos),
        .init_byte_counter(init_byte_counter),
        .data_in(data_in), .center_mask(center_mask),
        .absolute_byte_counter(absolute_byte_counter), .valid_in(valid_in),
        .data_out(data_out), .valid_out(valid_out),
        .schedule_error(schedule_error)
    );

    task load_session;
        input [63:0] seed;
        input [63:0] counter;
        begin
            @(negedge clk);
            init_lfsr = seed;
            init_byte_counter = counter;
            load_state = 1'b1;
            valid_in = 1'b0;
            @(negedge clk);
            load_state = 1'b0;
            #1;
            if (dut.expected_byte_counter !== counter || schedule_error) begin
                $display("FAIL load counter=%016x got expected=%016x error=%x",
                         counter, dut.expected_byte_counter, schedule_error);
                errors = errors + 1;
            end
        end
    endtask

    task check_accept;
        input [7:0] input_byte;
        input [7:0] mask;
        input [63:0] counter;
        input [7:0] expected_output;
        reg [63:0] lfsr_before;
        begin
            @(negedge clk);
            data_in = input_byte;
            center_mask = mask;
            absolute_byte_counter = counter;
            valid_in = 1'b1;
            lfsr_before = dut.lfsr;
            #1;
            if (dut.expected_byte_counter !== counter) begin
                $display("FAIL accept pre-counter got=%016x want=%016x",
                         dut.expected_byte_counter, counter);
                errors = errors + 1;
            end
            if (dut.r4_out_fwd !== input_byte ||
                dut.center_out !== expected_output ||
                dut.center_out !== (input_byte ^ mask)) begin
                $display("FAIL accept center %02x xor %02x got=%02x want=%02x",
                         input_byte, mask, dut.center_out, expected_output);
                errors = errors + 1;
            end
            @(posedge clk);
            #1;
            if (!valid_out || data_out !== expected_output) begin
                $display("FAIL accept output valid=%x data=%02x want=%02x",
                         valid_out, data_out, expected_output);
                errors = errors + 1;
            end
            if (schedule_error || dut.expected_byte_counter !== counter + 64'd1) begin
                $display("FAIL accept schedule error=%x counter=%016x want=%016x",
                         schedule_error, dut.expected_byte_counter, counter + 64'd1);
                errors = errors + 1;
            end
            if (dut.lfsr === lfsr_before) begin
                $display("FAIL accept did not step lfsr=%016x", dut.lfsr);
                errors = errors + 1;
            end
            @(negedge clk);
            valid_in = 1'b0;
        end
    endtask

    task check_reject;
        input [63:0] supplied_counter;
        input [63:0] expected_counter;
        reg [63:0] lfsr_before;
        reg [31:0] offsets_before;
        reg [7:0] output_before;
        begin
            @(negedge clk);
            data_in = 8'hc7;
            center_mask = 8'h3d;
            absolute_byte_counter = supplied_counter;
            valid_in = 1'b1;
            lfsr_before = dut.lfsr;
            offsets_before = {dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4};
            output_before = data_out;
            @(posedge clk);
            #1;
            if (valid_out || data_out !== output_before) begin
                $display("FAIL reject emitted valid=%x data=%02x prior=%02x",
                         valid_out, data_out, output_before);
                errors = errors + 1;
            end
            if (!schedule_error) begin
                $display("FAIL reject did not set schedule_error");
                errors = errors + 1;
            end
            if (dut.expected_byte_counter !== expected_counter ||
                dut.lfsr !== lfsr_before ||
                {dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4} !== offsets_before) begin
                $display("FAIL reject stepped counter=%016x/%016x lfsr=%016x/%016x offsets=%08x/%08x",
                         dut.expected_byte_counter, expected_counter,
                         dut.lfsr, lfsr_before,
                         {dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4}, offsets_before);
                errors = errors + 1;
            end
            @(negedge clk);
            valid_in = 1'b0;
            @(posedge clk);
            #1;
            if (!schedule_error || valid_out ||
                dut.expected_byte_counter !== expected_counter ||
                dut.lfsr !== lfsr_before ||
                {dut.offset_r1, dut.offset_r2, dut.offset_r3, dut.offset_r4} !== offsets_before) begin
                $display("FAIL reject error was not sticky or state moved while idle");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Explicitly load all nine fixture-v4 tables as identity permutations.
        for (table_index = 0; table_index < 9; table_index = table_index + 1) begin
            for (address_index = 0; address_index < 256; address_index = address_index + 1) begin
                @(negedge clk);
                wr_en = 1'b1;
                wr_sel = table_index[3:0];
                wr_addr = address_index[7:0];
                wr_data = address_index[7:0];
            end
        end
        @(negedge clk);
        wr_en = 1'b0;

        load_session(64'h0123456789abcdef, 64'd42);
        check_accept(8'ha5, 8'h00, 64'd42, 8'ha5);
        check_accept(8'h3c, 8'h5a, 64'd43, 8'h66);

        // Expected counter is now 44. A counter of 45 must be rejected without
        // producing output or moving any cipher/schedule state.
        check_reject(64'd45, 64'd44);

        // Loading a session clears the sticky error. UInt64.max is exhausted
        // rather than wrapping and must be rejected even when it matches.
        load_session(64'hfedcba9876543210, 64'hffffffffffffffff);
        check_reject(64'hffffffffffffffff, 64'hffffffffffffffff);

        if (errors == 0)
            $display("PASS: fixture-v4 center XOR and counter schedule acceptance/rejection");
        else
            $display("FAIL: fixture-v4 center directed vectors errors=%0d", errors);
        $finish(errors == 0 ? 0 : 1);
    end
endmodule
