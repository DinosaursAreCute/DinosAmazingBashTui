#!/usr/bin/env bash
# state.sh - global state for the core layout/widget engine (tui.sh).
#
# tui.sh labels these as "INTERNAL STATE" sections at its own top; this file
# is that state pulled out into one place so its shape can be scanned
# without wading through the ~3000 lines of engine logic around it. Sourced
# first by tui.sh, before any function body that touches these runs.
#
# Everything here is still private engine state (leading underscore =
# internal, plain TUI_* = public but engine-owned) - callbacks should go
# through tui_api.sh, not touch these directly. State declared right next
# to its one function (e.g. _TUI_SGR_NAMED, _HIT_PANE) stays local to that
# function in tui.sh - only the three big up-front registries below moved
# (UI & LAYOUT, BACKGROUND EXECUTION, and FACTORY).

# ═══════════════════════════════════════════════════════════════════════
#  UI & LAYOUT
# ═══════════════════════════════════════════════════════════════════════

declare -gA _TUI_P_ROW=() _TUI_P_COL=()
declare -gA _TUI_P_H=() _TUI_P_W=()
declare -gA _TUI_P_DIR=()
declare -gA _TUI_P_CHILDREN=()
declare -gA _TUI_P_WEIGHTS=()                                                # per parent: space-joined per-child size spec (plain weight, or 2A unit token: N%, Nfr, auto, fill, clamp(...))
declare -gA _TUI_P_GAP=()                                                    # per parent: cells between children on the split axis (2A)
declare -gA _TUI_P_CELLW=() _TUI_P_CELLH=() _TUI_P_SPAN=() _TUI_P_NEWLINE=() # fixed-size grid (tui.fixed)
declare -gA _TUI_P_TITLE=()
declare -gA _TUI_P_BORDER=()
declare -gA _TUI_P_ALIGN=()
declare -gA _TUI_P_VALIGN=()
declare -gA _TUI_P_MINW=() _TUI_P_MINH=()
declare -gA _TUI_P_MAXW=() _TUI_P_MAXH=()
declare -ga _TUI_P_LEAVES=()
declare -ga _TUI_P_ALL=()
declare -gA _TUI_P_CONTENT=()
declare -gA _TUI_P_SCROLL=()
declare -gA _TUI_P_SOFF_V=()
declare -gA _TUI_P_SOFF_H=()
declare -gA _TUI_P_CONTENT_H=() # per pane: total height in rows of widgets in the pane
declare -gA _TUI_P_STUCK=()     # per pane: id of the pinned widget currently stuck at the top, absent if none
declare -gA _TUI_P_NOREVEAL=()  # per pane: 1 if scroll_into_view is disabled (don't auto-reveal on focus)
declare -gA _TUI_P_HPAD=() _TUI_P_VPAD=() _TUI_P_BORDER_EXPL=()
declare -gA _TUI_W_HPAD=() _TUI_W_VPAD=()
declare -g _TUI_DRAG_PANE=""
declare -g _TUI_DRAG_AXIS=""
declare -gA _TUI_P_LINES=()
declare -gA _TUI_P_MAX_W=()

declare -gA _TUI_W_TYPE=()
declare -gA _TUI_W_PANE=()
declare -gA _TUI_W_ROW=()
declare -gA _TUI_W_LABEL=()
declare -gA _TUI_W_VALUE=()
declare -gA _TUI_W_ACTION=()
declare -gA _TUI_W_SUBMIT=()
declare -gA _TUI_W_PH=()
declare -gA _TUI_W_ALIGN=()
declare -gA _TUI_W_VALIGN=()
declare -gA _TUI_W_MINW=() _TUI_W_MAXW=() _TUI_W_MINH=() _TUI_W_MAXH=()
declare -gA _TUI_W_EXPAND=()                 # id -> "x"/"y"/"both": which dims _tui._widget_pos fills to the pane's content area (2A)
declare -gA _TUI_W_WIDTH=() _TUI_W_HEIGHT=() # id -> 2A unit-token size spec (cells, %, fr, auto, fill, clamp(...))
declare -gA _TUI_W_LABEL_ALIGN=()
declare -gA _TUI_W_RETAIN=() _TUI_W_STICKY=() # input focus policy: explicit retain (1/0) and sticky (see tui.input.retain / .sticky)
declare -gA _TUI_W_PIN=()                     # per widget: pin directive (only "top" accepted); pinned widgets stick at pane viewport top when scrolled past
declare -g TUI_INPUT_RETAIN_ON_SUBMIT=1       # default when an input has no retain_input_on_submit of its own
declare -gA _TUI_W_LABEL_WIDTH=()
declare -ga _TUI_W_ORDER=()
declare -ga _TUI_FOCUSABLE=()

# _tui_w.changed - the widget list or a widget's type changed: the focus order (tui_focus.sh) and the hit index
# (tui_hit.sh) are derived from it and rebuild on next use. Every writer of _TUI_W_ORDER/_TUI_W_TYPE calls this.
_tui_w.changed() { _TUI_FOCUS_DIRTY=1 _TUI_HZ_DIRTY=1; }

declare -g _TUI_FOCUS_ID=""
declare -g _TUI_FOCUS_IDX=-1
declare -g _TUI_CURSOR=0
declare -g _TUI_RUNNING=0
declare -g _TUI_OLD_STTY=""
declare -g _TUI_ROWS=0
declare -g _TUI_COLS=0
declare -g _WSR=0 _WSC=0 _WSW=0 _WSW_AVAIL=0

# Raw-byte pushback FIFO: bytes that were already read from stdin (while
# peeking ahead to coalesce mouse motion - see _tui._coalesce_mouse_motion)
# but turned out to belong to a different, non-coalescible event. They're
# stashed here and replayed through _tui._next_byte before the next real
# read, so nothing downstream has to know a peek ever happened.
declare -g _TUI_PENDING_INPUT=""
# Scratch output slot for _tui._read_escape_seq (a plain global instead of
# a command-substitution return, so assembling a sequence never forks).
declare -g _TUI_SEQ_BUF=""

declare -g _TUI_DRAG_LINES=0
declare -g _TUI_DRAG_MAX_W=0
declare -g _TUI_HOVERED_PANE=""
declare -g _TUI_HOVERED_WIDGET=""

# Debounced render queue for pane *content* only (tui.output / scroll).
# Scroll-wheel spins and drag-jumps can arrive in bursts much faster than
# the AWK shader needs to run, so they mark a pane dirty and arm one shared
# countdown instead of redrawing on every event; tui.run() flushes whatever
# is pending at most once per settled moment. Hover/focus restyling is a
# single cheap widget or border redraw and is drawn immediately instead
# (see _tui._draw_widgets_now) - debouncing it added latency without a
# throughput problem to justify it.
declare -gA _TUI_PANE_CONTENT=()   # pane id -> 1 when it holds tui.output content (MUST be associative: pane ids are names)
declare -gA _TUI_PENDING_OUTPUT=() # pane id -> content awaiting re-render
declare -g _TUI_RENDER_TIMEOUT=-1
declare -gi _TUI_DEFER_RENDER=0 # 1 while tui.goto loads a page: tui.goto renders once afterwards, so tui.render calls made by on_visit code are skipped

# ═══════════════════════════════════════════════════════════════════════
#  BACKGROUND EXECUTION (tui.exec instance registries)
# ═══════════════════════════════════════════════════════════════════════

declare -gA _EXEC_CMD=()       # iid -> command string
declare -gA _EXEC_OUT_PANE=()  # iid -> output pane id
declare -gA _EXEC_CTL_PANE=()  # iid -> control pane id, "" if none
declare -gA _EXEC_NS=()        # iid -> factory namespace for its controls, "" if none
declare -gA _EXEC_PID=()       # iid -> pid
declare -gA _EXEC_STATUS=()    # iid -> running|done|error|cancelled
declare -gA _EXEC_EXIT=()      # iid -> exit code
declare -gA _EXEC_TMPDIR=()    # iid -> tmp dir holding its fifo + outfile
declare -gA _EXEC_OUTFILE=()   # iid -> outfile path
declare -gA _EXEC_FIFO=()      # iid -> fifo path (this instance's own pipe)
declare -gA _EXEC_FIFO_FD=()   # iid -> open fd number for that fifo
declare -gA _EXEC_LAST_READ=() # iid -> lines already consumed from outfile
declare -g _EXEC_NEXT_ID=1
declare -g _TUI_EXEC_LAST_ID="" # set (not printed) by tui.exec, same convention as _TUI_FACTORY_LAST_ID

declare -gA _EXEC_WIDGET_TO_IID=()  # control/input widget id -> owning iid
declare -gA _EXEC_PANE_INSTANCES=() # out_pane -> "iid1 iid2 ..." (oldest→newest, finished ones stay until dismissed)
declare -gA _EXEC_PANE_CTL_ROW=()   # ctl_pane -> next free row block for a new instance's controls

# ═══════════════════════════════════════════════════════════════════════
#  FACTORY (tui.factory.* constructors and grid tracking)
# ═══════════════════════════════════════════════════════════════════════

declare -gA _TUI_FACTORY_IDS=()          # namespace -> "id1 id2 ..." (widgets + panes)
declare -gA _TUI_FACTORY_GRID_PARENTS=() # namespace -> "parent1 ..." (split state to reset, not remove)
declare -gA _TUI_FACTORY_COUNTER=()      # namespace -> next auto-id suffix
declare -ga _TUI_FACTORY_GRID_CELLS=()   # last tui.factory.grid call's cell ids, in order

# Sets _TUI_FACTORY_LAST_ID rather than printing its result: this
# increments _TUI_FACTORY_COUNTER as a side effect, and a command
# substitution (id="$(...)") runs in a subshell, which would silently
# discard that increment - every id in a loop would come back identical.
# Same fork-free convention as _HIT/_HIT_PANE elsewhere in this file.
declare -g _TUI_FACTORY_LAST_ID=""
