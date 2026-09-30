#!/usr/bin/env bash
# t.sh - in-process unit test runner for DABT (markup-v2 stage 0.1).
#
# Sources lib/ once, then every t_* function found in tests/unit/*.t.sh is a
# test. State is snapshotted right after load and restored before each test,
# so tests are order-independent and any one of them can run alone.
#
#   tools/t.sh            run every test
#   tools/t.sh -k PATTERN  run only tests whose name contains PATTERN
#
# Assertions available inside tests: eq EXPECTED ACTUAL, ok CONDITION..., match TEXT REGEX
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

_T_PATTERN=""
while (($#)); do
	case "$1" in
		-k)
			_T_PATTERN="$2"
			shift 2
			;;
		-p)
			pretty="$2"
			shift 2
			;;
		*)
			echo "usage: t.sh [-k PATTERN]" >&2
			exit 2
			;;
	esac
done

# ── isolate the host ─────────────────────────────────────────────────────
LC_ALL=C
TZ=UTC
export LC_ALL TZ
_T_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dabt-t.XXXXXX")"
trap 'rm -rf "$_T_ROOT"' EXIT
HOME="$_T_ROOT/home"
TUI_HOME="$_T_ROOT/home/.config/DABT"
XDG_CONFIG_HOME="$_T_ROOT/home/.config"
XDG_DATA_HOME="$_T_ROOT/home/.local/share"
XDG_CACHE_HOME="$_T_ROOT/home/.cache"
XDG_STATE_HOME="$_T_ROOT/home/.local/state"
mkdir -p "$HOME" "$TUI_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
export HOME TUI_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
export TUI_APP_NAME="t_runner"

# fixed terminal size for logic that reads it instead of querying a real tty
_TUI_ROWS=24
_TUI_COLS=80

# injectable clock: logic under test can read this instead of $EPOCHREALTIME directly.
# not yet wired into lib/ (that's a later task) - this is just the injection point.
declare -g _TUI_CLOCK=0

source "$REPO/lib/tui.sh"

# ── snapshot/restore ─────────────────────────────────────────────────────
# Scoped to the mutable runtime state a test can plausibly touch (pane tree,
# widgets, focus, tabs) rather than every TUI_*/_TUI_* global: restoring all
# ~300 of those (mostly static config/lookup tables, never mutated by tests)
# blows the speed budget for no correctness gain. Extend the pattern below
# as later stages add mutable state modules with their own tests.
_t_snapshot() { declare -p $(compgen -v | grep -E '^(_TUI_P_|_TUI_W_|_TUI_FOCUS|_TUI_TABS_)') 2>/dev/null; }
_T_SNAPSHOT="$(_t_snapshot)"
# declare -p never emits -g (same gotcha tui_cache.sh's own _tui_cache_restore
# works around): eval-ing the dump as-is inside this function would declare
# fresh function-local shadows instead of resetting the real globals, so a
# test's array mutations would silently survive into the next one. Rewrite
# every "declare -X" to "declare -gX" line by line first - a blind whole-
# string replace on "declare -" would turn a scalar's "declare -- NAME=…"
# into the invalid "declare -g- NAME=…".
_t_restore() {
	local out="" line
	while IFS= read -r line; do
		if [[ "$line" == "declare --"* ]]; then
			line="declare -g${line#declare --}"
		elif [[ "$line" == "declare -"* ]]; then
			line="declare -g${line#declare -}"
		fi
		out+="$line"$'\n'
	done <<<"$_T_SNAPSHOT"
	eval "$out"
}

# ── assertions ────────────────────────────────────────────────────────────
_t_fail() {
	local frame
	frame="$(caller 1)" # "LINENO FUNCNAME FILE" of the assertion's caller (the test body), one frame above eq/ok/match itself
	local line="${frame%% *}"
	local file="${frame##* }"
	_T_FAILED=1
	_T_FAIL_LINES+=("${_T_CUR}"$'\t'"${file}:${line}"$'\t'"$1")
}

eq() {
	[[ "$1" == "$2" ]] || _t_fail "eq: expected [$1] got [$2]"
}

ok() {
	eval "$@" || _t_fail "ok: false: $*"
}

match() {
	[[ "$1" =~ $2 ]] || _t_fail "match: [$1] !~ [$2]"
}

# ── discover tests ────────────────────────────────────────────────────────
for _t_file in "$REPO"/tests/unit/*.t.sh; do
	[[ -r "$_t_file" ]] && source "$_t_file"
done
unset _t_file

mapfile -t _T_ALL < <(compgen -A function t_)
_T_NAMES=()
for _t_name in "${_T_ALL[@]}"; do
	[[ -z "$_T_PATTERN" || "$_t_name" == *"$_T_PATTERN"* ]] && _T_NAMES+=("$_t_name")
done
unset _t_name

# ── run ───────────────────────────────────────────────────────────────────
_T_PASS=0
_T_FAIL=0
_T_FAIL_LINES=()
_T_START="${EPOCHREALTIME//[!0-9]/}"

for _T_CUR in "${_T_NAMES[@]}"; do
	_t_restore
	_T_FAILED=0
	"$_T_CUR"
	# when stumbling upon this add current test out name output with a waiting simboly ... then when fails or succeeds add green [OK] or [FAIL] with the full line being red"
	if ((_T_FAILED)); then
		((_T_FAIL++))
	else
		((_T_PASS++))
	fi
done

_T_END="${EPOCHREALTIME//[!0-9]/}"
_T_MS=$(((_T_END - _T_START) / 1000))

for _t_line in "${_T_FAIL_LINES[@]}"; do
	printf '%s\n' "$_t_line"
done

printf '%d %d %d\n' "$_T_PASS" "$_T_FAIL" "$_T_MS"

_T_COUNT=${#_T_NAMES[@]}
if ((_T_COUNT > 0)); then
	_T_BUDGET_MS=$((200 * _T_COUNT / 100))
	((_T_BUDGET_MS < 1)) && _T_BUDGET_MS=1
	if ((_T_MS > _T_BUDGET_MS)); then
		echo "t.sh: speed budget exceeded: ${_T_COUNT} tests took ${_T_MS}ms, budget ${_T_BUDGET_MS}ms" >&2
		exit 1
	fi
fi

((_T_FAIL == 0))
