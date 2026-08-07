// HELUT Enigma core: 3-rotor sequential machine with sync resetn.
// Alphabet is A..Z encoded as 0..25 in the low 5 bits of each byte.
// Designed for Yosys `synth -flatten; abc -lut 2` → $_SDFF* / $lut netlist.

module enigma_core(
    input  wire       clk,
    input  wire       resetn,
    input  wire [7:0] ciphertext_char,
    output reg  [7:0] plaintext_char
);

    // Rotor positions (Grundstellung / stepping state), 0..25.
    reg [7:0] rotor_r;
    reg [7:0] rotor_m;
    reg [7:0] rotor_l;

    // Historical notch positions (Rotor III / II / I): V=21, E=4, Q=16.
    localparam [7:0] NOTCH_R = 8'd21;
    localparam [7:0] NOTCH_M = 8'd4;

    // --- Wiring tables (Enigma I) as combinational LUTs ---

    function automatic [7:0] clamp26;
        input [7:0] x;
        begin
            if (x >= 8'd26)
                clamp26 = 8'd0;
            else
                clamp26 = x;
        end
    endfunction

    function automatic [7:0] add26;
        input [7:0] a;
        input [7:0] b;
        reg [8:0] s;
        begin
            s = {1'b0, clamp26(a)} + {1'b0, clamp26(b)};
            if (s >= 9'd26)
                add26 = s[7:0] - 8'd26;
            else
                add26 = s[7:0];
        end
    endfunction

    function automatic [7:0] sub26;
        input [7:0] a;
        input [7:0] b;
        begin
            if (clamp26(a) >= clamp26(b))
                sub26 = clamp26(a) - clamp26(b);
            else
                sub26 = clamp26(a) + 8'd26 - clamp26(b);
        end
    endfunction

    // Rotor I forward: EKMFLGDQVZNTOWYHXUSPAIBRCJ
    function automatic [7:0] wir_i_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_i_fwd = 8'd4;
                8'd1:  wir_i_fwd = 8'd10;
                8'd2:  wir_i_fwd = 8'd12;
                8'd3:  wir_i_fwd = 8'd5;
                8'd4:  wir_i_fwd = 8'd11;
                8'd5:  wir_i_fwd = 8'd6;
                8'd6:  wir_i_fwd = 8'd3;
                8'd7:  wir_i_fwd = 8'd16;
                8'd8:  wir_i_fwd = 8'd21;
                8'd9:  wir_i_fwd = 8'd25;
                8'd10: wir_i_fwd = 8'd13;
                8'd11: wir_i_fwd = 8'd19;
                8'd12: wir_i_fwd = 8'd14;
                8'd13: wir_i_fwd = 8'd22;
                8'd14: wir_i_fwd = 8'd24;
                8'd15: wir_i_fwd = 8'd7;
                8'd16: wir_i_fwd = 8'd23;
                8'd17: wir_i_fwd = 8'd20;
                8'd18: wir_i_fwd = 8'd18;
                8'd19: wir_i_fwd = 8'd15;
                8'd20: wir_i_fwd = 8'd0;
                8'd21: wir_i_fwd = 8'd8;
                8'd22: wir_i_fwd = 8'd1;
                8'd23: wir_i_fwd = 8'd17;
                8'd24: wir_i_fwd = 8'd2;
                8'd25: wir_i_fwd = 8'd9;
                default: wir_i_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_i_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd4:  wir_i_rev = 8'd0;
                8'd10: wir_i_rev = 8'd1;
                8'd12: wir_i_rev = 8'd2;
                8'd5:  wir_i_rev = 8'd3;
                8'd11: wir_i_rev = 8'd4;
                8'd6:  wir_i_rev = 8'd5;
                8'd3:  wir_i_rev = 8'd6;
                8'd16: wir_i_rev = 8'd7;
                8'd21: wir_i_rev = 8'd8;
                8'd25: wir_i_rev = 8'd9;
                8'd13: wir_i_rev = 8'd10;
                8'd19: wir_i_rev = 8'd11;
                8'd14: wir_i_rev = 8'd12;
                8'd22: wir_i_rev = 8'd13;
                8'd24: wir_i_rev = 8'd14;
                8'd7:  wir_i_rev = 8'd15;
                8'd23: wir_i_rev = 8'd16;
                8'd20: wir_i_rev = 8'd17;
                8'd18: wir_i_rev = 8'd18;
                8'd15: wir_i_rev = 8'd19;
                8'd0:  wir_i_rev = 8'd20;
                8'd8:  wir_i_rev = 8'd21;
                8'd1:  wir_i_rev = 8'd22;
                8'd17: wir_i_rev = 8'd23;
                8'd2:  wir_i_rev = 8'd24;
                8'd9:  wir_i_rev = 8'd25;
                default: wir_i_rev = 8'd0;
            endcase
        end
    endfunction

    // Rotor II forward: AJDKSIRUXBLHWTMCQGZNPYFVOE
    function automatic [7:0] wir_ii_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_ii_fwd = 8'd0;
                8'd1:  wir_ii_fwd = 8'd9;
                8'd2:  wir_ii_fwd = 8'd3;
                8'd3:  wir_ii_fwd = 8'd10;
                8'd4:  wir_ii_fwd = 8'd18;
                8'd5:  wir_ii_fwd = 8'd8;
                8'd6:  wir_ii_fwd = 8'd17;
                8'd7:  wir_ii_fwd = 8'd20;
                8'd8:  wir_ii_fwd = 8'd23;
                8'd9:  wir_ii_fwd = 8'd1;
                8'd10: wir_ii_fwd = 8'd11;
                8'd11: wir_ii_fwd = 8'd7;
                8'd12: wir_ii_fwd = 8'd22;
                8'd13: wir_ii_fwd = 8'd19;
                8'd14: wir_ii_fwd = 8'd12;
                8'd15: wir_ii_fwd = 8'd2;
                8'd16: wir_ii_fwd = 8'd16;
                8'd17: wir_ii_fwd = 8'd6;
                8'd18: wir_ii_fwd = 8'd25;
                8'd19: wir_ii_fwd = 8'd13;
                8'd20: wir_ii_fwd = 8'd15;
                8'd21: wir_ii_fwd = 8'd24;
                8'd22: wir_ii_fwd = 8'd5;
                8'd23: wir_ii_fwd = 8'd21;
                8'd24: wir_ii_fwd = 8'd14;
                8'd25: wir_ii_fwd = 8'd4;
                default: wir_ii_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_ii_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_ii_rev = 8'd0;
                8'd9:  wir_ii_rev = 8'd1;
                8'd3:  wir_ii_rev = 8'd2;
                8'd10: wir_ii_rev = 8'd3;
                8'd18: wir_ii_rev = 8'd4;
                8'd8:  wir_ii_rev = 8'd5;
                8'd17: wir_ii_rev = 8'd6;
                8'd20: wir_ii_rev = 8'd7;
                8'd23: wir_ii_rev = 8'd8;
                8'd1:  wir_ii_rev = 8'd9;
                8'd11: wir_ii_rev = 8'd10;
                8'd7:  wir_ii_rev = 8'd11;
                8'd22: wir_ii_rev = 8'd12;
                8'd19: wir_ii_rev = 8'd13;
                8'd12: wir_ii_rev = 8'd14;
                8'd2:  wir_ii_rev = 8'd15;
                8'd16: wir_ii_rev = 8'd16;
                8'd6:  wir_ii_rev = 8'd17;
                8'd25: wir_ii_rev = 8'd18;
                8'd13: wir_ii_rev = 8'd19;
                8'd15: wir_ii_rev = 8'd20;
                8'd24: wir_ii_rev = 8'd21;
                8'd5:  wir_ii_rev = 8'd22;
                8'd21: wir_ii_rev = 8'd23;
                8'd14: wir_ii_rev = 8'd24;
                8'd4:  wir_ii_rev = 8'd25;
                default: wir_ii_rev = 8'd0;
            endcase
        end
    endfunction

    // Rotor III forward: BDFHJLCPRTXVZNYEIWGAKMUSQO
    function automatic [7:0] wir_iii_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_iii_fwd = 8'd1;
                8'd1:  wir_iii_fwd = 8'd3;
                8'd2:  wir_iii_fwd = 8'd5;
                8'd3:  wir_iii_fwd = 8'd7;
                8'd4:  wir_iii_fwd = 8'd9;
                8'd5:  wir_iii_fwd = 8'd11;
                8'd6:  wir_iii_fwd = 8'd2;
                8'd7:  wir_iii_fwd = 8'd15;
                8'd8:  wir_iii_fwd = 8'd17;
                8'd9:  wir_iii_fwd = 8'd19;
                8'd10: wir_iii_fwd = 8'd23;
                8'd11: wir_iii_fwd = 8'd21;
                8'd12: wir_iii_fwd = 8'd25;
                8'd13: wir_iii_fwd = 8'd13;
                8'd14: wir_iii_fwd = 8'd24;
                8'd15: wir_iii_fwd = 8'd4;
                8'd16: wir_iii_fwd = 8'd8;
                8'd17: wir_iii_fwd = 8'd22;
                8'd18: wir_iii_fwd = 8'd6;
                8'd19: wir_iii_fwd = 8'd0;
                8'd20: wir_iii_fwd = 8'd10;
                8'd21: wir_iii_fwd = 8'd12;
                8'd22: wir_iii_fwd = 8'd20;
                8'd23: wir_iii_fwd = 8'd18;
                8'd24: wir_iii_fwd = 8'd16;
                8'd25: wir_iii_fwd = 8'd14;
                default: wir_iii_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_iii_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd1:  wir_iii_rev = 8'd0;
                8'd3:  wir_iii_rev = 8'd1;
                8'd5:  wir_iii_rev = 8'd2;
                8'd7:  wir_iii_rev = 8'd3;
                8'd9:  wir_iii_rev = 8'd4;
                8'd11: wir_iii_rev = 8'd5;
                8'd2:  wir_iii_rev = 8'd6;
                8'd15: wir_iii_rev = 8'd7;
                8'd17: wir_iii_rev = 8'd8;
                8'd19: wir_iii_rev = 8'd9;
                8'd23: wir_iii_rev = 8'd10;
                8'd21: wir_iii_rev = 8'd11;
                8'd25: wir_iii_rev = 8'd12;
                8'd13: wir_iii_rev = 8'd13;
                8'd24: wir_iii_rev = 8'd14;
                8'd4:  wir_iii_rev = 8'd15;
                8'd8:  wir_iii_rev = 8'd16;
                8'd22: wir_iii_rev = 8'd17;
                8'd6:  wir_iii_rev = 8'd18;
                8'd0:  wir_iii_rev = 8'd19;
                8'd10: wir_iii_rev = 8'd20;
                8'd12: wir_iii_rev = 8'd21;
                8'd20: wir_iii_rev = 8'd22;
                8'd18: wir_iii_rev = 8'd23;
                8'd16: wir_iii_rev = 8'd24;
                8'd14: wir_iii_rev = 8'd25;
                default: wir_iii_rev = 8'd0;
            endcase
        end
    endfunction

    // Reflector B: YRUHQSLDPXNGOKMIEBFZCWVJAT
    function automatic [7:0] reflector_b;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  reflector_b = 8'd24;
                8'd1:  reflector_b = 8'd17;
                8'd2:  reflector_b = 8'd20;
                8'd3:  reflector_b = 8'd7;
                8'd4:  reflector_b = 8'd16;
                8'd5:  reflector_b = 8'd18;
                8'd6:  reflector_b = 8'd11;
                8'd7:  reflector_b = 8'd3;
                8'd8:  reflector_b = 8'd15;
                8'd9:  reflector_b = 8'd23;
                8'd10: reflector_b = 8'd13;
                8'd11: reflector_b = 8'd6;
                8'd12: reflector_b = 8'd14;
                8'd13: reflector_b = 8'd10;
                8'd14: reflector_b = 8'd12;
                8'd15: reflector_b = 8'd8;
                8'd16: reflector_b = 8'd4;
                8'd17: reflector_b = 8'd1;
                8'd18: reflector_b = 8'd5;
                8'd19: reflector_b = 8'd25;
                8'd20: reflector_b = 8'd2;
                8'd21: reflector_b = 8'd22;
                8'd22: reflector_b = 8'd21;
                8'd23: reflector_b = 8'd9;
                8'd24: reflector_b = 8'd0;
                8'd25: reflector_b = 8'd19;
                default: reflector_b = 8'd0;
            endcase
        end
    endfunction

    // Identity plugboard (Steckerbrett) — kept as an explicit LUT stage.
    function automatic [7:0] plugboard;
        input [7:0] x;
        begin
            plugboard = clamp26(x);
        end
    endfunction

    function automatic [7:0] apply_rotor_fwd;
        input [7:0] ch;
        input [7:0] pos;
        input [1:0] which; // 0=III (fast), 1=II, 2=I (slow)
        reg [7:0] shifted, wired, unshifted;
        begin
            shifted = add26(ch, pos);
            case (which)
                2'd0: wired = wir_iii_fwd(shifted);
                2'd1: wired = wir_ii_fwd(shifted);
                default: wired = wir_i_fwd(shifted);
            endcase
            unshifted = sub26(wired, pos);
            apply_rotor_fwd = unshifted;
        end
    endfunction

    function automatic [7:0] apply_rotor_rev;
        input [7:0] ch;
        input [7:0] pos;
        input [1:0] which;
        reg [7:0] shifted, wired, unshifted;
        begin
            shifted = add26(ch, pos);
            case (which)
                2'd0: wired = wir_iii_rev(shifted);
                2'd1: wired = wir_ii_rev(shifted);
                default: wired = wir_i_rev(shifted);
            endcase
            unshifted = sub26(wired, pos);
            apply_rotor_rev = unshifted;
        end
    endfunction

    function automatic [7:0] scramble;
        input [7:0] ct;
        input [7:0] pos_r;
        input [7:0] pos_m;
        input [7:0] pos_l;
        reg [7:0] x;
        begin
            x = plugboard(ct);
            x = apply_rotor_fwd(x, pos_r, 2'd0);
            x = apply_rotor_fwd(x, pos_m, 2'd1);
            x = apply_rotor_fwd(x, pos_l, 2'd2);
            x = reflector_b(x);
            x = apply_rotor_rev(x, pos_l, 2'd2);
            x = apply_rotor_rev(x, pos_m, 2'd1);
            x = apply_rotor_rev(x, pos_r, 2'd0);
            scramble = plugboard(x);
        end
    endfunction

    // Combinational next-state stepping (double-stepping Enigma mechanics).
    wire step_m = (rotor_r == NOTCH_R) || (rotor_m == NOTCH_M);
    wire step_l = (rotor_m == NOTCH_M);

    wire [7:0] next_r = add26(rotor_r, 8'd1);
    wire [7:0] next_m = step_m ? add26(rotor_m, 8'd1) : rotor_m;
    wire [7:0] next_l = step_l ? add26(rotor_l, 8'd1) : rotor_l;

    // Encrypt uses post-step positions (classic Enigma: step, then scramble).
    wire [7:0] scrambled = scramble(ciphertext_char, next_r, next_m, next_l);

    // Synchronous reset / clocked state — synthesizes to $_SDFF* cells.
    always @(posedge clk) begin
        if (!resetn) begin
            rotor_r         <= 8'd0;
            rotor_m         <= 8'd0;
            rotor_l         <= 8'd0;
            plaintext_char  <= 8'd0;
        end else begin
            rotor_r         <= next_r;
            rotor_m         <= next_m;
            rotor_l         <= next_l;
            plaintext_char  <= scrambled;
        end
    end

endmodule
