#!/usr/bin/env bash
# Build a document from canonical TeX → PDF + Markdown.
#
#   ./Scripts/build_writeup.sh              # writeup.tex (repo root)
#   ./Scripts/build_writeup.sh writeup.tex
#   ./Scripts/build_writeup.sh paper/helut.tex
#
# Markdown is generated — do not edit *.md by hand; edit the .tex.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEX_ARG="${1:-writeup.tex}"
if [[ "$TEX_ARG" = /* ]]; then
  TEX="$TEX_ARG"
else
  TEX="$ROOT/$TEX_ARG"
fi
if [[ ! -f "$TEX" ]]; then
  echo "error: missing $TEX_ARG" >&2
  exit 1
fi

tex_dir="$(cd "$(dirname "$TEX")" && pwd)"
base="$(basename "$TEX" .tex)"
rel_dir="${tex_dir#"$ROOT"/}"
if [[ "$rel_dir" == "$tex_dir" || -z "$rel_dir" || "$rel_dir" == "$ROOT" ]]; then
  rel_dir="."
  outdir="$ROOT/build/$base"
else
  outdir="$ROOT/build/$rel_dir/$base"
fi
mkdir -p "$outdir"

if ! command -v latexmk >/dev/null 2>&1; then
  echo "error: latexmk not found (install MacTeX / TeX Live)" >&2
  exit 1
fi
if ! command -v pandoc >/dev/null 2>&1; then
  echo "error: pandoc not found (brew install pandoc)" >&2
  exit 1
fi

echo "==> PDF  ${TEX_ARG} → ${rel_dir}/${base}.pdf"
(
  cd "$tex_dir"
  latexmk -pdf -interaction=nonstopmode -halt-on-error \
    -outdir="$outdir" \
    "${base}.tex"
)
cp -f "$outdir/${base}.pdf" "${tex_dir}/${base}.pdf"

echo "==> MD   ${TEX_ARG} → ${rel_dir}/${base}.md"
tmp_md="$(mktemp)"
tmp_raw="$(mktemp)"
# Pandoc resolves \\input relative to cwd, not the .tex path.
(
  cd "$tex_dir"
  pandoc "${base}.tex" -f latex -t markdown --wrap=none -s -o "$tmp_raw"
)
python3 - "$tmp_raw" "$tmp_md" <<'PY'
import re, sys, yaml

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
if not text.startswith("---\n") and not text.startswith("---\r\n"):
    open(dst, "w", encoding="utf-8").write(text)
    raise SystemExit(0)

# First YAML document only (em-dashes inside values must not be written as --- by pandoc).
rest = text[3:]  # drop opening ---
end = rest.find("\n---")
if end < 0:
    open(dst, "w", encoding="utf-8").write(text)
    raise SystemExit(0)
yaml_block, body = rest[:end], rest[end + 4 :].lstrip("\n")
meta = yaml.safe_load(yaml_block) or {}

def clean(val) -> str:
    if val is None:
        return ""
    if isinstance(val, list):
        return " — ".join(clean(v) for v in val if clean(v))
    s = str(val)
    s = s.replace("\\\n", " ").replace("\n", " ")
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"\1", s)
    s = re.sub(r"[ \t]+", " ", s).strip()
    return s

title = clean(meta.get("title"))
author = clean(meta.get("author"))
date = clean(meta.get("date"))
abstract = clean(meta.get("abstract"))

out = []
if title:
    out += [f"# {title}", ""]
meta_line = " · ".join(p for p in (author, date) if p)
if meta_line:
    out += [f"*{meta_line}*", ""]
if abstract:
    out += ["## Abstract", "", abstract, ""]
out.append(body.rstrip() + "\n")
open(dst, "w", encoding="utf-8").write("\n".join(out))
PY
{
  echo "<!-- Generated from ${base}.tex — do not edit by hand. Run: make writeup   (or ./Scripts/build_writeup.sh ${TEX_ARG}) -->"
  echo
  cat "$tmp_md"
} > "${tex_dir}/${base}.md"
rm -f "$tmp_md" "$tmp_raw"

echo "done: ${tex_dir}/${base}.pdf"
echo "      ${tex_dir}/${base}.md"
echo "      aux: ${outdir}/"
