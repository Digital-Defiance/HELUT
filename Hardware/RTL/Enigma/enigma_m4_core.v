// HELUT Enigma M4 core for P1030680 / M-Thetis tensor bombe.
// Static Greek Zusatzwalze + thin UKW + three stepping naval rotors.
// Linguistic score: accumulate German/naval trigram hits (EIN,CHT,NDE,VON,UUU,…).
// Default Walzenlage: γ / IV-III-VIII / thin B / rings AAAA / identity stecker
// (recompile with parameters for other Thetis hypotheses).
// Alphabet A..Z = 0..25 in low 5 bits.

module enigma_m4_core(
    input  wire        clk,
    input  wire        resetn,
    input  wire [7:0]  ciphertext_char,
    output reg  [7:0]  plaintext_char,
    output reg  [15:0] linguistic_score
);

    // --- Partition parameters (outer Thetis hypotheses) ---
    // GREEK_SEL: 0=beta, 1=gamma
    // UKW_SEL:   0=thin B, 1=thin C
    // ROTOR_{L,M,R}: 1..8 naval Walzen
    // GREEK_POS: fixed Greek window for this netlist (26³ batch sweeps L/M/R only)
    parameter integer GREEK_SEL = 1;
    parameter integer UKW_SEL   = 0;
    parameter integer ROTOR_L   = 4;
    parameter integer ROTOR_M   = 3;
    parameter integer ROTOR_R   = 8;
    parameter integer GREEK_POS = 0;

    // Stepping rotor positions (Grundstellung / message-key L/M/R).
    reg [7:0] rotor_r;
    reg [7:0] rotor_m;
    reg [7:0] rotor_l;

    // Trigram shift register for linguistic scoring sub-circuit.
    reg [7:0] prev_plain_1;
    reg [7:0] prev_plain_0;
    reg [1:0] letters_seen; // 0,1,2+


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
                8'd10:  wir_i_fwd = 8'd13;
                8'd11:  wir_i_fwd = 8'd19;
                8'd12:  wir_i_fwd = 8'd14;
                8'd13:  wir_i_fwd = 8'd22;
                8'd14:  wir_i_fwd = 8'd24;
                8'd15:  wir_i_fwd = 8'd7;
                8'd16:  wir_i_fwd = 8'd23;
                8'd17:  wir_i_fwd = 8'd20;
                8'd18:  wir_i_fwd = 8'd18;
                8'd19:  wir_i_fwd = 8'd15;
                8'd20:  wir_i_fwd = 8'd0;
                8'd21:  wir_i_fwd = 8'd8;
                8'd22:  wir_i_fwd = 8'd1;
                8'd23:  wir_i_fwd = 8'd17;
                8'd24:  wir_i_fwd = 8'd2;
                8'd25:  wir_i_fwd = 8'd9;
                default: wir_i_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_i_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_i_rev = 8'd20;
                8'd1:  wir_i_rev = 8'd22;
                8'd2:  wir_i_rev = 8'd24;
                8'd3:  wir_i_rev = 8'd6;
                8'd4:  wir_i_rev = 8'd0;
                8'd5:  wir_i_rev = 8'd3;
                8'd6:  wir_i_rev = 8'd5;
                8'd7:  wir_i_rev = 8'd15;
                8'd8:  wir_i_rev = 8'd21;
                8'd9:  wir_i_rev = 8'd25;
                8'd10:  wir_i_rev = 8'd1;
                8'd11:  wir_i_rev = 8'd4;
                8'd12:  wir_i_rev = 8'd2;
                8'd13:  wir_i_rev = 8'd10;
                8'd14:  wir_i_rev = 8'd12;
                8'd15:  wir_i_rev = 8'd19;
                8'd16:  wir_i_rev = 8'd7;
                8'd17:  wir_i_rev = 8'd23;
                8'd18:  wir_i_rev = 8'd18;
                8'd19:  wir_i_rev = 8'd11;
                8'd20:  wir_i_rev = 8'd17;
                8'd21:  wir_i_rev = 8'd8;
                8'd22:  wir_i_rev = 8'd13;
                8'd23:  wir_i_rev = 8'd16;
                8'd24:  wir_i_rev = 8'd14;
                8'd25:  wir_i_rev = 8'd9;
                default: wir_i_rev = 8'd0;
            endcase
        end
    endfunction

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
                8'd10:  wir_ii_fwd = 8'd11;
                8'd11:  wir_ii_fwd = 8'd7;
                8'd12:  wir_ii_fwd = 8'd22;
                8'd13:  wir_ii_fwd = 8'd19;
                8'd14:  wir_ii_fwd = 8'd12;
                8'd15:  wir_ii_fwd = 8'd2;
                8'd16:  wir_ii_fwd = 8'd16;
                8'd17:  wir_ii_fwd = 8'd6;
                8'd18:  wir_ii_fwd = 8'd25;
                8'd19:  wir_ii_fwd = 8'd13;
                8'd20:  wir_ii_fwd = 8'd15;
                8'd21:  wir_ii_fwd = 8'd24;
                8'd22:  wir_ii_fwd = 8'd5;
                8'd23:  wir_ii_fwd = 8'd21;
                8'd24:  wir_ii_fwd = 8'd14;
                8'd25:  wir_ii_fwd = 8'd4;
                default: wir_ii_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_ii_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_ii_rev = 8'd0;
                8'd1:  wir_ii_rev = 8'd9;
                8'd2:  wir_ii_rev = 8'd15;
                8'd3:  wir_ii_rev = 8'd2;
                8'd4:  wir_ii_rev = 8'd25;
                8'd5:  wir_ii_rev = 8'd22;
                8'd6:  wir_ii_rev = 8'd17;
                8'd7:  wir_ii_rev = 8'd11;
                8'd8:  wir_ii_rev = 8'd5;
                8'd9:  wir_ii_rev = 8'd1;
                8'd10:  wir_ii_rev = 8'd3;
                8'd11:  wir_ii_rev = 8'd10;
                8'd12:  wir_ii_rev = 8'd14;
                8'd13:  wir_ii_rev = 8'd19;
                8'd14:  wir_ii_rev = 8'd24;
                8'd15:  wir_ii_rev = 8'd20;
                8'd16:  wir_ii_rev = 8'd16;
                8'd17:  wir_ii_rev = 8'd6;
                8'd18:  wir_ii_rev = 8'd4;
                8'd19:  wir_ii_rev = 8'd13;
                8'd20:  wir_ii_rev = 8'd7;
                8'd21:  wir_ii_rev = 8'd23;
                8'd22:  wir_ii_rev = 8'd12;
                8'd23:  wir_ii_rev = 8'd8;
                8'd24:  wir_ii_rev = 8'd21;
                8'd25:  wir_ii_rev = 8'd18;
                default: wir_ii_rev = 8'd0;
            endcase
        end
    endfunction

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
                8'd10:  wir_iii_fwd = 8'd23;
                8'd11:  wir_iii_fwd = 8'd21;
                8'd12:  wir_iii_fwd = 8'd25;
                8'd13:  wir_iii_fwd = 8'd13;
                8'd14:  wir_iii_fwd = 8'd24;
                8'd15:  wir_iii_fwd = 8'd4;
                8'd16:  wir_iii_fwd = 8'd8;
                8'd17:  wir_iii_fwd = 8'd22;
                8'd18:  wir_iii_fwd = 8'd6;
                8'd19:  wir_iii_fwd = 8'd0;
                8'd20:  wir_iii_fwd = 8'd10;
                8'd21:  wir_iii_fwd = 8'd12;
                8'd22:  wir_iii_fwd = 8'd20;
                8'd23:  wir_iii_fwd = 8'd18;
                8'd24:  wir_iii_fwd = 8'd16;
                8'd25:  wir_iii_fwd = 8'd14;
                default: wir_iii_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_iii_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_iii_rev = 8'd19;
                8'd1:  wir_iii_rev = 8'd0;
                8'd2:  wir_iii_rev = 8'd6;
                8'd3:  wir_iii_rev = 8'd1;
                8'd4:  wir_iii_rev = 8'd15;
                8'd5:  wir_iii_rev = 8'd2;
                8'd6:  wir_iii_rev = 8'd18;
                8'd7:  wir_iii_rev = 8'd3;
                8'd8:  wir_iii_rev = 8'd16;
                8'd9:  wir_iii_rev = 8'd4;
                8'd10:  wir_iii_rev = 8'd20;
                8'd11:  wir_iii_rev = 8'd5;
                8'd12:  wir_iii_rev = 8'd21;
                8'd13:  wir_iii_rev = 8'd13;
                8'd14:  wir_iii_rev = 8'd25;
                8'd15:  wir_iii_rev = 8'd7;
                8'd16:  wir_iii_rev = 8'd24;
                8'd17:  wir_iii_rev = 8'd8;
                8'd18:  wir_iii_rev = 8'd23;
                8'd19:  wir_iii_rev = 8'd9;
                8'd20:  wir_iii_rev = 8'd22;
                8'd21:  wir_iii_rev = 8'd11;
                8'd22:  wir_iii_rev = 8'd17;
                8'd23:  wir_iii_rev = 8'd10;
                8'd24:  wir_iii_rev = 8'd14;
                8'd25:  wir_iii_rev = 8'd12;
                default: wir_iii_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_iv_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_iv_fwd = 8'd4;
                8'd1:  wir_iv_fwd = 8'd18;
                8'd2:  wir_iv_fwd = 8'd14;
                8'd3:  wir_iv_fwd = 8'd21;
                8'd4:  wir_iv_fwd = 8'd15;
                8'd5:  wir_iv_fwd = 8'd25;
                8'd6:  wir_iv_fwd = 8'd9;
                8'd7:  wir_iv_fwd = 8'd0;
                8'd8:  wir_iv_fwd = 8'd24;
                8'd9:  wir_iv_fwd = 8'd16;
                8'd10:  wir_iv_fwd = 8'd20;
                8'd11:  wir_iv_fwd = 8'd8;
                8'd12:  wir_iv_fwd = 8'd17;
                8'd13:  wir_iv_fwd = 8'd7;
                8'd14:  wir_iv_fwd = 8'd23;
                8'd15:  wir_iv_fwd = 8'd11;
                8'd16:  wir_iv_fwd = 8'd13;
                8'd17:  wir_iv_fwd = 8'd5;
                8'd18:  wir_iv_fwd = 8'd19;
                8'd19:  wir_iv_fwd = 8'd6;
                8'd20:  wir_iv_fwd = 8'd10;
                8'd21:  wir_iv_fwd = 8'd3;
                8'd22:  wir_iv_fwd = 8'd2;
                8'd23:  wir_iv_fwd = 8'd12;
                8'd24:  wir_iv_fwd = 8'd22;
                8'd25:  wir_iv_fwd = 8'd1;
                default: wir_iv_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_iv_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_iv_rev = 8'd7;
                8'd1:  wir_iv_rev = 8'd25;
                8'd2:  wir_iv_rev = 8'd22;
                8'd3:  wir_iv_rev = 8'd21;
                8'd4:  wir_iv_rev = 8'd0;
                8'd5:  wir_iv_rev = 8'd17;
                8'd6:  wir_iv_rev = 8'd19;
                8'd7:  wir_iv_rev = 8'd13;
                8'd8:  wir_iv_rev = 8'd11;
                8'd9:  wir_iv_rev = 8'd6;
                8'd10:  wir_iv_rev = 8'd20;
                8'd11:  wir_iv_rev = 8'd15;
                8'd12:  wir_iv_rev = 8'd23;
                8'd13:  wir_iv_rev = 8'd16;
                8'd14:  wir_iv_rev = 8'd2;
                8'd15:  wir_iv_rev = 8'd4;
                8'd16:  wir_iv_rev = 8'd9;
                8'd17:  wir_iv_rev = 8'd12;
                8'd18:  wir_iv_rev = 8'd1;
                8'd19:  wir_iv_rev = 8'd18;
                8'd20:  wir_iv_rev = 8'd10;
                8'd21:  wir_iv_rev = 8'd3;
                8'd22:  wir_iv_rev = 8'd24;
                8'd23:  wir_iv_rev = 8'd14;
                8'd24:  wir_iv_rev = 8'd8;
                8'd25:  wir_iv_rev = 8'd5;
                default: wir_iv_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_v_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_v_fwd = 8'd21;
                8'd1:  wir_v_fwd = 8'd25;
                8'd2:  wir_v_fwd = 8'd1;
                8'd3:  wir_v_fwd = 8'd17;
                8'd4:  wir_v_fwd = 8'd6;
                8'd5:  wir_v_fwd = 8'd8;
                8'd6:  wir_v_fwd = 8'd19;
                8'd7:  wir_v_fwd = 8'd24;
                8'd8:  wir_v_fwd = 8'd20;
                8'd9:  wir_v_fwd = 8'd15;
                8'd10:  wir_v_fwd = 8'd18;
                8'd11:  wir_v_fwd = 8'd3;
                8'd12:  wir_v_fwd = 8'd13;
                8'd13:  wir_v_fwd = 8'd7;
                8'd14:  wir_v_fwd = 8'd11;
                8'd15:  wir_v_fwd = 8'd23;
                8'd16:  wir_v_fwd = 8'd0;
                8'd17:  wir_v_fwd = 8'd22;
                8'd18:  wir_v_fwd = 8'd12;
                8'd19:  wir_v_fwd = 8'd9;
                8'd20:  wir_v_fwd = 8'd16;
                8'd21:  wir_v_fwd = 8'd14;
                8'd22:  wir_v_fwd = 8'd5;
                8'd23:  wir_v_fwd = 8'd4;
                8'd24:  wir_v_fwd = 8'd2;
                8'd25:  wir_v_fwd = 8'd10;
                default: wir_v_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_v_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_v_rev = 8'd16;
                8'd1:  wir_v_rev = 8'd2;
                8'd2:  wir_v_rev = 8'd24;
                8'd3:  wir_v_rev = 8'd11;
                8'd4:  wir_v_rev = 8'd23;
                8'd5:  wir_v_rev = 8'd22;
                8'd6:  wir_v_rev = 8'd4;
                8'd7:  wir_v_rev = 8'd13;
                8'd8:  wir_v_rev = 8'd5;
                8'd9:  wir_v_rev = 8'd19;
                8'd10:  wir_v_rev = 8'd25;
                8'd11:  wir_v_rev = 8'd14;
                8'd12:  wir_v_rev = 8'd18;
                8'd13:  wir_v_rev = 8'd12;
                8'd14:  wir_v_rev = 8'd21;
                8'd15:  wir_v_rev = 8'd9;
                8'd16:  wir_v_rev = 8'd20;
                8'd17:  wir_v_rev = 8'd3;
                8'd18:  wir_v_rev = 8'd10;
                8'd19:  wir_v_rev = 8'd6;
                8'd20:  wir_v_rev = 8'd8;
                8'd21:  wir_v_rev = 8'd0;
                8'd22:  wir_v_rev = 8'd17;
                8'd23:  wir_v_rev = 8'd15;
                8'd24:  wir_v_rev = 8'd7;
                8'd25:  wir_v_rev = 8'd1;
                default: wir_v_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_vi_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_vi_fwd = 8'd9;
                8'd1:  wir_vi_fwd = 8'd15;
                8'd2:  wir_vi_fwd = 8'd6;
                8'd3:  wir_vi_fwd = 8'd21;
                8'd4:  wir_vi_fwd = 8'd14;
                8'd5:  wir_vi_fwd = 8'd20;
                8'd6:  wir_vi_fwd = 8'd12;
                8'd7:  wir_vi_fwd = 8'd5;
                8'd8:  wir_vi_fwd = 8'd24;
                8'd9:  wir_vi_fwd = 8'd16;
                8'd10:  wir_vi_fwd = 8'd1;
                8'd11:  wir_vi_fwd = 8'd4;
                8'd12:  wir_vi_fwd = 8'd13;
                8'd13:  wir_vi_fwd = 8'd7;
                8'd14:  wir_vi_fwd = 8'd25;
                8'd15:  wir_vi_fwd = 8'd17;
                8'd16:  wir_vi_fwd = 8'd3;
                8'd17:  wir_vi_fwd = 8'd10;
                8'd18:  wir_vi_fwd = 8'd0;
                8'd19:  wir_vi_fwd = 8'd18;
                8'd20:  wir_vi_fwd = 8'd23;
                8'd21:  wir_vi_fwd = 8'd11;
                8'd22:  wir_vi_fwd = 8'd8;
                8'd23:  wir_vi_fwd = 8'd2;
                8'd24:  wir_vi_fwd = 8'd19;
                8'd25:  wir_vi_fwd = 8'd22;
                default: wir_vi_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_vi_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_vi_rev = 8'd18;
                8'd1:  wir_vi_rev = 8'd10;
                8'd2:  wir_vi_rev = 8'd23;
                8'd3:  wir_vi_rev = 8'd16;
                8'd4:  wir_vi_rev = 8'd11;
                8'd5:  wir_vi_rev = 8'd7;
                8'd6:  wir_vi_rev = 8'd2;
                8'd7:  wir_vi_rev = 8'd13;
                8'd8:  wir_vi_rev = 8'd22;
                8'd9:  wir_vi_rev = 8'd0;
                8'd10:  wir_vi_rev = 8'd17;
                8'd11:  wir_vi_rev = 8'd21;
                8'd12:  wir_vi_rev = 8'd6;
                8'd13:  wir_vi_rev = 8'd12;
                8'd14:  wir_vi_rev = 8'd4;
                8'd15:  wir_vi_rev = 8'd1;
                8'd16:  wir_vi_rev = 8'd9;
                8'd17:  wir_vi_rev = 8'd15;
                8'd18:  wir_vi_rev = 8'd19;
                8'd19:  wir_vi_rev = 8'd24;
                8'd20:  wir_vi_rev = 8'd5;
                8'd21:  wir_vi_rev = 8'd3;
                8'd22:  wir_vi_rev = 8'd25;
                8'd23:  wir_vi_rev = 8'd20;
                8'd24:  wir_vi_rev = 8'd8;
                8'd25:  wir_vi_rev = 8'd14;
                default: wir_vi_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_vii_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_vii_fwd = 8'd13;
                8'd1:  wir_vii_fwd = 8'd25;
                8'd2:  wir_vii_fwd = 8'd9;
                8'd3:  wir_vii_fwd = 8'd7;
                8'd4:  wir_vii_fwd = 8'd6;
                8'd5:  wir_vii_fwd = 8'd17;
                8'd6:  wir_vii_fwd = 8'd2;
                8'd7:  wir_vii_fwd = 8'd23;
                8'd8:  wir_vii_fwd = 8'd12;
                8'd9:  wir_vii_fwd = 8'd24;
                8'd10:  wir_vii_fwd = 8'd18;
                8'd11:  wir_vii_fwd = 8'd22;
                8'd12:  wir_vii_fwd = 8'd1;
                8'd13:  wir_vii_fwd = 8'd14;
                8'd14:  wir_vii_fwd = 8'd20;
                8'd15:  wir_vii_fwd = 8'd5;
                8'd16:  wir_vii_fwd = 8'd0;
                8'd17:  wir_vii_fwd = 8'd8;
                8'd18:  wir_vii_fwd = 8'd21;
                8'd19:  wir_vii_fwd = 8'd11;
                8'd20:  wir_vii_fwd = 8'd15;
                8'd21:  wir_vii_fwd = 8'd4;
                8'd22:  wir_vii_fwd = 8'd10;
                8'd23:  wir_vii_fwd = 8'd16;
                8'd24:  wir_vii_fwd = 8'd3;
                8'd25:  wir_vii_fwd = 8'd19;
                default: wir_vii_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_vii_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_vii_rev = 8'd16;
                8'd1:  wir_vii_rev = 8'd12;
                8'd2:  wir_vii_rev = 8'd6;
                8'd3:  wir_vii_rev = 8'd24;
                8'd4:  wir_vii_rev = 8'd21;
                8'd5:  wir_vii_rev = 8'd15;
                8'd6:  wir_vii_rev = 8'd4;
                8'd7:  wir_vii_rev = 8'd3;
                8'd8:  wir_vii_rev = 8'd17;
                8'd9:  wir_vii_rev = 8'd2;
                8'd10:  wir_vii_rev = 8'd22;
                8'd11:  wir_vii_rev = 8'd19;
                8'd12:  wir_vii_rev = 8'd8;
                8'd13:  wir_vii_rev = 8'd0;
                8'd14:  wir_vii_rev = 8'd13;
                8'd15:  wir_vii_rev = 8'd20;
                8'd16:  wir_vii_rev = 8'd23;
                8'd17:  wir_vii_rev = 8'd5;
                8'd18:  wir_vii_rev = 8'd10;
                8'd19:  wir_vii_rev = 8'd25;
                8'd20:  wir_vii_rev = 8'd14;
                8'd21:  wir_vii_rev = 8'd18;
                8'd22:  wir_vii_rev = 8'd11;
                8'd23:  wir_vii_rev = 8'd7;
                8'd24:  wir_vii_rev = 8'd9;
                8'd25:  wir_vii_rev = 8'd1;
                default: wir_vii_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_viii_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_viii_fwd = 8'd5;
                8'd1:  wir_viii_fwd = 8'd10;
                8'd2:  wir_viii_fwd = 8'd16;
                8'd3:  wir_viii_fwd = 8'd7;
                8'd4:  wir_viii_fwd = 8'd19;
                8'd5:  wir_viii_fwd = 8'd11;
                8'd6:  wir_viii_fwd = 8'd23;
                8'd7:  wir_viii_fwd = 8'd14;
                8'd8:  wir_viii_fwd = 8'd2;
                8'd9:  wir_viii_fwd = 8'd1;
                8'd10:  wir_viii_fwd = 8'd9;
                8'd11:  wir_viii_fwd = 8'd18;
                8'd12:  wir_viii_fwd = 8'd15;
                8'd13:  wir_viii_fwd = 8'd3;
                8'd14:  wir_viii_fwd = 8'd25;
                8'd15:  wir_viii_fwd = 8'd17;
                8'd16:  wir_viii_fwd = 8'd0;
                8'd17:  wir_viii_fwd = 8'd12;
                8'd18:  wir_viii_fwd = 8'd4;
                8'd19:  wir_viii_fwd = 8'd22;
                8'd20:  wir_viii_fwd = 8'd13;
                8'd21:  wir_viii_fwd = 8'd8;
                8'd22:  wir_viii_fwd = 8'd20;
                8'd23:  wir_viii_fwd = 8'd24;
                8'd24:  wir_viii_fwd = 8'd6;
                8'd25:  wir_viii_fwd = 8'd21;
                default: wir_viii_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_viii_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_viii_rev = 8'd16;
                8'd1:  wir_viii_rev = 8'd9;
                8'd2:  wir_viii_rev = 8'd8;
                8'd3:  wir_viii_rev = 8'd13;
                8'd4:  wir_viii_rev = 8'd18;
                8'd5:  wir_viii_rev = 8'd0;
                8'd6:  wir_viii_rev = 8'd24;
                8'd7:  wir_viii_rev = 8'd3;
                8'd8:  wir_viii_rev = 8'd21;
                8'd9:  wir_viii_rev = 8'd10;
                8'd10:  wir_viii_rev = 8'd1;
                8'd11:  wir_viii_rev = 8'd5;
                8'd12:  wir_viii_rev = 8'd17;
                8'd13:  wir_viii_rev = 8'd20;
                8'd14:  wir_viii_rev = 8'd7;
                8'd15:  wir_viii_rev = 8'd12;
                8'd16:  wir_viii_rev = 8'd2;
                8'd17:  wir_viii_rev = 8'd15;
                8'd18:  wir_viii_rev = 8'd11;
                8'd19:  wir_viii_rev = 8'd4;
                8'd20:  wir_viii_rev = 8'd22;
                8'd21:  wir_viii_rev = 8'd25;
                8'd22:  wir_viii_rev = 8'd19;
                8'd23:  wir_viii_rev = 8'd6;
                8'd24:  wir_viii_rev = 8'd23;
                8'd25:  wir_viii_rev = 8'd14;
                default: wir_viii_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_beta_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_beta_fwd = 8'd11;
                8'd1:  wir_beta_fwd = 8'd4;
                8'd2:  wir_beta_fwd = 8'd24;
                8'd3:  wir_beta_fwd = 8'd9;
                8'd4:  wir_beta_fwd = 8'd21;
                8'd5:  wir_beta_fwd = 8'd2;
                8'd6:  wir_beta_fwd = 8'd13;
                8'd7:  wir_beta_fwd = 8'd8;
                8'd8:  wir_beta_fwd = 8'd23;
                8'd9:  wir_beta_fwd = 8'd22;
                8'd10:  wir_beta_fwd = 8'd15;
                8'd11:  wir_beta_fwd = 8'd1;
                8'd12:  wir_beta_fwd = 8'd16;
                8'd13:  wir_beta_fwd = 8'd12;
                8'd14:  wir_beta_fwd = 8'd3;
                8'd15:  wir_beta_fwd = 8'd17;
                8'd16:  wir_beta_fwd = 8'd19;
                8'd17:  wir_beta_fwd = 8'd0;
                8'd18:  wir_beta_fwd = 8'd10;
                8'd19:  wir_beta_fwd = 8'd25;
                8'd20:  wir_beta_fwd = 8'd6;
                8'd21:  wir_beta_fwd = 8'd5;
                8'd22:  wir_beta_fwd = 8'd20;
                8'd23:  wir_beta_fwd = 8'd7;
                8'd24:  wir_beta_fwd = 8'd14;
                8'd25:  wir_beta_fwd = 8'd18;
                default: wir_beta_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_beta_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_beta_rev = 8'd17;
                8'd1:  wir_beta_rev = 8'd11;
                8'd2:  wir_beta_rev = 8'd5;
                8'd3:  wir_beta_rev = 8'd14;
                8'd4:  wir_beta_rev = 8'd1;
                8'd5:  wir_beta_rev = 8'd21;
                8'd6:  wir_beta_rev = 8'd20;
                8'd7:  wir_beta_rev = 8'd23;
                8'd8:  wir_beta_rev = 8'd7;
                8'd9:  wir_beta_rev = 8'd3;
                8'd10:  wir_beta_rev = 8'd18;
                8'd11:  wir_beta_rev = 8'd0;
                8'd12:  wir_beta_rev = 8'd13;
                8'd13:  wir_beta_rev = 8'd6;
                8'd14:  wir_beta_rev = 8'd24;
                8'd15:  wir_beta_rev = 8'd10;
                8'd16:  wir_beta_rev = 8'd12;
                8'd17:  wir_beta_rev = 8'd15;
                8'd18:  wir_beta_rev = 8'd25;
                8'd19:  wir_beta_rev = 8'd16;
                8'd20:  wir_beta_rev = 8'd22;
                8'd21:  wir_beta_rev = 8'd4;
                8'd22:  wir_beta_rev = 8'd9;
                8'd23:  wir_beta_rev = 8'd8;
                8'd24:  wir_beta_rev = 8'd2;
                8'd25:  wir_beta_rev = 8'd19;
                default: wir_beta_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_gamma_fwd;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_gamma_fwd = 8'd5;
                8'd1:  wir_gamma_fwd = 8'd18;
                8'd2:  wir_gamma_fwd = 8'd14;
                8'd3:  wir_gamma_fwd = 8'd10;
                8'd4:  wir_gamma_fwd = 8'd0;
                8'd5:  wir_gamma_fwd = 8'd13;
                8'd6:  wir_gamma_fwd = 8'd20;
                8'd7:  wir_gamma_fwd = 8'd4;
                8'd8:  wir_gamma_fwd = 8'd17;
                8'd9:  wir_gamma_fwd = 8'd7;
                8'd10:  wir_gamma_fwd = 8'd12;
                8'd11:  wir_gamma_fwd = 8'd1;
                8'd12:  wir_gamma_fwd = 8'd19;
                8'd13:  wir_gamma_fwd = 8'd8;
                8'd14:  wir_gamma_fwd = 8'd24;
                8'd15:  wir_gamma_fwd = 8'd2;
                8'd16:  wir_gamma_fwd = 8'd22;
                8'd17:  wir_gamma_fwd = 8'd11;
                8'd18:  wir_gamma_fwd = 8'd16;
                8'd19:  wir_gamma_fwd = 8'd15;
                8'd20:  wir_gamma_fwd = 8'd25;
                8'd21:  wir_gamma_fwd = 8'd23;
                8'd22:  wir_gamma_fwd = 8'd21;
                8'd23:  wir_gamma_fwd = 8'd6;
                8'd24:  wir_gamma_fwd = 8'd9;
                8'd25:  wir_gamma_fwd = 8'd3;
                default: wir_gamma_fwd = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] wir_gamma_rev;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  wir_gamma_rev = 8'd4;
                8'd1:  wir_gamma_rev = 8'd11;
                8'd2:  wir_gamma_rev = 8'd15;
                8'd3:  wir_gamma_rev = 8'd25;
                8'd4:  wir_gamma_rev = 8'd7;
                8'd5:  wir_gamma_rev = 8'd0;
                8'd6:  wir_gamma_rev = 8'd23;
                8'd7:  wir_gamma_rev = 8'd9;
                8'd8:  wir_gamma_rev = 8'd13;
                8'd9:  wir_gamma_rev = 8'd24;
                8'd10:  wir_gamma_rev = 8'd3;
                8'd11:  wir_gamma_rev = 8'd17;
                8'd12:  wir_gamma_rev = 8'd10;
                8'd13:  wir_gamma_rev = 8'd5;
                8'd14:  wir_gamma_rev = 8'd2;
                8'd15:  wir_gamma_rev = 8'd19;
                8'd16:  wir_gamma_rev = 8'd18;
                8'd17:  wir_gamma_rev = 8'd8;
                8'd18:  wir_gamma_rev = 8'd1;
                8'd19:  wir_gamma_rev = 8'd12;
                8'd20:  wir_gamma_rev = 8'd6;
                8'd21:  wir_gamma_rev = 8'd22;
                8'd22:  wir_gamma_rev = 8'd16;
                8'd23:  wir_gamma_rev = 8'd21;
                8'd24:  wir_gamma_rev = 8'd14;
                8'd25:  wir_gamma_rev = 8'd20;
                default: wir_gamma_rev = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] ukw_thin_b;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  ukw_thin_b = 8'd4;
                8'd1:  ukw_thin_b = 8'd13;
                8'd2:  ukw_thin_b = 8'd10;
                8'd3:  ukw_thin_b = 8'd16;
                8'd4:  ukw_thin_b = 8'd0;
                8'd5:  ukw_thin_b = 8'd20;
                8'd6:  ukw_thin_b = 8'd24;
                8'd7:  ukw_thin_b = 8'd22;
                8'd8:  ukw_thin_b = 8'd9;
                8'd9:  ukw_thin_b = 8'd8;
                8'd10:  ukw_thin_b = 8'd2;
                8'd11:  ukw_thin_b = 8'd14;
                8'd12:  ukw_thin_b = 8'd15;
                8'd13:  ukw_thin_b = 8'd1;
                8'd14:  ukw_thin_b = 8'd11;
                8'd15:  ukw_thin_b = 8'd12;
                8'd16:  ukw_thin_b = 8'd3;
                8'd17:  ukw_thin_b = 8'd23;
                8'd18:  ukw_thin_b = 8'd25;
                8'd19:  ukw_thin_b = 8'd21;
                8'd20:  ukw_thin_b = 8'd5;
                8'd21:  ukw_thin_b = 8'd19;
                8'd22:  ukw_thin_b = 8'd7;
                8'd23:  ukw_thin_b = 8'd17;
                8'd24:  ukw_thin_b = 8'd6;
                8'd25:  ukw_thin_b = 8'd18;
                default: ukw_thin_b = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] ukw_thin_c;
        input [7:0] x;
        begin
            case (clamp26(x))
                8'd0:  ukw_thin_c = 8'd17;
                8'd1:  ukw_thin_c = 8'd3;
                8'd2:  ukw_thin_c = 8'd14;
                8'd3:  ukw_thin_c = 8'd1;
                8'd4:  ukw_thin_c = 8'd9;
                8'd5:  ukw_thin_c = 8'd13;
                8'd6:  ukw_thin_c = 8'd19;
                8'd7:  ukw_thin_c = 8'd10;
                8'd8:  ukw_thin_c = 8'd21;
                8'd9:  ukw_thin_c = 8'd4;
                8'd10:  ukw_thin_c = 8'd7;
                8'd11:  ukw_thin_c = 8'd12;
                8'd12:  ukw_thin_c = 8'd11;
                8'd13:  ukw_thin_c = 8'd5;
                8'd14:  ukw_thin_c = 8'd2;
                8'd15:  ukw_thin_c = 8'd22;
                8'd16:  ukw_thin_c = 8'd25;
                8'd17:  ukw_thin_c = 8'd0;
                8'd18:  ukw_thin_c = 8'd23;
                8'd19:  ukw_thin_c = 8'd6;
                8'd20:  ukw_thin_c = 8'd24;
                8'd21:  ukw_thin_c = 8'd8;
                8'd22:  ukw_thin_c = 8'd15;
                8'd23:  ukw_thin_c = 8'd18;
                8'd24:  ukw_thin_c = 8'd20;
                8'd25:  ukw_thin_c = 8'd16;
                default: ukw_thin_c = 8'd0;
            endcase
        end
    endfunction

    function automatic [7:0] rotor_fwd_sel;
        input [7:0] x;
        input integer which; // 1..8, or 100=beta, 101=gamma
        begin
            case (which)
                1: rotor_fwd_sel = wir_i_fwd(x);
                2: rotor_fwd_sel = wir_ii_fwd(x);
                3: rotor_fwd_sel = wir_iii_fwd(x);
                4: rotor_fwd_sel = wir_iv_fwd(x);
                5: rotor_fwd_sel = wir_v_fwd(x);
                6: rotor_fwd_sel = wir_vi_fwd(x);
                7: rotor_fwd_sel = wir_vii_fwd(x);
                8: rotor_fwd_sel = wir_viii_fwd(x);
                100: rotor_fwd_sel = wir_beta_fwd(x);
                default: rotor_fwd_sel = wir_gamma_fwd(x);
            endcase
        end
    endfunction

    function automatic [7:0] rotor_rev_sel;
        input [7:0] x;
        input integer which;
        begin
            case (which)
                1: rotor_rev_sel = wir_i_rev(x);
                2: rotor_rev_sel = wir_ii_rev(x);
                3: rotor_rev_sel = wir_iii_rev(x);
                4: rotor_rev_sel = wir_iv_rev(x);
                5: rotor_rev_sel = wir_v_rev(x);
                6: rotor_rev_sel = wir_vi_rev(x);
                7: rotor_rev_sel = wir_vii_rev(x);
                8: rotor_rev_sel = wir_viii_rev(x);
                100: rotor_rev_sel = wir_beta_rev(x);
                default: rotor_rev_sel = wir_gamma_rev(x);
            endcase
        end
    endfunction

    function automatic [7:0] thin_ukw;
        input [7:0] x;
        begin
            if (UKW_SEL == 0)
                thin_ukw = ukw_thin_b(x);
            else
                thin_ukw = ukw_thin_c(x);
        end
    endfunction

    function automatic at_notch;
        input [7:0] pos;
        input integer which;
        reg [7:0] p;
        begin
            p = clamp26(pos);
            case (which)
                1: at_notch = (p == 8'd16); // Q
                2: at_notch = (p == 8'd4);  // E
                3: at_notch = (p == 8'd21); // V
                4: at_notch = (p == 8'd9);  // J
                5: at_notch = (p == 8'd25); // Z
                6, 7, 8: at_notch = (p == 8'd12) || (p == 8'd25); // M,Z
                default: at_notch = 1'b0;
            endcase
        end
    endfunction

    function automatic [7:0] apply_fwd;
        input [7:0] ch;
        input [7:0] pos;
        input integer which;
        reg [7:0] shifted, wired;
        begin
            shifted = add26(ch, pos);
            wired = rotor_fwd_sel(shifted, which);
            apply_fwd = sub26(wired, pos);
        end
    endfunction

    function automatic [7:0] apply_rev;
        input [7:0] ch;
        input [7:0] pos;
        input integer which;
        reg [7:0] shifted, wired;
        begin
            shifted = add26(ch, pos);
            wired = rotor_rev_sel(shifted, which);
            apply_rev = sub26(wired, pos);
        end
    endfunction

    function automatic [7:0] plugboard;
        input [7:0] x;
        begin
            plugboard = clamp26(x);
        end
    endfunction

    function automatic [7:0] scramble;
        input [7:0] ct;
        input [7:0] pos_r;
        input [7:0] pos_m;
        input [7:0] pos_l;
        reg [7:0] x;
        integer gwhich;
        begin
            gwhich = (GREEK_SEL == 0) ? 100 : 101;
            x = plugboard(ct);
            x = apply_fwd(x, pos_r, ROTOR_R);
            x = apply_fwd(x, pos_m, ROTOR_M);
            x = apply_fwd(x, pos_l, ROTOR_L);
            x = apply_fwd(x, clamp26(GREEK_POS), gwhich);
            x = thin_ukw(x);
            x = apply_rev(x, clamp26(GREEK_POS), gwhich);
            x = apply_rev(x, pos_l, ROTOR_L);
            x = apply_rev(x, pos_m, ROTOR_M);
            x = apply_rev(x, pos_r, ROTOR_R);
            scramble = plugboard(x);
        end
    endfunction

    // High-probability German / naval trigrams for in-graph score spikes.
    function automatic trigram_hit;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        reg [7:0] aa, bb, cc;
        begin
            aa = clamp26(a);
            bb = clamp26(b);
            cc = clamp26(c);
            // EIN E=4 I=8 N=13
            // CHT C=2 H=7 T=19
            // NDE N=13 D=3 E=4
            // DER D=3 E=4 R=17
            // UND U=20 N=13 D=3
            // VON V=21 O=14 N=13
            // UUU U=20
            // EINS partial handled as EIN
            // DIE D=3 I=8 E=4
            // ICH I=8 C=2 H=7
            // SCH S=18 C=2 H=7
            // XX? not trigram; XXA etc skipped
            trigram_hit =
                (aa==8'd4  && bb==8'd8  && cc==8'd13) || // EIN
                (aa==8'd2  && bb==8'd7  && cc==8'd19) || // CHT
                (aa==8'd13 && bb==8'd3  && cc==8'd4)  || // NDE
                (aa==8'd3  && bb==8'd4  && cc==8'd17) || // DER
                (aa==8'd20 && bb==8'd13 && cc==8'd3)  || // UND
                (aa==8'd21 && bb==8'd14 && cc==8'd13) || // VON
                (aa==8'd20 && bb==8'd20 && cc==8'd20) || // UUU
                (aa==8'd3  && bb==8'd8  && cc==8'd4)  || // DIE
                (aa==8'd8  && bb==8'd2  && cc==8'd7)  || // ICH
                (aa==8'd18 && bb==8'd2  && cc==8'd7)  || // SCH
                (aa==8'd13 && bb==8'd20 && cc==8'd11) || // NUL
                (aa==8'd15 && bb==8'd0  && cc==8'd18) || // PAS (PASS)
                (aa==8'd22 && bb==8'd4  && cc==8'd19) || // WET (WETTER)
                (aa==8'd19 && bb==8'd4  && cc==8'd17) || // TER (WETTER)
                (aa==8'd2  && bb==8'd7  && cc==8'd4)  || // CHE (CHEF)
                (aa==8'd7  && bb==8'd4  && cc==8'd5)  || // HEF (CHEF)
                (aa==8'd20 && bb==8'd1  && cc==8'd14) || // UBO (UBOOT)
                (aa==8'd14 && bb==8'd14 && cc==8'd19) || // OOT (UBOOT)
                (aa==8'd12 && bb==8'd4  && cc==8'd11) || // MEL (MELDUNG)
                (aa==8'd16 && bb==8'd20 && cc==8'd0)  || // QUA (QUADRAT)
                (aa==8'd12 && bb==8'd0  && cc==8'd17) || // MAR (MARINE)
                (aa==8'd10 && bb==8'd20 && cc==8'd17) || // KUR (KURS)
                (aa==8'd5  && bb==8'd4  && cc==8'd8);    // FEI (FEIND)
        end
    endfunction

    // Monogram prior: bump score for common German letters E N I R S T A D.
    function automatic [3:0] monogram_weight;
        input [7:0] ch;
        reg [7:0] c;
        begin
            c = clamp26(ch);
            case (c)
                8'd4, 8'd13, 8'd8, 8'd17, 8'd18, 8'd19, 8'd0, 8'd3: monogram_weight = 4'd1;
                default: monogram_weight = 4'd0;
            endcase
        end
    endfunction


    wire notch_r = at_notch(rotor_r, ROTOR_R);
    wire notch_m = at_notch(rotor_m, ROTOR_M);
    wire step_m = notch_r || notch_m;
    wire step_l = notch_m;

    wire [7:0] next_r = add26(rotor_r, 8'd1);
    wire [7:0] next_m = step_m ? add26(rotor_m, 8'd1) : rotor_m;
    wire [7:0] next_l = step_l ? add26(rotor_l, 8'd1) : rotor_l;

    wire [7:0] scrambled = scramble(ciphertext_char, next_r, next_m, next_l);

    wire hit = (letters_seen >= 2'd2) && trigram_hit(prev_plain_1, prev_plain_0, scrambled);
    wire [15:0] score_inc = {12'd0, monogram_weight(scrambled)} + (hit ? 16'd8 : 16'd0);
    wire [15:0] next_score = linguistic_score + score_inc;

    always @(posedge clk) begin
        if (!resetn) begin
            rotor_r            <= 8'd0;
            rotor_m            <= 8'd0;
            rotor_l            <= 8'd0;
            plaintext_char     <= 8'd0;
            linguistic_score   <= 16'd0;
            prev_plain_1       <= 8'd0;
            prev_plain_0       <= 8'd0;
            letters_seen       <= 2'd0;
        end else begin
            rotor_r            <= next_r;
            rotor_m            <= next_m;
            rotor_l            <= next_l;
            plaintext_char     <= scrambled;
            linguistic_score   <= next_score;
            prev_plain_1       <= prev_plain_0;
            prev_plain_0       <= scrambled;
            if (letters_seen < 2'd2)
                letters_seen   <= letters_seen + 2'd1;
        end
    end

endmodule
