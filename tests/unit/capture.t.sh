# capture.t.sh - tui.capture: $( ) without the subshell.

_cap_hello() { printf 'hello\n\n'; }
_cap_args() { printf '%s|%s' "$1" "$2"; }
_cap_sets_global() {
	CAP_SIDE=set
	printf x
}
_cap_fails() {
	printf out
	return 3
}
_cap_nested() {
	tui.capture _CAP_IN _cap_hello
	printf '<%s>' "$_CAP_IN"
}

t_capture_stores_stdout_and_strips_trailing_newlines() {
	tui.capture out _cap_hello
	eq "hello" "$out"
}

t_capture_passes_arguments() {
	tui.capture out _cap_args a b
	eq "a|b" "$out"
}

t_capture_runs_in_the_current_shell() {
	CAP_SIDE=""
	tui.capture out _cap_sets_global
	eq "set" "$CAP_SIDE"
}

t_capture_returns_the_command_status() {
	tui.capture out _cap_fails
	local rc=$?
	eq 3 "$rc"
	eq "out" "$out"
}

t_capture_nests() {
	tui.capture out _cap_nested
	eq "<hello>" "$out"
}

t_capture_matches_command_substitution() {
	local a b
	a="$(_cap_args 1 2)"
	tui.capture b _cap_args 1 2
	eq "$a" "$b"
}
