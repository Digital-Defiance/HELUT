#!/usr/bin/env bash
# Compute sha256 for a HELUT release tag and print fields for homebrew-tap/Formula/helut.rb
set -euo pipefail
TAG="${1:?usage: $0 0.1.0}"
URL="https://github.com/Digital-Defiance/HELUT/archive/refs/tags/${TAG}.tar.gz"
TMP="$(mktemp -t helut-brewXXXXXX.tar.gz)"
echo "Fetching ${URL}"
curl -fsSL -o "$TMP" "$URL"
SUM="$(shasum -a 256 "$TMP" | awk '{print $1}')"
rm -f "$TMP"
VER="${TAG#helut-lib-}"
VER="${VER#v}"
TAP_FORMULA="${HOMEBREW_TAP_FORMULA:-/Volumes/Code/homebrew-tap/Formula/helut.rb}"
echo ""
echo "  url \"${URL}\""
echo "  version \"${VER}\""
echo "  sha256 \"${SUM}\""
echo ""
echo "Update: ${TAP_FORMULA}"
