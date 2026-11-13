#!/usr/bin/env bash
# cases.sh - the cases the renderer profiler measures: every public renderer of lib/terminal_renderer.sh, called through its
# *_string form, on several datasets (size, content) and with several argument sets. Sourced by harness.sh.
#
#   rc_case RENDERER DATASET ARGS_LABEL -- COMMAND...
#     registers one case; COMMAND runs once per timed call, with the output captured by _rc_cap.
#   rc_budget RENDERER MS
#     the per-call budget the report rates RENDERER against (default RC_BUDGET_MS).
#
# Datasets are built here, deterministically (no random numbers, no clock): the same case always renders the same bytes.

declare -ga RC_IDS=()
declare -gA RC_RENDERER=() RC_DATASET=() RC_ARGS=() RC_BUDGET=() RC_FN=() RC_TAGS=()
declare -g RC_BUDGET_MS=5 # a renderer call inside one repaint may take about a tenth of the 50 ms input-feedback budget
declare -g _RC_TMP="" _RC_OUT=""

rc_budget() { RC_BUDGET[$1]=$2; }

# rc_case RENDERER DATASET ARGS_LABEL -- COMMAND...
rc_case() {
	local renderer="$1" dataset="$2" label="$3" id fn
	shift 4
	id="$renderer/$dataset/$label"
	fn="_rc_run_${#RC_IDS[@]}"
	eval "$fn() { $*; }"
	RC_IDS+=("$id")
	RC_RENDERER[$id]="$renderer" RC_DATASET[$id]="$dataset" RC_ARGS[$id]="$label" RC_FN[$id]="$fn"
}

# rc_tag_cases - tags every case, for the scenario selectors: plain (no arguments) or args; unicode (non-ASCII content); and, among the cases of
# one renderer that carry a number in their dataset name, small (the lowest number) and large (the highest).
rc_tag_cases() {
	local id r lo hi n
	local -A low=() high=()
	for id in "${RC_IDS[@]}"; do
		r="${RC_RENDERER[$id]}"
		[[ "${RC_DATASET[$id]}" =~ ([0-9]+)[^0-9]*$ ]] || continue
		n="${BASH_REMATCH[1]}"
		[[ -z "${low[$r]:-}" ]] || ((n < low[$r])) && low[$r]=$n
		[[ -z "${high[$r]:-}" ]] || ((n > high[$r])) && high[$r]=$n
	done
	for id in "${RC_IDS[@]}"; do
		r="${RC_RENDERER[$id]}"
		[[ "${RC_ARGS[$id]}" == plain ]] && RC_TAGS[$id]="plain" || RC_TAGS[$id]="args"
		[[ "${RC_DATASET[$id]}" == unicode ]] && RC_TAGS[$id]+=",unicode"
		if [[ "${RC_DATASET[$id]}" =~ ([0-9]+)[^0-9]*$ ]]; then
			n="${BASH_REMATCH[1]}"
			((n == low[$r])) && RC_TAGS[$id]+=",small"
			((n == high[$r])) && RC_TAGS[$id]+=",large"
		fi
	done
}

# _rc_cap COMMAND... - runs it with stdout to a file and the result in _RC_OUT: no command substitution, so no fork of its own
_rc_cap() {
	"$@" >"$_RC_TMP"
	local rc=$?
	_RC_OUT=$(<"$_RC_TMP")
	return $rc
}

# ── dataset builders (all fork-free) ─────────────────────────────────────────

_RC_WORDS=(render cache terminal widget layout border column buffer frame input focus scroll theme style paint flush)
_RC_SEED=7
_rc_rand() { # N -> _RC_R in [0, N): a fixed linear congruential sequence
	_RC_SEED=$(((_RC_SEED * 1103515245 + 12345) & 0x7fffffff))
	_RC_R=$(((_RC_SEED >> 8) % $1))
}
_rc_reset() { _RC_SEED=7; }

# _rc_text WORDS -> _RC_T : WORDS words, a line break every 12
_rc_text() {
	local i out=""
	for ((i = 0; i < $1; i++)); do
		out+="${_RC_WORDS[i % ${#_RC_WORDS[@]}]}$((i % 10))"
		((i % 12 == 11)) && out+=$'\n' || out+=" "
	done
	_RC_T="$out"
}

# _rc_series N MIN MAX SEP -> _RC_S : N values between MIN and MAX joined by SEP
_rc_series() {
	local i out="" v
	_rc_reset
	for ((i = 0; i < $1; i++)); do
		_rc_rand $(($3 - $2 + 1))
		v=$(($2 + _RC_R))
		out+="${out:+$4}$v"
	done
	_RC_S="$out"
}

# _rc_pairs N PREFIX MAX -> array _RC_P : "PREFIXi:value"
_rc_pairs() {
	local i
	_RC_P=()
	_rc_reset
	for ((i = 0; i < $1; i++)); do
		_rc_rand $(($3 + 1))
		_RC_P+=("$2$i:$_RC_R")
	done
}

# _rc_rows ROWS COLS -> array _RC_ROWS : header, then ROWS rows of COLS cells joined by |
_rc_rows() {
	local r c line
	_RC_ROWS=()
	line=""
	for ((c = 0; c < $2; c++)); do line+="${line:+|}col$c"; done
	_RC_ROWS+=("$line")
	for ((r = 0; r < $1; r++)); do
		line=""
		for ((c = 0; c < $2; c++)); do line+="${line:+|}${_RC_WORDS[(r + c) % ${#_RC_WORDS[@]}]}$r"; done
		_RC_ROWS+=("$line")
	done
}

# _rc_float_series N SCALE -> _RC_S : N one-decimal values ("12.3 4.5 ...") for the float charts
_rc_float_series() {
	local i out="" v
	_rc_reset
	for ((i = 0; i < $1; i++)); do
		_rc_rand $(($2 * 10))
		out+="${out:+ }$((_RC_R / 10)).$((_RC_R % 10))"
	done
	_RC_S="$out"
}

# _rc_csv FILE ROWS COLS : a CSV with a header row
_rc_csv() {
	local r c line
	line="x"
	for ((c = 1; c <= $3; c++)); do line+=",S$c"; done
	{
		echo "$line"
		_rc_reset
		for ((r = 0; r < $2; r++)); do
			line="t$r"
			for ((c = 1; c <= $3; c++)); do
				_rc_rand 100
				line+=",$_RC_R"
			done
			echo "$line"
		done
	} >"$1"
}

# ── the cases ────────────────────────────────────────────────────────────────

rc_define_cases() {
	local tmp="$1" r c n s i p
	_RC_TMP="$tmp/out"

	# box / divider / alert / quote: text in, framed text out
	_rc_text 3
	local short="$_RC_T"
	_rc_text 60
	local para="$_RC_T"
	_rc_text 240
	local long="$_RC_T"
	local wide="日本語のテキスト、ünïcödé àccents, ✓ symbols — 한국어 text that is wider than it looks"
	rc_case box 3-words plain -- _rc_cap box_string "\"$short\""
	rc_case box 60-words plain -- _rc_cap box_string "\"$para\""
	rc_case box 240-words plain -- _rc_cap box_string "\"$long\""
	rc_case box unicode plain -- _rc_cap box_string "\"$wide\""
	rc_case divider none plain -- _rc_cap divider_string
	rc_case divider none label -- _rc_cap divider_string SECTION
	for s in info warn error success; do
		rc_case alert 3-words "$s" -- _rc_cap alert_string "$s" "\"$short\""
	done
	rc_case alert 60-words info -- _rc_cap alert_string info "\"$para\""
	rc_case alert unicode warn -- _rc_cap alert_string warn "\"$wide\""
	rc_case quote 3-words plain -- _rc_cap quote_string "\"$short\""
	rc_case quote 60-words plain -- _rc_cap quote_string "\"$para\""
	rc_case quote unicode plain -- _rc_cap quote_string "\"$wide\""

	# table: rows x columns, plain and unicode cells, a custom delimiter
	for p in "5 3" "50 5" "200 8"; do
		_rc_rows ${p% *} ${p#* }
		declare -ga "_RC_T_${p% *}_${p#* }=(\"\${_RC_ROWS[@]}\")"
		rc_case table "${p% *}x${p#* }" plain -- _rc_cap table_string "\"\${_RC_T_${p% *}_${p#* }[@]}\""
	done
	_RC_TWIDE=("Name|Stadt|Größe" "Zoë|München|1,5 m" "李雷|北京|1,7 m" "Ørjan|Tromsø|1,8 m")
	rc_case table unicode plain -- _rc_cap table_string '"${_RC_TWIDE[@]}"'
	_RC_TCSV=("Name,Age,City" "Alice,30,NYC" "Bob,25,LA" "Cy,41,Oslo")
	rc_case table 3x3 delimiter -- _rc_cap table_string -d '","' '"${_RC_TCSV[@]}"'

	# kv: pairs x style
	for n in 5 50; do
		_RC_KV=()
		for ((i = 0; i < n; i++)); do _RC_KV+=("key$i: value of $i"); done
		declare -ga "_RC_KV_$n=(\"\${_RC_KV[@]}\")"
		for s in dots plain dashes; do
			rc_case kv "$n-pairs" "$s" -- _rc_cap kv_string -t "$s" "\"\${_RC_KV_$n[@]}\""
		done
	done

	# bars and gauges: count x arguments
	for n in 5 30 100; do
		_rc_pairs $n bar 100
		declare -ga "_RC_HB_$n=(\"\${_RC_P[@]}\")"
		rc_case hbar "$n-bars" plain -- _rc_cap hbar_string "\"\${_RC_HB_$n[@]}\""
		rc_case hbar "$n-bars" "width50-labels12" -- _rc_cap hbar_string -w 50 -lw 12 "\"\${_RC_HB_$n[@]}\""
		rc_case hbar "$n-bars" colored -- _rc_cap hbar_string -c GREEN,YELLOW,RED "\"\${_RC_HB_$n[@]}\""
	done
	for n in 0 50 100; do
		rc_case gauge "value-$n" plain -- _rc_cap gauge_string "$n"
	done
	rc_case gauge value-72 "label-width40" -- _rc_cap gauge_string -l CPU -w 40 72
	rc_case gauge value-72 "fixed-color-range" -- _rc_cap gauge_string -c CYAN -n 10 -m 200 150
	for n in 4 16 64; do
		_rc_pairs $n col 100
		declare -ga "_RC_VB_$n=(\"\${_RC_P[@]}\")"
		rc_case vbar "$n-columns" plain -- _rc_cap vbar_string "\"\${_RC_VB_$n[@]}\""
		rc_case vbar "$n-columns" "height20-colwidth4" -- _rc_cap vbar_string -h 20 -cw 4 "\"\${_RC_VB_$n[@]}\""
		rc_case vbar "$n-columns" "colored-fixed-scale" -- _rc_cap vbar_string -h 8 -n 0 -m 100 -c GREEN,YELLOW,RED "\"\${_RC_VB_$n[@]}\""
	done

	# sparkline / linechart / histogram: number of points
	for n in 20 200 2000; do
		_rc_series $n 0 100 " "
		declare -g "_RC_SP_$n=$_RC_S"
		rc_case sparkline "$n-points" plain -- _rc_cap sparkline_string "\"\$_RC_SP_$n\""
		rc_case sparkline "$n-points" "width20-colored" -- _rc_cap sparkline_string -w 20 -c CYAN "\"\$_RC_SP_$n\""
		rc_case sparkline "$n-points" fixed-scale -- _rc_cap sparkline_string -n 0 -m 100 "\"\$_RC_SP_$n\""
	done
	for n in 20 200 1000; do
		_rc_series $n 0 100 ","
		declare -g "_RC_LC_$n=$_RC_S"
		rc_case linechart "1x$n" plain -- _rc_cap linechart_string "\"CPU:\$_RC_LC_$n\""
		rc_case linechart "3x$n" "height12-width30" -- _rc_cap linechart_string -h 12 -w 30 "\"A:\$_RC_LC_$n\"" "\"B:\$_RC_LC_$n\"" "\"C:\$_RC_LC_$n\""
		rc_case linechart "1x$n" "fixed-range-colored" -- _rc_cap linechart_string -n 0 -m 100 -c GREEN "\"Load:\$_RC_LC_$n\""
	done
	for n in 100 2000; do
		_rc_float_series $n 50
		declare -g "_RC_HI_$n=$_RC_S"
		rc_case histogram "$n-values" plain -- _rc_cap histogram_string "\"\$_RC_HI_$n\""
		rc_case histogram "$n-values" "height10-width40" -- _rc_cap histogram_string "\"\$_RC_HI_$n\"" -h 10 -w 40
	done

	# csv charts: files of 10 and 200 rows, one or three series
	for p in "10 1" "200 1" "200 3"; do
		_rc_csv "$tmp/data_${p% *}_${p#* }.csv" ${p% *} ${p#* }
		rc_case csv_hbar "${p% *}rows-${p#* }col" plain -- _rc_cap csv_hbar_string "\"$tmp/data_${p% *}_${p#* }.csv\""
		rc_case csv_vbar "${p% *}rows-${p#* }col" plain -- _rc_cap csv_vbar_string "\"$tmp/data_${p% *}_${p#* }.csv\""
		rc_case csv_linechart "${p% *}rows-${p#* }col" plain -- _rc_cap csv_linechart_string "\"$tmp/data_${p% *}_${p#* }.csv\""
	done

	# statistics charts: scatter, boxplot, forest, heatmap
	for n in 20 200; do
		_rc_series $n 1 100 " "
		local xs="" ys="" v
		_rc_reset
		for ((i = 0; i < n; i++)); do
			_rc_rand 100
			xs+="${xs:+ }$i,$_RC_R"
		done
		declare -g "_RC_SC_$n=$xs"
		rc_case scatter "2x$n" plain -- _rc_cap scatter_string "\"Tests:\$_RC_SC_$n\"" "\"Median:\$_RC_SC_$n\""
		rc_case scatter "2x$n" "height15-width60" -- _rc_cap scatter_string "\"Tests:\$_RC_SC_$n\"" -h 15 -w 60
	done
	for n in 30 300; do
		_rc_series $n 60 500 ","
		declare -g "_RC_BX_$n=$_RC_S"
		rc_case boxplot "3x$n" plain -- _rc_cap boxplot_string "\"A:\$_RC_BX_$n\"" "\"B:\$_RC_BX_$n\"" "\"C:\$_RC_BX_$n\""
		rc_case boxplot "3x$n" width50 -- _rc_cap boxplot_string "\"A:\$_RC_BX_$n\"" "\"B:\$_RC_BX_$n\"" "\"C:\$_RC_BX_$n\"" -w 50 -lw 12
	done
	rc_case forest 4rows plain -- _rc_cap forest_string "\"Keyboard B:-6.2,-9.8,-2.7\"" "\"Layout C:1.3,-0.8,3.3\"" "\"Layout D:4.1,2.0,5.9\"" "\"Layout E:-1.0,0.5,1.2\""
	rc_case forest 4rows "width60-range" -- _rc_cap forest_string "\"Keyboard B:-6.2,-9.8,-2.7\"" "\"Layout C:1.3,-0.8,3.3\"" -w 60 -n -12 -m 8
	for n in 5 20; do
		local hdr="" row
		_RC_HM=()
		for ((c = 0; c < n; c++)); do hdr+="|m$c"; done
		_RC_HM+=("$hdr")
		_rc_reset
		for ((r = 0; r < n; r++)); do
			row="m$r"
			for ((c = 0; c < n; c++)); do
				_rc_rand 200
				row+="|$(((_RC_R - 100) / 100)).$((_RC_R % 10))"
			done
			_RC_HM+=("$row")
		done
		declare -ga "_RC_HM_$n=(\"\${_RC_HM[@]}\")"
		rc_case heatmap "${n}x$n" plain -- _rc_cap heatmap_string "\"\${_RC_HM_$n[@]}\""
		rc_case heatmap "${n}x$n" "cellwidth6-1decimal" -- _rc_cap heatmap_string "\"\${_RC_HM_$n[@]}\"" -cw 6 -p 1
	done

	# banners: text length x font x scale
	for s in "HI" "DABT BANNER"; do
		for p in block5 seg3 box3 blk3 half2; do
			rc_case banner "${s// /_}" "$p" -- _rc_cap banner_string "\"$s\"" "$p"
		done
		rc_case banner "${s// /_}" "block5-scale2" -- _rc_cap banner_string "\"$s\"" block5 2
	done

	# tree / columns / badges / list
	for n in 10 100; do
		local -a lines=("root")
		for ((i = 0; i < n; i++)); do
			case $((i % 4)) in
				0) lines+=("  node$i") ;;
				1) lines+=("    child$i") ;;
				2) lines+=("      leaf$i") ;;
				3) lines+=("  node$i") ;;
			esac
		done
		declare -ga "_RC_TR_$n=(\"\${lines[@]}\")"
		rc_case tree "$n-nodes" plain -- _rc_cap tree_string "\"\${_RC_TR_$n[@]}\""
	done
	_rc_text 30
	local left="$_RC_T"
	rc_case columns "2-blocks-3-words" plain -- _rc_cap columns_string "\"$short\"" "\"$short\""
	rc_case columns "2-blocks-240-words" plain -- _rc_cap columns_string "\"$left\"" "\"$long\""
	for n in 4 40; do
		local -a bs=()
		for ((i = 0; i < n; i++)); do
			case $((i % 4)) in 0) bs+=("pass:Build$i") ;; 1) bs+=("fail:Tests$i") ;; 2) bs+=("skip:Lint$i") ;; 3) bs+=("info:v2.$i") ;; esac
		done
		declare -ga "_RC_BG_$n=(\"\${bs[@]}\")"
		rc_case badges "$n-badges" plain -- _rc_cap badges_string "\"\${_RC_BG_$n[@]}\""
	done
	for n in 5 100; do
		local -a li=()
		for ((i = 0; i < n; i++)); do li+=("item number $i with some text"); done
		declare -ga "_RC_LI_$n=(\"\${li[@]}\")"
		rc_case list "$n-items" plain -- _rc_cap list_string "\"\${_RC_LI_$n[@]}\""
	done

	# the heavier charts get a looser per-call budget
	local r
	for r in table banner; do rc_budget "$r" 10; done
	for r in vbar linechart histogram csv_hbar csv_vbar csv_linechart scatter boxplot forest heatmap tree; do rc_budget "$r" 15; done
}
