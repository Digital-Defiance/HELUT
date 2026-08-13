# Document builds — canonical source is TeX; Markdown is generated.
#
#   make writeup     # writeup.tex → writeup.pdf + writeup.md
#   make paper       # paper/helut.tex → paper/helut.pdf + paper/helut.md
#   make textbook    # textbook/helut-living-textbook.tex → pdf + md
#   make docs        # writeup + paper + textbook
#   make test-metal-p1  # Phase 1 Metal BR XCTest battery (release)

.PHONY: writeup paper textbook docs clean-docs test-metal-p1

writeup: writeup.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh writeup.tex

paper: paper/helut.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh paper/helut.tex

textbook: textbook/helut-living-textbook.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh textbook/helut-living-textbook.tex

docs: writeup paper textbook

test-metal-p1:
	@chmod +x Scripts/helut_metal_phase1_test.sh
	./Scripts/helut_metal_phase1_test.sh

clean-docs:
	rm -rf build/writeup build/paper build/textbook
	rm -f writeup.aux writeup.log writeup.out writeup.fls writeup.fdb_latexmk writeup.synctex.gz
	rm -f paper/helut.aux paper/helut.log paper/helut.out paper/helut.fls paper/helut.fdb_latexmk paper/helut.synctex.gz
	rm -f textbook/helut-living-textbook.aux textbook/helut-living-textbook.log textbook/helut-living-textbook.out
	rm -f textbook/helut-living-textbook.fls textbook/helut-living-textbook.fdb_latexmk textbook/helut-living-textbook.synctex.gz
	rm -f textbook/helut-living-textbook.toc textbook/helut-living-textbook.bbl textbook/helut-living-textbook.blg
