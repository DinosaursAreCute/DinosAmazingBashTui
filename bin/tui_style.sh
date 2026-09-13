#!/usr/bin/env bash
# tui_style.sh — CSS-like theming for tui.sh (pure bash + POSIX utilities).
#
# Stylesheet format (see config/theme.css):
#   .classname { fg: red; bg: black; mods: bold underline; }
#   .classname:focus { ... }   pseudo-state, applied only while focused
#   .classname:border { ... }  applied to a pane's border
#   .classname:title { ... }   applied to a pane's title text
#
# fg/bg accept a colors.sh name (e.g. "red") or a "#RRGGBB" hex value.
# mods is a space-separated list of style.* modifiers (e.g. "bold underline").
#
# tui.load_theme FILE   parses a stylesheet into the class table.
# tui.class ID CLASS    applies a class's rules to a pane or widget id.
# tui.style ID:STATE FG BG MODS   sets style directly, bypassing classes.
#   STATE is one of: normal (default), focus, border, title.

declare -gA _TUI_STYLE_FG=() _TUI_STYLE_BG=() _TUI_STYLE_MOD=()
declare -gA _TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()

# tui.style ID FG BG MODS [STATE]  — low-level setter behind tui.class.
tui.style() {
    local id="$1" fg="$2" bg="$3" mods="$4" state="${5:-normal}"
    local key="${id}_${state}"
    [[ -n "$fg" ]]   && _TUI_STYLE_FG[$key]="$fg"
    [[ -n "$bg" ]]   && _TUI_STYLE_BG[$key]="$bg"
    [[ -n "$mods" ]] && _TUI_STYLE_MOD[$key]="$mods"
}

# tui.load_theme FILE — parse a .css-like stylesheet into the class table.
tui.load_theme() {
    local file="$1"
    [[ -r "$file" ]] || { echo "tui.load_theme: cannot read '$file'" >&2; return 1; }

    local line trimmed cur=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="$(_markup_trim "$line")"
        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == /\** ]] && continue

        if [[ "$trimmed" =~ ^\.([A-Za-z0-9_-]+(:[a-z]+)?)[[:space:]]*\{$ ]]; then
            cur="${BASH_REMATCH[1]/:/_}"
            continue
        fi
        if [[ "$trimmed" == "}" ]]; then
            cur=""
            continue
        fi
        [[ -z "$cur" ]] && continue

        local decl_re='^([a-z]+)[[:space:]]*:[[:space:]]*([^;]+);?$'
        if [[ "$trimmed" =~ $decl_re ]]; then
            local key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
            val="$(_markup_trim "$val")"
            case "$key" in
                fg)   _TUI_CLASS_FG[$cur]="$val" ;;
                bg)   _TUI_CLASS_BG[$cur]="$val" ;;
                mods) _TUI_CLASS_MOD[$cur]="$val" ;;
            esac
        fi
    done < "$file"
}

# tui.class ID CLASS — applies .class (+ optional :focus/:border/:title
# variants) to a widget or pane id's normal/focus/border/title style keys.
tui.class() {
    local id="$1" cls="$2"
    [[ -z "$cls" ]] && return

    local state suffix
    for state in normal focus border title; do
        suffix="$cls"
        [[ "$state" != "normal" ]] && suffix="${cls}_${state}"
        if [[ -n "${_TUI_CLASS_FG[$suffix]:-}${_TUI_CLASS_BG[$suffix]:-}${_TUI_CLASS_MOD[$suffix]:-}" ]]; then
            tui.style "$id" "${_TUI_CLASS_FG[$suffix]:-}" "${_TUI_CLASS_BG[$suffix]:-}" "${_TUI_CLASS_MOD[$suffix]:-}" "$state"
        fi
    done
}
