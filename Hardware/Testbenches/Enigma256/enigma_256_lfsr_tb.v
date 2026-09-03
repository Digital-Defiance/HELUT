`timescale 1ns / 1ps

// Independent checkpoint regression for the E256-v2 right-shift/LSB LFSR.
module enigma_256_lfsr_tb;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         load_state = 1'b0;
    reg  [63:0] init_lfsr = 64'h0123456789abcdef;
    reg         step = 1'b0;
    wire [63:0] lfsr;
    wire step_r1, step_r2, step_r3, step_r4;
    integer clock_count;

    enigma_256_step_cone dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_state(load_state),
        .init_lfsr(init_lfsr),
        .step(step),
        .lfsr(lfsr),
        .step_r1(step_r1),
        .step_r2(step_r2),
        .step_r3(step_r3),
        .step_r4(step_r4)
    );

    task tick;
        begin
            #5 clk = 1'b1;
            #1;
            clk = 1'b0;
            #4;
        end
    endtask

    task check_state;
        input integer at_clock;
        input [63:0] expected;
        begin
            if (lfsr !== expected) begin
                $display("FAIL: clock %0d got %016h expected %016h", at_clock, lfsr, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        tick;
        rst_n = 1'b1;
        load_state = 1'b1;
        tick;
        load_state = 1'b0;
        check_state(0, 64'h0123456789abcdef);

        for (clock_count = 1; clock_count <= 1024; clock_count = clock_count + 1) begin
            step = 1'b1;
            tick;
            step = 1'b0;
            if (lfsr == 64'd0) begin
                $display("FAIL: zero lock at clock %0d", clock_count);
                $fatal(1);
            end
            case (clock_count)
                1:    check_state(1,    64'hd891a2b3c4d5e6f7);
                2:    check_state(2,    64'hb448d159e26af37b);
                58:   check_state(58,   64'h612ecbb1347b9ee4);
                59:   check_state(59,   64'h309765d89a3dcf72);
                60:   check_state(60,   64'h184bb2ec4d1ee7b9);
                64:   check_state(64,   64'hc284bb2ec4d1ee7b);
                128:  check_state(128,  64'hc0be3a6e926e3a6e);
                1024: check_state(1024, 64'h16f2abbbe6663b1c);
                default: ;
            endcase
        end

        $display("PASS: E256-v2 LFSR matched independent checkpoints through 1024 clocks");
        $finish;
    end
endmodule
