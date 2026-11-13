#!/usr/bin/env bash
# harness.sh [--quick] [--calls N] [--only R1,R2] [--tag T1,T2] [--cases FILE] [--trace DIR] [--list] [--check] - the renderer profiler's
# measuring side. Sources lib/terminal_renderer.sh and a cases file (default scenarios/cases.sh), runs the selected cases and prints one TSV
# row per case (profile.py turns the rows into the report):
#   id  renderer  dataset  args  budget_ms  calls  samples_us(comma separated)  bytes  forks
# --only keeps the listed renderers, --tag the cases that carry one of the tags (plain, args, unicode, small, large); both together keep
# the cases that pass both. --calls N overrides the calls per case. --trace DIR writes one xtrace per case (DIR/N.trace) and DIR/functions.
# --ids FILE runs the cases whose ids are listed in FILE (one per line). --check runs every case once and fails on a case that errors or prints nothing; --list prints "id<TAB>renderer<TAB>tags" per case.
# The caller sets the environment (HOME, XDG_*, LC_ALL, TR_WIDTH); nothing is read from the real ~/.config.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd -P "$HERE/../../.." && pwd -P)"
source "$REPO/lib/terminal_renderer.sh"

_H_QUICK=0 _H_ONLY="" _H_TAGS="" _H_MODE=run _H_CASES="$HERE/scenarios/cases.sh" _H_CALLS="" _H_TRACE="" _H_IDS=""
while (($#)); do
	case "$1" in
		--quick) _H_QUICK=1 ;;
		--only)
			_H_ONLY=",$2,"
			shift
			;;
		--tag)
			_H_TAGS=",$2,"
			shift
			;;
		--cases)
			_H_CASES="$2"
			shift
			;;
		--calls)
			_H_CALLS="$2"
			shift
			;;
		--trace)
			_H_TRACE="$2"
			shift
			;;
		--ids)
			_H_IDS="$2"
			shift
			;;
		--list) _H_MODE=list ;;
		--check) _H_MODE=check ;;
		*)
			echo "harness.sh: unknown option $1" >&2
			exit 2
			;;
	esac
	shift
done

source "$_H_CASES"
_H_WORK="$(mktemp -d "${TMPDIR:-/tmp}/dabt-renderers.XXXXXX")"
trap 'rm -rf "$_H_WORK"' EXIT
rc_define_cases "$_H_WORK"
rc_tag_cases

declare -A _H_TYPE=() # command word -> type -t answer (function, builtin, keyword, file, none), kept across cases

# _h_forks FN -> _H_FORKS : processes one call starts, from its xtrace: every subshell (a distinct BASHPID) and every command that is
# neither a function, builtin nor keyword. A last command that a subshell execs directly is counted twice, so it is an upper bound.
_h_forks() {
	local trace="$_H_WORK/trace" fd line pid word kind main=$BASHPID n=0
	local -A seen=()
	exec {fd}>"$trace"
	BASH_XTRACEFD=$fd PS4='@@${BASHPID}@@ '
	set -x
	"$1" >/dev/null 2>&1
	set +x
	exec {fd}>&-
	unset BASH_XTRACEFD
	while IFS= read -r line; do
		[[ "$line" == "@@"* ]] || continue
		pid="${line#@@}"
		pid="${pid%%@@*}"
		[[ "$pid" == "$main" ]] || seen[$pid]=1
		line="${line#*@@ }"
		word="${line%% *}"
		[[ -z "$word" || "$word" == *=* ]] && continue
		if [[ -z "${_H_TYPE[$word]:-}" ]]; then # one lookup (a fork) per distinct word for the whole run, not one per traced line
			kind="$(type -t -- "$word" 2>/dev/null)"
			_H_TYPE[$word]="${kind:-none}"
		fi
		[[ "${_H_TYPE[$word]}" == file ]] && ((n++))
	done <"$trace"
	_H_FORKS=$((n + ${#seen[@]}))
}

# _h_show ID - with RC_SHOW_FD (profile.py --watch) the case's rendered result goes to that fd, after the timing so it costs the numbers
# nothing. Clears the screen first, with the case name on top. RC_SHOW_WAIT seconds (profile.py --wait, default 0) keep it on screen.
_h_show() {
	[[ -n "${RC_SHOW_FD:-}" ]] || return 0
	printf '\e[H\e[2J\e[1;36m%s\e[0m  (%s)\n\n%b\n' "$1" "${RC_RENDERER[$1]}" "$_RC_OUT" >&"$RC_SHOW_FD" 2>/dev/null || return 0
	[[ "${RC_SHOW_WAIT:-0}" == 0 ]] || sleep "$RC_SHOW_WAIT"
}

_h_run_case() { # ID -> a TSV row
	local _hv_id="$1" _hv_fn="${RC_FN[$1]}" _hv_r="${RC_RENDERER[$1]}" _hv_budget _hv_t0 _hv_t1 _hv_calls=0 _hv_total=0 _hv_limit_us _hv_max_calls
	local -a _hv_samples=()
	_hv_budget="${RC_BUDGET[$_hv_r]:-$RC_BUDGET_MS}"
	"$_hv_fn" || return 1
	[[ -n "$_RC_OUT" ]] || return 2
	"$_hv_fn"
	if ((_H_QUICK)); then _hv_max_calls=8 _hv_limit_us=60000; else _hv_max_calls=40 _hv_limit_us=250000; fi
	[[ -n "$_H_CALLS" ]] && _hv_max_calls=$_H_CALLS _hv_limit_us=$((_H_CALLS * 100000))
	while ((_hv_calls < _hv_max_calls && (_hv_total < _hv_limit_us || _hv_calls < 5))); do
		_hv_t0=${EPOCHREALTIME//[!0-9]/}
		"$_hv_fn"
		_hv_t1=${EPOCHREALTIME//[!0-9]/}
		_hv_samples+=($((_hv_t1 - _hv_t0)))
		((_hv_total += _hv_t1 - _hv_t0, _hv_calls++))
	done
	local LC_ALL=C _hv_bytes=${#_RC_OUT}
	_h_forks "$_hv_fn"
	_h_show "$_hv_id"
	local IFS=,
	printf '%s\t%s\t%s\t%s\t%s\t%d\t%s\t%d\t%d\n' "$_hv_id" "$_hv_r" "${RC_DATASET[$_hv_id]}" "${RC_ARGS[$_hv_id]}" "$_hv_budget" "$_hv_calls" "${_hv_samples[*]}" "$_hv_bytes" "$_H_FORKS"
}

# _h_trace N FN - one xtrace of one call: "@epoch|file:line|function|" and the command, one line per command executed
_h_trace() {
	local fd
	exec {fd}>"$_H_TRACE/$1.trace"
	BASH_XTRACEFD=$fd PS4='@${EPOCHREALTIME//[!0-9]/}|${BASH_SOURCE[0]##*/}:${LINENO}|${FUNCNAME[0]:-main} ${FUNCNAME[1]:-} ${FUNCNAME[2]:-} ${FUNCNAME[3]:-} ${FUNCNAME[4]:-} ${FUNCNAME[5]:-} ${FUNCNAME[6]:-} ${FUNCNAME[7]:-}| '
	set -x
	"$2" >/dev/null 2>&1
	set +x
	exec {fd}>&-
	unset BASH_XTRACEFD
}

declare -A _H_WANT=()
_h_selected() { # ID: passes --ids, --only and --tag
	[[ -n "$_H_IDS" ]] && { [[ -n "${_H_WANT[$1]:-}" ]] || return 1; }
	[[ -z "$_H_ONLY" || "$_H_ONLY" == *",${RC_RENDERER[$1]},"* ]] || return 1
	[[ -z "$_H_TAGS" ]] && return 0
	local t
	for t in ${RC_TAGS[$1]//,/ }; do [[ "$_H_TAGS" == *",$t,"* ]] && return 0; done
	return 1
}

[[ -n "$_H_IDS" ]] && while IFS= read -r _h_line; do _H_WANT[$_h_line]=1; done <"$_H_IDS"
status=0
[[ -n "$_H_TRACE" ]] && {
	mkdir -p "$_H_TRACE"
	compgen -A function >"$_H_TRACE/functions"
	_h_n=0
}
for id in "${RC_IDS[@]}"; do
	_h_selected "$id" || continue
	case "$_H_MODE" in
		list) printf '%s\t%s\t%s\n' "$id" "${RC_RENDERER[$id]}" "${RC_TAGS[$id]}" ;;
		check)
			if ! "${RC_FN[$id]}" 2>/dev/null; then
				echo "FAIL (error)   $id" >&2
				status=1
			elif [[ -z "$_RC_OUT" ]]; then
				echo "FAIL (no output) $id" >&2
				status=1
			fi
			;;
		run)
			_h_run_case "$id" || {
				echo "harness.sh: case failed: $id" >&2
				status=1
			}
			[[ -n "$_H_TRACE" ]] && {
				"${RC_FN[$id]}" && _h_trace "$((_h_n++))" "${RC_FN[$id]}"
				echo "$id" >>"$_H_TRACE/ids"
			}
			;;
	esac
done
exit $status
