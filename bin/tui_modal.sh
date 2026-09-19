#!/usr/bin/env bash
# tui_modal.sh - overlay registry + modal input capture. The foundation for the command palette
# (tui_cmd.sh) and, later, dialogs / prompts / toasts.
#
# OVERLAYS are things drawn over the panes. Panes repaint under them (timers, resizes), so every overlay
# is REDRAWN after each full render and once per main-loop iteration - nothing that repaints underneath
# can leave one half covered. Removing one is a full repaint (tui.relayout), which wipes it.
#   tui.overlay.add FN | tui.overlay.remove FN     FN draws itself (absolute cursor moves, no state)
#
# A MODAL is an overlay that also owns the input: while one is open every key goes to its handler and the
# mouse goes to its mouse handler (or is ignored) - bindings, focus, scrolling and the pointer are
# suspended. Only the terminal-control chord (ctrl+alt+p) and quit-on-SIGINT still work.
#   tui.modal.open NAME KEYFN DRAWFN [MOUSEFN]
#       KEYFN   NAME_OF_KEY     canonical key name ("a", "enter", "ctrl+p", "up"...); "paste" with TUI_EVENT_PASTE
#       DRAWFN                  draws the modal
#       MOUSEFN EVENT X Y       EVENT = mouse:left, wheel:up, ...  (absolute 1-based cell)
#   tui.modal.close             remove it and repaint the screen
#   tui.modal.active [NAME]     rc 0 while a modal (or that one) is open
#   tui.modal.redraw            draw now (call after your state changes)
declare -ga _TUI_OVERLAY_FNS=()
declare -g  _TUI_MODAL="" _TUI_MODAL_KEYFN="" _TUI_MODAL_DRAWFN="" _TUI_MODAL_MOUSEFN=""

tui.overlay.add() {
    local f
    for f in "${_TUI_OVERLAY_FNS[@]}"; do [[ "$f" == "$1" ]] && return 0; done
    _TUI_OVERLAY_FNS+=("$1")
}
tui.overlay.remove() {
    local f; local -a keep=()
    for f in "${_TUI_OVERLAY_FNS[@]}"; do [[ "$f" == "$1" ]] || keep+=("$f"); done
    _TUI_OVERLAY_FNS=("${keep[@]}")
}
_TUI_FLUSH_GEN=0; _TUI_OVL_GEN=0
_tui_overlay.draw_all() {
    _TUI_OVL_GEN=$_TUI_FLUSH_GEN
    local f
    for f in "${_TUI_OVERLAY_FNS[@]}"; do "$f"; done
}

tui.modal.active() { [[ -n "$_TUI_MODAL" && ( -z "${1:-}" || "$_TUI_MODAL" == "$1" ) ]]; }
tui.modal.redraw() { [[ -n "$_TUI_MODAL_DRAWFN" ]] && _tui_overlay.draw_all; return 0; }

tui.modal.open() {
    [[ -n "$_TUI_MODAL" ]] && tui.modal.close
    _TUI_MODAL="$1"; _TUI_MODAL_KEYFN="$2"; _TUI_MODAL_DRAWFN="$3"; _TUI_MODAL_MOUSEFN="${4:-}"
    tui.overlay.add "$3"
    (( _TUI_RUNNING )) && _tui_overlay.draw_all
    return 0
}

tui.modal.close() {
    [[ -n "$_TUI_MODAL" ]] || return 0
    tui.overlay.remove "$_TUI_MODAL_DRAWFN"
    _TUI_MODAL=""; _TUI_MODAL_KEYFN=""; _TUI_MODAL_DRAWFN=""; _TUI_MODAL_MOUSEFN=""
    tui.relayout                 # one synchronized full repaint: the overlay is gone, everything under it is back
}

# tui.reset_ui: a modal never survives a page change
_tui_modal.reset() {
    [[ -n "$_TUI_MODAL" ]] || return 0
    tui.overlay.remove "$_TUI_MODAL_DRAWFN"
    _TUI_MODAL=""; _TUI_MODAL_KEYFN=""; _TUI_MODAL_DRAWFN=""; _TUI_MODAL_MOUSEFN=""
}

# tui.overlay.box ROW COL WIDTH SGR TITLE LINE... - draws a framed box in place (for overlay/modal DRAWFNs).
#   SGR: the colours as SGR parameters, e.g. "1;97;44".  LINEs are cut/padded to the inner width. No state kept.
tui.overlay.box() {
    local row="$1" col="$2" w="$3" sgr="$4" title="$5"; shift 5
    local inner=$(( w - 2 )) bar hz line sp t out=$'\e7' r="$row"
    printf -v bar '%*s' "$inner" ''; hz="${bar// /─}"
    t=" $title "
    out+=$'\e['"${sgr}m"$'\e['"${r};${col}H┌─${t}${hz:0:$(( inner - ${#t} - 1 ))}┐"
    for line in "$@"; do
        (( r++ )); line=" ${line}"; line="${line:0:$inner}"
        printf -v sp '%*s' "$(( inner - ${#line} ))" ''
        out+=$'\e['"${r};${col}H│${line}${sp}│"
    done
    (( r++ ))
    out+=$'\e['"${r};${col}H└${hz}┘"$'\e[0m\e8'
    printf '%s' "$out"
}
