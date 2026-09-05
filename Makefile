# Document builds — canonical source is TeX; Markdown is generated.
#
#   make writeup     # writeup.tex → writeup.pdf + writeup.md
#   make paper       # paper/helut.tex → paper/helut.pdf + paper/helut.md
#   make textbook    # textbook/helut-living-textbook.tex → pdf + md
#   make docs        # writeup + paper + textbook
#   make hardware-check  # manifest + root compatibility-copy integrity
#   make test-metal-p1  # Phase 1 Metal BR XCTest battery (release)
#   make gates       # hardware + claim lint + determinism + exact C69 n=512 smoke
#   make determinism # fast in-process + cross-process determinism guards
#   make c69-smoke   # exact N=1024 / n=512 covering-b2 SING regression

.PHONY: writeup paper textbook note docs clean-docs test-metal-p1 gates determinism c69-smoke \
	hardware-manifest-check hardware-compat-check hardware-check hardware-compat-sync \
	rust-reference-toolchain rust-reference-format rust-reference-clippy rust-reference-test \
	rust-reference-verify rust-reference-check \
	generate-m4-artifacts promote-m4-artifacts \
	generate-ab0cde-netlist promote-ab0cde-netlist \
	generate-e256-tensorlut promote-e256-tensorlut \
	generate-e256-profile check-e256-profile promote-e256-profile \
	radio radio-edge

HARDWARE_SCRATCH := build/hardware
AB0CDE_SCRATCH := $(HARDWARE_SCRATCH)/Examples
AB0CDE_SCRATCH_NETLIST := $(AB0CDE_SCRATCH)/ab0cde_netlist.json
M4_SCRATCH := $(HARDWARE_SCRATCH)/EnigmaM4
M4_SCRATCH_NETLIST := $(M4_SCRATCH)/enigma_m4_netlist.json
M4_SCRATCH_TENSORLUT := $(M4_SCRATCH)/enigma_m4_tensorlut_baseline.v
E256_SCRATCH := $(HARDWARE_SCRATCH)/Enigma256
E256_SCRATCH_STEP_TENSORLUT := $(E256_SCRATCH)/enigma_256_step_cone_tensorlut.v
E256_SCRATCH_NLFF_TENSORLUT := $(E256_SCRATCH)/enigma_256_tensorlut_baseline.v
E256_PROFILE_SCRATCH := $(HARDWARE_SCRATCH)/Profiles/Enigma256
E256_PROFILE_SCRATCH_VERILOG := $(E256_PROFILE_SCRATCH)/enigma_256_nlff_v2.vh
E256_PROFILE_SCRATCH_JSON := $(E256_PROFILE_SCRATCH)/enigma256_generation.json
RUST_REFERENCE_MANIFEST := Reference/Rust/Cargo.toml
RUST_REFERENCE_TARGET := $(CURDIR)/build/rust-reference
RUST_REFERENCE_TOOLCHAIN := 1.97.1
RUST_REFERENCE_ENV := CARGO_TARGET_DIR="$(RUST_REFERENCE_TARGET)" RUSTUP_TOOLCHAIN="$(RUST_REFERENCE_TOOLCHAIN)"

writeup: writeup.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh writeup.tex

paper: paper/helut.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh paper/helut.tex

textbook: textbook/helut-living-textbook.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh textbook/helut-living-textbook.tex

note: note/lut-relaxation.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh note/lut-relaxation.tex

docs: writeup paper textbook

# Read-only integrity gates for the canonical Hardware/Generated trees and the
# checked-in root compatibility surface.
hardware-manifest-check:
	python3 Scripts/validate_hardware_manifest.py

hardware-compat-check:
	python3 Scripts/sync_hardware_artifacts.py --check

hardware-check: hardware-manifest-check hardware-compat-check

# Portable, read-only reference lane. Cargo output stays under ignored build/;
# the commands consume canonical fixtures and generated netlists without
# providing emit, bless, or promotion operations. RUSTUP_TOOLCHAIN selects the
# pin where rustup is present; the explicit check also fails closed for direct
# package-manager toolchains.
rust-reference-toolchain:
	@set -- $$($(RUST_REFERENCE_ENV) rustc --version); \
	if [ "$$1" != "rustc" ] || [ "$$2" != "$(RUST_REFERENCE_TOOLCHAIN)" ]; then \
		echo "Rust $(RUST_REFERENCE_TOOLCHAIN) required; got $$1 $$2" >&2; \
		exit 1; \
	fi

rust-reference-format: rust-reference-toolchain
	$(RUST_REFERENCE_ENV) cargo fmt --manifest-path "$(RUST_REFERENCE_MANIFEST)" -- --check

rust-reference-clippy: rust-reference-toolchain
	$(RUST_REFERENCE_ENV) cargo-clippy clippy --locked --all-targets --manifest-path "$(RUST_REFERENCE_MANIFEST)" -- -D warnings

rust-reference-test: rust-reference-toolchain
	$(RUST_REFERENCE_ENV) cargo test --locked --manifest-path "$(RUST_REFERENCE_MANIFEST)"

rust-reference-verify: rust-reference-toolchain
	$(RUST_REFERENCE_ENV) cargo run --locked --manifest-path "$(RUST_REFERENCE_MANIFEST)" -- e256-kat \
		--profile Fixtures/enigma256_generation.json \
		--bundle Fixtures/enigma256_golden \
		--receipt logs/e256-v2-gen0-nlff-search.json
	$(RUST_REFERENCE_ENV) cargo run --locked --manifest-path "$(RUST_REFERENCE_MANIFEST)" -- yosys-parity \
		--full-adder Generated/Netlists/Examples/netlist.json \
		--counter Generated/Netlists/Examples/counter_netlist.json \
		--toy-isa Generated/Netlists/Examples/toy_isa_netlist.json

rust-reference-check: rust-reference-format rust-reference-clippy rust-reference-test rust-reference-verify

# The only normal canonical-to-root mutation. Generators and promotion targets
# never write through compatibility names as a side effect.
hardware-compat-sync:
	python3 Scripts/sync_hardware_artifacts.py --sync
	python3 Scripts/validate_hardware_manifest.py

# The Episode 13 callsign matcher follows the same scratch-first promotion rule:
# synthesize authored RTL under ignored build/, validate the result, then copy
# only the reviewed canonical artifact into Generated/.
generate-ab0cde-netlist:
	@mkdir -p "$(AB0CDE_SCRATCH)"
	yosys -Q -p "read_verilog Hardware/RTL/Examples/ab0cde_matcher.v; hierarchy -check -top ab0cde_matcher; synth -top ab0cde_matcher -flatten; abc -lut 2; check -assert; write_json $(AB0CDE_SCRATCH_NETLIST)"
	yosys -Q -p "read_json $(AB0CDE_SCRATCH_NETLIST); hierarchy -check -top ab0cde_matcher; check -assert; stat"

promote-ab0cde-netlist:
	@test -s "$(AB0CDE_SCRATCH_NETLIST)"
	yosys -Q -p "read_json $(AB0CDE_SCRATCH_NETLIST); hierarchy -check -top ab0cde_matcher; check -assert"
	cp "$(AB0CDE_SCRATCH_NETLIST)" Generated/Netlists/Examples/ab0cde_netlist.json
	python3 Scripts/sync_hardware_artifacts.py --sync
	python3 Scripts/validate_hardware_manifest.py
	@echo "Promoted the canonical AB0CDE netlist and refreshed its root compatibility copy."

# M4 generation is scratch-first. Promotion updates only canonical checked-in
# artifacts; refresh root compatibility copies separately after review.
generate-m4-artifacts:
	@mkdir -p "$(M4_SCRATCH)"
	yosys -Q -p "read_verilog -sv Hardware/RTL/Enigma/enigma_m4_core.v; hierarchy -check -top enigma_m4_core; synth -top enigma_m4_core -flatten; abc -lut 2; check -assert; write_json $(M4_SCRATCH_NETLIST)"
	swift run -c release helut-bench --emit-tensorlut-verilog "$(M4_SCRATCH_NETLIST)" \
		--emit-module-name enigma_m4_tensorlut_baseline \
		--emit-out "$(M4_SCRATCH_TENSORLUT)"

promote-m4-artifacts: hardware-manifest-check
	@test -s "$(M4_SCRATCH_NETLIST)"
	@test -s "$(M4_SCRATCH_TENSORLUT)"
	yosys -Q -p "read_json $(M4_SCRATCH_NETLIST); hierarchy -check -top enigma_m4_core; check -assert"
	yosys -Q -p "read_verilog $(M4_SCRATCH_TENSORLUT); hierarchy -check -top enigma_m4_tensorlut_baseline; check -assert"
	@mkdir -p Generated/Netlists/Enigma Generated/TensorLUT/EnigmaM4
	cp "$(M4_SCRATCH_NETLIST)" Generated/Netlists/Enigma/enigma_m4_netlist.json
	cp "$(M4_SCRATCH_TENSORLUT)" Generated/TensorLUT/EnigmaM4/enigma_m4_tensorlut_baseline.v
	@echo "Promoted M4 canonical artifacts; run 'make hardware-compat-sync' after review."

generate-e256-tensorlut:
	./Scripts/enigma256_tensorlut.sh

promote-e256-tensorlut: hardware-manifest-check
	@test -s "$(E256_SCRATCH_STEP_TENSORLUT)"
	@test -s "$(E256_SCRATCH_NLFF_TENSORLUT)"
	yosys -Q -p "read_verilog -lib +/xilinx/cells_sim.v; read_verilog -sv $(E256_SCRATCH_STEP_TENSORLUT); hierarchy -check -top enigma_256_step_cone_tensorlut; check -assert"
	yosys -Q -p "read_verilog -lib +/xilinx/cells_sim.v; read_verilog -sv $(E256_SCRATCH_NLFF_TENSORLUT); hierarchy -check -top enigma_256_tensorlut_baseline; check -assert"
	@mkdir -p Generated/TensorLUT/Enigma256
	cp "$(E256_SCRATCH_STEP_TENSORLUT)" Generated/TensorLUT/Enigma256/enigma_256_step_cone_tensorlut.v
	cp "$(E256_SCRATCH_NLFF_TENSORLUT)" Generated/TensorLUT/Enigma256/enigma_256_tensorlut_baseline.v
	@echo "Promoted E256 TensorLUT artifacts; run 'make hardware-compat-sync' after review."

generate-e256-profile:
	python3 Scripts/e256_nlff_emit.py

check-e256-profile:
	python3 Scripts/e256_nlff_emit.py --check

promote-e256-profile: hardware-manifest-check
	python3 Scripts/e256_nlff_emit.py --check \
		--verilog-out "$(E256_PROFILE_SCRATCH_VERILOG)" \
		--profile-out "$(E256_PROFILE_SCRATCH_JSON)"
	@mkdir -p Generated/Profiles/Enigma256 Fixtures
	cp "$(E256_PROFILE_SCRATCH_VERILOG)" Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh
	cp "$(E256_PROFILE_SCRATCH_JSON)" Fixtures/enigma256_generation.json
	@echo "Promoted E256 profile artifacts; run 'make hardware-compat-sync' after review."

test-metal-p1:
	@chmod +x Scripts/helut_metal_phase1_test.sh
	./Scripts/helut_metal_phase1_test.sh

# Encrypted-path determinism. Two fast guards catch different things: the XCTest
# permutes Dictionary keys within one process, while the script runs separate
# processes with per-process hash reseeding active. Neither is redundant.
#
# SWIFT_DETERMINISTIC_HASHING must stay unset here; it pins the hash seed and
# makes the cross-process check vacuous. The script refuses to run if it is set.
determinism:
	swift test -c release --filter EncryptedDeterminismTests
	python3 Scripts/determinism_cross_process.py --runs 5 --verbose

# End-to-end preservation gate for the result the Dictionary-order fix recovered.
# This is intentionally separate from routine XCTest because it exercises the
# exact N=1024 / n=512 noisy covering path and takes roughly one minute.
c69-smoke:
	bash Scripts/c69_n512_smoke.sh

# Pre-commit ritual for anything that touches a claim. macOS CI runs the same
# determinism and C69 preservation gates; Linux CI retains the pure-Python lints.
gates: hardware-check determinism c69-smoke
	python3 Scripts/claim_audit.py
	python3 Scripts/eps_claim_audit.py

clean-docs:
	rm -rf build/writeup build/paper build/textbook
	rm -f writeup.aux writeup.log writeup.out writeup.fls writeup.fdb_latexmk writeup.synctex.gz
	rm -f paper/helut.aux paper/helut.log paper/helut.out paper/helut.fls paper/helut.fdb_latexmk paper/helut.synctex.gz
	rm -f textbook/helut-living-textbook.aux textbook/helut-living-textbook.log textbook/helut-living-textbook.out
	rm -f textbook/helut-living-textbook.fls textbook/helut-living-textbook.fdb_latexmk textbook/helut-living-textbook.synctex.gz
	rm -f textbook/helut-living-textbook.toc textbook/helut-living-textbook.bbl textbook/helut-living-textbook.blg

# GNU Radio C ABI (libHELUTRadio.dylib) + smoke CLI. Does not require gnuradio.
radio:
	swift build -c release --product HELUTRadio
	swift build -c release --product helut-radio
	.build/release/helut-radio --selftest
	python3 Apps/gr-helut/examples/helut_regex_demo.py --text 'XXDEFYYDEFZZ'

# Closed-loop mindblower (needs radioconda activated — see
# https://github.com/radioconda/radioconda-installer ;
# Apple Silicon pkg: https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg
# Homebrew gnuradio is deprecated).
radio-edge:
	swift build -c release --product HELUTRadio
	HELUT_RADIO_LIB="$(CURDIR)/.build/release/libHELUTRadio.dylib" \
	PYTHONPATH="$(CURDIR)/Apps/gr-helut/python$${PYTHONPATH:+:$$PYTHONPATH}" \
	python Apps/gr-helut/examples/helut_edge_matcher.py --batch 10000 --noise 0.0 --encrypted-freeze


# Mulein cleartext RTL lane. Canonical source lives under Apps/Mulein; the root .v file is a
# compatibility entry point. All generated artifacts stay under the ignored root build tree.
MULEIN_RTL := Apps/Mulein/rtl/mulein_closure_core.sv
MULEIN_TB := Apps/Mulein/tests/rtl/mulein_closure_core_tb.sv
MULEIN_BUILD := build/mulein
MULEIN_VVP := $(MULEIN_BUILD)/mulein_closure_core_tb.vvp
MULEIN_JSON := $(MULEIN_BUILD)/mulein_closure_core.json
MULEIN_BOUNDED_RTL := Apps/Mulein/rtl/mulein_closure_bounded.sv
MULEIN_BOUNDED_TB := Apps/Mulein/tests/rtl/mulein_closure_bounded_tb.sv
MULEIN_BOUNDED_SOURCE_VVP := $(MULEIN_BUILD)/mulein_closure_bounded_source.vvp
MULEIN_BOUNDED_POST_VVP := $(MULEIN_BUILD)/mulein_closure_bounded_post.vvp
MULEIN_LUT_JSON := $(MULEIN_BUILD)/mulein_closure_bounded_lut6.json
MULEIN_LUT_VERILOG := $(MULEIN_BUILD)/mulein_closure_bounded_lut6.v
MULEIN_SEED_RTL := Apps/Mulein/rtl/mulein_closure_seed.sv
MULEIN_FUTURE_TOP_RTL := Apps/Mulein/rtl/mulein_future_tensorlut_top.sv
MULEIN_BANK_LANES ?= 1
MULEIN_FUTURE_PREFIX := $(MULEIN_BUILD)/mulein_future_bank$(MULEIN_BANK_LANES)
MULEIN_FUTURE_JSON := $(MULEIN_FUTURE_PREFIX)_lut6.json
MULEIN_FUTURE_VERILOG := $(MULEIN_FUTURE_PREFIX)_lut6.v
MULEIN_FUTURE_STAT := $(MULEIN_FUTURE_PREFIX)_stat.txt
MULEIN_FUTURE_MANIFEST_SOURCE ?= Fixtures/p1030680_maxupper_strongest_menus.json
MULEIN_FUTURE_DELTA ?= 4
MULEIN_FUTURE_MANIFEST ?= Fixtures/p1030680_mulein_identity_postgap_delta$(MULEIN_FUTURE_DELTA).json
MULEIN_FUTURE_CAMPAIGN_LEDGER ?= logs/p1030680-mulein-unified.jsonl
MULEIN_FUTURE_SETTINGS ?= 2048
MULEIN_FUTURE_REPETITIONS ?= 5
MULEIN_FUTURE_TENSOR_SETTINGS ?= 16
MULEIN_FUTURE_TICK_LIMIT ?= 100000
MULEIN_FUTURE_WIDTHS ?= 1 2 4 8 16

.PHONY: test-mulein-rtl synth-mulein-rtl test-mulein-bounded-rtl \
	synth-mulein-tensorlut test-mulein-tensorlut \
	synth-mulein-future-tensorlut test-mulein-future-tensorlut \
	emit-mulein-future-manifest build-mulein-future-bench \
	test-mulein-future-control grade-mulein-future-metal \
	grade-mulein-future-tensorlut sweep-mulein-future-tensorlut \
	build-mulein-future-campaign plan-mulein-future-campaign clean-mulein

$(MULEIN_VVP): mulein_closure_core.v $(MULEIN_RTL) $(MULEIN_TB)
	@mkdir -p "$(MULEIN_BUILD)"
	iverilog -g2012 -Wall -I"$(CURDIR)" -s mulein_closure_core_tb \
		-o "$@" mulein_closure_core.v "$(MULEIN_TB)"

test-mulein-rtl: $(MULEIN_VVP)
	vvp "$<"

$(MULEIN_JSON): $(MULEIN_RTL)
	@mkdir -p "$(MULEIN_BUILD)"
	yosys -Q -p "read_verilog -sv $(MULEIN_RTL); hierarchy -check -top mulein_closure_core; synth -top mulein_closure_core; check -assert; write_json $(MULEIN_JSON)"

synth-mulein-rtl: $(MULEIN_JSON)

# Four-edge/four-step conformance wrapper. `dffunmap` is deliberately after technology
# mapping: otherwise a later opt pass re-forms SDFFCE/SDFFE cells whose reset/enable priority
# the Float TensorLUT DFF descriptor cannot represent. `zinit` gives post-map four-state RTL a
# deterministic power-up only for simulation; every receipt still exercises resetn before start.
$(MULEIN_LUT_JSON): $(MULEIN_RTL) $(MULEIN_BOUNDED_RTL)
	@mkdir -p "$(MULEIN_BUILD)"
	yosys -Q -p "read_verilog -sv $(MULEIN_RTL) $(MULEIN_BOUNDED_RTL); hierarchy -check -top mulein_closure_bounded; proc; flatten; memory; opt; techmap; opt; dffunmap; zinit -all; abc -lut 6; opt_clean; check -assert; stat; write_json $(MULEIN_LUT_JSON); write_verilog -noattr $(MULEIN_LUT_VERILOG)"

$(MULEIN_LUT_VERILOG): $(MULEIN_LUT_JSON)
	@test -f "$@"

synth-mulein-tensorlut: $(MULEIN_LUT_JSON) $(MULEIN_LUT_VERILOG)

$(MULEIN_BOUNDED_SOURCE_VVP): $(MULEIN_RTL) $(MULEIN_BOUNDED_RTL) $(MULEIN_BOUNDED_TB)
	@mkdir -p "$(MULEIN_BUILD)"
	iverilog -g2012 -Wall -s mulein_closure_bounded_tb -o "$@" \
		$(MULEIN_RTL) $(MULEIN_BOUNDED_RTL) $(MULEIN_BOUNDED_TB)

$(MULEIN_BOUNDED_POST_VVP): $(MULEIN_LUT_VERILOG) $(MULEIN_BOUNDED_TB)
	@mkdir -p "$(MULEIN_BUILD)"
	iverilog -g2012 -Wall -s mulein_closure_bounded_tb -o "$@" \
		$(MULEIN_LUT_VERILOG) $(MULEIN_BOUNDED_TB)

test-mulein-bounded-rtl: $(MULEIN_BOUNDED_SOURCE_VVP) $(MULEIN_BOUNDED_POST_VVP)
	vvp "$(MULEIN_BOUNDED_SOURCE_VVP)"
	vvp "$(MULEIN_BOUNDED_POST_VVP)"

test-mulein-tensorlut: synth-mulein-tensorlut
	swift test -c release --filter MuleinClosureTensorLUTTests

# Production-width single-seed/Future-Bank artifact. BANK_LANES is a measured synthesis
# parameter; generated names include the width so a wider sweep cannot reuse a stale graph.
$(MULEIN_FUTURE_JSON): $(MULEIN_SEED_RTL) $(MULEIN_FUTURE_TOP_RTL)
	@mkdir -p "$(MULEIN_BUILD)"
	yosys -Q -p "read_verilog -sv $(MULEIN_SEED_RTL) $(MULEIN_FUTURE_TOP_RTL); chparam -set BANK_LANES $(MULEIN_BANK_LANES) mulein_future_tensorlut_top; hierarchy -check -top mulein_future_tensorlut_top; proc; flatten; memory; opt; techmap; opt; dffunmap; zinit -all; abc -lut 6; opt_clean; check -assert; tee -o $(MULEIN_FUTURE_STAT) stat; write_json $(MULEIN_FUTURE_JSON); write_verilog -noattr $(MULEIN_FUTURE_VERILOG)"

$(MULEIN_FUTURE_VERILOG) $(MULEIN_FUTURE_STAT): $(MULEIN_FUTURE_JSON)
	@test -f "$@"

synth-mulein-future-tensorlut: $(MULEIN_FUTURE_JSON) $(MULEIN_FUTURE_VERILOG) $(MULEIN_FUTURE_STAT)

test-mulein-future-tensorlut:
	swift test -c release --filter MuleinFutureTensorLUTTests

# Deterministic finite target inventory only. This compiles identity plus one selected
# post-gap-delta geometry family with stable provenance; it evaluates no settings and cannot
# establish a decrypt. The emitter rejects any delta that exceeds the 80-step Future envelope.
emit-mulein-future-manifest: build-mulein-future-bench
	.build/release/helut-bench --mulein-future-manifest-emit \
		--mulein-future-manifest-source "$(MULEIN_FUTURE_MANIFEST_SOURCE)" \
		--mulein-future-manifest-delta "$(MULEIN_FUTURE_DELTA)" \
		--mulein-future-manifest-out "$(MULEIN_FUTURE_MANIFEST)"

# These are macOS/Metal known-key controls. They never read P1030680. The control grade
# cross-checks complete Metal receipts against the independent Swift board; the throughput
# grade compares one fused bank with repeated singleton dispatches over identical work.
build-mulein-future-bench:
	swift build -c release --product helut-bench -Xswiftc -suppress-warnings

build-mulein-future-campaign:
	swift build -c release --product helut-bombe -Xswiftc -suppress-warnings

# Safe plan receipt for the selected W=4 artifact. This reads and validates target inputs but
# evaluates no P1030680 settings and writes no campaign ledger.
plan-mulein-future-campaign: build-mulein-future-campaign
	.build/release/helut-bombe --mulein-future-campaign --mulein-future-plan-only \
		--mulein-future-manifest "$(MULEIN_FUTURE_MANIFEST)" \
		--mulein-future-netlist "$(MULEIN_BUILD)/mulein_future_bank4_lut6.json" \
		--mulein-bank-lanes 4 --subspace potsdam-neighbourhood --rings AAAA \
		--shell-from 0 --shell-count 1 --setting-from 0 --setting-count 256 \
		--future-from 0 --future-count 1 --chunk-settings 16 --tensor-batch 16 \
		--campaign-ledger "$(MULEIN_FUTURE_CAMPAIGN_LEDGER)"

test-mulein-future-control: build-mulein-future-bench
	.build/release/helut-bench --mulein-future-control-grade

grade-mulein-future-metal: build-mulein-future-bench
	.build/release/helut-bench --mulein-future-metal-grade \
		--mulein-future-settings "$(MULEIN_FUTURE_SETTINGS)" \
		--mulein-future-repetitions "$(MULEIN_FUTURE_REPETITIONS)"

# One width per fresh process so allocator retention cannot distort RSS comparisons.
grade-mulein-future-tensorlut: build-mulein-future-bench
	.build/release/helut-bench --mulein-future-tensorlut-grade \
		--mulein-future-bank-lanes "$(MULEIN_BANK_LANES)" \
		--mulein-future-tensorlut-json "$(MULEIN_FUTURE_JSON)" \
		--mulein-future-settings "$(MULEIN_FUTURE_TENSOR_SETTINGS)" \
		--mulein-future-repetitions "$(MULEIN_FUTURE_REPETITIONS)" \
		--mulein-future-tick-limit "$(MULEIN_FUTURE_TICK_LIMIT)"

# Requires the already-synthesized width artifacts. Every process evaluates the same complete
# 16-job stream; the sweep rejects semantic-digest drift before ranking median receipt rate.
sweep-mulein-future-tensorlut: build-mulein-future-bench
	@set -eu; \
		rates="$(MULEIN_BUILD)/mulein_future_tensorlut_rates.txt"; \
		selection="$(MULEIN_BUILD)/mulein_future_tensorlut_selection.txt"; \
		: > "$$rates"; \
		for width in $(MULEIN_FUTURE_WIDTHS); do \
			artifact="$(MULEIN_BUILD)/mulein_future_bank$${width}_lut6.json"; \
			log="$(MULEIN_BUILD)/mulein_future_bank$${width}_bench.txt"; \
			test -f "$$artifact" || { echo "missing $$artifact" >&2; exit 1; }; \
			if ! .build/release/helut-bench --mulein-future-tensorlut-grade \
				--mulein-future-bank-lanes "$$width" \
				--mulein-future-tensorlut-json "$$artifact" \
				--mulein-future-settings "$(MULEIN_FUTURE_TENSOR_SETTINGS)" \
				--mulein-future-repetitions "$(MULEIN_FUTURE_REPETITIONS)" \
				--mulein-future-tick-limit "$(MULEIN_FUTURE_TICK_LIMIT)" \
				> "$$log" 2>&1; then cat "$$log"; exit 1; fi; \
			cat "$$log"; \
			rate=$$(awk -F': *' '/^median_receipts_per_s/{print $$2}' "$$log"); \
			test -n "$$rate" || { echo "missing rate in $$log" >&2; exit 1; }; \
			printf '%s %s %s %s\n' "$$width" "$$rate" "$$artifact" "$$log" >> "$$rates"; \
		done; \
		digest_count=$$(for width in $(MULEIN_FUTURE_WIDTHS); do \
			awk -F': *' '/^receipt_digest/{print $$2}' \
				"$(MULEIN_BUILD)/mulein_future_bank$${width}_bench.txt"; \
		done | sort -u | wc -l | tr -d ' '); \
		test "$$digest_count" = "1" || { echo "receipt digests differ across widths" >&2; exit 1; }; \
		sort -k2,2nr "$$rates" | head -n 1 > "$$selection"; \
		awk '{print "SELECTED bank_lanes=" $$1 " median_receipts_per_s=" $$2 \
			" artifact=" $$3 " log=" $$4}' "$$selection"

clean-mulein:
	rm -rf "$(MULEIN_BUILD)"
