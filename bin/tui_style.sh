#!/usr/bin/env bash
# tui_style.sh — CSS-like theming for tui.sh (pure bash + POSIX utilities).
#
# Stylesheet format (see config/theme.css):
#   .classname { fg: red; bg: black; mods: bold underline; }
#   .classname:focus { ... }   applied while a widget is focused; on a pane,
#                               applied to its border ring while any widget
#                               inside it is focused — see _tui._draw_pane_border
#                               and _tui._draw_widget in tui.sh.
#   .classname:border { ... }  a pane's border in its normal (unfocused) state
#   .classname:title { ... }   applied to a pane's title text
#   .classname:hover { ... }   applied to a *widget* (button/input) while the
#                               mouse is over it; a widget with no :hover
#                               rules keeps its normal look. Has no effect on
#                               panes — pane borders only react to :focus.
#
# fg/bg accept a colors.sh name (e.g. "red") or a "#RRGGBB" hex value.
# mods is a space-separated list of style.* modifiers (e.g. "bold underline").
#
# tui.load_theme FILE   parses a stylesheet into the class table.
# tui.class ID CLASS    applies a class's rules to a pane or widget id.
# tui.style ID:STATE FG BG MODS   sets style directly, bypassing classes.
#   STATE is one of: normal (default), focus, border, title, hover.

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

    _tui._find_theme_collisions
    local finding
    for finding in "${_TUI_THEME_COLLISIONS[@]}"; do
        tui.log.warn "tui.load_theme($file): $finding"
    done
}

# _tui._find_theme_collisions — scans the just-loaded theme for classes
# where a pane's border ring, in the state it actually shows while
# focused, resolves to the exact same fg/bg/mods as that class's :title.
# These two are drawn immediately adjacent to each other — the border
# ring, then the title tag right after it — any time a pane using that
# class has a title and gets focused (_tui._draw_pane_border in tui.sh).
# Identical styles there don't produce a visible error; they produce a
# run of same-colored characters that reads, in a screenshot, like
# garbled output rather than what it actually is: nobody chose to make
# the border and the title look different once the pane has focus. This
# is exactly the bug `.sidebar:focus` shipped with earlier in this
# project's history (copied from `.sidebar:title` verbatim) — findings
# are populated into _TUI_THEME_COLLISIONS as plain description strings;
# tui.load_theme logs each one via tui.log.warn, and scripts/lint_theme.sh
# prints them for a human to look at directly, both reading the exact
# same array so there's one place this check can ever be wrong.
declare -ga _TUI_THEME_COLLISIONS=()

_tui._theme_state_triplet() {
    local class="$1"
    local state="$2"
    local suffix="$class"
    [[ "$state" != "normal" ]] && suffix="${class}_${state}"
    printf '%s\x1f%s\x1f%s' "${_TUI_CLASS_FG[$suffix]:-}" "${_TUI_CLASS_BG[$suffix]:-}" "${_TUI_CLASS_MOD[$suffix]:-}"
}

_tui._theme_triplet_set() { [[ "$1" != $'\x1f\x1f' ]]; }

_tui._find_theme_collisions() {
    _TUI_THEME_COLLISIONS=()

    local -A bases=()
    local key base
    for key in "${!_TUI_CLASS_FG[@]}" "${!_TUI_CLASS_BG[@]}" "${!_TUI_CLASS_MOD[@]}"; do
        base="$key"
        base="${base%_focus}"; base="${base%_border}"; base="${base%_title}"; base="${base%_hover}"
        bases[$base]=1
    done

    local title ring focus
    for base in "${!bases[@]}"; do
        title="$(_tui._theme_state_triplet "$base" title)"
        _tui._theme_triplet_set "$title" || continue

        focus="$(_tui._theme_state_triplet "$base" focus)"
        if _tui._theme_triplet_set "$focus"; then
            ring="$focus"
        else
            ring="$(_tui._theme_state_triplet "$base" border)"
        fi
        _tui._theme_triplet_set "$ring" || continue

        if [[ "$title" == "$ring" ]]; then
            _TUI_THEME_COLLISIONS+=(".$base — :focus (falling back to :border) resolves identically to :title. A pane using this class will show its title tag blending into its border ring the moment it's focused.")
        fi
    done
}

# tui.class ID CLASS — applies .class (+ optional :focus/:border/:title
# variants) to a widget or pane id's normal/focus/border/title style keys.
tui.class() {
    local id="$1" cls="$2"
    [[ -z "$cls" ]] && return

    local state suffix
    for state in normal focus border title hover; do
        suffix="$cls"
        [[ "$state" != "normal" ]] && suffix="${cls}_${state}"
        if [[ -n "${_TUI_CLASS_FG[$suffix]:-}${_TUI_CLASS_BG[$suffix]:-}${_TUI_CLASS_MOD[$suffix]:-}" ]]; then
            tui.style "$id" "${_TUI_CLASS_FG[$suffix]:-}" "${_TUI_CLASS_BG[$suffix]:-}" "${_TUI_CLASS_MOD[$suffix]:-}" "$state"
        fi
    done
}
