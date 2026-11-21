#!/usr/bin/env bash
# ab.sh - traceable A/B(/C..) timing: run N things from a scenario file, compare them, keep everything.
#
#   ab.sh run SCENARIO [-n ROUNDS] [-w WARMUP] [-o OUTDIR]   run all sides interleaved, report, save a run dir
#   ab.sh compare RUN_A RUN_B [SIDE_A [SIDE_B]]               compare two saved runs (no sides = every shared side label)
#   ab.sh list                                                one line per saved run
#   ab.sh show RUN                                            print a run's meta + report
#
# Scenario file (sourced bash):
#   AB_NAME="my-test"               required, used in the run dir name
#   AB_DESC="what is compared"      optional
#   AB_SIDES=(inline d1 d2)         side labels (>= 2)
#   AB_CMDS=(run_inline "run_d 1" "run_d 2")   one per side: a function from the scenario, or a command / script path
#   AB_CONTROL=inline               optional side whose median is subtracted (loop overhead etc.) and used as the base
#   AB_UNITS=10000                  optional work units per sample (calls, iterations): adds ns/unit columns
#   AB_UNIT_NAME=iteration          what one unit is called in the report (default: unit)
#   AB_PER=(0 1 2)                 optional: inner operations per unit for each side (e.g. calls per iteration); the report
#   AB_PER_NAME=call                then shows the net cost of ONE such operation (default name: call)
#   AB_X=(0 1 2)                    optional numeric x per side: adds a slope/intercept (cost per x) over the per-unit value
#   AB_ROUNDS=30 AB_WARMUP=3        defaults, overridable with -n / -w
#   ab_setup() / ab_teardown()      optional, once per run
#   ab_before_side LABEL            optional, before every sample of that side (not timed)
#   AB_SUITE=(a.sh b.sh)            instead of sides: run those scenarios (paths relative to this file) one after another
#   Two-side shorthand: A_LABEL/A_CMD/B_LABEL/B_CMD instead of AB_SIDES/AB_CMDS.
#
# A run dir (runs/<UTC stamp>_<name>/) holds: scenario.sh (copy), meta.txt (git rev, host, cpu, hashes,
# the function bodies that ran), samples.tsv (round side us), report.txt. runs/index.tsv gets one line per run.
AB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AB_RUNS="${AB_RUNS:-$AB_DIR/runs}"
LC_ALL=C
export LC_ALL

die() {
	printf 'ab: %s\n' "$*" >&2
	exit 1
}

# _report_run DIR - one table for every side in DIR/meta.txt (side lines) + DIR/samples.tsv.
# Columns: n, mean/median/p95/min/sd in us; with units: ns per unit (median) and, with a control side,
# net ns per unit (median minus control). "vs base" = median delta vs the control (else first side) and
# a Welch t verdict on the means (|t|<2 = ~ within noise); all deltas are median-based. With a numeric x per side: least-squares slope/intercept of
# the per-unit value over x. Last line is "summary: ...".
_report_run() {
	awk -F'\t' '
	FNR == NR {
		if ($0 ~ /^--- /) stop = 1
		if (stop) next
		if ($1 == "side") { order[++ns] = $2; xs[$2] = $4 }
		else if ($1 == "units") units = $2 + 0
		else if ($1 == "control") control = $2
		next
	}
	{ v[$2, ++cnt[$2]] = $3 }
	function stat(s,   n, i, j, x, t, sum, m, ss) {
		n = cnt[s]; if (!n) return 0
		for (i = 1; i <= n; i++) { t[i] = v[s, i]; sum += t[i] }
		m = sum / n
		for (i = 1; i <= n; i++) ss += (t[i] - m) ^ 2
		SD[s] = n > 1 ? sqrt(ss / (n - 1)) : 0
		for (i = 2; i <= n; i++) { x = t[i]; j = i - 1; while (j > 0 && t[j] > x) { t[j + 1] = t[j]; j-- } t[j + 1] = x }
		MED[s] = n % 2 ? t[(n + 1) / 2] : (t[n / 2] + t[n / 2 + 1]) / 2
		j = int(n * 0.95); if (j >= n) j = n - 1
		P95[s] = t[j + 1]; MIN[s] = t[1]; MAX[s] = t[n]; MEAN[s] = m
		return 1
	}
	function verdict(s, b,   se, t, pct) {
		se = sqrt(SD[s] ^ 2 / cnt[s] + SD[b] ^ 2 / cnt[b])
		t = se ? (MEAN[s] - MEAN[b]) / se : 0; if (t < 0) t = -t
		pct = MED[b] ? (MED[s] - MED[b]) * 100 / MED[b] : 0
		return sprintf("%+.1f%% %s (t=%.1f)", pct, t < 2 ? "~noise" : (MED[s] < MED[b] ? "faster" : "slower"), t)
	}
	function fmt(us,   a) {
		a = us < 0 ? -us : us
		return a < 1000 ? sprintf("%.0f us", us) : a < 1000000 ? sprintf("%.2f ms", us / 1000) : sprintf("%.3f s", us / 1000000)
	}
	function pad(s) { return sprintf("%-22.22s", s) }
	END {
		for (k = 1; k <= ns; k++) { if (!stat(order[k])) die = 1 }
		base = control != "" ? control : order[1]
		printf "%-22.22s %5s %10s %10s %10s %10s %10s", "side", "n", "mean_us", "median_us", "p95_us", "min_us", "sd_us"
		if (units) printf " %11s", "ns/unit"
		if (units && control != "") printf " %11s", "net_ns/unit"
		printf "  vs %s\n", base
		npts = 0
		for (k = 1; k <= ns; k++) {
			s = order[k]
			printf "%-22.22s %5d %10.0f %10.0f %10d %10d %10.0f", s, cnt[s], MEAN[s], MED[s], P95[s], MIN[s], SD[s]
			per = units ? MED[s] * 1000 / units : MED[s]
			net = (units && control != "") ? (MED[s] - MED[control]) * 1000 / units : per
			if (units) printf " %11.1f", per
			if (units && control != "") printf " %11.1f", net
			printf "  %s\n", s == base ? "(base)" : verdict(s, base)
			if (xs[s] != "") { npts++; px[npts] = xs[s] + 0; py[npts] = net }
		}
		printf "\nRESULT (times per sample, \"average\" = median over %d rounds)\n", cnt[base]
		for (k = 1; k <= ns; k++) {
			s = order[k]
			printf "  %s median %-10s slowest %-10s fastest %-10s%s\n", pad(s), fmt(MED[s]), fmt(MAX[s]), fmt(MIN[s]), s == base ? "  (base)" : ""
		}
		for (k = 1; k <= ns; k++) {
			s = order[k]; if (s == base) continue
			d = MED[s] - MED[base]; pct = MED[base] ? d * 100 / MED[base] : 0
			se = sqrt(SD[s] ^ 2 / cnt[s] + SD[base] ^ 2 / cnt[base]); tt = se ? (MEAN[s] - MEAN[base]) / se : 0; if (tt < 0) tt = -tt
			ad = d < 0 ? -d : d; ap = pct < 0 ? -pct : pct
			if (tt < 2) printf "  %s vs %s: NO CLEAR DIFFERENCE - %s by %.1f%% / %s on average is within noise (t=%.1f)\n", s, base, d < 0 ? "faster" : "slower", ap, fmt(ad), tt
			else printf "  %s is %s than %s by an average of %.1f%% / %s%s\n", s, d < 0 ? "FASTER" : "SLOWER", base, ap, fmt(ad), units ? sprintf(" (%.1f ns per unit)", ad * 1000 / units) : ""
		}
		printf "\n"
		if (npts >= 3 && npts == ns) {
			for (i = 1; i <= npts; i++) { sx += px[i]; sy += py[i]; sxx += px[i] ^ 2; sxy += px[i] * py[i] }
			den = npts * sxx - sx ^ 2
			if (den) { sl = (npts * sxy - sx * sy) / den; ic = (sy - sl * sx) / npts }
			printf "summary: slope=%.1f %s per x, intercept=%.1f %s\n", sl, units ? "ns/unit" : "us", ic, units ? "ns/unit" : "us"
		} else {
			printf "summary: %s vs %s: %s\n", order[ns], base, order[ns] == base ? "(base)" : verdict(order[ns], base)
		}
	}' "$1/meta.txt" "$1/samples.tsv"
}

# _pair_report DIR_A SIDE_A DIR_B SIDE_B - one two-row table from two saved runs
_pair_report() {
	local t
	t="$(mktemp -d)" || die "mktemp failed"
	printf 'side\tA/%s\t\t\nside\tB/%s\t\t\nunits\t%s\n' "$2" "$4" "$(_meta "$1" units)" >"$t/meta.txt"
	{
		awk -F'\t' -v s="$2" '$2 == s { print $1 "\tA/" s "\t" $3 }' "$1/samples.tsv"
		awk -F'\t' -v s="$4" '$2 == s { print $1 "\tB/" s "\t" $3 }' "$3/samples.tsv"
	} >"$t/samples.tsv"
	_report_run "$t"
	rm -rf "$t"
}

# the shared reporter needs python3 and tools/benchmarks/reporting; AB_PLAIN=1 forces the plain awk report
_have_reporter() { [[ -z $AB_PLAIN ]] && command -v python3 >/dev/null && [[ -d $AB_DIR/../reporting ]]; }

_cpu_info() {
	local gov="" model=""
	[[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]] && read -r gov </sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null)"
	printf '%s | governor=%s | load=%s' "${model#*: }" "${gov:-?}" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
}

# _cmd_body CMD - function body when CMD names a function, else the script file's hash, else the command text
_cmd_body() {
	local first="${1%% *}"
	if declare -F "$first" >/dev/null; then
		declare -f "$first"
	elif [[ -f $first ]]; then
		printf '%s  %s\n' "$(sha256sum "$first" | cut -c1-16)" "$first"
	else
		printf '%s\n' "$1"
	fi
}

_time_side() { # CMD -> us on stdout via _AB_US
	local t0 t1
	t0="${EPOCHREALTIME//[!0-9]/}"
	$1 >/dev/null 2>&1
	_AB_RC=$?
	t1="${EPOCHREALTIME//[!0-9]/}"
	_AB_US=$((t1 - t0))
}

cmd_run() {
	local scn="" rounds="" warm="" out=""
	while (($#)); do
		case "$1" in
			-n)
				rounds="$2"
				shift 2
				;;
			-w)
				warm="$2"
				shift 2
				;;
			-o)
				out="$2"
				shift 2
				;;
			*)
				scn="$1"
				shift
				;;
		esac
	done
	[[ -f $scn ]] || die "scenario file not found: '$scn'"
	scn="$(cd -P "$(dirname "$scn")" && pwd -P)/$(basename "$scn")"
	AB_SIDES=() AB_CMDS=() AB_X=() AB_PER=() AB_CONTROL="" AB_UNITS="" AB_UNIT_NAME="" AB_PER_NAME="" AB_SUITE=()
	# shellcheck disable=SC1090
	source "$scn"
	if ((${#AB_SUITE[@]})); then # a suite: run each listed scenario as its own run
		local f args=()
		[[ -n $rounds ]] && args+=(-n "$rounds")
		[[ -n $warm ]] && args+=(-w "$warm")
		local list
		list="$(mktemp)" || die "mktemp failed"
		for f in "${AB_SUITE[@]}"; do
			printf '\n##### %s\n' "$f"
			AB_SUITE_LIST="$list" bash "$AB_DIR/ab.sh" run "$(dirname "$scn")/$f" "${args[@]}" || die "suite scenario failed: $f"
		done
		local runs=()
		mapfile -t runs <"$list"
		rm -f "$list"
		printf '\n'
		if _have_reporter; then
			python3 -I "$AB_DIR/ab_report.py" --suite "${runs[@]}" --save "$AB_RUNS/$(date -u +%Y%m%dT%H%M%SZ)_suite_${scn##*/}.txt"
		else
			for f in "${runs[@]}"; do printf '%s\t%s\n' "${f##*/}" "$(grep '^summary: ' "$f/report.txt")"; done
		fi
		return
	fi
	: "${AB_NAME:?scenario must set AB_NAME}"
	if ((${#AB_SIDES[@]} == 0)); then # two-sided shorthand
		: "${A_CMD:?scenario must set AB_SIDES/AB_CMDS or A_CMD and B_CMD}" "${B_CMD:?scenario must set B_CMD}"
		AB_SIDES=("${A_LABEL:-A}" "${B_LABEL:-B}")
		AB_CMDS=("$A_CMD" "$B_CMD")
	fi
	local ns=${#AB_SIDES[@]} i k
	((ns >= 2)) || die "need at least 2 sides"
	((ns == ${#AB_CMDS[@]})) || die "AB_SIDES and AB_CMDS differ in length"
	((${#AB_X[@]} == 0 || ${#AB_X[@]} == ns)) || die "AB_X must be empty or one value per side"
	((${#AB_PER[@]} == 0 || ${#AB_PER[@]} == ns)) || die "AB_PER must be empty or one value per side"
	[[ -z $AB_CONTROL ]] || [[ " ${AB_SIDES[*]} " == *" $AB_CONTROL "* ]] || die "AB_CONTROL '$AB_CONTROL' is not a side"
	rounds="${rounds:-${AB_ROUNDS:-30}}" warm="${warm:-${AB_WARMUP:-3}}"
	local stamp dir
	stamp="$(date -u +%Y%m%dT%H%M%SZ)"
	dir="${out:-$AB_RUNS/${stamp}_${AB_NAME}}"
	mkdir -p "$dir" || die "cannot create $dir"
	cp "$scn" "$dir/scenario.sh"

	local rev dirty=""
	if rev="$(git -C "$AB_DIR" rev-parse --short HEAD 2>/dev/null)"; then
		[[ -n "$(git -C "$AB_DIR" status --porcelain 2>/dev/null)" ]] && dirty="+dirty"
	else
		rev="no-git"
	fi
	{
		printf 'name\t%s\ndesc\t%s\nstamp\t%s\nrounds\t%s\nwarmup\t%s\nunits\t%s\ncontrol\t%s\nunit_name\t%s\nper_name\t%s\n' \
			"$AB_NAME" "${AB_DESC:-}" "$stamp" "$rounds" "$warm" "$AB_UNITS" "$AB_CONTROL" "${AB_UNIT_NAME:-unit}" "${AB_PER_NAME:-call}"
		for ((i = 0; i < ns; i++)); do printf 'side\t%s\t%s\t%s\t%s\n' "${AB_SIDES[i]}" "${AB_CMDS[i]}" "${AB_X[i]:-}" "${AB_PER[i]:-}"; done
		printf 'scenario_sha\t%s\ngit\t%s%s\nhost\t%s\nkernel\t%s\ncpu\t%s\ncwd\t%s\nbash\t%s\n' \
			"$(sha256sum "$scn" | cut -c1-16)" "$rev" "$dirty" "$(hostname)" "$(uname -sr)" "$(_cpu_info)" "$PWD" "$BASH_VERSION"
		for ((i = 0; i < ns; i++)); do
			printf '\n--- %s body ---\n' "${AB_SIDES[i]}"
			_cmd_body "${AB_CMDS[i]}"
		done
	} >"$dir/meta.txt"

	declare -F ab_setup >/dev/null && ab_setup
	local fails=0 t_start="${EPOCHREALTIME//[!0-9]/}" live_pid=""
	: >"$dir/samples.tsv"
	: >"$dir/warmup.tsv"
	# live view: the shared reporter follows the two sample files; it costs a little CPU beside the run (AB_LIVE=0: off)
	if _have_reporter && [[ ${AB_LIVE:-1} != 0 ]]; then
		python3 -I "$AB_DIR/ab_report.py" "$dir" --live --pid $$ &
		live_pid=$!
	fi
	for ((i = 1; i <= warm; i++)); do
		for ((k = 0; k < ns; k++)); do
			declare -F ab_before_side >/dev/null && ab_before_side "${AB_SIDES[k]}"
			_time_side "${AB_CMDS[k]}"
			printf '%d\t%s\t%d\n' "$i" "${AB_SIDES[k]}" "$_AB_US" >>"$dir/warmup.tsv"
		done
	done
	for ((i = 1; i <= rounds; i++)); do
		# rotate which side goes first each round: cancels order bias and slow drift
		for ((k = 0; k < ns; k++)); do
			local idx=$(((i + k) % ns))
			declare -F ab_before_side >/dev/null && ab_before_side "${AB_SIDES[idx]}"
			_time_side "${AB_CMDS[idx]}"
			((_AB_RC)) && ((fails++))
			printf '%d\t%s\t%d\n' "$i" "${AB_SIDES[idx]}" "$_AB_US" >>"$dir/samples.tsv"
		done
		[[ -n $live_pid ]] || printf '\r  round %d/%d' "$i" "$rounds" >&2
	done
	[[ -n $live_pid ]] && wait "$live_pid"
	printf '\r%*s\r' 30 '' >&2
	declare -F ab_teardown >/dev/null && ab_teardown
	printf '%d\n' $((("${EPOCHREALTIME//[!0-9]/}" - t_start) / 1000000)) >"$dir/duration_s"

	if _have_reporter; then
		python3 -I "$AB_DIR/ab_report.py" "$dir" --save || die "reporter failed (AB_PLAIN=1 for the plain awk report)"
	else
		{
			printf '%s  [%s]  %s\n' "$AB_NAME" "$stamp" "${AB_DESC:-}"
			printf 'rounds=%s warmup=%s units=%s control=%s git=%s%s non-zero exits=%s\n\n' "$rounds" "$warm" "${AB_UNITS:--}" "${AB_CONTROL:--}" "$rev" "$dirty" "$fails"
			_report_run "$dir"
		} | tee "$dir/report.txt"
	fi
	local summary
	summary="$(grep '^summary: ' "$dir/report.txt")"
	printf '%s\t%s\t%s\t%s\n' "$stamp" "$AB_NAME" "$rev$dirty" "${summary#summary: }" >>"$AB_RUNS/index.tsv"
	printf '\nsaved: %s\n' "$dir"
	[[ -n $AB_SUITE_LIST ]] && printf '%s\n' "$dir" >>"$AB_SUITE_LIST"
}

_resolve_run() { # name or path -> dir
	if [[ -d $1 ]]; then
		(cd -P "$1" && pwd -P)
		return
	fi
	local m=("$AB_RUNS"/*"$1"*/)
	[[ -d ${m[0]} ]] || die "no run matching '$1'"
	((${#m[@]} > 1)) && die "'$1' is ambiguous (${#m[@]} runs)"
	printf '%s\n' "${m[0]%/}"
}

_meta() { awk -F'\t' -v k="$2" '$1 == k { print $2; exit }' "$1/meta.txt"; }

cmd_compare() {
	(($# >= 2)) || die "usage: compare RUN_A RUN_B [SIDE_A SIDE_B]  (no sides = every side label both runs share)"
	local da db sa="${3:-}" sb="${4:-}"
	da="$(_resolve_run "$1")" || exit 1
	db="$(_resolve_run "$2")" || exit 1
	printf 'A = %s\nB = %s\n' "$(basename "$da")" "$(basename "$db")"
	printf 'git: %s vs %s | scenario sha: %s vs %s\n' "$(_meta "$da" git)" "$(_meta "$db" git)" "$(_meta "$da" scenario_sha)" "$(_meta "$db" scenario_sha)"
	[[ "$(_meta "$da" scenario_sha)" != "$(_meta "$db" scenario_sha)" ]] && printf 'WARNING: scenarios differ - the comparison may not be like for like\n'
	printf '\n'
	if [[ -n $sa ]]; then
		_pair_report "$da" "$sa" "$db" "${sb:-$sa}"
		return
	fi
	if _have_reporter; then # B's full report with the diff block against A
		python3 -I "$AB_DIR/ab_report.py" "$db" --vs "$da"
		return
	fi
	local l
	while IFS= read -r l; do
		grep -q "^side	$l	" "$db/meta.txt" && {
			_pair_report "$da" "$l" "$db" "$l"
			printf '\n'
		}
	done < <(awk -F'\t' '/^--- /{exit} $1 == "side" { print $2 }' "$da/meta.txt")
}

cmd_list() {
	[[ -f $AB_RUNS/index.tsv ]] || {
		echo "no runs yet"
		return
	}
	printf 'stamp\tname\tgit\tverdict\n'
	cat "$AB_RUNS/index.tsv"
}

cmd_show() {
	local d
	d="$(_resolve_run "${1:?usage: show RUN}")" || exit 1
	cat "$d/meta.txt" "$d/report.txt"
}

case "${1:-}" in
	run)
		shift
		cmd_run "$@"
		;;
	compare)
		shift
		cmd_compare "$@"
		;;
	list) cmd_list ;;
	show)
		shift
		cmd_show "$@"
		;;
	*)
		sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 2
		;;
esac
