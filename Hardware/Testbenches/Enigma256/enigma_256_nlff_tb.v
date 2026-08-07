`timescale 1ns / 1ps

// Independent fixed-vector regression for the E256-v2/gen0 native NLFF.
module enigma_256_nlff_tb;
    reg  [63:0] lfsr;
    wire step_r1;
    wire step_r2;
    wire step_r3;
    wire step_r4;
    integer checks;

    enigma_256_nlff_combo dut (
        .lfsr(lfsr),
        .step_r1(step_r1),
        .step_r2(step_r2),
        .step_r3(step_r3),
        .step_r4(step_r4)
    );

    task check_mask;
        input [63:0] state;
        input [3:0] expected_r1_to_r4;
        begin
            lfsr = state;
            #1;
            checks = checks + 1;
            if ({step_r1, step_r2, step_r3, step_r4} !== expected_r1_to_r4) begin
                $display(
                    "FAIL: state=%016h got=%b%b%b%b expected=%04b",
                    state, step_r1, step_r2, step_r3, step_r4, expected_r1_to_r4
                );
                $fatal(1);
            end
        end
    endtask

    initial begin
        checks = 0;
        check_mask(64'h0000000000000000, 4'b0000);
        check_mask(64'h0000000000000001, 4'b0100);
        check_mask(64'h0123456789abcdef, 4'b1010);
        check_mask(64'hffffffffffffffff, 4'b1010);
        check_mask(64'hd891a2b3c4d5e6f7, 4'b1011);
        check_mask(64'hb448d159e26af37b, 4'b0111);
        check_mask(64'h612ecbb1347b9ee4, 4'b0011);
        check_mask(64'h309765d89a3dcf72, 4'b0011);
        check_mask(64'h184bb2ec4d1ee7b9, 4'b1000);
        check_mask(64'hc284bb2ec4d1ee7b, 4'b1001);
        check_mask(64'hc0be3a6e926e3a6e, 4'b0001);
        check_mask(64'h16f2abbbe6663b1c, 4'b0000);
        check_mask(64'h8000000000000001, 4'b0100);
        check_mask(64'ha5a5a5a5a5a5a5a5, 4'b0100);
        $display("PASS: E256-v2/gen0 native NLFF matched %0d fixed vectors", checks);
        $finish;
    end
endmodule
