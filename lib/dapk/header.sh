#!/usr/bin/env bash
# header.sh - the block-font header images used in release notes (same look as assets/headers/*.svg).
#
# dapk.header.generate TEXT OUT [CELL_PX]   writes a transparent SVG of TEXT in the block5 font (default cell 7px, height = 5 cells); rc 1 on failure
#     Font: A-Z 0-9 . - : ? / _ !  (lowercase is uppercased, other characters are dropped). Env HEADER_COLORS="#ff8cbf #a8d8ff ..." (cycled per letter).
# dapk.header.version_file VERSION          assets/headers/v1-4-2.svg (the file `dabt pkg release` writes and the release notes point at)

_DAPK_HEADER_COLORS="#ff8cbf #a8d8ff #fff3a8 #ff9e9e"

dapk.header.version_file() {
	local v="${1//./-}"
	printf 'assets/headers/v%s.svg' "${v//+/-}"
}

dapk.header.generate() {
	local text="${1^^}" out="$2" C="${3:-7}" LG=1 WG=3 body="" cx=0 i=0 n r c ch row w
	local -a cols rows
	[[ -n "$text" && -n "$out" ]] || return 1
	# shellcheck source=../terminal_renderer.sh
	declare -F _banner_font_init >/dev/null || source "${TUI_ROOT:-${DAPK_DIR%/lib/dapk}}/lib/terminal_renderer.sh" || return 1
	[[ -n "${_BANNER_FONT[A]+x}" ]] || _banner_font_init
	read -ra cols <<<"${HEADER_COLORS:-$_DAPK_HEADER_COLORS}"
	for ((n = 0; n < ${#text}; n++)); do
		ch="${text:n:1}"
		if [[ "$ch" == " " ]]; then
			cx=$((cx + WG))
			continue
		fi
		[[ -n "${_BANNER_FONT[$ch]+x}" ]] || continue
		IFS='|' read -ra rows <<<"${_BANNER_FONT[$ch]}"
		for ((r = 0; r < 5; r++)); do
			row="${rows[r]}"
			for ((c = 0; c < ${#row}; c++)); do
				[[ "${row:c:1}" == "█" ]] && body+="<rect fill=\"${cols[i % ${#cols[@]}]}\" x=\"$(((cx + c) * C))\" y=\"$((r * C))\" width=\"$C\" height=\"$C\"/>"$'\n'
			done
		done
		cx=$((cx + ${#rows[0]} + LG))
		i=$((i + 1))
	done
	((i)) || return 1
	w=$(((cx - LG) * C))
	mkdir -p "$(dirname "$out")" || return 1
	printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" shape-rendering="crispEdges">\n%s</svg>\n' "$w" $((5 * C)) "$w" $((5 * C)) "$body" >"$out"
}
