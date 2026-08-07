`timescale 1ns / 1ps
`default_nettype none

// Loaded E256 core. Sixteen 16-bit words. The host supplies one round of
// multipliers. Decrypt is the inverse path. The byte-walk core this file
// replaced is kept, unmodified, at
// Fixtures/Historical/Enigma256/E256-v2-gen0-fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4-fixture-v4/enigma_256_core.v
//
// Polynomial x^16 + x^12 + x^3 + x + 1. Public constant 1. No reflector.

module enigma_256_core (
    input  wire         decrypt,
    input  wire [255:0] st,
    input  wire [255:0] scale,
    output wire [255:0] st_out
);
  e256v6_round round (
    .decrypt(decrypt),
    .st(st),
    .scale(scale),
    .st_out(st_out)
  );
endmodule
