#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_job.sh                                                           ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui.job.run [--delay MS] [--silent] [--label TEXT] ID WORKFN DONEFN [ARG...]
#                     runs WORKFN ARG... in the background; the interface stays responsive. If it is still
#                     running after MS milliseconds (default $TUI_JOB_SPINNER_MS = 100) a spinner with TEXT appears
#                     in the top-right corner of the frame (--silent: never, for work nobody waits for). When WORKFN has
#                     finished, the spinner goes and
#                     DONEFN ID RC OUTFILE runs in the main shell - the one place the result is put on screen.
# tui.job.cancel ID   stops the job; DONEFN is not called
# tui.job.running ID  rc 0 while the job is pending
#
# WORKFN runs in a background subshell: it cannot change the main shell's variables, so it hands its result back as
# data. Its stdout is OUTFILE; $TUI_JOB_PREFIX is a path prefix it may build more files from ("${TUI_JOB_PREFIX}blob"),
# and its stderr is "${TUI_JOB_PREFIX}err". Nothing it prints reaches the terminal.
# DONEFN gets ID, WORKFN's exit status and OUTFILE; $TUI_JOB_PREFIX is set there too. Because nothing is drawn until
# DONEFN runs, a page built in WORKFN appears all at once, never half-finished.
# Starting a job with an ID that is already pending cancels the earlier one.
#
# The loop calls _tui_job.tick on every pass while a job is pending (tui.tick.add); no timers, no signals.
# requires: tui_configuration

declare -g TUI_JOB_PREFIX=""

# Internal aliases from tui_configuration.sh (for backward compatibility with code using _TJ_* names)
_TJ_FRAME_US="$TUI_JOB_FRAME_US"
_TJ_GLYPHS=("${TUI_JOB_SPINNER_GLYPHS[@]}")

declare -ga _TJ_IDS=()
declare -gA _TJ_PID=() _TJ_FILES=() _TJ_START=() _TJ_DELAY=() _TJ_LABEL=() _TJ_DONE=() _TJ_SHOWN=()
declare -g _TJ_ROOT="" _TJ_SEQ=0 _TJ_ON=0 _TJ_FRAME=-1
declare -gi _TJ_DRAWN=0 # 1 while the spinner's cells are on screen and nothing has repainted them

tui.job.run() {
	local delay="$TUI_JOB_SPINNER_MS" label="Working..." silent=0
	while [[ "${1:-}" == --* ]]; do
		case "$1" in
			--silent)
				silent=1
				shift
				;;
			--delay)
				delay="${2:-}"
				shift 2
				;;
			--label)
				label="${2:-}"
				shift 2
				;;
			--)
				shift
				break
				;;
			*)
				echo "tui.job.run: unknown option '$1'" >&2
				return 1
				;;
		esac
	done
	local id="${1:-}" work="${2:-}" done_fn="${3:-}"
	if [[ -z "$id" ]] || ! declare -F "$work" >/dev/null || ! declare -F "$done_fn" >/dev/null; then
		echo "tui.job.run: need ID, a defined WORKFN and a defined DONEFN" >&2
		return 1
	fi
	[[ "$delay" =~ ^[0-9]+$ ]] || {
		echo "tui.job.run: --delay takes whole milliseconds, got '$delay'" >&2
		return 1
	}
	shift 3
	tui.job.cancel "$id"
	if [[ -z "$_TJ_ROOT" ]]; then
		_TJ_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tui_job.XXXXXX")" || return 1 # the one process this module starts for itself
		tui.hook.on exit _tui_job.shutdown
	fi
	# files, not a directory per job: redirects create them with no process; the whole root goes at exit
	# BASHPID in the name: a job's work is a copy of this shell with the same counter, and a job it starts itself (a page's
	# on_visit runs inside a page build) must not write into the numbers this shell is about to use
	local dir="$_TJ_ROOT/$BASHPID.$((++_TJ_SEQ))."
	if ((TUI_JOB_BACKGROUND)); then
		_tui_job.work "$dir" "$work" "$@" &
		_TJ_PID[$id]=$!
		disown "$!" 2>/dev/null
	else
		_tui_job.work "$dir" "$work" "$@"
		_TJ_PID[$id]=0
	fi
	((silent)) && delay=-1
	_TJ_FILES[$id]="$dir" _TJ_START[$id]="${EPOCHREALTIME//[!0-9]/}" _TJ_DELAY[$id]="$delay"
	_TJ_LABEL[$id]="$label" _TJ_DONE[$id]="$done_fn"
	unset '_TJ_SHOWN[$id]'
	_TJ_IDS+=("$id")
	if ((TUI_JOB_BACKGROUND)); then
		tui.tick.add _tui_job.tick
	else
		_tui_job.finish "$id"
	fi
	return 0
}

# _tui_job.work DIR WORKFN ARGS... - WORKFN in a child process; its stdout, stderr and exit status land in DIR's files
_tui_job.work() {
	local dir="$1" work="$2"
	shift 2
	(
		TUI_JOB_PREFIX="$dir"
		# the copy of the job table belongs to the main shell: a job of the same ID started in here would stop the main
		# shell's process (tui.job.cancel kills the recorded PID)
		_TJ_IDS=() _TJ_PID=() _TJ_FILES=() _TJ_START=() _TJ_DELAY=() _TJ_LABEL=() _TJ_DONE=() _TJ_SHOWN=()
		"$work" "$@"
	) </dev/null >"${dir}out" 2>"${dir}err"
	printf '%s' "$?" >"${dir}rc"
}

tui.job.running() { [[ -n "${_TJ_FILES[$1]+x}" ]]; }

tui.job.cancel() {
	local id="${1:-}"
	tui.job.running "$id" || return 1
	kill "${_TJ_PID[$id]}" 2>/dev/null
	_tui_job.forget "$id"
	_tui_job.sync_spinner erase
	return 0
}

# _tui_job.shutdown - at exit: stop what is still running, remove the temp files (hook "exit")
_tui_job.shutdown() {
	local id
	for id in "${_TJ_IDS[@]}"; do kill "${_TJ_PID[$id]}" 2>/dev/null; done
	[[ -n "$_TJ_ROOT" ]] && rm -rf "$_TJ_ROOT"
	_TJ_ROOT=""
}

# _tui_job.forget ID - drop ID's bookkeeping (not its files)
_tui_job.forget() {
	local id="$1" i
	local -a keep=()
	for i in "${_TJ_IDS[@]}"; do [[ "$i" == "$id" ]] || keep+=("$i"); done
	_TJ_IDS=("${keep[@]}")
	unset '_TJ_PID[$id]' '_TJ_FILES[$id]' '_TJ_START[$id]' '_TJ_DELAY[$id]' '_TJ_LABEL[$id]' '_TJ_DONE[$id]' '_TJ_SHOWN[$id]'
	((${#_TJ_IDS[@]})) || tui.tick.remove _tui_job.tick
}

# _tui_job.tick - once per loop pass while jobs are pending: finish the ones that are done, show the spinner for
# the ones past their delay, and advance its animation.
_tui_job.tick() {
	local now="${EPOCHREALTIME//[!0-9]/}" id
	local -a ids=("${_TJ_IDS[@]}")
	for id in "${ids[@]}"; do
		[[ -n "${_TJ_FILES[$id]+x}" ]] || continue # a DONEFN of an earlier job cancelled it
		if [[ -s "${_TJ_FILES[$id]}rc" ]]; then
			_tui_job.finish "$id"
		elif [[ -z "${_TJ_SHOWN[$id]:-}" ]] && ((_TJ_DELAY[$id] >= 0 && now - _TJ_START[$id] >= _TJ_DELAY[$id] * 1000)); then
			_TJ_SHOWN[$id]=1
		fi
	done
	_tui_job.sync_spinner
	return 0
}

# _tui_job.finish ID - run DONEFN, then take the spinner away. If DONEFN did not redraw the screen itself, the page is
# redrawn so no spinner is left behind.
_tui_job.finish() {
	local id="$1" dir="${_TJ_FILES[$1]}" fn="${_TJ_DONE[$1]}" rc gen drawn
	read -r rc <"${dir}rc"
	_tui_job.forget "$id"
	_tui_job.sync_spinner # off before DONEFN: its own redraw must not paint the spinner back on top of the new page
	drawn=$_TJ_DRAWN
	gen=$_TUI_FLUSH_GEN
	TUI_JOB_PREFIX="$dir"
	"$fn" "$id" "$rc" "${dir}out"
	: >"${dir}out" # the result is not needed any more: keep the temp files empty until exit
	: >"${dir}err"
	TUI_JOB_PREFIX=""
	if ((drawn && _TUI_RUNNING && _TUI_FLUSH_GEN == gen)); then
		_TJ_DRAWN=0
		tui.render
	elif ((drawn)); then
		_TJ_DRAWN=0
	fi
}

# _tui_job.sync_spinner [erase] - make the spinner overlay match the jobs: on while any job is past its delay, with the
# frame for this moment; off (and the area repainted when called from cancel) otherwise.
_tui_job.sync_spinner() {
	local id want=0 frame
	for id in "${_TJ_IDS[@]}"; do [[ -n "${_TJ_SHOWN[$id]:-}" ]] && want=1; done
	frame=$(((${EPOCHREALTIME//[!0-9]/} / _TJ_FRAME_US) % ${#_TJ_GLYPHS[@]}))
	if ((want)); then
		if ((! _TJ_ON)); then
			_TJ_ON=1
			tui.layer.fn_add _tui_job.spinner_draw
		elif ((frame == _TJ_FRAME)); then
			return 0
		fi
		_TJ_FRAME=$frame
		_TJ_DRAWN=1
		((_TUI_RUNNING)) && _tui_layer.draw_all
	elif ((_TJ_ON)); then
		_TJ_ON=0
		_TJ_FRAME=-1
		tui.layer.fn_remove _tui_job.spinner_draw
		if [[ "${1:-}" == erase ]] && ((_TJ_DRAWN && _TUI_RUNNING)); then
			_TJ_DRAWN=0
			tui.render
		fi
	fi
	return 0
}

# top function layer: appends to _TUI_FRAME (see _tui_layer.draw_all). Top-right corner, on the frame's top row.
_tui_job.spinner_draw() {
	local id label="" n=0 txt x
	for id in "${_TJ_IDS[@]}"; do
		[[ -n "${_TJ_SHOWN[$id]:-}" ]] || continue
		n=$((n + 1))
		label="${_TJ_LABEL[$id]}"
	done
	((n)) || return 0
	((n > 1)) && label+=" (+$((n - 1)))"
	txt=" ${_TJ_GLYPHS[_TJ_FRAME]} $label "
	x=$((_TUI_COLS - ${#txt} - 1))
	((x < 1)) && x=1
	_tui._style_v job_spinner_normal
	_TUI_FRAME+=$'\e7\e['"1;${x}H${_SGR:-$'\e[1;7m'}${txt}"$'\e[0m\e8'
}

# ── tui.page.rebuild ─────────────────────────────────────────────────────

# tui.page.rebuild [--delay MS] [--label TEXT] [--quiet [--expanded]] FILE
#   Builds page FILE again in the background (the same headless build the start-up warm-up does), with the spinner of
#   tui.job.run if it takes longer than the delay. When the build is complete its result becomes FILE's cached page
#   and, if FILE is still the page on screen, the app goes to it in one redraw - never a half-built page. If the user
#   has moved on, nothing is drawn; the next visit uses the fresh build. A failed build keeps the old page and says why
#   in a toast. With --quiet only the cache is refreshed (no spinner, nothing drawn): tui.page.refresh uses it to
#   bring the cached copy of a page up to date after it changed the screen itself. With --expanded (quiet only) the
#   build starts from the expanded tree that is in the node store now instead of parsing FILE again: the caller
#   vouches that the tree is FILE's current one. Use it after something FILE depends on has changed (an addon file, a generated include).
tui.page.rebuild() {
	local -a opts=()
	local quiet=0 work=_tui_job.page_build
	while [[ "${1:-}" == --* ]]; do
		case "$1" in
			--quiet)
				quiet=1
				shift
				;;
			--expanded)
				work=_tui_job.page_rebuild_expanded
				shift
				;;
			*)
				opts+=("$1" "${2:-}")
				shift 2
				;;
		esac
	done
	local file="${1:-}"
	[[ -r "$file" ]] || {
		echo "tui.page.rebuild: cannot read '$file'" >&2
		return 1
	}
	_tui_path_canon "$file"
	if ((quiet)); then # only the cache: no spinner, and the page on screen is left alone
		tui.job.run --silent "page-cache:$_CANON" "$work" _tui_job.page_cache_done "$_CANON"
		return
	fi
	tui.job.run "${opts[@]}" "page:$_CANON" _tui_job.page_build _tui_job.page_done "$_CANON"
}

# WORKFN (background): build the page, hand the cache entry back as one blob
_tui_job.page_build() {
	tui.reset_ui
	tui.cache.record "$1" || return 1
	tui.cache.encode "$1" >"${TUI_JOB_PREFIX}blob"
}

# WORKFN (background): the same entry from the expanded tree this shell holds. The fork inherited the node store and
# _TUI_P_RAW; reset_ui clears the raw tree, so it is put back for the build to keep and cache.
_tui_job.page_rebuild_expanded() {
	local raw="$_TUI_P_RAW"
	tui.reset_ui
	_TUI_P_RAW="$raw"
	_TUI_BUILD_REUSE_TREE=1
	tui.cache.record "$1" || return 1
	tui.cache.encode "$1" >"${TUI_JOB_PREFIX}blob"
}

# DONEFN of a quiet rebuild: just the cache entry
_tui_job.page_cache_done() {
	local file="${1#page-cache:}"
	(($2 == 0)) || return 0
	tui.cache.decode "$file" "$(<"${TUI_JOB_PREFIX}blob")"
	: >"${TUI_JOB_PREFIX}blob"
}

# DONEFN (main shell)
_tui_job.page_done() {
	local file="${1#page:}" msg=""
	if (($2 != 0)); then
		read -r msg <"${TUI_JOB_PREFIX}err"
		tui.notify "Could not build ${file##*/}: ${msg:-see the log}" error
		return 0
	fi
	tui.cache.decode "$file" "$(<"${TUI_JOB_PREFIX}blob")"
	: >"${TUI_JOB_PREFIX}blob"
	[[ "${_TUI_MARKUP_FILE:-}" == "$file" ]] && tui.goto "$file"
	return 0
}
