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

text=${1:?usage: gen_header.sh "TEXT" [OUT.svg] [CELL_PX]}
text=${text^^}
C=${3:-7} LG=1 WG=3
read -ra cols <<<"${HEADER_COLORS:-#ff8cbf #a8d8ff #fff3a8 #ff9e9e}"
slug=$(tr -c 'a-z0-9\n' '-' <<<"${text,,}" | sed 's/--*/-/g; s/^-//; s/-$//')
out=${2:-$here/assets/headers/$slug.svg}
mkdir -p "$(dirname "$out")"

body="" cx=0 i=0
for ((n=0;n<${#text};n++)); do
  ch=${text:n:1}
  if [[ $ch == " " ]]; then cx=$((cx+WG)); continue; fi
  [[ -n "${_BANNER_FONT[$ch]+x}" ]] || continue
  IFS='|' read -ra rows <<<"${_BANNER_FONT[$ch]}"
  for ((r=0;r<5;r++)); do
    row=${rows[r]}
    for ((c=0;c<${#row};c++)); do
      [[ ${row:c:1} == "█" ]] && body+="<rect fill=\"${cols[i%${#cols[@]}]}\" x=\"$(((cx+c)*C))\" y=\"$((r*C))\" width=\"$C\" height=\"$C\"/>"$'\n'
    done
  done
  cx=$((cx+${#rows[0]}+LG)); i=$((i+1))
done
w=$(((cx-LG)*C))
printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" shape-rendering="crispEdges">\n%s</svg>\n' \
  "$w" $((5*C)) "$w" $((5*C)) "$body" > "$out"
echo "$out"
