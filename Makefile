# Document builds — canonical source is TeX; Markdown is generated.
#
#   make writeup     # writeup.tex → writeup.pdf + writeup.md
#   make paper       # paper/helut.tex → paper/helut.pdf + paper/helut.md
#   make textbook    # textbook/helut-living-textbook.tex → pdf + md
#   make docs        # writeup + paper + textbook
#   make test-metal-p1  # Phase 1 Metal BR XCTest battery (release)
#   make gates       # claim lint + determinism gates (run before committing science)
#   make determinism # in-process + cross-process encrypted determinism only

.PHONY: writeup paper textbook note docs clean-docs test-metal-p1 gates determinism

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

test-metal-p1:
	@chmod +x Scripts/helut_metal_phase1_test.sh
	./Scripts/helut_metal_phase1_test.sh

# Encrypted-path determinism. Two gates, because they catch different things:
# the XCTest permutes Dictionary keys within one process, while the script runs
# separate processes — and per-process hash reseeding was the actual 2026-08-15
# fault. Neither is redundant.
#
# SWIFT_DETERMINISTIC_HASHING must stay unset here; it pins the hash seed and
# makes the cross-process check vacuous. The script refuses to run if it is set.
determinism:
	swift test -c release --filter EncryptedDeterminismTests
	python3 Scripts/determinism_cross_process.py --runs 5 --verbose

# Pre-commit ritual for anything that touches a claim. Cheap enough to run every
# time: the lint is seconds, the determinism gates are well under a minute.
# Not CI-enforced — both GitHub runners are ubuntu-latest and this needs macOS.
gates: determinism
	python3 Scripts/claim_audit.py

clean-docs:
	rm -rf build/writeup build/paper build/textbook
	rm -f writeup.aux writeup.log writeup.out writeup.fls writeup.fdb_latexmk writeup.synctex.gz
	rm -f paper/helut.aux paper/helut.log paper/helut.out paper/helut.fls paper/helut.fdb_latexmk paper/helut.synctex.gz
	rm -f textbook/helut-living-textbook.aux textbook/helut-living-textbook.log textbook/helut-living-textbook.out
	rm -f textbook/helut-living-textbook.fls textbook/helut-living-textbook.fdb_latexmk textbook/helut-living-textbook.synctex.gz
	rm -f textbook/helut-living-textbook.toc textbook/helut-living-textbook.bbl textbook/helut-living-textbook.blg
