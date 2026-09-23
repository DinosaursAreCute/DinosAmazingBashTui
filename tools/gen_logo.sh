#!/usr/bin/env bash
# Generates assets/logo.svg from the block5 banner glyphs (lib/terminal_renderer.sh).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
W=1280 H=640 C=44 G=0 LG=44 # canvas, cell size, cell gap, letter gap
glyphs=("███ |█  █|█  █|█  █|███ " " ██ |████|█  █|████|█  █" "███ |█  █|███ |█  █|███ " "█████|  █  |  █  |  █  |  █  ")
# total width in cells
tw=0
for g in "${glyphs[@]}"; do
	IFS='|' read -ra r <<<"$g"
	tw=$((tw + ${#r[0]} * C + LG))
done
tw=$((tw - LG))
cols=("#ff8cbf" "#a8d8ff" "#fff3a8" "#ff9e9e")
x0=$(((W - tw) / 2))
y0=200
{
	echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$W\" height=\"$H\" viewBox=\"0 0 $W $H\">"
	echo "<rect width=\"$W\" height=\"$H\" fill=\"#0d1117\"/>"
	echo '<g shape-rendering="crispEdges">'
	x=$x0
	i=0
	for g in "${glyphs[@]}"; do
		IFS='|' read -ra rows <<<"$g"
		for ((r = 0; r < 5; r++)); do
			row=${rows[r]}
			for ((c = 0; c < ${#row}; c++)); do
				[[ ${row:c:1} == "█" ]] && echo "<rect fill=\"${cols[i]}\" x=\"$((x + c * C))\" y=\"$((y0 + r * C))\" width=\"$((C - G))\" height=\"$((C - G))\"/>"
			done
		done
		x=$((x + ${#rows[0]} * C + LG))
		i=$((i + 1))
	done
	echo '</g>'
	echo "<text x=\"$((W / 2))\" y=\"490\" text-anchor=\"middle\" font-family=\"monospace\" font-size=\"34\" fill=\"#8b949e\" letter-spacing=\"6\">DinosAmazingBashTui</text>"
	echo "<text x=\"$((W / 2))\" y=\"545\" text-anchor=\"middle\" font-family=\"monospace\" font-size=\"22\" fill=\"#6e7681\">declarative terminal UIs · pure bash · zero dependencies</text>"
	echo '</svg>'
} >"$here/assets/logo.svg"
grep -v "fill=\"#0d1117\"" "$here/assets/logo.svg" >"$here/assets/logo-transparent.svg"
