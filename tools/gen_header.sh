#!/usr/bin/env bash
# Generate a block5 header SVG (transparent bg) from a string.
# Usage: tools/gen_header.sh "TEXT" [OUT.svg] [CELL_PX]
#   OUT defaults to assets/headers/<slug>.svg; CELL_PX defaults to 7 (height = 5 cells).
# Font: A-Z 0-9 . - : ? / _ !  (lowercase is uppercased, other chars dropped)
# Env: HEADER_COLORS="#ff8cbf #a8d8ff #fff3a8 #ff9e9e" (cycled per letter)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
source "$here/lib/terminal_renderer.sh"
_banner_font_init
DAPK_DIR="$here/lib/dapk"

text=${1:?usage: gen_header.sh "TEXT" [OUT.svg] [CELL_PX]}
source "$here/lib/dapk/header.sh"
text=${text^^}
slug=$(tr -c 'a-z0-9\n' '-' <<<"${text,,}" | sed 's/--*/-/g; s/^-//; s/-$//')
out=${2:-$here/assets/headers/$slug.svg}
dapk.header.generate "$text" "$out" "${3:-7}"
echo "$out"
