#!/usr/bin/env bash
# tui_tmp.sh - private temporary files and folders without mktemp (not POSIX). Pure Bash + mkdir; no tui.sh needed, so the app
# lifecycle (dabt app ..., install, update) and the runtime share it. The result goes into a variable: no command substitution.
#
#   _tui_mkdtemp VAR PREFIX    a new 0700 folder under ${TMPDIR:-/tmp} -> VAR ; rc 1 when none can be made
#   _tui_mktemp  VAR PREFIX    a new empty 0600 file in the same place -> VAR
# requires:

# mkdir is atomic, so a name already taken is just retried.
_tui_mkdtemp() {
	local -n _mkd_out="$1"
	local _mkd_root="${TMPDIR:-/tmp}" _mkd_n=0 _mkd_d
	[[ -d "$_mkd_root" && -w "$_mkd_root" ]] || return 1
	while ((_mkd_n++ < 50)); do
		_mkd_d="$_mkd_root/$2.$$.$RANDOM$RANDOM"
		if mkdir -m 700 "$_mkd_d" 2>/dev/null; then
			_mkd_out="$_mkd_d"
			return 0
		fi
	done
	return 1
}

# noclobber turns > into an exclusive create; the subshell scopes it and the umask (one fork, no exec).
_tui_mktemp() {
	local -n _mkt_out="$1"
	local _mkt_root="${TMPDIR:-/tmp}" _mkt_n=0 _mkt_f
	[[ -d "$_mkt_root" && -w "$_mkt_root" ]] || return 1
	while ((_mkt_n++ < 50)); do
		_mkt_f="$_mkt_root/$2.$$.$RANDOM$RANDOM"
		if (
			umask 077
			set -C
			: >"$_mkt_f"
		) 2>/dev/null; then
			_mkt_out="$_mkt_f"
			return 0
		fi
	done
	return 1
}
