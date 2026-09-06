#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  tui_exec.sh — Run commands in the background with live TUI output       ║
# ║                                                                          ║
# ║  Source after tui.sh.  Provides tui.exec which launches a command,       ║
# ║  streams its stdout/stderr into a pane, and wires up controls for        ║
# ║  cancel, save, view-source, and forwarding stdin.                        ║
# ║                                                                          ║
# ║  HOW IT WORKS                                                            ║
# ║    • tui.run is overridden with a tick-aware loop: when _TUI_TICK_FN     ║
# ║      is set, `read` uses a 50 ms timeout so we can poll on every         ║
# ║      iteration.  When unset the loop is identical to the original.       ║
# ║    • The command writes to a temp file; the tick reads new lines via      ║
# ║      tail -n +N (incremental, no re-read of old data).                   ║
# ║    • Process stdin goes through a named FIFO whose write-end FD stays    ║
# ║      open for the lifetime of the process.                               ║
# ║    • Process liveness is checked with kill -0 on each tick.              ║
# ║                                                                          ║
# ║  USAGE                                                                   ║
# ║    source tui.sh                                                         ║
# ║    source tui_exec.sh                                                    ║
# ║                                                                          ║
# ║    tui.init                                                              ║
# ║    tui.vsplit "root" "output:75" "controls:25"                           ║
# ║    tui.exec "./my_script.sh arg1 arg2" "output" "controls"              ║
# ║    tui.run                                                               ║
# ║                                                                          ║
# ║  tui.exec can also be called from a button callback during tui.run.     ║
# ╚════════════════════════════════════════════════════════════════════════════╝

_EXEC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_TUI_P_ROW+x}" ]] && source "${_EXEC_SCRIPT_DIR}/tui.sh"

# ═══════════════════════════════════════════════════════════════════════
#  EXEC STATE
# ═══════════════════════════════════════════════════════════════════════

declare -ga _EXEC_BUF=()           # accumulated output lines
declare -g  _EXEC_PID=0            # background PID
declare -g  _EXEC_CMD=""           # command string
declare -g  _EXEC_OUTFILE=""       # temp file receiving stdout+stderr
declare -g  _EXEC_FIFO=""          # named pipe for stdin
declare -g  _EXEC_FIFO_FD=""       # write-end FD kept open
declare -g  _EXEC_STATUS="idle"    # idle | running | done | error | cancelled
declare -g  _EXEC_EXIT=""          # exit code once finished
declare -g  _EXEC_TMPDIR=""        # temp dir housing fifo + output
declare -g  _EXEC_OUT_PANE=""      # pane id: scrolling output
declare -g  _EXEC_CTL_PANE=""      # pane id: controls
declare -g  _EXEC_VROWS=0          # visible output rows in pane
declare -g  _EXEC_LAST_READ=0      # lines already consumed from file
declare -g  _TUI_TICK_FN=""        # tick callback (set by tui.exec)


tui.log(){
    local msg="$1"
    local level="${2:-info}"
    echo "[$(date +%H:%M:%S)] [$level] $msg" >> ".tui_exec.log"
}

tui.log.debug() { tui.log "$1" "debug"; }
tui.log.info()  { tui.log "$1" "info"; }
tui.log.warn()  { tui.log "$1" "warn"; }
tui.log.error() { tui.log "$1" "error"; }

# ═══════════════════════════════════════════════════════════════════════
#  TICK-ENABLED EVENT LOOP  (overrides tui.run from tui.sh)
# ═══════════════════════════════════════════════════════════════════════
#  When _TUI_TICK_FN is empty  → blocking read, zero overhead.
#  When _TUI_TICK_FN is set    → 50 ms timeout, tick called each pass.

tui.run() {
    tui.log.debug "tui.run() starting"
    _TUI_RUNNING=1
    
    # Use unified cleanup for interrupts
    trap '_master_cleanup; exit 1' INT TERM

    tui.render
    tui.log.debug "tui.run() rendered"
    while (( _TUI_RUNNING )); do

        # ── Read one byte ──
        local char=""
        local got_char=0
        
        if [[ -n "${_TUI_TICK_FN:-}" ]]; then
            IFS= read -rsn1 -t 0.05 char && got_char=1
        else
            IFS= read -rsn1 char && got_char=1 || break
        fi

        # BASH FIX: If read succeeded but char is empty, it was a newline (Enter key)
        [[ -z "$char" && got_char -eq 1 ]] && char=$'\n'

        # ── Dispatch input (unchanged from tui.sh) ──
        if [[ -n "$char" ]]; then

            if [[ "$char" == $'\e' ]]; then
                local seq=""
                while IFS= read -rsn1 -t 0.01 c; do
                    seq+="$c"
                    [[ "$c" =~ [A-Za-z~Mm] ]] && break
                done

                if [[ -z "$seq" ]]; then
                    if [[ -n "$_TUI_FOCUS_ID" \
                       && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                        _tui._unfocus
                    fi

                elif [[ "$seq" == "[<"* ]]; then
                    _tui._handle_mouse "$seq"

                elif [[ "$seq" == "[Z" ]]; then
                    _tui._focus_prev

                elif [[ "$seq" == "[A" || "$seq" == "[B" ]]; then
                    [[ "$seq" == "[A" ]] && _tui._focus_prev || _tui._focus_next

                elif [[ -n "$_TUI_FOCUS_ID" \
                     && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                    _tui._input_seq "$_TUI_FOCUS_ID" "$seq"
                fi

            elif [[ "$char" == $'\t' ]]; then
                _tui._focus_next

            elif [[ "$char" == $'\n' || "$char" == $'\r' ]]; then
                if [[ -n "$_TUI_FOCUS_ID" ]]; then
                    local ftype="${_TUI_W_TYPE[$_TUI_FOCUS_ID]}"
                    local faction="${_TUI_W_ACTION[$_TUI_FOCUS_ID]:-}"
                    if [[ "$ftype" == "button" ]]; then
                        [[ -n "$faction" ]] && "$faction" "$_TUI_FOCUS_ID"
                    elif [[ "$ftype" == "input" ]]; then
                        [[ -n "$faction" ]] && "$faction" "$_TUI_FOCUS_ID"
                        _tui._unfocus
                    fi
                fi

            elif [[ -n "$_TUI_FOCUS_ID" \
                 && "${_TUI_W_TYPE[$_TUI_FOCUS_ID]}" == "input" ]]; then
                _tui._input_key "$_TUI_FOCUS_ID" "$char"
            fi
        fi

        # ── Tick ──
        [[ -n "${_TUI_TICK_FN:-}" ]] && "$_TUI_TICK_FN"
    done

    # Use unified cleanup for normal exits
    _master_cleanup
}

# ═══════════════════════════════════════════════════════════════════════
#  tui.exec  —  launch a command
# ═══════════════════════════════════════════════════════════════════════
#
#  tui.exec <command_string> <output_pane> <controls_pane>
#
#  Can be called before tui.run (setup time) or from a callback
#  during tui.run (re-launches cleanly).

tui.exec() {
    local cmd="$1" out_pane="$2" ctl_pane="$3"
    tui.log.info "tui.exec() initiating command: '$cmd'"

    # Fatal configuration: Do not launch
    if [[ -z "$cmd" || -z "$out_pane" || -z "$ctl_pane" ]]; then
        tui.log.error "tui.exec: Fatal config error. Missing arguments."
        return 1
    fi

    # Broken configuration: Warn but launch for debugging
    if [[ -z "${_TUI_P_ROW[$out_pane]:-}" || -z "${_TUI_P_ROW[$ctl_pane]:-}" ]]; then
        tui.log.warn "tui.exec: Pane configuration broken. '$out_pane' or '$ctl_pane' missing."
        # Print a red banner bypassing pane logic
        printf '\e7\e[1;1H\e[41;37m ERROR: Pane configuration broken. Launching in degraded mode. \e[0m\e8'
    fi

    tui.log.debug "tui.exec() called with cmd='$cmd', out_pane='$out_pane', ctl_pane='$ctl_pane'"
    
    # Tear down any previous run
    _exec_cleanup_process
    _exec_remove_widgets

    _EXEC_CMD="$cmd"
    _EXEC_OUT_PANE="$out_pane"
    _EXEC_CTL_PANE="$ctl_pane"
    _EXEC_BUF=()
    _EXEC_LAST_READ=0
    _EXEC_STATUS="running"
    _EXEC_EXIT=""

    # ── Temp dir, output file, stdin FIFO ──
    _EXEC_TMPDIR=$(mktemp -d /tmp/tui_exec.XXXXXX)
    _EXEC_OUTFILE="${_EXEC_TMPDIR}/out"
    _EXEC_FIFO="${_EXEC_TMPDIR}/in"

    touch "$_EXEC_OUTFILE"
    mkfifo "$_EXEC_FIFO"

    # Open write-end of the FIFO and keep it alive.
    # The <> (read-write) prevents blocking if the child hasn't opened
    # its read-end yet.
    exec {_EXEC_FIFO_FD}<>"$_EXEC_FIFO"

    # ── Launch ──
    script -q -e -c "$cmd" /dev/null < "$_EXEC_FIFO" >> "$_EXEC_OUTFILE" 2>&1 &    
    _EXEC_PID=$!

    # ── Build widgets ──
    _exec_setup_output_pane
    _exec_setup_controls

    # ── Register tick ──
    _TUI_TICK_FN="_exec_tick"

    # ── If the loop is already running, redraw immediately ──
    if (( _TUI_RUNNING )); then
        tui.clear_pane "$out_pane"
        tui.clear_pane "$ctl_pane"
        _tui._draw_pane "$out_pane"
        _tui._draw_pane "$ctl_pane"
        for wid in "${_TUI_W_ORDER[@]}"; do
            [[ "$wid" == _x* ]] && _tui._draw_widget "$wid"
        done
        _exec_render_status
    fi
}

# ═══════════════════════════════════════════════════════════════════════
#  WIDGET SETUP
# ═══════════════════════════════════════════════════════════════════════

_exec_setup_output_pane() {
    local pane="$_EXEC_OUT_PANE"
    local ph=${_TUI_P_H[$pane]}
    local border="${_TUI_P_BORDER[$pane]:-single}"

    if [[ "$border" == "none" ]]; then
        _EXEC_VROWS=$ph
    else
        _EXEC_VROWS=$(( ph - 2 ))
    fi

    # Row 0: command header
    tui.label "_xhdr" "$pane" 0 ""

    # Rows 1 .. VROWS-1: scrollable output lines
    local orows=$(( _EXEC_VROWS - 1 ))
    for (( i = 0; i < orows; i++ )); do
        tui.label "_xo_${i}" "$pane" $(( i + 1 )) ""
    done
}

_exec_setup_controls() {
    local pane="$_EXEC_CTL_PANE"

    tui.label  "_xstat"    "$pane" 0 ""
    tui.button "_xcancel"  "$pane" 1 "[ Cancel ]"        _exec_on_cancel
    tui.button "_xsave"    "$pane" 2 "[ Save Output ]"   _exec_on_save
    tui.button "_xview"    "$pane" 3 "[ View Command ]"  _exec_on_view
    tui.button "_xlsh"     "$pane" 4 "[ Launch Shell ]"  _exec_on_lsh
    tui.input  "_xinput"   "$pane" 5 "type and press Enter…" "stdin▸"
    tui.on_action "_xinput" _exec_on_send
}


# ═══════════════════════════════════════════════════════════════════════
#  WIDGET TEARDOWN  (safe to call more than once)
# ═══════════════════════════════════════════════════════════════════════

_exec_remove_widgets() {
    # Filter out every widget whose id starts with _x
    local new_order=() new_focus=()
    for w in "${_TUI_W_ORDER[@]}"; do
        [[ "$w" == _x* ]] || new_order+=("$w")
    done
    for w in "${_TUI_FOCUSABLE[@]}"; do
        [[ "$w" == _x* ]] || new_focus+=("$w")
    done
    _TUI_W_ORDER=("${new_order[@]}")
    _TUI_FOCUSABLE=("${new_focus[@]}")

    [[ "${_TUI_FOCUS_ID:-}" == _x* ]] && _TUI_FOCUS_ID="" && _TUI_FOCUS_IDX=-1
}


# ═══════════════════════════════════════════════════════════════════════
#  TICK  —  called every ~50 ms while a process is tracked
# ═══════════════════════════════════════════════════════════════════════

_exec_tick() {
    # Nothing to poll once the process is finished
    [[ "$_EXEC_STATUS" == "running" ]] || return

    local changed=0

    # ── Incremental read: grab lines we haven't seen yet ──
    if [[ -s "$_EXEC_OUTFILE" ]]; then
        local new_lines=()
        mapfile -t new_lines < <(
            tail -n +"$(( _EXEC_LAST_READ + 1 ))" "$_EXEC_OUTFILE" 2>/dev/null
        )
        if (( ${#new_lines[@]} > 0 )); then
            _EXEC_BUF+=("${new_lines[@]}")
            (( _EXEC_LAST_READ += ${#new_lines[@]} ))
            changed=1
        fi
    fi

    # ── Process alive? ──
    if ! kill -0 "$_EXEC_PID" 2>/dev/null; then
        wait "$_EXEC_PID" 2>/dev/null
        _EXEC_EXIT=$?

        # Drain anything left
        local leftover=()
        mapfile -t leftover < <(
            tail -n +"$(( _EXEC_LAST_READ + 1 ))" "$_EXEC_OUTFILE" 2>/dev/null
        )
        (( ${#leftover[@]} > 0 )) && _EXEC_BUF+=("${leftover[@]}")

        _EXEC_STATUS=$(( _EXEC_EXIT == 0 )) && _EXEC_STATUS="done" || _EXEC_STATUS="error"
        # Bash arithmetic truthiness is inverted; be explicit:
        if (( _EXEC_EXIT == 0 )); then _EXEC_STATUS="done"; else _EXEC_STATUS="error"; fi

        _exec_render_status
        changed=1
    fi

    (( changed )) && _exec_render_output
}


# ═══════════════════════════════════════════════════════════════════════
#  RENDERING
# ═══════════════════════════════════════════════════════════════════════

_exec_render_status() {
    local icon

    case "$_EXEC_STATUS" in
        running)   icon="● RUNNING  PID ${_EXEC_PID}"  ;;
        done)      icon="✔ DONE     exit ${_EXEC_EXIT}" ;;
        error)     icon="✖ ERROR    exit ${_EXEC_EXIT}" ;;
        cancelled) icon="■ CANCELLED"                    ;;
        *)         icon="○ IDLE"                         ;;
    esac

    tui.update "_xstat" "$icon"

    # Header shows the command (truncated)
    local short="$_EXEC_CMD"
    _tui._widget_pos "_xhdr"
    (( ${#short} > _WSW - 2 )) && short="${short:0:$((_WSW - 5))}..."
    tui.update "_xhdr" "$ ${short}"
}

_exec_render_output() {
    local orows=$(( _EXEC_VROWS - 1 ))
    local total=${#_EXEC_BUF[@]}

    # Tail view: show the last orows lines
    local start=0
    (( total > orows )) && start=$(( total - orows ))

    mode.sync_start
    for (( i = 0; i < orows; i++ )); do
        local idx=$(( start + i ))
        local text=""
        (( idx < total )) && text="${_EXEC_BUF[$idx]}"

        # Truncate to fit pane
        _tui._widget_pos "_xo_${i}"
        tui.update "_xo_${i}" "${text:0:$_WSW}"
    done
    mode.sync_end
}


# ═══════════════════════════════════════════════════════════════════════
#  BUTTON / INPUT CALLBACKS
# ═══════════════════════════════════════════════════════════════════════

_exec_on_cancel() {
    [[ "$_EXEC_STATUS" != "running" ]] && return

    kill -TERM "$_EXEC_PID" 2>/dev/null
    # Give it a moment, then force
    { sleep 0.15; kill -KILL "$_EXEC_PID" 2>/dev/null; } &
    wait "$_EXEC_PID" 2>/dev/null

    _EXEC_STATUS="cancelled"
    _EXEC_BUF+=("--- process cancelled (PID ${_EXEC_PID}) ---")
    _exec_render_status
    _exec_render_output
}

_exec_on_save() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local savefile="exec_output_${ts}.log"

    # Try CWD first, fall back to tmpdir
    if printf '%s\n' "${_EXEC_BUF[@]}" > "$savefile" 2>/dev/null; then
        _EXEC_BUF+=("── saved → $(pwd)/${savefile} ──")
    else
        savefile="${_EXEC_TMPDIR}/output_${ts}.log"
        printf '%s\n' "${_EXEC_BUF[@]}" > "$savefile"
        _EXEC_BUF+=("── saved → ${savefile} ──")
    fi
    _exec_render_output
}

_exec_on_view() {
    _EXEC_BUF+=("┈┈┈ command ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈")
    _EXEC_BUF+=("${_EXEC_CMD}")

    # If the first token is a readable file, show its source
    local first="${_EXEC_CMD%% *}"
    if [[ -f "$first" && -r "$first" ]]; then
        _EXEC_BUF+=("┈┈┈ source: ${first} ┈┈┈┈┈┈┈┈┈")
        while IFS= read -r src_line; do
            _EXEC_BUF+=("  ${src_line}")
        done < "$first"
    fi
    _EXEC_BUF+=("┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈")

    _exec_render_output
}

_exec_on_send() {
    local text
    text=$(tui.get "_xinput")
    [[ -z "$text" ]] && return
    
    tui.log.debug "Sending input: [REDACTED]"

    if [[ "$_EXEC_STATUS" == "running" ]]; then
        # Run in a background subshell. Use printf to prevent 
        # echo from parsing backslashes or hyphens in passwords.
        ( printf "%s\n" "$text" >&"$_EXEC_FIFO_FD" & ) 2>/dev/null
        
        # Mask the output to prevent displaying passwords in plain text
        local masked
        masked="$(printf '%*s' "${#text}" | tr ' ' '*')"
        _EXEC_BUF+=("▸ ${masked}")
    else
        tui.log.warn "Attempted to send input, but process is not running."
        _EXEC_BUF+=("(process not running — input discarded)")
    fi

    tui.set "_xinput" ""
    _tui._draw_widget "_xinput"
    _exec_render_output
}

_exec_on_lsh(){
    tui.log.info "Launch Shell button clicked."
    tui.exec "lsh install" "$_EXEC_OUT_PANE" "$_EXEC_CTL_PANE"
}


# ═══════════════════════════════════════════════════════════════════════
#  CLEANUP
# ═══════════════════════════════════════════════════════════════════════

_kill_process_tree() {
    local pid=$1
    # Recursively find and kill all child processes
    local children
    children=$(pgrep -P "$pid" 2>/dev/null)
    for child in $children; do
        _kill_process_tree "$child"
    done
    kill -TERM "$pid" 2>/dev/null
    sleep 0.05
    kill -KILL "$pid" 2>/dev/null
}

_exec_cleanup_process() {
    # Kill the child and its entire process tree if still alive
    if (( _EXEC_PID > 0 )) && kill -0 "$_EXEC_PID" 2>/dev/null; then
        _kill_process_tree "$_EXEC_PID"
        wait "$_EXEC_PID" 2>/dev/null
    fi
    _EXEC_PID=0

    # Close the stdin FIFO fd
    if [[ -n "${_EXEC_FIFO_FD:-}" ]]; then
        exec {_EXEC_FIFO_FD}>&- 2>/dev/null
        _EXEC_FIFO_FD=""
    fi
}

_master_cleanup() {
    _exec_cleanup_all 2>/dev/null
    tui.cleanup 2>/dev/null
    # Hard reset terminal state (ANSI resets + stty cooked mode)
    printf "\e[0m\e[?25h\e[?1000l\e[?1002l\e[?1006l\e[?1049l\r\n"
    stty sane 2>/dev/null
    stty echo 2>/dev/null
}

_exec_cleanup_all() {
    _exec_cleanup_process
    _TUI_TICK_FN=""
    [[ -n "$_EXEC_TMPDIR" && -d "$_EXEC_TMPDIR" ]] && rm -rf "$_EXEC_TMPDIR"
}


# ═══════════════════════════════════════════════════════════════════════
#  DEMO  —  bash tui_exec.sh
# ═══════════════════════════════════════════════════════════════════════

_exec_demo() {

    # A sample script that produces output over time
    _demo_script="${TMPDIR:-/tmp}/_tui_exec_demo_$$.sh"
    cat > "$_demo_script" <<'SCRIPT'
#!/usr/bin/env bash
echo "Build started at $(date +%H:%M:%S)"
for i in $(seq 1 12); do
    printf '[%2d/12] Compiling module_%02d.c ...\n' "$i" "$i"
    sleep 0.4
done
echo ""
echo "All modules compiled."
echo -n "Enter project name to tag the build: "
read -r name
echo "Tagged build as: ${name:-unnamed}"
echo "Build finished at $(date +%H:%M:%S)"
SCRIPT
    chmod +x "$_demo_script"

    on_quit() { tui.stop; }

    on_rerun() {
        tui.exec "$_demo_script" "output" "controls"
    }

    # ── Layout ──

    tui.init

    tui.hsplit "root"       "output:70"   "sidebar:30"
    tui.vsplit "sidebar"    "controls:70" "nav:30"

    tui.pane_title  "output"   "Output"
    tui.pane_title  "controls" "Controls"
    tui.pane_title  "nav"      "Navigation"
    tui.pane_border "output"   "heavy"

    # Extra buttons in the nav pane (always visible)
    tui.button "btn_rerun" "nav" 0 "[ Re-run ]" on_rerun
    tui.button "btn_quit"  "nav" 1 "[ Quit ]"   on_quit
    # ── Launch ──


    tui.run

    rm -f "$_demo_script"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _exec_demo
fi