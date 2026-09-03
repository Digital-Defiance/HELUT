`timescale 1ns / 1ps

module enigma_256_v3_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg wr_en = 1'b0;
    reg [3:0] wr_sel = 4'd0;
    reg [7:0] wr_addr = 8'd0;
    reg [7:0] wr_data = 8'd0;

    reg load_dut = 1'b0;
    reg load_control = 1'b0;
    reg [63:0] init_lfsr = 64'h0123456789abcdef;
    reg [7:0] init_r1_pos = 8'h11;
    reg [7:0] init_r2_pos = 8'h22;
    reg [7:0] init_r3_pos = 8'h33;
    reg [7:0] init_r4_pos = 8'h44;
    reg [63:0] init_byte_counter = 64'd0;

    reg [7:0] data_in = 8'd0;
    reg [7:0] center_mask = 8'd0;
    reg [63:0] absolute_byte_counter = 64'd0;
    reg valid_in = 1'b0;

    wire [7:0] dut_data_out;
    wire dut_valid_out;
    wire dut_schedule_error;
    wire dut_configuration_error;
    wire [7:0] control_data_out;
    wire control_valid_out;
    wire control_schedule_error;
    wire control_configuration_error;

    reg [63:0] nlff_state = 64'd1;
    wire v2_r1, v2_r2, v2_r3, v2_r4;
    wire v3_r1, v3_r2, v3_r3, v3_r4;

    enigma_256_core_v3 dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .load_state(load_dut), .init_lfsr(init_lfsr),
        .init_r1_pos(init_r1_pos), .init_r2_pos(init_r2_pos),
        .init_r3_pos(init_r3_pos), .init_r4_pos(init_r4_pos),
        .init_byte_counter(init_byte_counter),
        .data_in(data_in), .center_mask(center_mask),
        .absolute_byte_counter(absolute_byte_counter), .valid_in(valid_in),
        .data_out(dut_data_out), .valid_out(dut_valid_out),
        .schedule_error(dut_schedule_error),
        .configuration_error(dut_configuration_error)
    );

    enigma_256_core_v3 control_core (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .load_state(load_control), .init_lfsr(init_lfsr),
        .init_r1_pos(init_r1_pos), .init_r2_pos(init_r2_pos),
        .init_r3_pos(init_r3_pos), .init_r4_pos(init_r4_pos),
        .init_byte_counter(init_byte_counter),
        .data_in(data_in), .center_mask(center_mask),
        .absolute_byte_counter(absolute_byte_counter), .valid_in(valid_in),
        .data_out(control_data_out), .valid_out(control_valid_out),
        .schedule_error(control_schedule_error),
        .configuration_error(control_configuration_error)
    );

    enigma_256_nlff_combo v2_nlff (
        .lfsr(nlff_state), .step_r1(v2_r1), .step_r2(v2_r2),
        .step_r3(v2_r3), .step_r4(v2_r4)
    );
    enigma_256_nlff_v3_combo v3_nlff (
        .lfsr(nlff_state), .step_r1(v3_r1), .step_r2(v3_r2),
        .step_r3(v3_r3), .step_r4(v3_r4)
    );

    task pulse_both_loads;
        begin
            @(negedge clk);
            load_dut = 1'b1;
            load_control = 1'b1;
            @(posedge clk); #1;
            load_dut = 1'b0;
            load_control = 1'b0;
        end
    endtask

    task send_and_compare;
        input [63:0] counter;
        input [7:0] value;
        input [7:0] mask;
        begin
            @(negedge clk);
            absolute_byte_counter = counter;
            data_in = value;
            center_mask = mask;
            valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0;
            if (!dut_valid_out || !control_valid_out) begin
                $display("FAIL v3 valid_out missing at counter %0d", counter);
                $fatal(1);
            end
            if (dut_schedule_error || control_schedule_error) begin
                $display("FAIL unexpected schedule error at counter %0d", counter);
                $fatal(1);
            end
            if (dut_data_out !== control_data_out) begin
                $display("FAIL rejected load changed active state at counter %0d: %02x != %02x",
                         counter, dut_data_out, control_data_out);
                $fatal(1);
            end
        end
    endtask

    task send_and_expect_quiescent;
        input [63:0] counter;
        input [7:0] value;
        input [7:0] mask;
        reg [63:0] lfsr_before;
        reg [31:0] offsets_before;
        reg [63:0] expected_counter_before;
        begin
            lfsr_before = dut.core.lfsr;
            offsets_before = {
                dut.core.offset_r1, dut.core.offset_r2,
                dut.core.offset_r3, dut.core.offset_r4
            };
            expected_counter_before = dut.core.expected_byte_counter;
            @(negedge clk);
            absolute_byte_counter = counter;
            data_in = value;
            center_mask = mask;
            valid_in = 1'b1;
            @(posedge clk); #1;
            valid_in = 1'b0;
            if (dut_valid_out || dut_schedule_error) begin
                $display("FAIL unarmed v3 core accepted payload at counter %0d", counter);
                $fatal(1);
            end
            if (!dut_configuration_error || dut.configuration_armed) begin
                $display("FAIL unarmed payload did not preserve configuration fault");
                $fatal(1);
            end
            if (dut.core.lfsr !== lfsr_before ||
                {dut.core.offset_r1, dut.core.offset_r2,
                 dut.core.offset_r3, dut.core.offset_r4} !== offsets_before ||
                dut.core.expected_byte_counter !== expected_counter_before) begin
                $display("FAIL unarmed payload changed active core state");
                $fatal(1);
            end
        end
    endtask

    reg [63:0] state_before_rejected_load;
    reg [31:0] offsets_before_rejected_load;
    reg [63:0] counter_before_rejected_load;
    integer sample;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // The versioned v3 include must preserve the explicitly frozen NLFF.
        for (sample = 0; sample < 1024; sample = sample + 1) begin
            nlff_state = (64'h9e3779b97f4a7c15 * sample) ^ 64'h0123456789abcdef;
            #1;
            if ({v2_r4, v2_r3, v2_r2, v2_r1} !== {v3_r4, v3_r3, v3_r2, v3_r1}) begin
                $display("FAIL v2/v3 NLFF mismatch at sample %0d", sample);
                $fatal(1);
            end
        end

        // Reset alone is not a configuration. Payload cannot arm or advance it.
        send_and_expect_quiescent(64'd0, 8'h96, 8'h69);

        init_lfsr = 64'h0123456789abcdef;
        init_r1_pos = 8'h11;
        init_r2_pos = 8'h22;
        init_r3_pos = 8'h33;
        init_r4_pos = 8'h44;
        init_byte_counter = 64'd0;
        pulse_both_loads();
        if (dut_configuration_error || control_configuration_error ||
            !dut.configuration_armed || !control_core.configuration_armed) begin
            $display("FAIL valid nonzero state load did not arm configuration");
            $fatal(1);
        end

        send_and_compare(64'd0, 8'h3c, 8'ha5);

        // Attempt to replace only DUT state with malformed zero and unrelated
        // offsets/counter. The wrapper must reject before the active core sees it,
        // disarm traffic, and preserve the physically retained state.
        state_before_rejected_load = dut.core.lfsr;
        offsets_before_rejected_load = {
            dut.core.offset_r1, dut.core.offset_r2,
            dut.core.offset_r3, dut.core.offset_r4
        };
        counter_before_rejected_load = dut.core.expected_byte_counter;
        @(negedge clk);
        init_lfsr = 64'd0;
        init_r1_pos = 8'hee;
        init_r2_pos = 8'hdd;
        init_r3_pos = 8'hcc;
        init_r4_pos = 8'hbb;
        init_byte_counter = 64'h1111222233334444;
        load_dut = 1'b1;
        load_control = 1'b0;
        @(posedge clk); #1;
        load_dut = 1'b0;
        if (!dut_configuration_error || dut.configuration_armed) begin
            $display("FAIL zero-state load did not raise error and disarm traffic");
            $fatal(1);
        end
        if (control_configuration_error || !control_core.configuration_armed) begin
            $display("FAIL control configuration changed during rejected DUT load");
            $fatal(1);
        end
        if (dut.core.lfsr !== state_before_rejected_load ||
            {dut.core.offset_r1, dut.core.offset_r2,
             dut.core.offset_r3, dut.core.offset_r4} !== offsets_before_rejected_load ||
            dut.core.expected_byte_counter !== counter_before_rejected_load) begin
            $display("FAIL rejected zero load changed retained active state");
            $fatal(1);
        end

        send_and_expect_quiescent(64'd1, 8'hc3, 8'h5a);
        send_and_expect_quiescent(64'd2, 8'h00, 8'hff);

        // A subsequent valid state load clears the sticky configuration error.
        init_lfsr = 64'hfedcba9876543211;
        init_r1_pos = 8'h01;
        init_r2_pos = 8'h02;
        init_r3_pos = 8'h03;
        init_r4_pos = 8'h04;
        init_byte_counter = 64'd9;
        pulse_both_loads();
        if (dut_configuration_error || control_configuration_error ||
            !dut.configuration_armed || !control_core.configuration_armed) begin
            $display("FAIL valid reload did not clear error and re-arm traffic");
            $fatal(1);
        end
        send_and_compare(64'd9, 8'h7e, 8'h81);

        $display("PASS E256-v3 RTL zero-state rejection, traffic quiescence, and NLFF include identity");
        $finish;
    end
endmodule
