#!/usr/bin/env bash
# docu_callbacks.sh - builds the documentation page's tabs dynamically
# from whatever .md files actually exist (README, docs/README.md, docs/guide/, docs/api/reference.md, docs/design/),
# instead of a hand-maintained list that goes stale every time a doc is
# added, renamed, or removed. Driven by <tui on_visit="on_docu_visit">
# in docu.xml, which fires once the page's panes/widgets are built.
tui.require terminal_renderer

_DOCU_ROOT="$TUI_ROOT"
declare -gA _DOCU_TAB_FILE=()
declare -gA _DOCU_TAB_TITLE=()

# Short tab label for a markdown file: the part of its first H1 heading
# before a colon (most of these docs are titled "Title: Subtitle"),
# capped to a sane length. README gets a fixed label instead of parsing
# its heading, which starts with an emoji and a trailing <br/>.
_docu_short_title() {
    local file="$1"
    local base; base="$(basename "$file" .md)"
    if [[ "${base,,}" == "readme" ]]; then
        [[ "$file" == */docs/README.md ]] && printf 'Docs index' || printf 'README'
        return
    fi
    local heading; heading="$(head -1 "$file")"
    heading="${heading#\# }"
    heading="${heading%%:*}"
    printf '%s' "${heading:0:16}"
}

# Banner text for a doc: the full part of its first H1 heading before a
# colon, unlike _docu_short_title above this is not capped to tab-label
# length - the banner has the width of the whole content pane to work
# with, not a narrow tab strip.
_docu_banner_title() {
    local file="$1"
    local base; base="$(basename "$file" .md)"
    if [[ "${base,,}" == "readme" ]]; then
        [[ "$file" == */docs/README.md ]] && printf 'Docs index' || printf 'README'
        return
    fi
    local heading; heading="$(head -1 "$file")"
    heading="${heading#\# }"
    heading="${heading%%:*}"
    printf '%s' "$heading"
}

on_docu_visit() {
    _DOCU_TAB_FILE=()
    _DOCU_TAB_TITLE=()

    local -a files=()
    [[ -f "$_DOCU_ROOT/README.md" ]] && files+=("$_DOCU_ROOT/README.md")
    local f
    for f in "$_DOCU_ROOT/docs/README.md" "$_DOCU_ROOT/docs/guide"/*.md "$_DOCU_ROOT/docs/api/reference.md" "$_DOCU_ROOT/docs/design"/*.md; do
        [[ -f "$f" ]] && files+=("$f")
    done

    if (( ${#files[@]} == 0 )); then
        tui.output "content" "$(alert_string error "No documentation files found under docs/.")"
        return
    fi

    local -a tab_ids=()
    local -A seen_titles=()
    local i tab_id title is_default base
    for i in "${!files[@]}"; do
        tab_id="doc_tab_${i}"
        title="$(_docu_short_title "${files[$i]}")"
        if [[ -n "${seen_titles[$title]:-}" ]]; then
            # Two docs' headings collided after truncation (e.g. two
            # "Developer Guide: ..." titles) - fall back to the filename
            # to keep tabs distinguishable, since a repeated label is
            # confusing no matter how well it clips.
            base="$(basename "${files[$i]}" .md)"
            base="${base//[_-]/ }"
            title="${base:0:16}"
        fi
        seen_titles[$title]=1
        _DOCU_TAB_FILE[$tab_id]="${files[$i]}"
        _DOCU_TAB_TITLE[$tab_id]="$title"
        is_default=""
        (( i == 0 )) && is_default="true"
        tui.tabs.add "$tab_id" "$title" on_docu_tab_activate "$is_default"
        tab_ids+=("$tab_id")
    done

    # Compact: tabs_header is a thin (weight="4") strip, only 1 row tall
    # at most terminal sizes - nowhere near the 3 rows a framed (bordered)
    # header cell needs.
    tui.tabs.compact "docu_tabs" true
    tui.tabs.build "docu_tabs" "tabs_header" "content" "${tab_ids[@]}"
}

on_docu_tab_activate() {
    local tab_id="$1"
    load_document "${_DOCU_TAB_FILE[$tab_id]}"
}

load_document() {
    local doc_path="$1"
    local raw_doc=""

    raw_doc+="\n$(banner_string "$(_docu_banner_title "$doc_path")")\n\n"

    if [[ -f "$doc_path" ]]; then
        raw_doc+="$(cat "$doc_path")\n"
    else
        raw_doc+="$(alert_string error "Document not found at: $doc_path")\n"
    fi

    local formatted_doc="$(printf '%b' "$raw_doc")"
    tui.output "content" "$formatted_doc"
    tui.pane_title "content" "$(basename "$doc_path")"
}
