#!/usr/bin/env bash
# precommit.sh - everything to run before a commit, in order, so none of it is forgotten. It changes the working tree
# (regenerated docs, baseline, explorer page) but never touches git: stage and commit yourself afterwards.
#
#   tools/precommit.sh                 regenerate -> tests -> bench compare -> deep profile -> explorer export
#   tools/precommit.sh --quick         profiler --quick (~1.5 min) instead of --deep (~10 min)
#   tools/precommit.sh --no-profile    skip the profiler and the explorer export
#   tools/precommit.sh --baseline      also rewrite tools/bench/baseline.txt from this run (do it deliberately)
#   tools/precommit.sh --label TEXT    description of this run for the explorer's revision list
#   tools/precommit.sh --skip-bench    skip the bench comparison
#   tools/precommit.sh --keep-going    do not stop at the first failing step (default: stop, with a summary of every error so far)
#
# Every step streams its output live (escape sequences stripped) above a spinner line that shows the step number, its
# name, the elapsed time and the latest output line. Without a terminal the spinner is off and output is printed plainly.
# The first failing step STOPS the run: a summary of every step so far and every error or warning seen is printed and the
# exit code is 1 (--keep-going runs the remaining steps anyway). Full logs: the folder printed at the end.
#
#   1 regenerate  gen_load_order.sh, gen_api_docs.sh, gen_terminal_controls_doc.sh
#   2 tests       unit suite (tools/t.sh), bats (tests/ and tests/dapk/), golden frames, generated files in sync
#   3 bench       bench/run.sh --compare baseline.txt   (--baseline then rewrites it)
#   4 profile     profile.sh --deep|--quick --scenario full, machine.txt (cores, model, commit) next to the report
#   5 explorer    adds the report to REVISIONS in tools/profiler/site_export.py and exports the explorer page
#   6 summary     what changed in the tree, and what only a human can do
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO" || exit 1

profile=deep run_profile=1 run_bench=1 write_baseline=0 keep_going=0 label=""
while (($#)); do
	case "$1" in
		--quick) profile=quick ;;
		--no-profile) run_profile=0 ;;
		--baseline) write_baseline=1 ;;
		--skip-bench) run_bench=0 ;;
		--keep-going) keep_going=1 ;;
		--label)
			label="${2:-}"
			shift
			;;
		-h | --help)
			sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			echo "precommit: unknown option '$1' (try --help)" >&2
			exit 2
			;;
	esac
	shift
done

_have() { command -v "$1" >/dev/null 2>&1; }

# ── display ─────────────────────────────────────────────────────────────────
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/dabt-precommit.XXXXXX")"
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) # the DABT job spinner
TTY=0
[[ -t 1 ]] && TTY=1
if ((TTY)); then
	C_AMBER=$'\e[38;5;208m' C_TEAL=$'\e[38;5;73m' C_DIM=$'\e[2m' C_GOOD=$'\e[32m' C_BAD=$'\e[31m' C_OFF=$'\e[0m'
else
	C_AMBER="" C_TEAL="" C_DIM="" C_GOOD="" C_BAD="" C_OFF=""
fi

declare -a RES_NAME=() RES_STATUS=() RES_SECS=() RES_LOG=()
FAILED=0 STEP_NO=0
CHILD=0

# planned number of steps, for the "[3/9]" counter
STEP_TOTAL=$((3 + 4 + run_bench + write_baseline + (run_profile ? 2 : 0)))

_cleanup() {
	((CHILD > 0)) && kill "$CHILD" 2>/dev/null
	((TTY)) && printf '\r\e[K\e[?25h'
}
trap '_cleanup; echo; echo "precommit: interrupted"; exit 130' INT TERM
trap '((TTY)) && printf "\e[?25h"' EXIT

# _clean TEXT -> _CLEAN : TEXT without escape sequences, CR and empty lines
_clean() {
	_CLEAN="$(printf '%s' "$1" | sed -E $'s/\x1b(\\[[0-9;?]*[A-Za-z]|\\][^\a]*\a|[()][A-Z0-9])//g; s/\r//g' | sed '/^[[:space:]]*$/d')"
}

# _errors LOG : the lines of a step's log that look like an error or a warning (cleaned, de-duplicated, at most 12)
_errors() {
	local _e
	_e="$(sed -E $'s/\x1b(\\[[0-9;?]*[A-Za-z]|\\][^\a]*\a|[()][A-Z0-9])//g; s/\r//g' "$1" |
		grep -aiE 'not ok|^# |fail|error|exceeded|not found|bad array|warn|regress|traceback|cannot|no such|mismatch|stale|undocumented' |
		grep -avE '^\s*ok ' | awk '!seen[$0]++' | head -12)"
	printf '%s' "$_e"
}

# _report : every step so far with its status, then every error or warning each one produced
_report() {
	local i n=${#RES_NAME[@]} errs shown=0
	printf '\n%s== steps so far%s\n' "$C_AMBER" "$C_OFF"
	for ((i = 0; i < n; i++)); do
		if [[ "${RES_STATUS[$i]}" == ok ]]; then
			printf '   %s✔%s %5ss  %s\n' "$C_GOOD" "$C_OFF" "${RES_SECS[$i]}" "${RES_NAME[$i]}"
		else
			printf '   %s✘%s %5ss  %s\n' "$C_BAD" "$C_OFF" "${RES_SECS[$i]}" "${RES_NAME[$i]}"
		fi
	done
	for ((i = 0; i < n; i++)); do
		[[ -s "${RES_LOG[$i]:-/nonexistent}" ]] || continue
		errs="$(_errors "${RES_LOG[$i]}")"
		[[ -n "$errs" ]] || continue
		((shown++ == 0)) && printf '\n%s== errors and warnings seen%s\n' "$C_AMBER" "$C_OFF"
		printf '   %s[%s] %s%s   (%s)\n' "$C_AMBER" "$((i + 1))" "${RES_NAME[$i]}" "$C_OFF" "${RES_LOG[$i]}"
		printf '%s\n' "$errs" | sed 's/^/      /' | cut -c1-200
	done
	printf '\n   logs: %s\n' "$LOGDIR"
}

# _abort : the run stops here (unless --keep-going)
_abort() {
	((keep_going)) && return 0
	_report
	printf '\n%sprecommit: stopped at the first failing step (%s failed). Fix it and rerun, or use --keep-going.%s\n' \
		"$C_BAD" "$FAILED" "$C_OFF"
	exit 1
}

# _step NAME CMD... : runs CMD in the background, streams its output, animates the spinner, records status and time
_step() {
	local name="$1" t0=$SECONDS rc log off=0 chunk part line last="" i=0 secs cols
	shift
	STEP_NO=$((STEP_NO + 1))
	log="$LOGDIR/$STEP_NO.log"
	printf '\n%s[%s/%s] %s%s\n' "$C_AMBER" "$STEP_NO" "$STEP_TOTAL" "$name" "$C_OFF"
	mkdir -p "$LOGDIR"
	: >"$log"
	"$@" >"$log" 2>&1 </dev/null &
	CHILD=$!

	# prints the lines of the log that are complete and not shown yet (byte offsets: C locale)
	_drain() {
		local LC_ALL=C
		[[ -r "$log" ]] || return 0 # the folder was removed under us: keep waiting for the step quietly
		chunk="$(
			tail -c +$((off + 1)) "$log" 2>/dev/null
			printf x
		)"
		chunk="${chunk%x}"
		[[ "$chunk" == *$'\n'* ]] || return 0
		part="${chunk%$'\n'*}"
		off=$((off + ${#part} + 1))
		_clean "$part"
		[[ -n "$_CLEAN" ]] || return 0
		while IFS= read -r line; do
			((TTY)) && printf '\r\e[K'
			printf '   %s|%s %s\n' "$C_DIM" "$C_OFF" "$line"
			last="$line"
		done <<<"$_CLEAN"
	}

	if ((TTY)); then
		cols="$(tput cols 2>/dev/null || echo 100)"
		printf '\e[?25l'
		while kill -0 "$CHILD" 2>/dev/null; do
			_drain
			secs=$((SECONDS - t0))
			printf '\r\e[K%s%s%s %s%s%s  %s%ss%s  %s' "$C_TEAL" "${SPIN[i++ % 10]}" "$C_OFF" "$C_AMBER" "$name" "$C_OFF" \
				"$C_DIM" "$secs" "$C_OFF" "${last:0:$((cols - ${#name} - 14))}"
			read -rt 0.1 <> <(:)
		done
		printf '\r\e[K\e[?25h'
	else
		while kill -0 "$CHILD" 2>/dev/null; do
			_drain
			read -rt 0.2 <> <(:)
		done
	fi
	wait "$CHILD"
	rc=$?
	CHILD=0
	printf '\n' >>"$log" # terminates an unfinished last line so it is shown
	_drain

	secs=$((SECONDS - t0))
	if ((rc == 0)); then
		printf '%s✔%s %s  %ss\n' "$C_GOOD" "$C_OFF" "$name" "$secs"
		RES_STATUS+=(ok)
	else
		printf '%s✘%s %s  rc=%s  %ss   log: %s\n' "$C_BAD" "$C_OFF" "$name" "$rc" "$secs" "$log"
		RES_STATUS+=(FAILED)
		FAILED=$((FAILED + 1))
	fi
	RES_NAME+=("$name")
	RES_SECS+=("$secs")
	RES_LOG+=("$log")
	[[ "${RES_STATUS[-1]}" == ok ]] || _abort
}

# _fail NAME REASON : records a step that could not even start
_fail() {
	STEP_NO=$((STEP_NO + 1))
	printf '\n%s[%s/%s] %s%s\n%s✘%s %s\n' "$C_AMBER" "$STEP_NO" "$STEP_TOTAL" "$1" "$C_OFF" "$C_BAD" "$C_OFF" "$2"
	RES_NAME+=("$1")
	RES_STATUS+=(FAILED)
	RES_SECS+=(0)
	RES_LOG+=("")
	FAILED=$((FAILED + 1))
	_abort
}

# ── 1 regenerate ────────────────────────────────────────────────────────────
_step "load order" tools/gen_load_order.sh
_step "api docs" tools/gen_api_docs.sh
_step "terminal controls doc" tools/gen_terminal_controls_doc.sh

# ── 2 tests ─────────────────────────────────────────────────────────────────
_step "unit suite (tools/t.sh)" tools/t.sh
if _have bats; then
	jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
	((jobs > 8)) && jobs=8
	if _have parallel; then
		_step "bats ($jobs jobs)" bats -j "$jobs" --tap tests/ tests/dapk/
	else
		_step "bats (serial: GNU parallel not found)" bats --tap tests/ tests/dapk/
	fi
else
	STEP_TOTAL=$((STEP_TOTAL)) # the missing step still counts
	_fail "bats" "bats not found: tests/ cannot run, install bats and rerun"
fi
_step "golden frames" tools/t_golden.sh --check
_step "generated files in sync" bash -c 'tools/gen_api_docs.sh --check && tools/gen_load_order.sh --check'

# ── 3 bench ─────────────────────────────────────────────────────────────────
if ((run_bench)); then
	_step "bench vs baseline" tools/bench/run.sh --compare tools/bench/baseline.txt
fi
if ((write_baseline)); then
	_step "bench baseline rewritten" bash -c 'tools/bench/run.sh > tools/bench/baseline.txt.new && mv tools/bench/baseline.txt.new tools/bench/baseline.txt'
fi

# ── 4 profile, 5 explorer ───────────────────────────────────────────────────
if ((run_profile)); then
	_step "profiler --$profile --scenario full ($(nproc 2>/dev/null || echo '?') cores, machine kept awake)" \
		tools/profiler/profile.sh "--$profile" --scenario full
	latest="tools/profiler/reports/latest"
	if [[ -e "$latest" ]]; then
		ts="$(basename "$(readlink -f "$latest")")"
		model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2)"
		printf 'cores: %s\nmodel:%s\nbash: %s\ncommit: %s\nprofile: %s\n' \
			"$(nproc 2>/dev/null || echo '?')" "$model" "$BASH_VERSION" "$(git rev-parse --short HEAD 2>/dev/null)" "$profile" \
			>"tools/profiler/reports/$ts/machine.txt"

		if ! grep -q "\"$ts\"" tools/profiler/site_export.py; then
			if [[ -z "$label" && -t 0 ]]; then
				read -rp "Explorer label for run $ts (what changed since the last run): " label
			fi
			[[ -n "$label" ]] || label="Run $ts"
			python3 -I - "$ts" "$label" "$profile" <<'PY'
import sys
ts, label, profile = sys.argv[1:4]
path = "tools/profiler/site_export.py"
src = open(path, encoding="utf-8").read()
end = src.index("\n]\n", src.index("REVISIONS = ["))
entry = '\n    (%r, %r, %r, %r, %s),' % ("r" + ts, label[:40], ts, label, "True" if profile == "deep" else "False")
open(path, "w", encoding="utf-8").write(src[:end] + entry + src[end:])
PY
		fi
		_step "explorer export" python3 tools/profiler/site_export.py
	else
		_fail "explorer export" "no tools/profiler/reports/latest: the profiler produced no report"
	fi
fi

# ── 6 summary ───────────────────────────────────────────────────────────────
_report

printf '\n%s== changed in the working tree (regenerated files show up here: review, then stage)%s\n' "$C_AMBER" "$C_OFF"
git status --short | head -40 | sed 's/^/   /'

printf '\n%s== only you can do these%s\n' "$C_AMBER" "$C_OFF"
cat <<'EOF'
   - CHANGELOG.md [Unreleased]: an entry for every user-visible change
   - VERSION / README news: bump and write them when this is a release
   - README headings changed or added:   tools/gen_headers.sh
   - files added, renamed or removed:    tools/gen_tree.sh (paste into README "Project structure")
   - new profiler report is git-ignored: git add -f tools/profiler/reports/<timestamp> if it should be kept
   - bench: if a regression above is intended, rerun with --baseline and commit tools/bench/baseline.txt
EOF

if ((FAILED == 0)); then
	printf '\n%sprecommit: all steps ok%s\n' "$C_GOOD" "$C_OFF"
else
	printf '\n%sprecommit: %s step(s) FAILED%s\n' "$C_BAD" "$FAILED" "$C_OFF"
fi
exit $((FAILED > 0))
