#!/usr/bin/env bash
# settings_callbacks.sh - Settings page: every control does something real.
#   theme      -> tui.theme.set: app-wide overlay from themes/*.css, survives page changes
#   border/pad -> tui.pane_border / tui.pane_pad on the preview pane + tui.relayout
#   font/text  -> banner preview and a live tui.clock in that font
#   clock      -> starts/stops the tui.clock job
#   notify     -> toast via tui.after (auto-clears)
# All values persist to ~/.config/dabt_demo/settings.conf and reload on visit.

tui.require terminal_renderer

_ST_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dabt_demo/settings.conf"
declare -gA ST=()
_ST_BORDERS=(single double heavy none)
_ST_FONTS=(box3 seg3 block5 blk3 half2)

_st_defaults() { ST=([theme]=default [border]=single [hpad]=1 [vpad]=1 [font]=box3 [clock]=1 [notify]=1 [text]=DABT); }

_st_load() {
    _st_defaults
    local k v
    [[ -r "$_ST_FILE" ]] || return 0
    while IFS='=' read -r k v; do [[ -n "${ST[$k]+x}" ]] && ST[$k]="$v"; done < "$_ST_FILE"
}

_st_save() {
    mkdir -p "${_ST_FILE%/*}"
    local k
    for k in "${!ST[@]}"; do printf '%s=%s\n' "$k" "${ST[$k]}"; done | sort > "$_ST_FILE"
    _st_dump
}

_st_next() {   # ARRAYNAME CURRENT -> next element (wraps)
    local -n _arr="$1"; local i
    for i in "${!_arr[@]}"; do
        [[ "${_arr[i]}" == "$2" ]] && { printf '%s' "${_arr[(i + 1) % ${#_arr[@]}]}"; return; }
    done
    printf '%s' "${_arr[0]}"
}

_st_toast() {
    [[ "${ST[notify]}" == 1 ]] || return 0
    tui.update lbl_toast "✔ $1"
    tui.after 3 _st_toast_clear st_toast
}
_st_toast_clear() { tui.update lbl_toast ""; }

_st_dump() {
    local rows cols eff
    tui.pane_size preview
    rows=$TUI_PANE_ROWS; cols=$TUI_PANE_COLS
    eff="$(tui.get.border preview)"
    tui.output status "$(kv_string \
        "file: ${_ST_FILE/#$HOME/~}" \
        "theme: ${ST[theme]}   (tui.theme.current = $(basename "$(tui.theme.current)" 2>/dev/null))" \
        "border: ${ST[border]}   (effective now: $eff)" \
        "pad: hpad=${ST[hpad]} vpad=${ST[vpad]}   ->  usable preview area ${cols} x ${rows}" \
        "font: ${ST[font]}   text: ${ST[text]}" \
        "clock: ${ST[clock]}   notifications: ${ST[notify]}" | sed 's/\\n/\n/g')"
}

# Frame = border/pad props. Content = banner/clock/dump. A change ends with
# tui.relayout preview: repaints ONLY that pane, in one synchronized frame.
_st_frame() {
    tui.pane_border preview "${ST[border]}"
    tui.pane_pad preview "${ST[hpad]}" "${ST[vpad]}"
}

_st_content() {
    local out
    out="$(banner_string "${ST[text]}" "${ST[font]}")"
    tui.output preview "$(printf '%b' "$out")"$'\n\n'"border=${ST[border]}  hpad=${ST[hpad]}  vpad=${ST[vpad]}  font=${ST[font]}"
    _st_clock
    _st_dump
}

_st_clock() {
    if [[ "${ST[clock]}" == 1 ]]; then
        tui.clock preview_clock "%H:%M:%S" "${ST[font]}"
    else
        tui.every.cancel clock_preview_clock
        tui.output_clear preview_clock
    fi
}

_st_labels() {
    tui.set_label btn_border "Border: ${ST[border]}  (click to cycle)"
    tui.set_label btn_font "Font: ${ST[font]}  (click to cycle)"
    tui.set inp_hpad "${ST[hpad]}"; tui.set inp_vpad "${ST[vpad]}"; tui.set inp_text "${ST[text]}"
    tui.update chk_clock  "${ST[clock]}"
    tui.update chk_notify "${ST[notify]}"
    local t
    for t in default ocean forest sunset light; do
        tui.set_label "btn_th_$t" "$([[ "${ST[theme]}" == "$t" ]] && echo "● $t (active)" || echo "  $t")"
    done
}

_st_theme_sync() {   # returns 1 when it triggered a page reload
    local want=""
    [[ "${ST[theme]}" != default ]] && want="$(dirname "$(tui.get.page)")/themes/${ST[theme]}.css"
    [[ "$(tui.theme.current)" == "$want" ]] && return 0
    if [[ -z "$want" ]]; then tui.theme.clear; else tui.theme.set "$want"; fi
    return 1
}

settings_visit() {
    _st_load
    _st_theme_sync || return 0        # reload re-enters settings_visit with the theme applied
    _st_labels
    _st_frame; _st_content
}

on_theme_pick() { ST[theme]="${1#btn_th_}"; _st_save; _st_theme_sync; }
on_border_cycle() { ST[border]="$(_st_next _ST_BORDERS "${ST[border]}")"; _st_labels; _st_save; _st_frame; _st_content; tui.relayout preview; _st_toast "border → ${ST[border]}"; }
on_font_cycle()   { ST[font]="$(_st_next _ST_FONTS "${ST[font]}")"; _st_labels; _st_save; _st_content; _st_toast "font → ${ST[font]}"; }

on_pad_apply() {
    local h v
    h="$(tui.get inp_hpad)"; v="$(tui.get inp_vpad)"
    [[ "$h" =~ ^[0-9]$ ]] && ST[hpad]=$h
    [[ "$v" =~ ^[0-9]$ ]] && ST[vpad]=$v
    _st_labels; _st_save; _st_frame; _st_content; tui.relayout preview; _st_toast "padding → ${ST[hpad]} x ${ST[vpad]}"
}

on_text_apply() {
    local t; t="$(tui.get inp_text)"
    [[ -n "$t" ]] && ST[text]="${t:0:12}"
    _st_labels; _st_save; _st_content; _st_toast "text → ${ST[text]}"
}

on_clock_toggle()  { ST[clock]="$(tui.get chk_clock)"; _st_save; _st_clock; _st_toast "clock $([[ ${ST[clock]} == 1 ]] && echo on || echo off)"; }
on_notify_toggle() { ST[notify]="$(tui.get chk_notify)"; _st_save; tui.update lbl_toast "notifications $([[ ${ST[notify]} == 1 ]] && echo on || echo off)"; tui.after 3 _st_toast_clear st_toast; }

on_reset() {
    rm -f "$_ST_FILE"
    _st_defaults
    _st_save
    tui.theme.clear          # reloads this page -> settings_visit picks up the defaults
}
