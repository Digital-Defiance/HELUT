# Document builds — canonical source is TeX; Markdown is generated.
#
#   make writeup     # writeup.tex → writeup.pdf + writeup.md
#   make paper       # paper/helut.tex → paper/helut.pdf + paper/helut.md
#   make docs        # both
#   make clean-docs  # LaTeX aux under build/

.PHONY: writeup paper docs clean-docs

writeup: writeup.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh writeup.tex

paper: paper/helut.tex Scripts/build_writeup.sh
	@chmod +x Scripts/build_writeup.sh
	./Scripts/build_writeup.sh paper/helut.tex

docs: writeup paper

clean-docs:
	rm -rf build/writeup build/paper
	rm -f writeup.aux writeup.log writeup.out writeup.fls writeup.fdb_latexmk writeup.synctex.gz
	rm -f paper/helut.aux paper/helut.log paper/helut.out paper/helut.fls paper/helut.fdb_latexmk paper/helut.synctex.gz
