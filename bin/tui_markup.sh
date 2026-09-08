#!/usr/bin/env bash
# tui_markup.sh — declarative HTML/XML-like config loader for tui.sh
#
# Pure bash + POSIX utilities only (no python/perl/xmlstarlet/jq).
# Format restriction: one tag per line, attributes as name="value".
#
# Tags:
#   <tui>                                     root wrapper (ignored)
#   <script src="callbacks.sh"/>              source a bash callback file
#   <theme src="theme.css"/>                  load a CSS-like stylesheet (see tui_style.sh)
#   <include src="fragment.xml"/>             inline another markup file (fragments/shared nav)
#   <pane id="x" split="h|v" weight="N" title="…" border="…" align="left|center|right|fill"
#         valign="top|middle|bottom" min_width="N" min_height="N" max_width="N" max_height="N"
#         class="name">   layout node
#   <label  id="x" pane="p" row="N" text="…" align="…" valign="…" min_width="N" max_width="N" class="name"/>
#   <input  id="x" pane="p" row="N" label="…" placeholder="…" submit="fn" align="…" valign="…"
#           min_width="N" max_width="N" label_align="left|center|right" label_width="N" class="name"/>
#   <button id="x" pane="p" row="N" text="…" action="fn" align="…" valign="…" min_width="N" max_width="N" class="name"/>
#   <button id="x" pane="p" row="N" text="…" page="other.xml"/>  navigate to another page
#
# `align`/`valign` on a <pane> set the default for widgets inside it; the same
# attributes on a widget override that default for just that widget (buttons
# center horizontally by default, everything else is left/top). `align="fill"`
# paints the whole row with the element's fg/bg instead of just the text.
#
# `class` applies a named style from a loaded <theme> stylesheet — see
# bin/tui_style.sh and config/theme.css.
#
# `text="…"`/`label="…"` on label/button support ${command args…} runtime
# expressions (see _tui._resolve_text in tui.sh); call tui.redraw to refresh
# them on demand.
#
# `min_width`/`min_height` (panes) and `min_width` (widgets) show a
# "min space = …" warning in place of normal content when the available space
# is smaller than declared. `max_width`/`max_height` cap how large an element
# is allowed to grow.
#
# Multi-page TUIs: each file is a self-contained page (its own <tui>…</tui>).
# tui.goto "path/to/page.xml" clears the current UI and loads a new page,
# so buttons can link between files like anchors between HTML pages.

declare -gA _TUI_MARKUP_SEEN=()
declare -gA _TUI_MARKUP_PENDING=()
declare -gA _TUI_MARKUP_TITLE=()
declare -gA _TUI_MARKUP_BORDER=()
declare -g  _TUI_MARKUP_DIR=""

_markup_attr() {
    local line="$1" name="$2"
    [[ "$line" =~ $name[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}"
}

_markup_tagname() {
    local line="$1"
    [[ "$line" =~ ^\<(/?)([a-zA-Z_][a-zA-Z0-9_-]*) ]] && printf '%s' "${BASH_REMATCH[2]}"
}

_markup_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Recursively resolves <include src="…"/> tags, printing the expanded line stream.
_markup_expand() {
    local file="$1"
    local dir base key
    dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || { echo "tui.load: cannot resolve '$file'" >&2; return 1; }
    base="$(basename "$file")"
    key="${dir}/${base}"

    if [[ -n "${_TUI_MARKUP_SEEN[$key]:-}" ]]; then
        echo "tui.load: include cycle detected at '$key'" >&2
        return 0
    fi
    _TUI_MARKUP_SEEN[$key]=1

    local raw_line trimmed src resolved
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        trimmed="$(_markup_trim "$raw_line")"
        if [[ "$trimmed" == \<include* ]]; then
            src="$(_markup_attr "$trimmed" src)"
            if [[ -n "$src" ]]; then
                resolved="$src"
                [[ "$resolved" != /* ]] && resolved="${dir}/${src}"
                _markup_expand "$resolved"
            fi
            continue
        fi
        printf '%s\n' "$raw_line"
    done < "$key"
}

# tui.load FILE — parse a markup file and build panes/widgets via tui.* calls.
tui.load() {
    local file="$1"
    [[ -r "$file" ]] || { echo "tui.load: cannot read '$file'" >&2; return 1; }

    _TUI_MARKUP_SEEN=()
    _TUI_MARKUP_PENDING=()
    _TUI_MARKUP_TITLE=()
    _TUI_MARKUP_BORDER=()
    _TUI_MARKUP_DIR="$(cd "$(dirname "$file")" && pwd)"

    local -a stack_id=() stack_dir=()
    local raw_line line tag closing selfclose

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        line="$(_markup_trim "$raw_line")"
        [[ -z "$line" ]] && continue
        [[ "$line" == \<!--* ]] && continue

        closing=0; selfclose=0
        [[ "$line" == \</* ]] && closing=1
        [[ "$line" == *"/>" ]] && selfclose=1

        tag="$(_markup_tagname "$line")"
        [[ -z "$tag" ]] && continue

        case "$tag" in
            tui) continue ;;

            script)
                local src resolved
                src="$(_markup_attr "$line" src)"
                [[ -z "$src" ]] && continue
                resolved="$src"
                [[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR}/${src}"
                # shellcheck disable=SC1090
                source "$resolved"
                ;;

            theme)
                local tsrc tresolved
                tsrc="$(_markup_attr "$line" src)"
                [[ -z "$tsrc" ]] && continue
                tresolved="$tsrc"
                [[ "$tresolved" != /* ]] && tresolved="${_TUI_MARKUP_DIR}/${tsrc}"
                tui.load_theme "$tresolved"
                ;;

            pane)
                if (( closing )); then
                    local n=${#stack_id[@]}
                    (( n == 0 )) && continue
                    local id="${stack_id[$((n-1))]}" dirn="${stack_dir[$((n-1))]}"
                    unset 'stack_id[n-1]' 'stack_dir[n-1]'

                    if [[ -n "${_TUI_MARKUP_PENDING[$id]:-}" ]]; then
                        if [[ "$dirn" == "v" ]]; then
                            tui.vsplit "$id" ${_TUI_MARKUP_PENDING[$id]}
                        else
                            tui.hsplit "$id" ${_TUI_MARKUP_PENDING[$id]}
                        fi
                        unset '_TUI_MARKUP_PENDING[$id]'
                    fi
                    continue
                fi

                local id split weight title border align valign minw minh maxw maxh class
                id="$(_markup_attr "$line" id)"
                split="$(_markup_attr "$line" split)"
                weight="$(_markup_attr "$line" weight)"
                title="$(_markup_attr "$line" title)"
                border="$(_markup_attr "$line" border)"
                align="$(_markup_attr "$line" align)"
                valign="$(_markup_attr "$line" valign)"
                minw="$(_markup_attr "$line" min_width)"
                minh="$(_markup_attr "$line" min_height)"
                maxw="$(_markup_attr "$line" max_width)"
                maxh="$(_markup_attr "$line" max_height)"
                class="$(_markup_attr "$line" class)"

                if [[ -n "$id" && "$id" != "root" ]]; then
                    local n=${#stack_id[@]}
                    if (( n > 0 )); then
                        local parent="${stack_id[$((n-1))]}"
                        _TUI_MARKUP_PENDING[$parent]="${_TUI_MARKUP_PENDING[$parent]:+${_TUI_MARKUP_PENDING[$parent]} }${id}:${weight:-1}"
                    fi
                fi

                # tui.hsplit/vsplit reset child title/border to defaults, so these are applied afterwards.
                [[ -n "$title" ]]  && _TUI_MARKUP_TITLE[$id]="$title"
                [[ -n "$border" ]] && _TUI_MARKUP_BORDER[$id]="$border"
                tui.pane_align "$id" "$align"
                tui.pane_valign "$id" "$valign"
                tui.pane_minsize "$id" "$minw" "$minh"
                tui.pane_maxsize "$id" "$maxw" "$maxh"
                tui.class "$id" "$class"

                if [[ -n "$split" && $selfclose -eq 0 ]]; then
                    stack_id+=("$id")
                    stack_dir+=("$split")
                fi
                ;;

            label)
                local lid="$(_markup_attr "$line" id)" lalign="$(_markup_attr "$line" align)"
                local lvalign="$(_markup_attr "$line" valign)" lminw="$(_markup_attr "$line" min_width)" lmaxw="$(_markup_attr "$line" max_width)"
                local lclass="$(_markup_attr "$line" class)"
                tui.label "$lid" "$(_markup_attr "$line" pane)" \
                    "$(_markup_attr "$line" row)" "$(_markup_attr "$line" text)"
                tui.align "$lid" "$lalign"
                tui.valign "$lid" "$lvalign"
                tui.minsize "$lid" "$lminw"
                tui.maxsize "$lid" "$lmaxw"
                tui.class "$lid" "$lclass"
                ;;

            input)
                local iid="$(_markup_attr "$line" id)" ialign="$(_markup_attr "$line" align)"
                local ivalign="$(_markup_attr "$line" valign)" iminw="$(_markup_attr "$line" min_width)" imaxw="$(_markup_attr "$line" max_width)"
                local ilalign="$(_markup_attr "$line" label_align)" ilwidth="$(_markup_attr "$line" label_width)"
                local iclass="$(_markup_attr "$line" class)"
                tui.input "$iid" "$(_markup_attr "$line" pane)" \
                    "$(_markup_attr "$line" row)" "$(_markup_attr "$line" placeholder)" \
                    "$(_markup_attr "$line" label)" "$(_markup_attr "$line" submit)"
                tui.align "$iid" "$ialign"
                tui.valign "$iid" "$ivalign"
                tui.minsize "$iid" "$iminw"
                tui.maxsize "$iid" "$imaxw"
                tui.label_align "$iid" "$ilalign"
                tui.label_width "$iid" "$ilwidth"
                tui.class "$iid" "$iclass"
                ;;

            button)
                local bid bpane brow btext baction bpage balign bvalign bminw bmaxw bclass
                bid="$(_markup_attr "$line" id)"
                bpane="$(_markup_attr "$line" pane)"
                brow="$(_markup_attr "$line" row)"
                btext="$(_markup_attr "$line" text)"
                baction="$(_markup_attr "$line" action)"
                bpage="$(_markup_attr "$line" page)"
                balign="$(_markup_attr "$line" align)"
                bvalign="$(_markup_attr "$line" valign)"
                bminw="$(_markup_attr "$line" min_width)"
                bmaxw="$(_markup_attr "$line" max_width)"
                bclass="$(_markup_attr "$line" class)"

                if [[ -n "$bpage" && -z "$baction" ]]; then
                    local fn="_tui_goto_${bid//[^A-Za-z0-9_]/_}"
                    eval "$(printf '%s() { tui.goto %q; }' "$fn" "$bpage")"
                    baction="$fn"
                fi

                tui.button "$bid" "$bpane" "$brow" "$btext" "$baction"
                tui.align "$bid" "$balign"
                tui.valign "$bid" "$bvalign"
                tui.minsize "$bid" "$bminw"
                tui.maxsize "$bid" "$bmaxw"
                tui.class "$bid" "$bclass"
                ;;
        esac
    done < <(_markup_expand "$file")

    local pid
    for pid in "${!_TUI_MARKUP_TITLE[@]}"; do
        tui.pane_title "$pid" "${_TUI_MARKUP_TITLE[$pid]}"
    done
    for pid in "${!_TUI_MARKUP_BORDER[@]}"; do
        tui.pane_border "$pid" "${_TUI_MARKUP_BORDER[$pid]}"
    done
}

# tui.reset_ui — wipe all panes/widgets and rebuild a full-screen root pane.
tui.reset_ui() {
    _TUI_P_ROW=(); _TUI_P_COL=(); _TUI_P_H=(); _TUI_P_W=()
    _TUI_P_DIR=(); _TUI_P_CHILDREN=(); _TUI_P_WEIGHTS=()
    _TUI_P_TITLE=(); _TUI_P_BORDER=(); _TUI_P_LEAVES=()
    _TUI_P_ALIGN=(); _TUI_P_VALIGN=()
    _TUI_P_MINW=(); _TUI_P_MINH=(); _TUI_P_MAXW=(); _TUI_P_MAXH=()
    _TUI_W_TYPE=(); _TUI_W_PANE=(); _TUI_W_ROW=(); _TUI_W_LABEL=()
    _TUI_W_VALUE=(); _TUI_W_ACTION=(); _TUI_W_SUBMIT=(); _TUI_W_PH=()
    _TUI_W_ALIGN=(); _TUI_W_VALIGN=(); _TUI_W_MINW=(); _TUI_W_MAXW=()
    _TUI_W_LABEL_ALIGN=(); _TUI_W_LABEL_WIDTH=()
    _TUI_W_ORDER=(); _TUI_FOCUSABLE=()
    _TUI_FOCUS_ID=""; _TUI_FOCUS_IDX=-1; _TUI_CURSOR=0
    _TUI_TICK_FN=""
    _TUI_MARKUP_PENDING=()
    _TUI_STYLE_FG=(); _TUI_STYLE_BG=(); _TUI_STYLE_MOD=()

    (( _EXEC_PID > 0 )) && _exec_cleanup_process

    term.size _TUI_ROWS _TUI_COLS
    _TUI_P_ROW[root]=1; _TUI_P_COL[root]=1
    _TUI_P_H[root]=$_TUI_ROWS; _TUI_P_W[root]=$_TUI_COLS
    _TUI_P_BORDER[root]="single"
    _TUI_P_TITLE[root]=""
    _TUI_P_LEAVES=(root)

    erase.all
}

# tui.goto FILE — navigate to another page, resolved relative to the current page's directory.
tui.goto() {
    local file="$1" resolved="$file"
    [[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR:-.}/${file}"

    tui.reset_ui
    tui.load "$resolved"
    (( _TUI_RUNNING )) && tui.render
}

# tui.start FILE — full lifecycle for a config-driven TUI: init, load, run, and
# guaranteed cleanup, so callers only need to hand over a markup file.
tui.start() {
    local file="$1"
    [[ -r "$file" ]] || { echo "tui.start: cannot read '$file'" >&2; return 1; }

    tui.init
    if ! tui.load "$file"; then
        _master_cleanup
        return 1
    fi
    tui.run
}
