#!/usr/bin/env bash
# _header.sh - the demo's shared header: a static title banner plus a live clock, both built on tui_api.sh
# (tui.clock / tui.every), so they need no per-page tick hook and don't touch _TUI_TICK_FN.
tui.require terminal_renderer

# Title banner in the pane's own theme colours. Change-detected by tui.set_text, so the 3-second refresh (which also
# re-fits it after a resize) costs nothing when nothing changed.
_dabt_title() {
    [[ -n "${_TUI_P_H[dabt_hdr_title]:-}" ]] || return 0
    local l out=""
    tui.style.sgr dabt_hdr_title
    _banner_build "DABT DEMO" box3
    for l in "${TR_RESULT[@]}"; do printf -v l '%b' "$l"; out+="${TUI_SGR}${l}"$'\e[0m\n'; done
    tui.set_text dabt_hdr_title "${out%$'\n'}"
}

tui.clock dabt_hdr_clock "%Y-%m-%d %H:%M:%S" box3
tui.every 3 _dabt_title dabt_hdr_title_job
