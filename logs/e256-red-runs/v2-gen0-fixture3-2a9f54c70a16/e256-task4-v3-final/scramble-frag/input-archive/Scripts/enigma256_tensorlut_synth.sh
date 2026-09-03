#!/usr/bin/env bash
# Synthesize LFSR+NLFF step cone (sequential) AND pure NLFF combo → LUT6 JSON.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT"

yosys -Q -p "
  read_verilog -sv -I. Hardware/RTL/Enigma256/enigma_256_step_cone.v
  hierarchy -check -top enigma_256_step_cone
  proc; opt; memory; opt
  techmap; opt
  abc -lut 6
  opt_clean
  write_json build/enigma_256_step_cone_netlist.json
  stat
"

yosys -Q -p "
  read_verilog -sv -I. Hardware/RTL/Enigma256/enigma_256_nlff_combo.v
  hierarchy -check -top enigma_256_nlff_combo
  proc; opt
  techmap; opt
  abc -lut 6
  opt_clean
  write_json build/enigma_256_nlff_combo_netlist.json
  stat
"

yosys -Q -p "
  read_verilog -sv -I. Hardware/RTL/Enigma256/enigma_256_nlff_lfsr_combo.v
  hierarchy -check -top enigma_256_nlff_lfsr_combo
  proc; opt
  techmap; opt
  abc -lut 6
  opt_clean
  write_json build/enigma_256_nlff_lfsr_combo_netlist.json
  stat
"

yosys -Q -p "
  read_verilog -sv -I. Hardware/RTL/Enigma256/enigma_256_nlff_offset_combo.v
  hierarchy -check -top enigma_256_nlff_offset_combo
  proc; opt
  techmap; opt
  abc -lut 6
  opt_clean
  write_json build/enigma_256_nlff_offset_combo_netlist.json
  stat
"

yosys -Q -p "
  read_verilog -sv -I. Hardware/RTL/Enigma256/enigma_256_scramble_frag_combo.v
  hierarchy -check -top enigma_256_scramble_frag_combo
  proc; opt
  techmap; opt
  abc -lut 6
  opt_clean
  write_json build/enigma_256_scramble_frag_combo_netlist.json
  stat
"

echo "Wrote build/enigma_256_step_cone_netlist.json"
echo "Wrote build/enigma_256_nlff_combo_netlist.json"
echo "Wrote build/enigma_256_nlff_lfsr_combo_netlist.json"
echo "Wrote build/enigma_256_nlff_offset_combo_netlist.json"
echo "Wrote build/enigma_256_scramble_frag_combo_netlist.json"
