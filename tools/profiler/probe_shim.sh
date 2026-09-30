#!/usr/bin/env bash
# probe_shim.sh - stands in for lib/tui.sh while the profiler runs an app.
# Sources the real library, then wraps a fixed list of coarse functions so each call
# reports begin/end timestamps (us, $EPOCHREALTIME) on fd 8. Wrappers add one printf
# per call; nothing else of the app changes. Optional xtrace goes to fd 9.
#
# Env in:  PROF_REPO (repo root)  PROF_WRAP ("name:kind ..." kind w=work s=span f=flush)
#          PROF_TRACE (1 = enable xtrace on fd 9)
# Lines out (fd 8):  B|name|t0|pid   E|name|t0|t1|arg|pid   (arg: length of $1, or exit code)

if [[ -z "${PROF_REPO:-}" ]]; then
	echo "probe_shim.sh is internal (the profiler sources it inside a pty). Run tools/profiler/profile.sh instead." >&2
	return 2 2>/dev/null || exit 2
fi

__prof_lib_t0=${EPOCHREALTIME//[!0-9]/}
printf 'E|shim_start|%s|%s|0|%s\n' "$__prof_lib_t0" "$__prof_lib_t0" "$BASHPID" >&8

# shellcheck source=/dev/null
source "$PROF_REPO/lib/tui.sh"
printf 'E|libload|%s|%s|0|%s\n' "$__prof_lib_t0" "${EPOCHREALTIME//[!0-9]/}" "$BASHPID" >&8

# __prof_wrap NAME KIND - renames NAME to __prof_orig_NAME and installs the reporting wrapper.
# kinds: w work, s span only, n span that also reports its first argument, f one flushed frame, p work only while output is pending,
#        a work unless called straight from the main loop (idle ticks are not user work)
__prof_wrap() {
	local fn="$1" kind="$2" body guard=""
	declare -F "$fn" >/dev/null || return 0
	body="$(declare -f "$fn")"
	eval "__prof_orig_${body}"
	case "$kind" in
		f)
			eval "$fn() { local __pt=\${EPOCHREALTIME//[!0-9]/} __pc=\"\${FUNCNAME[*]:1:8}\"; __prof_orig_$fn \"\$@\"; printf 'E|%s|%s|%s|%s|%s|%s\n' '$fn' \$__pt \${EPOCHREALTIME//[!0-9]/} \${#1} \$BASHPID \"\${__pc// /<}\" >&8; }"
			return
			;;
		n)
			eval "$fn() { local __pt=\${EPOCHREALTIME//[!0-9]/} __pa=\"\${1//[|<]/_}\" __prc; __prof_orig_$fn \"\$@\"; __prc=\$?; printf 'E|%s|%s|%s|%s|%s|%s\n' '$fn' \$__pt \${EPOCHREALTIME//[!0-9]/} 0 \$BASHPID \"\$__pa\" >&8; return \$__prc; }"
			return
			;;
		p) guard='if ((${#_TUI_PENDING_OUTPUT[@]} == 0)); then __prof_orig_'"$fn"' "$@"; return $?; fi;' ;;
		a) guard='if [[ ${FUNCNAME[1]} == *tui.run ]]; then __prof_orig_'"$fn"' "$@"; return $?; fi;' ;;
	esac
	eval "$fn() { $guard local __pt=\${EPOCHREALTIME//[!0-9]/} __prc; printf 'B|%s|%s|%s\n' '$fn' \$__pt \$BASHPID >&8; __prof_orig_$fn \"\$@\"; __prc=\$?; printf 'E|%s|%s|%s|%s|%s\n' '$fn' \$__pt \${EPOCHREALTIME//[!0-9]/} \$__prc \$BASHPID >&8; return \$__prc; }"
}

__prof_on_ready() { printf 'E|ready|%s|%s|0|%s\n' "${EPOCHREALTIME//[!0-9]/}" "${EPOCHREALTIME//[!0-9]/}" "$BASHPID" >&8; }
declare -F tui.hook.on >/dev/null && tui.hook.on ready __prof_on_ready

for __prof_w in $PROF_WRAP; do __prof_wrap "${__prof_w%%:*}" "${__prof_w##*:}"; done
unset __prof_w

if [[ "${PROF_TRACE:-0}" == 1 ]]; then
	BASH_XTRACEFD=9
	PS4='@${EPOCHREALTIME}|${BASHPID}|${BASH_SOURCE[0]##*/}:${LINENO}|${FUNCNAME[*]}|'
	set -x
fi
