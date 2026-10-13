#!/usr/bin/env bash
# docu_callbacks.sh - builds the documentation page's document list dynamically
# from whatever .md files actually exist (README, docs/README.md, docs/guide/, docs/api/reference.md, docs/design/),
# instead of a hand-maintained list that goes stale every time a doc is
# added, renamed, or removed. Driven by <tui on_visit="on_docu_visit">
# in docu.xml, which fires once the page's panes/widgets are built. The documents are drawn by the Markdown renderer.
tui.require terminal_renderer

_DOCU_ROOT="$TUI_ROOT"
declare -ga _DOCU_FILES=()

# Short list label for a markdown file: the part of its first H1 heading
# before a colon (most of these docs are titled "Title: Subtitle"),
# capped to a sane length. README gets a fixed label instead of parsing
# its heading, which starts with an emoji and a trailing <br/>.
_docu_short_title_v() {
	local file="$1" base="${1##*/}" heading
	base="${base%.md}"
	if [[ "${base,,}" == "readme" ]]; then
		[[ "$file" == */docs/README.md ]] && _DOCU_T='Docs index' || _DOCU_T='README'
		return
	fi
	# the first "# " line (front matter or a badge row may come before it); the file name when there is none
	heading=""
	local line n=0
	while IFS= read -r line && ((n++ < 30)); do
		[[ "$line" == "# "* ]] && {
			heading="${line#\# }"
			break
		}
	done <"$file"
	if [[ -z "$heading" ]]; then
		heading="${base//[_-]/ }"
	fi
	heading="${heading%%:*}"
	_DOCU_T="${heading:0:22}"
}
_docu_short_title() {
	_docu_short_title_v "$1"
	printf '%s' "$_DOCU_T"
}

on_docu_visit() {
	local -a files=()
	[[ -f "$_DOCU_ROOT/README.md" ]] && files+=("$_DOCU_ROOT/README.md")
	local f
	for f in "$_DOCU_ROOT/docs/README.md" "$_DOCU_ROOT/docs/guide"/*.md "$_DOCU_ROOT/docs/api/reference.md" "$_DOCU_ROOT/docs/design"/*.md; do
		[[ -f "$f" ]] && files+=("$f")
	done

	if ((${#files[@]} == 0)); then
		tui.capture _DOCU_T alert_string error "No documentation files found under docs/."
		tui.output "content" "$_DOCU_T"
		return
	fi

	# one list row per document; a title that collides after truncation falls back to the file name
	_DOCU_FILES=("${files[@]}")
	local -a titles=()
	local -A seen_titles=()
	local i title base
	for i in "${!files[@]}"; do
		_docu_short_title_v "${files[$i]}"
		title="$_DOCU_T"
		if [[ -n "${seen_titles[$title]:-}" ]]; then
			base="${files[$i]##*/}"
			base="${base%.md}"
			base="${base//[_-]/ }"
			title="${base:0:22}"
		fi
		seen_titles[$title]=1
		titles+=("$title")
	done
	tui.list.set "lst_docs" "${titles[@]}"
	tui.list.select "lst_docs" 0
	tui.focus "lst_docs"
	tui.md.keys content reader # plain reading keys (n N b / o z y ...) while the pane has the keyboard; alt chords always
	tui.md.on_navigate docu_navigated
	load_document "${files[0]}"
}

# docu_navigated FILE PANE - a followed link loaded another document: show it in the list and the title
docu_navigated() {
	local i
	for i in "${!_DOCU_FILES[@]}"; do
		if [[ "${_DOCU_FILES[i]}" == "$1" ]]; then
			tui.list.select "lst_docs" "$i"
			break
		fi
	done
	tui.pane_title "content" "${1##*/}"
}

# on_docu_open ID - Enter / double-click on a document: load it now
on_docu_open() {
	local i
	tui.list.selected "$1" i
	((i >= 0)) && load_document "${_DOCU_FILES[i]}"
}

# on_docu_moved ID - the selection moved: load the document once the arrow keys pause
on_docu_moved() { tui.after 0.15 on_docu_open docu_debounce_lst_docs; }

# load_document FILE - renders the Markdown file into the content pane (re-fitted when the pane is resized)
load_document() {
	local doc_path="$1" part
	if [[ -f "$doc_path" ]]; then
		tui.md.show_file "content" "$doc_path"
	else
		tui.md.forget "content"
		tui.capture part alert_string error "Document not found at: $doc_path"
		tui.output "content" "$part"
	fi
	tui.pane_title "content" "${doc_path##*/}"
}
