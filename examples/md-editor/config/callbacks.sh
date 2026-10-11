#!/usr/bin/env bash
# callbacks.sh - the behaviour of editor.xml and static.xml. Only public tui.* calls.

tui.md.fonts on # # and ## headings in block letters (alt+f toggles)

declare -g MD_STYLING=on  # source styling: on = rendered while typing, off = plain text
declare -g MD_PREVIEW=off # split preview, kept across the editor <-> static document switch
declare -g MD_PAGE=editor # editor | static: the page on screen
declare -gi MD_SEEDED=0   # the editor text is loaded once; keep_value brings it back after a page switch

# _md_preview - re-renders the whole document into the preview pane
_md_preview() {
	local text
	tui.get ta_src text
	tui.md.show view "$text"
}

# _md_bind_keys - the same shortcuts on both pages
_md_bind_keys() {
	tui.bind alt+m md_toggle_styling --always --desc "Source rendered / plain"
	tui.bind alt+p md_toggle_preview --always --desc "Split preview on/off"
	tui.bind alt+f md_toggle_fonts --always --desc "Heading block fonts on/off"
	tui.bind alt+b md_toggle_breaks --always --desc "Literal line breaks on/off"
	tui.bind alt+o md_toggle_static --always --desc "Open / close the static document"
	tui.bind esc md_leave_static --pass --desc "Back to the editor"
}

md_visit() {
	MD_PAGE=editor
	local f=${MD_EDITOR_FILE:-$MD_APP_DIR/scratch.md} text=""
	if ((! MD_SEEDED)); then
		[[ -r "$f" ]] && text=$(<"$f")
		tui.update ta_src "$text"
		MD_SEEDED=1
	fi
	_md_bind_keys
	[[ "$MD_PREVIEW" == on ]] && _md_preview || tui.collapse view on
	tui.focus ta_src
}

md_static_visit() {
	MD_PAGE=static
	_md_bind_keys
	tui.md.show_file doc "${MD_STATIC_FILE:-$MD_APP_DIR/static.md}"
}

# md_changed ID - every edit; the preview waits until typing pauses (the field itself repaints at once)
md_changed() { tui.after 0.12 _md_preview md_debounce; }

md_toggle_styling() {
	if [[ "$MD_STYLING" == on ]]; then
		MD_STYLING=off
		tui.text.mode ta_src plain
	else
		MD_STYLING=on
		tui.text.mode ta_src markdown
	fi
	tui.notify "Source: $([[ $MD_STYLING == on ]] && echo rendered || echo plain)" info 1
}

md_toggle_preview() {
	[[ "$MD_PREVIEW" == on ]] && MD_PREVIEW=off || MD_PREVIEW=on
	[[ "$MD_PAGE" == editor ]] || return 0
	tui.collapse view toggle
	_md_preview
}

# _md_rerender - re-renders what is on screen after a rendering setting changed
_md_rerender() {
	if [[ "$MD_PAGE" == editor ]]; then _md_preview; else tui.md.show_file doc "${MD_STATIC_FILE:-$MD_APP_DIR/static.md}"; fi
}

md_toggle_fonts() {
	tui.md.fonts toggle
	tui.notify "Heading fonts: $([[ $TUI_MD_FONTS == 1 ]] && echo on || echo off)" info 1
	_md_rerender
}

# md_toggle_breaks - every newline breaks the line (on) or joins it to the next (off); re-renders what is on screen
md_toggle_breaks() {
	tui.md.breaks toggle
	tui.notify "Line breaks: $([[ $TUI_MD_BREAKS == 1 ]] && echo literal || echo joined)" info 1
	_md_rerender
}

md_toggle_static() {
	if [[ "$MD_PAGE" == editor ]]; then tui.goto "$MD_APP_DIR/config/static.xml"; else tui.goto "$MD_APP_DIR/config/editor.xml"; fi
}

md_leave_static() { [[ "$MD_PAGE" == static ]] && tui.goto "$MD_APP_DIR/config/editor.xml"; }
