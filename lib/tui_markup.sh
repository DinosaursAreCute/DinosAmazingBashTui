#!/usr/bin/env bash
# tui_markup.sh - declarative HTML/XML-like config loader for tui.sh
#
# Pure bash + POSIX utilities only (no python/perl/xmlstarlet/jq).
# Format restriction: one tag per line, attributes as name="value".
#
# Tags:
#   <tui>                                     root wrapper (ignored)
#   <script src="callbacks.sh"/>              source a bash callback file
#   <theme src="theme.css"/>                  load a CSS-like stylesheet (see tui_style.sh)
#   <include src="fragment.xml"/>             inline another markup file (fragments/shared nav)
#   split="fixed" size_w="N" size_h="N": children are exactly N x M cells (child attrs span="K", newline="true")
#   <pane id="x" split="h|v" weight="N" title="…" border="…" align="left|center|right|fill"
#         valign="top|middle|bottom" min_width="N" min_height="N" max_width="N" max_height="N"
#         class="name">   layout node
#   hpad="N" vpad="N" (pane + label/input/button/checkbox): blank cols/rows per side. Parent pane: gap to children;
#   leaf pane: shrinks widget/output area. border= on a parent pane frames its children; borders drop when too small.
#   <footer [items="@tui.action.quit|Quit;ctrl+s|Save"]/>   one-row key-hint bar on the LAST terminal row (see tui_footer.sh)
#   <bind key="q" action="fn [args]" [pane="p"] [scope="global"] [pass="true"] [always="true"] desc="…"/>   key/mouse binding, see tui_input.sh
#   <tui on_visit="fn" defaults="-quit,-scroll">   switch default keybind groups off for this page (share/defaults/keybinds.xml)
#   <label  id="x" pane="p" row="N" text="…" align="…" valign="…" min_width="N" max_width="N" class="name"/>
#   <input  id="x" pane="p" row="N" label="…" placeholder="…" submit="fn" align="…" valign="…"  retain_input_on_submit="true|false" sticky="true"
#           min_width="N" max_width="N" label_align="left|center|right" label_width="N" class="name"/>
#   <button id="x" pane="p" row="N" text="…" action="fn" align="…" valign="…" min_width="N" max_width="N" class="name"/>
#   <button id="x" pane="p" row="N" text="…" page="other.xml"/>  navigate to another page
#   <password id pane row placeholder label submit/>   <textarea id pane row placeholder rows value submit on_change/>
#   <list id pane row action rows items="a|b|c" on_change/>   <table id pane row action rows columns="H1|H2" data="a|b;c|d"/>
#   <select id pane row label action items="a|b|c" value on_change/>   <progress id pane row label value/>   (see docs/guide/widgets.md)
#
# `align`/`valign` on a <pane> set the default for widgets inside it; the same
# attributes on a widget override that default for just that widget (buttons
# center horizontally by default, everything else is left/top). `align="fill"`
# paints the whole row with the element's fg/bg instead of just the text.
#
# `class` applies a named style from a loaded <theme> stylesheet - see
# lib/tui_style.sh and config/theme.css. A `.class:hover { … }` rule is
# applied to a widget (button/input) while the mouse sits over it; it has
# no effect on panes. A pane's border instead uses the class's `.class:focus`
# rule while any widget inside it has keyboard focus (falling back to
# `.class:border` otherwise).
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
declare -g  _TUI_MARKUP_FILE=""
declare -g  _TUI_MARKUP_ON_VISIT=""
declare -g  _TUI_APP_DIR=""          # directory of the first page an app started with (themes/ lives there)

# split="grid" only: a grid pane's own rows/cols/fit/weight attributes,
# stashed at its open tag and consumed at its close tag once every child's
# grid_row/grid_col (also stashed via _TUI_MARKUP_PENDING, see the pane
# tag handler) is known. Kept as separate arrays rather than packed into
# one string because row_weights/col_weights are themselves space-separated
# lists.
declare -gA _TUI_MARKUP_FIXED_W=() _TUI_MARKUP_FIXED_H=()
declare -gA _TUI_MARKUP_GRID_ROWS=()
declare -gA _TUI_MARKUP_GRID_COLS=()
declare -gA _TUI_MARKUP_GRID_FIT=()
declare -gA _TUI_MARKUP_GRID_ROWW=()
declare -gA _TUI_MARKUP_GRID_COLW=()

# <tabs>...</tabs> collection state - mirrors the grid arrays above: a
# <tabs> tag stashes its own attributes and an ordered list of the <tab>
# children it collects until its closing tag, where
# _tui_markup_resolve_tabs hands everything to tui.tabs.add/tui.tabs.build.
declare -gA _TUI_MARKUP_TABS_HEADER=()   # tabs id -> header_pane
declare -gA _TUI_MARKUP_TABS_CONTENT=()  # tabs id -> content_pane
declare -gA _TUI_MARKUP_TABS_ORDER=()    # tabs id -> "tabid1 tabid2 ..."
declare -gA _TUI_MARKUP_TAB_TEXT=()      # tab id -> text
declare -gA _TUI_MARKUP_TAB_ACTION=()    # tab id -> action
declare -gA _TUI_MARKUP_TAB_DEFAULT=()   # tab id -> "true"/""
declare -g  _TUI_MARKUP_CURRENT_TABS=""

_markup_attr() {
    local line="$1" name="$2"
    if [[ "$line" =~ $name[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
        local v="${BASH_REMATCH[1]}"
        [[ "$v" == *"&"* ]] && { v="${v//&lt;/<}"; v="${v//&gt;/>}"; v="${v//&quot;/\"}"; v="${v//&amp;/\&}"; }   # XML entities
        printf '%s' "$v"
    fi
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

# _tui_markup_resolve_grid ID - called when a <pane split="grid"> closes.
# Reads that grid's stashed rows/cols/fit/weights and its children's
# pending "childid:row:col" entries ("-" standing in for "no override" on
# a loose child - see how the pane tag handler above builds these) and
# resolves explicit-vs-auto-flow placement into one flat, row-major name
# list before handing it to tui.grid, which only deals in already-resolved
# geometry:
#   1. Cells with both grid_row and grid_col given are reserved first; a
#      collision keeps the later child and warns.
#   2. Remaining ("loose") children fill the remaining empty cells in
#      document order.
#   3. Any children left over once every cell is full grow the grid with
#      additional rows rather than being dropped.
_tui_markup_resolve_grid() {
    local id="$1"
    local -a entries=()
    read -ra entries <<< "${_TUI_MARKUP_PENDING[$id]:-}"
    unset '_TUI_MARKUP_PENDING[$id]'

    local total=${#entries[@]}
    local rows="${_TUI_MARKUP_GRID_ROWS[$id]:-}"
    local cols="${_TUI_MARKUP_GRID_COLS[$id]:-}"
    local fit="${_TUI_MARKUP_GRID_FIT[$id]:-pack}"
    local roww="${_TUI_MARKUP_GRID_ROWW[$id]:-}"
    local colw="${_TUI_MARKUP_GRID_COLW[$id]:-}"
    unset '_TUI_MARKUP_GRID_ROWS[$id]' '_TUI_MARKUP_GRID_COLS[$id]' \
          '_TUI_MARKUP_GRID_FIT[$id]' '_TUI_MARKUP_GRID_ROWW[$id]' '_TUI_MARKUP_GRID_COLW[$id]'

    if (( total == 0 )); then
        tui.grid "$id" "${rows:-1}" "${cols:-1}" "$fit" "$roww" "$colw"
        return
    fi

    if [[ -z "$cols" && -z "$rows" ]]; then
        cols=$(_tui._ceil_sqrt "$total")
        rows=$(( (total + cols - 1) / cols ))
    elif [[ -z "$cols" ]]; then
        cols=$(( (total + rows - 1) / rows ))
    elif [[ -z "$rows" ]]; then
        rows=$(( (total + cols - 1) / cols ))
    fi
    (( rows < 1 )) && rows=1
    (( cols < 1 )) && cols=1

    local total_cells=$(( rows * cols ))
    local -a flat=()
    local i
    for (( i = 0; i < total_cells; i++ )); do flat[$i]=""; done

    local -a loose=()
    local entry cid gr gc
    for entry in "${entries[@]}"; do
        IFS=: read -r cid gr gc <<< "$entry"
        [[ "$gr" == "-" ]] && gr=""
        [[ "$gc" == "-" ]] && gc=""
        if [[ -n "$gr" && -n "$gc" ]]; then
            local ci=$(( gr * cols + gc ))
            if (( ci >= 0 && ci < total_cells )); then
                if [[ -n "${flat[$ci]}" ]]; then
                    echo "tui.load: grid '$id' cell (${gr},${gc}) already occupied by '${flat[$ci]}' - '$cid' overrides it" >&2
                fi
                flat[$ci]="$cid"
            else
                echo "tui.load: grid '$id' child '$cid' grid_row/grid_col out of bounds - treating as loose" >&2
                loose+=("$cid")
            fi
        else
            loose+=("$cid")
        fi
    done

    local li=0
    for (( i = 0; i < total_cells && li < ${#loose[@]}; i++ )); do
        if [[ -z "${flat[$i]}" ]]; then
            flat[$i]="${loose[$li]}"
            (( li++ ))
        fi
    done
    while (( li < ${#loose[@]} )); do
        (( rows++ ))
        local base=$(( (rows - 1) * cols )) c
        for (( c = 0; c < cols && li < ${#loose[@]}; c++ )); do
            flat[$(( base + c ))]="${loose[$li]}"
            (( li++ ))
        done
    done

    tui.grid "$id" "$rows" "$cols" "$fit" "$roww" "$colw" "${flat[@]}"
}

# _tui_markup_resolve_tabs TABS_ID - called when a <tabs> closes. Hands
# every <tab> child collected since the matching open tag to
# tui.tabs.add/tui.tabs.build, then clears this tabs group's scratch state.
_tui_markup_resolve_tabs() {
    local tabs_id="$1"
    local header_pane="${_TUI_MARKUP_TABS_HEADER[$tabs_id]:-}"
    local content_pane="${_TUI_MARKUP_TABS_CONTENT[$tabs_id]:-}"
    local -a tab_ids=()
    read -ra tab_ids <<< "${_TUI_MARKUP_TABS_ORDER[$tabs_id]:-}"

    local tid
    for tid in "${tab_ids[@]}"; do
        tui.tabs.add "$tid" "${_TUI_MARKUP_TAB_TEXT[$tid]:-}" "${_TUI_MARKUP_TAB_ACTION[$tid]:-}" "${_TUI_MARKUP_TAB_DEFAULT[$tid]:-}"
    done
    tui.tabs.build "$tabs_id" "$header_pane" "$content_pane" "${tab_ids[@]}"

    unset '_TUI_MARKUP_TABS_HEADER[$tabs_id]' '_TUI_MARKUP_TABS_CONTENT[$tabs_id]' '_TUI_MARKUP_TABS_ORDER[$tabs_id]'
    for tid in "${tab_ids[@]}"; do
        unset '_TUI_MARKUP_TAB_TEXT[$tid]' '_TUI_MARKUP_TAB_ACTION[$tid]' '_TUI_MARKUP_TAB_DEFAULT[$tid]'
    done
}

# tui.load FILE - parse a markup file and build panes/widgets via tui.* calls.
tui.load() {
    local file="$1"
    [[ -r "$file" ]] || { echo "tui.load: cannot read '$file'" >&2; return 1; }

    _TUI_MARKUP_SEEN=()
    _TUI_MARKUP_PENDING=()
    _TUI_MARKUP_TITLE=()
    _TUI_MARKUP_BORDER=()
    _TUI_MARKUP_CURRENT_TABS=""
    _TUI_MARKUP_ON_VISIT=""
    _tui_path_canon "$file"; _TUI_MARKUP_FILE="$_CANON"; _TUI_MARKUP_DIR="${_CANON%/*}"

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
            tui)
                (( closing )) && continue
                local visit; visit="$(_markup_attr "$line" on_visit)"
                [[ -n "$visit" ]] && _TUI_MARKUP_ON_VISIT="$visit"
                local ddef dg; local -a dgs=()
                ddef="$(_markup_attr "$line" defaults)"       # defaults="-quit,-scroll": groups off for this page
                if [[ -n "$ddef" ]]; then
                    IFS=',' read -ra dgs <<< "$ddef"
                    for dg in "${dgs[@]}"; do [[ "$dg" == -* ]] && tui.defaults.off --page "${dg#-}"; done
                fi
                continue
                ;;

            script)
                local src resolved
                src="$(_markup_attr "$line" src)"
                [[ -z "$src" ]] && continue
                resolved="$src"
                [[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR}/${src}"
                _tui_cache_source "$resolved"
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

                    if [[ "$dirn" == "grid" ]]; then
                        _tui_markup_resolve_grid "$id"
                    elif [[ "$dirn" == "fixed" ]]; then
                        tui.fixed "$id" "${_TUI_MARKUP_FIXED_W[$id]:-4}" "${_TUI_MARKUP_FIXED_H[$id]:-3}" ${_TUI_MARKUP_PENDING[$id]:-}
                        unset '_TUI_MARKUP_PENDING[$id]'
                    elif [[ -n "${_TUI_MARKUP_PENDING[$id]:-}" ]]; then
                        if [[ "$dirn" == "v" ]]; then
                            tui.vsplit "$id" ${_TUI_MARKUP_PENDING[$id]}
                        else
                            tui.hsplit "$id" ${_TUI_MARKUP_PENDING[$id]}
                        fi
                        unset '_TUI_MARKUP_PENDING[$id]'
                    fi
                    continue
                fi

                local id split weight title border align valign minw minh maxw maxh class scroll strictfit
                local rows cols fit roww colw gridrow gridcol
                local sizew sizeh span newline
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

                # Extract scroll attribute here
                scroll="$(_markup_attr "$line" scroll)"
                strictfit="$(_markup_attr "$line" strict_fit)"

                # split="grid" attributes (see _tui_markup_resolve_grid)
                rows="$(_markup_attr "$line" rows)"
                cols="$(_markup_attr "$line" cols)"
                fit="$(_markup_attr "$line" fit)"
                roww="$(_markup_attr "$line" row_weights)"
                colw="$(_markup_attr "$line" col_weights)"
                gridrow="$(_markup_attr "$line" grid_row)"
                gridcol="$(_markup_attr "$line" grid_col)"
                sizew="$(_markup_attr "$line" size_w)"
                sizeh="$(_markup_attr "$line" size_h)"
                span="$(_markup_attr "$line" span)"
                newline="$(_markup_attr "$line" newline)"

                if [[ -n "$id" && "$id" != "root" ]]; then
                    local n=${#stack_id[@]}
                    if (( n > 0 )); then
                        local parent="${stack_id[$((n-1))]}"
                        if [[ "${stack_dir[$((n-1))]}" == "grid" ]]; then
                            _TUI_MARKUP_PENDING[$parent]="${_TUI_MARKUP_PENDING[$parent]:+${_TUI_MARKUP_PENDING[$parent]} }${id}:${gridrow:--}:${gridcol:--}"
                        elif [[ "${stack_dir[$((n-1))]}" == "fixed" ]]; then
                            _TUI_MARKUP_PENDING[$parent]="${_TUI_MARKUP_PENDING[$parent]:+${_TUI_MARKUP_PENDING[$parent]} }${id}:${span:-1}:${newline:+1}"
                        else
                            _TUI_MARKUP_PENDING[$parent]="${_TUI_MARKUP_PENDING[$parent]:+${_TUI_MARKUP_PENDING[$parent]} }${id}:${weight:-1}"
                        fi
                    fi
                fi

                if [[ "$split" == "fixed" ]]; then
                    _TUI_MARKUP_FIXED_W[$id]="$sizew"
                    _TUI_MARKUP_FIXED_H[$id]="$sizeh"
                fi

                if [[ "$split" == "grid" ]]; then
                    _TUI_MARKUP_GRID_ROWS[$id]="$rows"
                    _TUI_MARKUP_GRID_COLS[$id]="$cols"
                    _TUI_MARKUP_GRID_FIT[$id]="${fit:-pack}"
                    _TUI_MARKUP_GRID_ROWW[$id]="$roww"
                    _TUI_MARKUP_GRID_COLW[$id]="$colw"
                fi

                # tui.hsplit/vsplit/tui.grid reset child title/border to defaults, so these are applied afterwards.
                [[ -n "$title" ]]  && _TUI_MARKUP_TITLE[$id]="$title"
                [[ -n "$border" ]] && _TUI_MARKUP_BORDER[$id]="$border"
                tui.pane_align "$id" "$align"
                tui.pane_valign "$id" "$valign"
                tui.pane_minsize "$id" "$minw" "$minh"
                tui.pane_maxsize "$id" "$maxw" "$maxh"
                tui.pane_pad "$id" "$(_markup_attr "$line" hpad)" "$(_markup_attr "$line" vpad)"
                tui.class "$id" "$class"

                # Apply the scroll attribute here
                tui.pane_scroll "$id" "$scroll"
                [[ -n "$strictfit" ]] && tui.pane_strict_fit "$id" "$strictfit"

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
                tui.pad "$lid" "$(_markup_attr "$line" hpad)" "$(_markup_attr "$line" vpad)"
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
                local iretain; iretain="$(_markup_attr "$line" retain_input_on_submit)"
                [[ -n "$iretain" ]] && tui.input.retain "$iid" "$iretain"
                [[ "$(_markup_attr "$line" sticky)" == true ]] && tui.input.sticky "$iid"
                tui.class "$iid" "$iclass"
                tui.pad "$iid" "$(_markup_attr "$line" hpad)" "$(_markup_attr "$line" vpad)"
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
                    _tui_cache_define_goto "$fn" "$bpage" "$btext"
                    baction="$fn"
                fi

                tui.button "$bid" "$bpane" "$brow" "$btext" "$baction"
                tui.align "$bid" "$balign"
                tui.valign "$bid" "$bvalign"
                tui.minsize "$bid" "$bminw"
                tui.maxsize "$bid" "$bmaxw"
                tui.class "$bid" "$bclass"
                tui.pad "$bid" "$(_markup_attr "$line" hpad)" "$(_markup_attr "$line" vpad)"
                ;;

            checkbox)
                local kid kpane krow klabel kchecked kaction kalign kvalign kminw kmaxw kclass
                kid="$(_markup_attr "$line" id)"
                kpane="$(_markup_attr "$line" pane)"
                krow="$(_markup_attr "$line" row)"
                klabel="$(_markup_attr "$line" label)"
                kchecked="$(_markup_attr "$line" checked)"
                kaction="$(_markup_attr "$line" action)"
                kalign="$(_markup_attr "$line" align)"
                kvalign="$(_markup_attr "$line" valign)"
                kminw="$(_markup_attr "$line" min_width)"
                kmaxw="$(_markup_attr "$line" max_width)"
                kclass="$(_markup_attr "$line" class)"

                tui.checkbox "$kid" "$kpane" "$krow" "$klabel" "$kchecked" "$kaction"
                tui.align "$kid" "$kalign"
                tui.valign "$kid" "$kvalign"
                tui.minsize "$kid" "$kminw"
                tui.maxsize "$kid" "$kmaxw"
                tui.class "$kid" "$kclass"
                tui.pad "$kid" "$(_markup_attr "$line" hpad)" "$(_markup_attr "$line" vpad)"
                ;;

            password|textarea|list|table|select|progress)
                _markup_wx "$tag" "$line" ;;

            footer)
                # <footer items="..."/> - page-level, not a pane: drawn on the last terminal row wherever it appears
                (( closing )) && continue
                tui.footer.set "$(_markup_attr "$line" items)"
                ;;

            bind)
                local bkey bact bpane_s bpass balways bdesc
                bkey="$(_markup_attr "$line" key)"
                bact="$(_markup_attr "$line" action)"
                bpane_s="$(_markup_attr "$line" pane)"
                bpass="$(_markup_attr "$line" pass)"
                balways="$(_markup_attr "$line" always)"
                bdesc="$(_markup_attr "$line" desc)"
                local bscope; bscope="$(_markup_attr "$line" scope)"
                local -a bflags=(--page)
                [[ "$bscope" == global ]] && bflags=()          # scope="global": survives page changes
                [[ -n "$bpane_s" ]] && bflags+=(--pane "$bpane_s")
                [[ "$bpass" == true ]] && bflags+=(--pass)
                [[ "$balways" == true ]] && bflags+=(--always)
                [[ -n "$bdesc" ]] && bflags+=(--desc "$bdesc")
                tui.bind "$bkey" "$bact" "${bflags[@]}"
                ;;

            tabs)
                if (( closing )); then
                    [[ -n "$_TUI_MARKUP_CURRENT_TABS" ]] && _tui_markup_resolve_tabs "$_TUI_MARKUP_CURRENT_TABS"
                    _TUI_MARKUP_CURRENT_TABS=""
                    continue
                fi
                local tabsid thp tcp tstyle
                tabsid="$(_markup_attr "$line" id)"
                thp="$(_markup_attr "$line" header_pane)"
                tcp="$(_markup_attr "$line" content_pane)"
                tstyle="$(_markup_attr "$line" style)"
                _TUI_MARKUP_TABS_HEADER[$tabsid]="$thp"
                _TUI_MARKUP_TABS_CONTENT[$tabsid]="$tcp"
                _TUI_MARKUP_TABS_ORDER[$tabsid]=""
                [[ "$tstyle" == "compact" ]] && tui.tabs.compact "$tabsid" true
                _TUI_MARKUP_CURRENT_TABS="$tabsid"
                ;;

            tab)
                local tabid tabtext tabaction tabdefault
                tabid="$(_markup_attr "$line" id)"
                tabtext="$(_markup_attr "$line" text)"
                tabaction="$(_markup_attr "$line" action)"
                tabdefault="$(_markup_attr "$line" default)"
                if [[ -z "$_TUI_MARKUP_CURRENT_TABS" ]]; then
                    echo "tui.load: <tab id=\"$tabid\"> outside a <tabs> block, skipping" >&2
                    continue
                fi
                _TUI_MARKUP_TABS_ORDER[$_TUI_MARKUP_CURRENT_TABS]="${_TUI_MARKUP_TABS_ORDER[$_TUI_MARKUP_CURRENT_TABS]:+${_TUI_MARKUP_TABS_ORDER[$_TUI_MARKUP_CURRENT_TABS]} }${tabid}"
                _TUI_MARKUP_TAB_TEXT[$tabid]="$tabtext"
                _TUI_MARKUP_TAB_ACTION[$tabid]="$tabaction"
                _TUI_MARKUP_TAB_DEFAULT[$tabid]="$tabdefault"
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
    _tui_cache_relayout

    # <tui on_visit="fn"> - runs once the page's panes/widgets are fully
    # built, so a page can, say, scan a directory and build dynamic tabs
    # (see config/docu_callbacks.sh) instead of needing every widget known
    # up front in the markup. Fires on every tui.load, including a
    # tui.goto back to a page already visited before.
    _tui_cache_run_on_visit "$_TUI_MARKUP_ON_VISIT"
}

# Recorded by tui.cache so a replayed page also re-lays out once borders/pads
# are final, before its on_visit runs.
_tui_cache_relayout() { _tui._root_h; _tui._layout root; }      # _root_h: leave the last row to a <footer/>

# tui.reset_ui - wipe all panes/widgets and rebuild a full-screen root pane.
tui.reset_ui() {
    local _pc
    for _pc in "${!_TUI_PANE_CONTENT[@]}"; do unset "_TUI_PANE_CONTENT_${_pc}"; done
    _TUI_PANE_CONTENT=()
    _TUI_P_ROW=(); _TUI_P_COL=(); _TUI_P_H=(); _TUI_P_W=()
    _TUI_P_DIR=(); _TUI_P_CHILDREN=(); _TUI_P_WEIGHTS=(); _TUI_P_CELLW=(); _TUI_P_CELLH=(); _TUI_P_SPAN=(); _TUI_P_NEWLINE=()
    _TUI_P_TITLE=(); _TUI_P_BORDER=(); _TUI_P_LEAVES=()
    _TUI_P_ALIGN=(); _TUI_P_VALIGN=(); _TUI_P_CONTENT=()
    _TUI_P_MINW=(); _TUI_P_MINH=(); _TUI_P_MAXW=(); _TUI_P_MAXH=()
    _TUI_P_STRICT_FIT=(); _TUI_P_EFFECTIVE_MINW=(); _TUI_P_EFFECTIVE_MINH=()
    _TUI_P_HPAD=(); _TUI_P_VPAD=(); _TUI_P_BORDER_EXPL=(); _TUI_W_HPAD=(); _TUI_W_VPAD=()
    _TUI_FACTORY_IDS=(); _TUI_FACTORY_GRID_PARENTS=(); _TUI_FACTORY_COUNTER=()
    _TUI_TABS_ACTIVE=(); _TUI_TABS_CONTENT_PANE=(); _TUI_TABS_COMPACT=(); _TUI_TAB_TEXT=()
    _TUI_TAB_ACTION=(); _TUI_TAB_DEFAULT=(); _TUI_TAB_GROUP=()
    _TUI_W_TYPE=(); _TUI_W_PANE=(); _TUI_W_ROW=(); _TUI_W_LABEL=()
    _TUI_W_VALUE=(); _TUI_W_ACTION=(); _TUI_W_SUBMIT=(); _TUI_W_PH=()
    _TUI_W_ALIGN=(); _TUI_W_VALIGN=(); _TUI_W_MINW=(); _TUI_W_MAXW=()
    _TUI_W_LABEL_ALIGN=(); _TUI_W_LABEL_WIDTH=(); _TUI_W_RETAIN=(); _TUI_W_STICKY=()
    _tui_wx.reset
    _TUI_W_ORDER=(); _TUI_FOCUSABLE=()
    _TUI_FOCUS_ID=""; _TUI_FOCUS_IDX=-1; _TUI_CURSOR=0
    _TUI_PANE_FOCUS=""; _TUI_PANE_LAST_WIDGET=()
    _TUI_HOVERED_PANE=""; _TUI_HOVERED_WIDGET=""
    _TUI_PENDING_OUTPUT=()
    _TUI_RENDER_TIMEOUT=-1
    _TUI_TICK_FN=""
    _TUI_ON_RESIZE_FN=""
    _TUI_ON_INPUT_EVENT=""
    _TUI_ON_KEY_EVENT=""
    _TUI_MARKUP_PENDING=()
    _TUI_STYLE_FG=(); _TUI_STYLE_BG=(); _TUI_STYLE_MOD=()

    _tui_api.shutdown 2>/dev/null
    _tui_input.clear_page
    _tui_modal.reset
    _tui_footer.reset
    _tui_dialog.reset
    (( _EXEC_PID > 0 )) && _exec_cleanup_process

    term.size _TUI_ROWS _TUI_COLS
    _TUI_P_ROW[root]=1; _TUI_P_COL[root]=1
    _TUI_P_H[root]=$_TUI_ROWS; _TUI_P_W[root]=$_TUI_COLS
    _TUI_P_BORDER[root]="single"
    _TUI_P_TITLE[root]=""
    _TUI_P_LEAVES=(root)

    erase.all
}

# tui.goto FILE - navigate to another page, resolved relative to the current page's directory.
# _tui_path_canon PATH -> _CANON: absolute, with . and .. folded - string operations only. (`cd "$(dirname ..)" && pwd`
# was 3 forks per tui.goto and per cache lookup.) Symlinks are not resolved, matching what `pwd` printed.
_tui_path_canon() {
    local p="$1" IFS=/ part; local -a out=() parts
    [[ "$p" != /* ]] && p="${PWD}/$p"
    read -ra parts <<< "$p"
    for part in "${parts[@]}"; do
        case "$part" in
            ""|.) ;;
            ..)   (( ${#out[@]} )) && unset 'out[-1]' ;;
            *)    out+=("$part") ;;
        esac
    done
    _CANON="/${out[*]}"
}

declare -ga _TUI_PAGE_HISTORY=()
declare -g  _TUI_GOING_BACK=""

tui.goto() {
    local file="$1" resolved
    resolved="$file"
    [[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR:-.}/${file}"

    # Reloading the SAME page (theme switch, tui.theme.reload) keeps the user where they were:
    # remember the focused widget + cursor and put focus back if that id exists again.
    local keep_id="" keep_cur=0 canon
    _tui_path_canon "$resolved"; canon="$_CANON"
    if [[ "$canon" == "${_TUI_MARKUP_FILE:-}" ]]; then keep_id="$_TUI_FOCUS_ID"; keep_cur=$_TUI_CURSOR; fi
    # page history for tui.action.back: remember where we came from (not on a same-page reload, not while going back)
    if [[ "$canon" != "${_TUI_MARKUP_FILE:-}" && -n "${_TUI_MARKUP_FILE:-}" && -z "$_TUI_GOING_BACK" ]]; then
        _TUI_PAGE_HISTORY+=("$_TUI_MARKUP_FILE")
        (( ${#_TUI_PAGE_HISTORY[@]} > 30 )) && _TUI_PAGE_HISTORY=("${_TUI_PAGE_HISTORY[@]:1}")
    fi

    # One synchronized frame: the terminal never shows the cleared, half-built page.
    (( _TUI_RUNNING )) && mode.sync_start
    tui.reset_ui
    tui.load_cached "$resolved"
    if [[ -n "$keep_id" && -n "${_TUI_W_TYPE[$keep_id]:-}" ]]; then
        local i
        for (( i = 0; i < ${#_TUI_FOCUSABLE[@]}; i++ )); do
            [[ "${_TUI_FOCUSABLE[$i]}" == "$keep_id" ]] && { _TUI_FOCUS_ID="$keep_id"; _TUI_FOCUS_IDX=$i; _TUI_CURSOR=$keep_cur; break; }
        done
    fi
    if (( _TUI_RUNNING )); then tui.render; mode.sync_end; fi
    tui.hook.fire page "$resolved"
}

# tui.start FILE - full lifecycle for a config-driven TUI: init, load, run, and
# guaranteed cleanup, so callers only need to hand over a markup file.
tui.start() {
    local file="$1"
    _TUI_APP_DIR="$(cd "$(dirname "$file")" 2>/dev/null && pwd)"
    [[ -z "${TUI_THEMES_DIR:-}" && -d "$_TUI_APP_DIR/themes" ]] && TUI_THEMES_DIR="$_TUI_APP_DIR/themes"
    [[ -r "$file" ]] || { echo "tui.start: cannot read '$file'" >&2; return 1; }

    tui.init
    if ! tui.load "$file"; then
        _master_cleanup
        return 1
    fi
    tui.run
}
