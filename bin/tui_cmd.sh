#!/usr/bin/env bash
# tui_cmd.sh - command registry + command palette (the "command bar").
#
# The palette is just a front end for the REGISTRY, and the registry is the developer API: DABT's own
# default actions are registered through exactly the same calls an app uses (config/default/commands.xml
# plus the providers at the bottom of this file), so anything they can do, your commands can too.
#
#   tui.cmd.add ID "Title" ACTION [--group G] [--desc TEXT] [--when FN] [--key KEY]
#       ACTION  what to run: a function + args, several chained with ';'  ("tui.action.goto home.xml")
#       --when  predicate function: the command is listed only while it returns 0
#       --key   also bind KEY to it (shown as the hint in the palette)
#   tui.cmd.remove ID | tui.cmd.run ID | tui.cmd.list
#   tui.cmd.load FILE            <cmd id= title= action= [group=] [desc=] [when=] [key=]/> lines
#   tui.cmd.provider FN          FN runs each time the palette opens and may call tui.cmd.add for commands
#                                that depend on state (pages, themes, panes ...); those are dropped and
#                                regenerated on every open
#   tui.palette.open [QUERY]     open the palette (default keys: ctrl+p, ':')   tui.palette.close
#
# Keys inside: type to filter (fuzzy, every word must match) | up/down or ctrl+p/ctrl+n | pgup/pgdn | Enter run
# | Esc close | ctrl+u clear | backspace. Mouse: click a row to run it, wheel to move, click outside to close.

declare -ga _TUI_CMD_IDS=()
declare -gA _TUI_CMD_TITLE=() _TUI_CMD_ACTION=() _TUI_CMD_GROUP=() _TUI_CMD_DESC=() _TUI_CMD_WHEN=() _TUI_CMD_DYN=()
declare -ga _TUI_CMD_PROVIDERS=()
declare -g  _TUI_CMD_IN_PROVIDER=0

tui.cmd.add() {
    local id="$1" title="$2" action="$3" group="" desc="" when="" key="" i seen=0
    [[ -z "$id" || -z "$title" || -z "$action" ]] && { echo "tui.cmd.add: usage: tui.cmd.add ID TITLE ACTION [flags]" >&2; return 1; }
    shift 3
    while (( $# )); do
        case "$1" in
            --group) group="$2"; shift ;;
            --desc)  desc="$2"; shift ;;
            --when)  when="$2"; shift ;;
            --key)   key="$2"; shift ;;
        esac
        shift
    done
    for i in "${_TUI_CMD_IDS[@]}"; do [[ "$i" == "$id" ]] && { seen=1; break; }; done
    (( seen )) || _TUI_CMD_IDS+=("$id")
    _TUI_CMD_TITLE[$id]="$title"; _TUI_CMD_ACTION[$id]="$action"; _TUI_CMD_GROUP[$id]="$group"
    _TUI_CMD_DESC[$id]="$desc";   _TUI_CMD_WHEN[$id]="$when"
    if (( _TUI_CMD_IN_PROVIDER )); then _TUI_CMD_DYN[$id]=1; else unset '_TUI_CMD_DYN[$id]'; fi
    [[ -n "$key" ]] && tui.bind "$key" "tui.cmd.run $id" --desc "$title"
    return 0
}

tui.cmd.remove() {
    local i; local -a keep=()
    for i in "${_TUI_CMD_IDS[@]}"; do [[ "$i" == "$1" ]] || keep+=("$i"); done
    _TUI_CMD_IDS=("${keep[@]}")
    unset '_TUI_CMD_TITLE[$1]' '_TUI_CMD_ACTION[$1]' '_TUI_CMD_GROUP[$1]' '_TUI_CMD_DESC[$1]' '_TUI_CMD_WHEN[$1]' '_TUI_CMD_DYN[$1]'
}

tui.cmd.run() {
    [[ -n "${_TUI_CMD_ACTION[$1]:-}" ]] || { echo "tui.cmd.run: unknown command '$1'" >&2; return 1; }
    _tui_input.run "${_TUI_CMD_ACTION[$1]}"
}

tui.cmd.provider() {
    local f
    for f in "${_TUI_CMD_PROVIDERS[@]}"; do [[ "$f" == "$1" ]] && return 0; done
    _TUI_CMD_PROVIDERS+=("$1")
}

tui.cmd.list() {
    local id
    for id in "${_TUI_CMD_IDS[@]}"; do
        printf '%s\t%s\t%s\t%s\n' "$id" "${_TUI_CMD_GROUP[$id]}" "${_TUI_CMD_TITLE[$id]}" "${_TUI_CMD_ACTION[$id]}"
    done
}

# tui.cmd.load FILE - one <cmd .../> per line (same style as config/default/keybinds.xml)
tui.cmd.load() {
    local file="$1" line id title act group desc when key
    [[ -r "$file" ]] || { echo "tui.cmd.load: cannot read '$file'" >&2; return 1; }
    while IFS= read -r line; do
        [[ "$line" == *"<cmd "* ]] || continue
        _tui_input.attr "$line" id;     id="$_ATTR"
        _tui_input.attr "$line" title;  _tui_input.unesc "$_ATTR"; title="$_UNESC"
        _tui_input.attr "$line" action; _tui_input.unesc "$_ATTR"; act="$_UNESC"
        [[ -z "$id" || -z "$title" || -z "$act" ]] && continue
        _tui_input.attr "$line" group;  group="$_ATTR"
        _tui_input.attr "$line" desc;   _tui_input.unesc "$_ATTR"; desc="$_UNESC"
        _tui_input.attr "$line" when;   when="$_ATTR"
        _tui_input.attr "$line" key;    key="$_ATTR"
        local -a fl=()
        [[ -n "$group" ]] && fl+=(--group "$group")
        [[ -n "$desc" ]]  && fl+=(--desc "$desc")
        [[ -n "$when" ]]  && fl+=(--when "$when")
        [[ -n "$key" ]]   && fl+=(--key "$key")
        tui.cmd.add "$id" "$title" "$act" "${fl[@]}"
    done < "$file"
}

# ── palette ─────────────────────────────────────────────────────────────
declare -g  _PAL_Q="" _PAL_SEL=0 _PAL_TOP=0
declare -ga _PAL_IDS=()                   # filtered + ranked command ids
declare -gA _PAL_HINT=()                  # command id -> key hint
declare -g  _PAL_BX=0 _PAL_BY=0 _PAL_BW=0 _PAL_BH=0 _PAL_RY=0 _PAL_ROWS=0
declare -g  _PAL_SGR_BOX="" _PAL_SGR_IN="" _PAL_SGR_SEL="" _PAL_SGR_DIM=""
declare -g  TUI_PALETTE_ROWS=10           # visible result rows

# _tui_cmd.refresh: drop provider-made commands, run the providers, rebuild key hints
_tui_cmd.refresh() {
    local id f
    for id in "${!_TUI_CMD_DYN[@]}"; do tui.cmd.remove "$id"; done
    _TUI_CMD_IN_PROVIDER=1
    for f in "${_TUI_CMD_PROVIDERS[@]}"; do "$f"; done
    _TUI_CMD_IN_PROVIDER=0

    # action -> key, once (your binds, then code binds, then active defaults; longest name = the chord)
    local a
    _tui_input.reverse_keys
    _PAL_HINT=()
    for id in "${_TUI_CMD_IDS[@]}"; do
        a="${_TUI_CMD_ACTION[$id]}"
        _PAL_HINT[$id]="${_REVK[$a]:-${_REVK[tui.cmd.run $id]:-}}"
    done
}

# _tui_cmd.match QUERY TEXT -> _SCORE (-1 = no match). Every whitespace-separated word of QUERY must appear in
# order (a subsequence) in TEXT; consecutive runs, word starts and early positions score higher.
_tui_cmd.match() {
    local -a words; local w t="${2,,}" total=0 qi ti n last s c prev
    read -ra words <<< "${1,,}"
    (( ${#words[@]} )) || { _SCORE=0; return 0; }
    for w in "${words[@]}"; do
        qi=0; last=-2; s=0; n=${#t}
        for (( ti = 0; ti < n && qi < ${#w}; ti++ )); do
            c="${t:ti:1}"
            [[ "$c" == "${w:qi:1}" ]] || continue
            (( s += 10 ))
            (( ti == last + 1 )) && (( s += 15 ))
            if (( ti == 0 )); then (( s += 25 )); else prev="${t:ti-1:1}"; [[ "$prev" == [\ :/_.-] ]] && (( s += 20 )); fi
            last=$ti; (( qi++ ))
        done
        (( qi < ${#w} )) && { _SCORE=-1; return 0; }
        (( total += s - last ))
    done
    _SCORE=$total
}

_tui_cmd.filter() {
    local id when key sc; local -a ranked=()
    _PAL_IDS=()
    for id in "${_TUI_CMD_IDS[@]}"; do
        when="${_TUI_CMD_WHEN[$id]}"
        [[ -n "$when" ]] && ! "$when" && continue
        _tui_cmd.match "$_PAL_Q" "${_TUI_CMD_TITLE[$id]} ${_TUI_CMD_GROUP[$id]}"
        (( _SCORE < 0 )) && continue
        ranked+=("$_SCORE $id")
    done
    if [[ -z "${_PAL_Q// }" ]]; then                          # no query: registration order
        for sc in "${ranked[@]}"; do _PAL_IDS+=("${sc#* }"); done
    else                                                      # ranked, best first (insertion sort; the list is short)
        local i j item
        local -a sorted=()
        for item in "${ranked[@]}"; do
            for (( i = 0; i < ${#sorted[@]}; i++ )); do (( ${item%% *} > ${sorted[i]%% *} )) && break; done
            sorted=("${sorted[@]:0:i}" "$item" "${sorted[@]:i}")
        done
        for sc in "${sorted[@]}"; do _PAL_IDS+=("${sc#* }"); done
    fi
    (( _PAL_SEL >= ${#_PAL_IDS[@]} )) && _PAL_SEL=$(( ${#_PAL_IDS[@]} - 1 ))
    (( _PAL_SEL < 0 )) && _PAL_SEL=0
    _tui_cmd.scroll_into_view
}

_tui_cmd.scroll_into_view() {
    (( _PAL_SEL < _PAL_TOP )) && _PAL_TOP=$_PAL_SEL
    (( _PAL_SEL >= _PAL_TOP + _PAL_ROWS )) && _PAL_TOP=$(( _PAL_SEL - _PAL_ROWS + 1 ))
    (( _PAL_TOP < 0 )) && _PAL_TOP=0
}

# Colours: theme classes .palette / .palette_input / .palette_sel / .palette_dim when the theme has them,
# else built-in ones. Resolved once per open (a few forks, not per keystroke).
_tui_cmd.styles() {
    tui.class.sgr palette;       _PAL_SGR_BOX="${TUI_SGR:-$'\e[0;37;48;2;30;34;52m'}"
    tui.class.sgr palette_input; _PAL_SGR_IN="${TUI_SGR:-$'\e[1;97;48;2;30;34;52m'}"
    tui.class.sgr palette_sel;   _PAL_SGR_SEL="${TUI_SGR:-$'\e[1;30;48;2;97;175;239m'}"
    tui.class.sgr palette_dim;   _PAL_SGR_DIM="${TUI_SGR:-$'\e[2;37;48;2;30;34;52m'}"
}

tui.palette.open() {
    (( _TUI_RUNNING )) || return 0
    _tui_cmd.refresh
    _tui_cmd.styles
    _PAL_Q="${1:-}"; _PAL_SEL=0; _PAL_TOP=0
    _PAL_ROWS=$TUI_PALETTE_ROWS
    (( _PAL_ROWS > _TUI_ROWS - 8 )) && _PAL_ROWS=$(( _TUI_ROWS - 8 ))
    (( _PAL_ROWS < 3 )) && _PAL_ROWS=3
    _tui_cmd.filter
    tui.modal.open palette _tui_cmd.palette_key _tui_cmd.palette_draw _tui_cmd.palette_mouse
}
tui.palette.close() { tui.modal.active palette && tui.modal.close; }

# Run the selected command AFTER the palette is gone and the screen is repainted, so a command that changes
# page or focus starts from a clean frame.
_tui_cmd.run_selected() {
    local id="${_PAL_IDS[_PAL_SEL]:-}"
    [[ -n "$id" ]] || return 0
    tui.modal.close
    tui.cmd.run "$id"
}

_tui_cmd.palette_key() {
    local name="$1" t
    case "$name" in
        esc|ctrl+g)          tui.modal.close; return ;;
        enter)               _tui_cmd.run_selected; return ;;
        up|ctrl+p|ctrl+k)    (( _PAL_SEL > 0 )) && (( _PAL_SEL-- )) ;;
        down|ctrl+n|ctrl+j)  (( _PAL_SEL < ${#_PAL_IDS[@]} - 1 )) && (( _PAL_SEL++ )) ;;
        pgup)                (( _PAL_SEL -= _PAL_ROWS )); (( _PAL_SEL < 0 )) && _PAL_SEL=0 ;;
        pgdn)                (( _PAL_SEL += _PAL_ROWS )); (( _PAL_SEL >= ${#_PAL_IDS[@]} )) && _PAL_SEL=$(( ${#_PAL_IDS[@]} - 1 )); (( _PAL_SEL < 0 )) && _PAL_SEL=0 ;;
        home)                _PAL_SEL=0 ;;
        end)                 _PAL_SEL=$(( ${#_PAL_IDS[@]} - 1 )); (( _PAL_SEL < 0 )) && _PAL_SEL=0 ;;
        backspace)           _PAL_Q="${_PAL_Q%?}"; _PAL_SEL=0; _PAL_TOP=0; _tui_cmd.filter ;;
        ctrl+u)              _PAL_Q=""; _PAL_SEL=0; _PAL_TOP=0; _tui_cmd.filter ;;
        ctrl+w)              t="${_PAL_Q%"${_PAL_Q##*[![:space:]]}"}"; _PAL_Q="${t% *}"; [[ "$t" != *" "* ]] && _PAL_Q=""
                             [[ -n "$_PAL_Q" ]] && _PAL_Q+=" "; _PAL_SEL=0; _PAL_TOP=0; _tui_cmd.filter ;;
        space)               _PAL_Q+=" "; _PAL_SEL=0; _PAL_TOP=0; _tui_cmd.filter ;;
        paste)               t="${TUI_EVENT_PASTE%%$'\n'*}"; t="${t//[[:cntrl:]]/}"
                             _PAL_Q+="$t"; _PAL_SEL=0; _PAL_TOP=0; _tui_cmd.filter ;;
        *)                   if (( ${#name} == 1 )); then _PAL_Q+="$name"; _PAL_SEL=0; _PAL_TOP=0; _tui_cmd.filter; fi ;;
    esac
    _tui_cmd.scroll_into_view
    tui.modal.redraw
}

# EVENT X Y
_tui_cmd.palette_mouse() {
    local ev="$1" x="$2" y="$3" row
    case "$ev" in
        wheel:up)   (( _PAL_SEL > 0 )) && (( _PAL_SEL-- )); _tui_cmd.scroll_into_view; tui.modal.redraw ;;
        wheel:down) (( _PAL_SEL < ${#_PAL_IDS[@]} - 1 )) && (( _PAL_SEL++ )); _tui_cmd.scroll_into_view; tui.modal.redraw ;;
        mouse:left)
            if (( x < _PAL_BX || x >= _PAL_BX + _PAL_BW || y < _PAL_BY || y >= _PAL_BY + _PAL_BH )); then tui.modal.close; return; fi
            row=$(( y - _PAL_RY ))
            if (( row >= 0 && row < _PAL_ROWS && _PAL_TOP + row < ${#_PAL_IDS[@]} )); then
                _PAL_SEL=$(( _PAL_TOP + row )); _tui_cmd.run_selected
            fi ;;
    esac
}

# _tui_cmd.pad TEXT WIDTH -> _PADS: TEXT cut/padded to exactly WIDTH characters (char-based; printf %-*s counts bytes)
_tui_cmd.pad() {
    local s="${1:0:$2}" sp
    printf -v sp '%*s' "$(( $2 - ${#s} ))" ''
    _PADS="$s$sp"
}

_tui_cmd.palette_draw() {
    tui.modal.active palette || return 0
    local w=72 h n=${#_PAL_IDS[@]} r i idx id line hint title room desc foot bar hz
    (( w > _TUI_COLS - 4 )) && w=$(( _TUI_COLS - 4 ))
    (( w < 30 )) && w=30
    h=$(( _PAL_ROWS + 5 ))                       # top, input, separator, rows..., footer, bottom
    _PAL_BW=$w; _PAL_BH=$h
    _PAL_BX=$(( (_TUI_COLS - w) / 2 + 1 )); (( _PAL_BX < 1 )) && _PAL_BX=1
    _PAL_BY=3; (( _PAL_BY + h > _TUI_ROWS )) && _PAL_BY=1
    _PAL_RY=$(( _PAL_BY + 3 ))
    local inner=$(( w - 2 ))
    printf -v bar '%*s' "$inner" ''; hz="${bar// /─}"

    local out=$'\e7' x=$_PAL_BX
    # top border with title
    title=" Command palette "
    out+="${_PAL_SGR_BOX}"$'\e['"$_PAL_BY;${x}H┌─${title}${hz:0:$(( inner - ${#title} - 1 ))}┐"
    # input
    line="> ${_PAL_Q}"; (( ${#line} > inner - 3 )) && line="${line: -$(( inner - 3 ))}"
    _tui_cmd.pad " ${line}█" "$inner"
    out+=$'\e['"$(( _PAL_BY + 1 ));${x}H${_PAL_SGR_BOX}│${_PAL_SGR_IN}${_PADS}${_PAL_SGR_BOX}│"
    out+=$'\e['"$(( _PAL_BY + 2 ));${x}H${_PAL_SGR_BOX}├${hz}┤"
    # results
    for (( r = 0; r < _PAL_ROWS; r++ )); do
        idx=$(( _PAL_TOP + r ))
        if (( idx < n )); then
            id="${_PAL_IDS[idx]}"; hint="${_PAL_HINT[$id]:-}"
            title="${_TUI_CMD_TITLE[$id]}"
            room=$(( inner - 2 - ${#hint} - (${#hint} ? 2 : 0) ))
            (( ${#title} > room )) && title="${title:0:$(( room - 1 ))}…"
            if (( ${#hint} )); then _tui_cmd.pad " $title" "$(( inner - ${#hint} - 1 ))"; line="${_PADS}${hint} "
            else _tui_cmd.pad " $title" "$inner"; line="$_PADS"; fi
            if (( idx == _PAL_SEL )); then line="${_PAL_SGR_SEL}${line}"; else line="${_PAL_SGR_BOX}${line}"; fi
        else
            if (( n == 0 && r == 0 )); then _tui_cmd.pad " no matching command" "$inner"; else _tui_cmd.pad "" "$inner"; fi
            line="${_PAL_SGR_DIM}${_PADS}"
        fi
        out+=$'\e['"$(( _PAL_RY + r ));${x}H${_PAL_SGR_BOX}│${line}${_PAL_SGR_BOX}│"
    done
    # footer: description of the selection, or the key help; count on the right
    desc=""; [[ -n "${_PAL_IDS[_PAL_SEL]:-}" ]] && desc="${_TUI_CMD_DESC[${_PAL_IDS[_PAL_SEL]}]:-}"     # empty id = bad array subscript
    foot="${desc:-↑↓ select   ⏎ run   esc close}"
    local cnt="${n} cmd"; (( n != 1 )) && cnt+="s"
    room=$(( inner - ${#cnt} - 3 )); (( ${#foot} > room )) && foot="${foot:0:$(( room - 1 ))}…"
    _tui_cmd.pad " $foot" "$(( inner - ${#cnt} - 1 ))"
    out+=$'\e['"$(( _PAL_BY + _PAL_ROWS + 3 ));${x}H${_PAL_SGR_DIM}│${_PADS}${cnt} │"
    out+=$'\e['"$(( _PAL_BY + _PAL_ROWS + 4 ));${x}H${_PAL_SGR_BOX}└${hz}┘"$'\e[0m\e8'
    printf '%s' "$out"
}

# ── default providers (state-dependent commands, registered through the same API) ──
tui.cmd.provider _tui_cmd.provide_pages
tui.cmd.provider _tui_cmd.provide_themes
tui.cmd.provider _tui_cmd.provide_panes
tui.cmd.provider _tui_cmd.provide_groups

_tui_cmd.provide_pages() {
    local p title
    for p in "${!_TUI_PAGES[@]}"; do
        [[ "$_TUI_MARKUP_FILE" == "${_TUI_APP_DIR:-${_TUI_MARKUP_FILE%/*}}/$p" ]] && continue          # not the page you are on
        title="${_TUI_PAGES[$p]:-$p}"
        tui.cmd.add "goto:$p" "Go to: $title" "tui.action.goto $p" --group Pages --desc "Open $p"
    done
}

# every *.css in TUI_THEMES_DIR (default: <current page dir>/themes) is a selectable theme overlay
_tui_cmd.provide_themes() {
    local dir="${TUI_THEMES_DIR:-${_TUI_APP_DIR:-${_TUI_MARKUP_FILE%/*}}/themes}" f name cur mark
    [[ -d "$dir" ]] || return 0
    cur="${_TUI_THEME_OVERLAY:-}"
    tui.cmd.add theme:default "Theme: page default" "tui.theme.clear" --group Themes --desc "Remove the theme overlay"
    for f in "$dir"/*.css; do
        [[ -e "$f" ]] || continue
        name="${f##*/}"; name="${name%.css}"
        mark=""; [[ "$cur" == "$f" ]] && mark="  (active)"
        tui.cmd.add "theme:$name" "Theme: ${name^}$mark" "tui.theme.set $f" --group Themes --desc "Apply $name to every page"
    done
}

# jump keyboard focus to a named pane
_tui_cmd.provide_panes() {
    local p title
    _tui_input.nav_panes
    for p in "${_NAVP[@]}"; do
        title="${_TUI_P_TITLE[$p]:-$p}"
        tui.cmd.add "pane:$p" "Focus pane: $title" "tui.action.focus_pane $p" --group Panes --desc "Move keyboard focus to '$p'"
    done
}

# switch default keybind groups on/off
_tui_cmd.provide_groups() {
    local k g; local -A seen=()
    for k in "${!_TUI_BIND_DEF_GROUP[@]}"; do g="${_TUI_BIND_DEF_GROUP[$k]}"; seen[$g]=1; done
    for g in "${!seen[@]}"; do
        if [[ -n "${_TUI_DEF_OFF[$g]:-}" ]]; then
            tui.cmd.add "defaults:on:$g" "Default keys: turn '$g' group ON" "tui.defaults.on $g" --group Keybinds --desc "Re-enable the built-in '$g' keybinds"
        else
            tui.cmd.add "defaults:off:$g" "Default keys: turn '$g' group off" "tui.defaults.off $g" --group Keybinds --desc "Disable the built-in '$g' keybinds"
        fi
    done
}

# a few generic actions the default commands file points at
tui.action.reload_page() { [[ -n "$_TUI_MARKUP_FILE" ]] && tui.goto "$_TUI_MARKUP_FILE"; }
tui.action.redraw()      { tui.relayout; }

# DABT's own commands: data, like the default keybinds
tui.cmd.load "${TUI_DEFAULTS_DIR:-${SCRIPT_DIR:-.}/../config/default}/commands.xml" 2>/dev/null

# ── pages that ship with DABT (config/default/pages/) ────────────────────
# Settings and Keybinds pages every app gets through the palette ("DABT: Settings", "DABT: Keybinds"), so a
# developer need not build them. To use your own instead, re-register the same command id:
#     tui.cmd.add dabt.settings "Settings" "tui.action.goto my_settings.xml" --group App
tui.action.goto_default() { tui.goto "$TUI_DEFAULTS_DIR/pages/$1.xml"; }

# tui.action.back - return to the page you came from (the shipped pages have a Back button; bind it if you like)
tui.action.back() {
    local n=${#_TUI_PAGE_HISTORY[@]} f
    (( n )) || return 0
    f="${_TUI_PAGE_HISTORY[n-1]}"; unset "_TUI_PAGE_HISTORY[n-1]"
    _TUI_PAGE_HISTORY=("${_TUI_PAGE_HISTORY[@]}")
    _TUI_GOING_BACK=1; tui.goto "$f"; _TUI_GOING_BACK=""
}
_tui_cmd.has_history() { (( ${#_TUI_PAGE_HISTORY[@]} )); }
