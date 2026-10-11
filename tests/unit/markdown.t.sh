# Markdown renderer (lib/markdown/tui_markdown.sh): one behaviour per test, rows compared with the SGR stripped.
# Glyphs: bullet "•" "◦" "▪", quote bar "│", rule "─", clip marker "›" (each is one cell wide).

R=$'\e[0m'

# _md_flat TEXT WIDTH -> _F : rendered rows with SGR stripped, joined by "|"
_md_flat() {
	tui.md.render "$1" "$2"
	local r s out="" n=0
	for r in "${TUI_MD_ROWS[@]}"; do
		tui.md.strip "$r" s
		((n++)) && out+="|"
		out+="$s"
	done
	_F="$out"
}

# _md_sflat TEXT -> _F : styled rows with SGR stripped, joined by "|"
_md_sflat() {
	tui.md.style "$1"
	local r s out="" n=0
	for r in "${TUI_MD_ROWS[@]}"; do
		tui.md.strip "$r" s
		((n++)) && out+="|"
		out+="$s"
	done
	_F="$out"
}

# _md_vw STRING -> _W : visible cells (multi-byte glyphs of the renderer count as one under LC_ALL=C)
_md_vw() {
	local s
	tui.md.strip "$1" s
	s=${s//•/x} s=${s//◦/x} s=${s//▪/x} s=${s//│/x} s=${s//─/x} s=${s//›/x}
	_W=${#s}
}

# ── headings ──────────────────────────────────────────────────────────

t_md_heading_hides_marker_and_keeps_text() {
	_md_flat "# Title" 40
	eq "Title" "$_F"
}

t_md_heading_levels_use_their_own_class() {
	tui.md.render "# a" 40
	eq "${_TUI_MD_SGR[h1]}a${R}" "${TUI_MD_ROWS[0]}"
	tui.md.render "###### a" 40
	eq "${_TUI_MD_SGR[h6]}a${R}" "${TUI_MD_ROWS[0]}"
}

t_md_seven_hashes_is_a_paragraph() {
	_md_flat "####### x" 40
	eq "####### x" "$_F"
}

t_md_hash_without_space_is_a_paragraph() {
	_md_flat "#tag" 40
	eq "#tag" "$_F"
}

t_md_closing_hashes_are_dropped() {
	_md_flat "## Title ##" 40
	eq "Title" "$_F"
}

t_md_heading_interrupts_paragraph_with_gaps() {
	_md_flat $'a\n# H\nb' 40
	eq "a||H||b" "$_F"
}

t_md_heading_inline_markup_restores_heading_style() {
	tui.md.render "# a **b** c" 40
	eq "${_TUI_MD_SGR[h1]}a ${_TUI_MD_SGR[strong]}b${R}${_TUI_MD_SGR[h1]} c${R}" "${TUI_MD_ROWS[0]}"
}

# ── paragraphs and wrapping ───────────────────────────────────────────

t_md_paragraph_wraps_at_word_boundaries() {
	_md_flat "aaa bbb ccc" 7
	eq "aaa bbb|ccc" "$_F"
}

t_md_long_word_is_hard_split() {
	_md_flat "abcdefghij" 4
	eq "abcd|efgh|ij" "$_F"
}

t_md_soft_break_joins_lines_with_a_space() {
	_md_flat $'a\nb' 40
	eq "a b" "$_F"
}

t_md_blank_line_separates_paragraphs() {
	_md_flat $'a\n\nb' 40
	eq "a||b" "$_F"
}

t_md_two_trailing_spaces_make_a_hard_break() {
	_md_flat $'a  \nb' 40
	eq "a|b" "$_F"
}

t_md_trailing_backslash_makes_a_hard_break() {
	_md_flat $'a\\\nb' 40
	eq "a|b" "$_F"
}

t_md_repeated_spaces_collapse() {
	_md_flat "a    b" 40
	eq "a b" "$_F"
}

t_md_width_zero_behaves_as_one() {
	_md_flat "ab" 0
	eq "a|b" "$_F"
}

t_md_empty_input_has_no_rows() {
	tui.md.render "" 40
	eq 0 "${#TUI_MD_ROWS[@]}"
}

# ── literal line breaks (runtime setting) ─────────────────────────────

t_md_breaks_are_soft_by_default() {
	_md_flat $'a\nb' 40
	eq "a b" "$_F"
}

t_md_breaks_on_counts_every_newline() {
	tui.md.breaks on
	_md_flat $'a\nb\nc' 40
	eq "a|b|c" "$_F"
}

t_md_breaks_on_keeps_paragraph_gaps() {
	tui.md.breaks on
	_md_flat $'a\nb\n\nc' 40
	eq "a|b||c" "$_F"
}

t_md_breaks_on_applies_inside_list_items_and_quotes() {
	tui.md.breaks on
	_md_flat $'- a\n  b' 40
	eq "• a|  b" "$_F"
	_md_flat $'> a\n> b' 40
	eq "│ a|│ b" "$_F"
}

t_md_breaks_off_restores_soft_breaks() {
	tui.md.breaks on
	tui.md.breaks off
	_md_flat $'a\nb' 40
	eq "a b" "$_F"
}

t_md_breaks_toggle_flips_the_setting() {
	tui.md.breaks toggle
	eq 1 "$TUI_MD_BREAKS"
	tui.md.breaks toggle
	eq 0 "$TUI_MD_BREAKS"
}

t_md_breaks_on_does_not_split_a_wrapped_line_early() {
	tui.md.breaks on
	_md_flat $'aaa bbb ccc\nd' 7
	eq "aaa bbb|ccc|d" "$_F"
}

# ── heading fonts (block letters from the banner renderer) ───────────

# _md_banner TEXT FONT -> _B : the banner rows joined by "|" (backslash doubling undone), the expected block of a heading
_md_banner() {
	declare -F _banner_build >/dev/null || tui.require terminal_renderer
	_banner_build "$1" "$2"
	local r out="" n=0
	for r in "${TR_RESULT[@]}"; do
		((n++)) && out+="|"
		out+="${r//\\\\/\\}"
	done
	_B=$out
}

t_md_heading_fonts_are_off_by_default() {
	_md_flat "# Hi" 40
	eq "Hi" "$_F"
}

t_md_h1_uses_the_block5_font() {
	tui.md.fonts on
	_md_flat "# Hi" 80
	_md_banner "Hi" block5
	eq "$_B" "$_F"
}

t_md_h2_uses_the_box3_font() {
	tui.md.fonts on
	_md_flat "## Hi" 80
	_md_banner "Hi" box3
	eq "$_B" "$_F"
}

t_md_other_heading_levels_stay_plain() {
	tui.md.fonts on
	_md_flat "### Hi" 80
	eq "Hi" "$_F"
}

t_md_heading_font_rows_use_the_heading_style_and_the_heading_line() {
	tui.md.fonts on
	tui.md.render $'para\n\n## Hi' 80
	eq 5 "${#TUI_MD_ROWS[@]}"
	[[ "${TUI_MD_ROWS[2]}" == "${_TUI_MD_SGR[h2]}"* && "${TUI_MD_ROWS[2]}" == *"$R" ]] || _t_fail "row 2: ${TUI_MD_ROWS[2]}"
	eq "1 2 3 3 3" "${TUI_MD_MAP[*]}"
}

t_md_heading_font_rows_have_no_underline() {
	tui.md.fonts on
	tui.md.render "# Hi" 80
	[[ "${TUI_MD_ROWS[0]}" == $'\e['* ]] || _t_fail "row has no style"
	local seq=${TUI_MD_ROWS[0]%%m*}
	[[ ";${seq#$'\e['};" != *";4;"* ]] || _t_fail "underline in $seq"
}

t_md_heading_font_wraps_words_to_the_width() {
	tui.md.fonts on
	_md_banner "AA" box3
	local one=$_B
	_md_banner "AA BB" box3
	local both=$_B
	_tui_md.cellw "${one%%|*}"
	local w=$_VL
	_md_flat "## AA BB" "$w"
	local joined=$_F
	_md_banner "BB" box3
	eq "$one|$_B" "$joined"
	_md_flat "## AA BB" 200
	eq "$both" "$_F"
}

t_md_heading_font_falls_back_to_plain_when_a_word_is_too_wide() {
	tui.md.fonts on
	_md_flat "# Hello" 10
	eq "Hello" "$_F"
}

t_md_heading_font_text_has_no_markup() {
	tui.md.fonts on
	_md_flat "## **a** b" 80
	_md_banner "A B" box3
	eq "$_B" "$_F"
}

t_md_heading_font_can_be_set_per_level() {
	tui.md.fonts on
	tui.md.heading_font 3 seg3
	_md_flat "### Hi" 80
	_md_banner "Hi" seg3
	eq "$_B" "$_F"
	tui.md.heading_font 1 ""
	_md_flat "# Hi" 80
	eq "Hi" "$_F"
}

t_md_heading_font_rejects_unknown_names_and_levels() {
	tui.md.heading_font 1 nosuch
	eq 1 $?
	tui.md.heading_font 7 blk3
	eq 1 $?
	tui.md.fonts on
	_md_flat "# Hi" 80
	_md_banner "Hi" block5
	eq "$_B" "$_F"
}

t_md_fonts_toggle_and_off() {
	tui.md.fonts toggle
	eq 1 "$TUI_MD_FONTS"
	tui.md.fonts off
	_md_flat "# Hi" 80
	eq "Hi" "$_F"
	tui.md.fonts bogus
	eq 1 $?
}

t_md_heading_font_does_not_change_the_styled_source() {
	tui.md.fonts on
	_md_sflat "# Hi"
	eq "# Hi" "$_F"
}

# ── style specs and persisted settings (the Markdown settings page) ──

t_md_style_spec_builds_the_sgr_from_color_and_modifiers() {
	tui.md.style_spec h1 "cyan:bold,underline"
	eq $'\e[1;4;36m' "${_TUI_MD_SGR[h1]}"
	tui.md.style_spec strong "red"
	eq $'\e[31m' "${_TUI_MD_SGR[strong]}"
	tui.md.style_spec em "default:italic"
	eq $'\e[3m' "${_TUI_MD_SGR[em]}"
}

t_md_style_spec_takes_hex_and_bright_colors() {
	tui.md.style_spec code "#ff8000"
	eq $'\e[38;2;255;128;0m' "${_TUI_MD_SGR[code]}"
	tui.md.style_spec link "bright_blue:underline"
	eq $'\e[4;94m' "${_TUI_MD_SGR[link]}"
}

t_md_style_spec_rejects_unknown_input() {
	tui.md.style_spec nosuch red
	eq 1 $?
	tui.md.style_spec em "chartreuse"
	eq 1 $?
	tui.md.style_spec em "red:sparkly"
	eq 1 $?
	tui.md.style_spec em "#12345"
	eq 1 $?
	eq $'\e[3m' "${_TUI_MD_SGR[em]}"
}

t_md_style_spec_is_used_by_the_renderer() {
	tui.md.style_spec strong "green:bold"
	tui.md.render "**a**" 40
	eq $'\e[1;32ma\e[0m' "${TUI_MD_ROWS[0]}"
}

t_md_style_spec_of_reads_back_the_spec() {
	local v
	tui.md.style_spec h2 "magenta:bold,underline"
	tui.md.style_spec_of h2 v
	eq "magenta:bold,underline" "$v"
	tui.md.style_spec_of strong v
	eq "default:bold" "$v"
}

t_md_style_reset_restores_one_class_or_all() {
	local def=${_TUI_MD_SGR[em]}
	tui.md.style_spec em "red"
	tui.md.style_spec strong "red"
	tui.md.style_reset em
	eq "$def" "${_TUI_MD_SGR[em]}"
	eq $'\e[31m' "${_TUI_MD_SGR[strong]}"
	tui.md.style_reset
	eq $'\e[1m' "${_TUI_MD_SGR[strong]}"
}

t_md_heading_font_accepts_style_as_plain() {
	local f
	tui.md.heading_font 1 style
	tui.md.heading_font_of 1 f
	eq "style" "$f"
	tui.md.fonts on
	_md_flat "# Hi" 80
	eq "Hi" "$_F"
	tui.md.heading_font_of 2 f
	eq "box3" "$f"
}

t_md_config_apply_reads_the_persisted_settings() {
	_TUI_CFG[md.fonts]=1
	_TUI_CFG[md.breaks]=1
	_TUI_CFG[md.link_url]=hidden
	_TUI_CFG[md.font.1]=half2
	_TUI_CFG[md.font.2]=style
	_TUI_CFG[md.style.strong]="yellow:bold"
	tui.md.config_apply
	eq 1 "$TUI_MD_FONTS"
	eq 1 "$TUI_MD_BREAKS"
	eq hidden "$TUI_MD_LINK_URL"
	eq half2 "${_TUI_MD_HFONT[1]}"
	eq "" "${_TUI_MD_HFONT[2]}"
	eq $'\e[1;33m' "${_TUI_MD_SGR[strong]}"
	unset '_TUI_CFG[md.fonts]' '_TUI_CFG[md.breaks]' '_TUI_CFG[md.link_url]' '_TUI_CFG[md.font.1]' '_TUI_CFG[md.font.2]' '_TUI_CFG[md.style.strong]'
}

t_md_config_apply_without_settings_changes_nothing() {
	local before=${_TUI_MD_SGR[strong]}
	tui.md.config_apply
	eq 0 "$TUI_MD_FONTS"
	eq "$before" "${_TUI_MD_SGR[strong]}"
}

t_md_spec_survives_a_style_set_memo_flush() {
	tui.md.style_spec h1 "red:bold"
	tui.md.style_lines "" "# a"
	eq "${_TUI_MD_SGR[marker]}# ${R}"$'\e[1;31m'"a${R}" "${TUI_MD_ROWS[0]}"
}

# ── inline spans ──────────────────────────────────────────────────────

t_md_bold_with_stars_and_underscores() {
	tui.md.render "a **b** c" 40
	eq "a ${_TUI_MD_SGR[strong]}b${R} c" "${TUI_MD_ROWS[0]}"
	tui.md.render "a __b__ c" 40
	eq "a ${_TUI_MD_SGR[strong]}b${R} c" "${TUI_MD_ROWS[0]}"
}

t_md_italic_with_stars_and_underscores() {
	tui.md.render "a *b* c" 40
	eq "a ${_TUI_MD_SGR[em]}b${R} c" "${TUI_MD_ROWS[0]}"
	tui.md.render "a _b_ c" 40
	eq "a ${_TUI_MD_SGR[em]}b${R} c" "${TUI_MD_ROWS[0]}"
}

t_md_snake_case_is_not_italic() {
	_md_flat "use snake_case_name here" 40
	eq "use snake_case_name here" "$_F"
	tui.md.render "snake_case_name" 40
	eq "snake_case_name" "${TUI_MD_ROWS[0]}"
}

t_md_triple_star_is_bold_and_italic() {
	tui.md.render "***x***" 40
	eq "${_TUI_MD_SGR[strong]}${_TUI_MD_SGR[em]}x${R}" "${TUI_MD_ROWS[0]}"
}

t_md_emphasis_nests_inside_bold() {
	tui.md.render "**a *b* c**" 40
	eq "${_TUI_MD_SGR[strong]}a ${_TUI_MD_SGR[em]}b${R}${_TUI_MD_SGR[strong]} c${R}" "${TUI_MD_ROWS[0]}"
}

t_md_unclosed_emphasis_is_literal() {
	_md_flat "**a and *b" 40
	eq "**a and *b" "$_F"
}

t_md_star_surrounded_by_spaces_is_literal() {
	_md_flat "a * b * c" 40
	eq "a * b * c" "$_F"
}

t_md_inline_code_keeps_inner_markers() {
	tui.md.render 'a `b*c*d` e' 40
	eq "a ${_TUI_MD_SGR[code]}b*c*d${R} e" "${TUI_MD_ROWS[0]}"
}

t_md_code_span_with_double_backticks_holds_a_backtick() {
	_md_flat '`` a`b ``' 40
	eq 'a`b' "$_F"
}

t_md_unclosed_backtick_is_literal() {
	_md_flat 'a `b' 40
	eq 'a `b' "$_F"
}

t_md_backslash_escapes_punctuation_only() {
	_md_flat '\*not em\* and a\b' 40
	eq '*not em* and a\b' "$_F"
}

t_md_styled_span_continues_on_the_wrapped_row() {
	tui.md.render "**aaa bbb**" 3
	eq "${_TUI_MD_SGR[strong]}aaa${R}" "${TUI_MD_ROWS[0]}"
	eq "${_TUI_MD_SGR[strong]}bbb${R}" "${TUI_MD_ROWS[1]}"
}

# ── links ─────────────────────────────────────────────────────────────

t_md_link_shows_text_and_url() {
	_md_flat "see [Docs](https://x.y/z) now" 60
	eq "see Docs (https://x.y/z) now" "$_F"
}

t_md_link_text_uses_link_style() {
	tui.md.render "[Docs](u)" 40
	eq "${_TUI_MD_SGR[link]}Docs${R} (u)" "${TUI_MD_ROWS[0]}"
}

t_md_link_hidden_mode_shows_text_only() {
	TUI_MD_LINK_URL=hidden
	_md_flat "[Docs](https://x.y)" 40
	eq "Docs" "$_F"
}

t_md_links_are_collected_in_order() {
	tui.md.render "[a](u1) and [b](u2)" 40
	eq "u1 u2" "${TUI_MD_LINK_URLS[*]}"
	eq "a b" "${TUI_MD_LINK_TEXTS[*]}"
}

t_md_link_title_is_dropped() {
	TUI_MD_LINK_URL=hidden
	tui.md.render '[a](http://x "The title")' 40
	eq "http://x" "${TUI_MD_LINK_URLS[0]}"
}

t_md_link_url_may_hold_balanced_parens() {
	tui.md.render "[a](http://x/(y)) z" 40
	eq "http://x/(y)" "${TUI_MD_LINK_URLS[0]}"
	_md_flat "[a](http://x/(y)) z" 40
	eq "a (http://x/(y)) z" "$_F"
}

t_md_link_text_may_hold_emphasis() {
	TUI_MD_LINK_URL=hidden
	tui.md.render "[**a** b](u)" 40
	eq "${_TUI_MD_SGR[link]}${_TUI_MD_SGR[strong]}a${R}${_TUI_MD_SGR[link]} b${R}" "${TUI_MD_ROWS[0]}"
}

t_md_brackets_without_a_url_are_literal() {
	_md_flat "[a] and [b](" 40
	eq "[a] and [b](" "$_F"
	eq 0 "${#TUI_MD_LINK_URLS[@]}"
}

t_md_link_in_code_span_is_not_a_link() {
	_md_flat 'x `[a](u)` y' 40
	eq "x [a](u) y" "$_F"
	eq 0 "${#TUI_MD_LINK_URLS[@]}"
}

t_md_links_reset_on_every_render() {
	tui.md.render "[a](u1)" 40
	tui.md.render "plain" 40
	eq 0 "${#TUI_MD_LINK_URLS[@]}"
}

# ── block quotes ──────────────────────────────────────────────────────

t_md_quote_gets_a_bar() {
	_md_flat "> hi" 40
	eq "│ hi" "$_F"
}

t_md_quote_nests() {
	_md_flat "> > deep" 40
	eq "│ │ deep" "$_F"
}

t_md_quote_wraps_inside_its_prefix() {
	_md_flat "> aaa bbb" 7
	eq "│ aaa|│ bbb" "$_F"
}

t_md_quote_holds_blocks() {
	_md_flat $'> # T\n> - a\n> - b' 40
	eq "│ T|│ |│ • a|│ • b" "$_F"
}

t_md_quote_bar_uses_quote_style() {
	tui.md.render "> hi" 40
	eq "${_TUI_MD_SGR[quote]}│${R} hi" "${TUI_MD_ROWS[0]}"
}

# ── lists ─────────────────────────────────────────────────────────────

t_md_bullet_list_markers() {
	_md_flat $'- a\n* b\n+ c' 40
	eq "• a|• b|• c" "$_F"
}

t_md_ordered_list_keeps_numbers() {
	_md_flat $'1. a\n2) b\n10. c' 40
	eq "1. a|2) b|10. c" "$_F"
}

t_md_list_item_wraps_with_hanging_indent() {
	_md_flat "- aaa bbb" 6
	eq "• aaa|  bbb" "$_F"
}

t_md_nested_list_changes_bullet_glyph() {
	_md_flat $'- a\n  - b\n    - c' 40
	eq "• a|  ◦ b|    ▪ c" "$_F"
}

t_md_nested_ordered_list_inside_bullet() {
	_md_flat $'- a\n  1. b\n  2. c' 40
	eq "• a|  1. b|  2. c" "$_F"
}

t_md_loose_list_has_gaps_between_items() {
	_md_flat $'- a\n\n- b' 40
	eq "• a||• b" "$_F"
}

t_md_list_item_may_hold_a_second_paragraph() {
	_md_flat $'- a\n\n  b' 40
	eq "• a||  b" "$_F"
}

t_md_list_ends_at_unindented_paragraph() {
	_md_flat $'- a\n\nb' 40
	eq "• a||b" "$_F"
}

t_md_lazy_continuation_joins_the_item() {
	_md_flat $'- a\nb' 40
	eq "• a b" "$_F"
}

t_md_dash_without_space_is_text() {
	_md_flat "-a" 40
	eq "-a" "$_F"
}

t_md_list_bullet_uses_bullet_style() {
	tui.md.render "- a" 40
	eq "${_TUI_MD_SGR[bullet]}•${R} a" "${TUI_MD_ROWS[0]}"
}

# ── rules and code ────────────────────────────────────────────────────

t_md_thematic_break_fills_the_width() {
	_md_flat "---" 5
	eq "─────" "$_F"
	_md_flat "* * *" 3
	eq "───" "$_F"
	_md_flat "___" 3
	eq "───" "$_F"
}

t_md_thematic_break_separates_paragraphs() {
	_md_flat $'a\n\n---\n\nb' 3
	eq "a||───||b" "$_F"
}

t_md_fenced_code_hides_fences_and_pads_to_width() {
	tui.md.render $'```bash\nx  y\n```' 6
	eq "${_TUI_MD_SGR[codeblock]}x  y  ${R}" "${TUI_MD_ROWS[0]}"
	eq 1 "${#TUI_MD_ROWS[@]}"
}

t_md_code_block_is_not_inline_parsed() {
	_md_flat $'```\n# not a heading **no**\n```' 40
	eq "# not a heading **no**$(printf '%*s' 18 '')" "$_F"
}

t_md_code_block_is_clipped_not_wrapped() {
	_md_flat $'```\nabcdefgh\n```' 4
	eq "abc›" "$_F"
}

t_md_tilde_fence_and_unclosed_fence() {
	_md_flat $'~~~\na\nb' 3
	eq "a  |b  " "$_F"
}

t_md_fence_closes_only_on_a_long_enough_fence() {
	_md_flat $'````\n```\n````\nz' 5
	eq '```  ||z' "$_F"
}

# ── safety and normalisation ──────────────────────────────────────────

t_md_foreign_escapes_and_control_bytes_are_removed() {
	tui.md.render $'a\e[31mb\e]0;t\a\x01c' 40
	[[ "${TUI_MD_ROWS[0]}" != *$'\e'* && "${TUI_MD_ROWS[0]}" != *$'\a'* && "${TUI_MD_ROWS[0]}" != *$'\x01'* ]] || _t_fail "control byte survived"
}

t_md_crlf_and_tabs_are_normalised() {
	_md_flat $'a\r\n\r\n\tb' 40
	eq "a||b$(printf '%*s' 39 '')" "$_F" # a tab is four spaces: an indented code block, padded to the width
}

t_md_no_row_is_wider_than_the_width() {
	local plain=$'# A title that is long\n\npara with **bold text** and `code` and [a link](http://example.com/x) done\n\n---\n\n```\ncode line that is long\n```'
	local nested=$'> quote text that goes on\n\n- item one is long enough\n  - nested item also long\n1. first'
	local w r
	for w in 1 2 3 5 8 13 21 40; do
		tui.md.render "$plain" "$w"
		for r in "${TUI_MD_ROWS[@]}"; do
			_md_vw "$r"
			((_W <= w)) || _t_fail "width $w: row [$r] is $_W cells"
		done
	done
	for w in 8 13 21 40; do
		tui.md.render "$nested" "$w"
		for r in "${TUI_MD_ROWS[@]}"; do
			_md_vw "$r"
			((_W <= w)) || _t_fail "width $w: row [$r] is $_W cells"
		done
	done
}

t_md_every_row_ends_in_the_reset_state() {
	local r
	tui.md.render $'# **a** b\n\n**x y z** `c d` [l](u)\n\n> q\n\n- i' 4
	for r in "${TUI_MD_ROWS[@]}"; do
		[[ "$r" != *$'\e['* || "${r##*$'\e['}" == 0m* ]] || _t_fail "row [$r] ends inside a style"
	done
}

# ── source map ────────────────────────────────────────────────────────

t_md_map_points_rows_at_source_lines() {
	tui.md.render $'# T\n\npara a\npara b\n\n- x' 40
	eq "1 2 3 5 6" "${TUI_MD_MAP[*]}"
}

t_md_map_gives_code_rows_their_own_lines() {
	tui.md.render $'```\na\nb\n```' 40
	eq "2 3" "${TUI_MD_MAP[*]}"
}

t_md_row_for_line_finds_the_first_row_of_the_block() {
	tui.md.render $'# T\n\naaa bbb ccc\nmore\n\nend' 4
	tui.md.row_for_line 4 _r
	eq 2 "$_r"
	tui.md.line_for_row "$_r" _l
	eq 3 "$_l"
}

# ── degradation and theme ─────────────────────────────────────────────

t_md_large_document_skips_inline_parsing() {
	TUI_MD_MAX_BYTES=10
	_md_flat $'# h\n\n**a** [b](c)' 40
	eq "h||**a** [b](c)" "$_F"
	eq 1 "$TUI_MD_DEGRADED"
}

t_md_small_document_is_not_degraded() {
	tui.md.render "**a**" 40
	eq 0 "$TUI_MD_DEGRADED"
}

t_md_mono_mode_uses_attributes_only() {
	tui.md.mono on
	local k v
	for k in "${!_TUI_MD_SGR[@]}"; do
		v=${_TUI_MD_SGR[$k]}
		[[ -z "$v" ]] && continue # the page class has no style by default
		[[ "$v" =~ ^$'\e'\[[0-9\;]*m$ ]] || _t_fail "$k: not an SGR"
		[[ ";${v#$'\e['};" != *";38;"* && "$v" != *[34][0-7]* && "$v" != *9[0-7]* ]] || _t_fail "$k uses a color: $v"
	done
}

t_md_style_set_overrides_a_class() {
	tui.md.style_set strong $'\e[1;31m'
	tui.md.render "**a**" 40
	eq $'\e[1;31ma\e[0m' "${TUI_MD_ROWS[0]}"
}

# ── styled source (editor overlay) ────────────────────────────────────

t_md_style_keeps_every_source_character() {
	local doc=$'# Title ##\n\n**bold** and *em* and `code` and [a](http://u "t")\n> quote\n- item\n1. one\n---\n```sh\n# raw **x**\n```\n\\* escaped'
	local line s i=0
	tui.md.style "$doc"
	while IFS= read -r line; do
		tui.md.strip "${TUI_MD_ROWS[i]}" s
		eq "$line" "$s"
		((i++))
	done <<<"$doc"
	eq "$i" "${#TUI_MD_ROWS[@]}"
}

t_md_style_heading_dims_the_marker() {
	tui.md.style "# Hi"
	eq "${_TUI_MD_SGR[marker]}# ${R}${_TUI_MD_SGR[h1]}Hi${R}" "${TUI_MD_ROWS[0]}"
}

t_md_style_bold_dims_the_delimiters() {
	tui.md.style "a **b** c"
	eq "a ${_TUI_MD_SGR[marker]}**${R}${_TUI_MD_SGR[strong]}b${R}${_TUI_MD_SGR[marker]}**${R} c" "${TUI_MD_ROWS[0]}"
}

t_md_style_link_splits_text_and_target() {
	tui.md.style "[a](u)"
	eq "${_TUI_MD_SGR[marker]}[${R}${_TUI_MD_SGR[link]}a${R}${_TUI_MD_SGR[marker]}](u)${R}" "${TUI_MD_ROWS[0]}"
}

t_md_style_quote_and_list_markers() {
	tui.md.style "> q"
	eq "${_TUI_MD_SGR[marker]}>${R} q" "${TUI_MD_ROWS[0]}"
	tui.md.style "- i"
	eq "${_TUI_MD_SGR[bullet]}-${R} i" "${TUI_MD_ROWS[0]}"
}

t_md_style_fence_state_spans_lines() {
	tui.md.style $'```\n# not a heading\n```'
	eq "${_TUI_MD_SGR[codeblock]}# not a heading${R}" "${TUI_MD_ROWS[1]}"
}

t_md_style_row_per_line_and_identity_map() {
	tui.md.style $'a\n\nb'
	eq 3 "${#TUI_MD_ROWS[@]}"
	eq "" "${TUI_MD_ROWS[1]}"
	eq "1 2 3" "${TUI_MD_MAP[*]}"
}

# ── helper ────────────────────────────────────────────────────────────

t_md_strip_removes_sgr() {
	tui.md.strip $'\e[1mab\e[0m c' s
	eq "ab c" "$s"
}

# ── the editor app ────────────────────────────────────────────────────

ti_md_editor_pages_pass_the_validator() {
	tui.validate.files "$REPO/examples/md-editor/config/editor.xml" "$REPO/examples/md-editor/config/static.xml"
	eq "0" "$TUI_V_ERRORS"
}

# ── windowed styling (the textarea overlay) ───────────────────────────

t_md_style_lines_continues_an_open_fence() {
	tui.md.style_lines '`:3' "# not a heading" '```' "# heading"
	eq "${_TUI_MD_SGR[codeblock]}# not a heading${R}" "${TUI_MD_ROWS[0]}"
	eq "${_TUI_MD_SGR[marker]}\`\`\`${R}" "${TUI_MD_ROWS[1]}"
	eq "${_TUI_MD_SGR[marker]}# ${R}${_TUI_MD_SGR[h1]}heading${R}" "${TUI_MD_ROWS[2]}"
}

t_md_fence_before_reports_the_open_fence() {
	local s
	tui.md.fence_before $'a\n```\nb\nc' 3 s
	eq '`:3' "$s"
	tui.md.fence_before $'a\n```\nb\n```\nc' 4 s
	eq '' "$s"
	tui.md.fence_before $'a\n```\nb' 1 s
	eq '' "$s"
}

t_md_fence_before_without_fences_is_empty() {
	local s
	tui.md.fence_before $'a\nb\nc' 2 s
	eq '' "$s"
}

t_md_style_memo_follows_the_style_table() {
	tui.md.style_lines "" "# a"
	tui.md.style_set h1 $'\e[1;31m'
	tui.md.style_lines "" "# a"
	eq "${_TUI_MD_SGR[marker]}# ${R}"$'\e[1;31m'"a${R}" "${TUI_MD_ROWS[0]}"
}

t_md_style_lines_gives_one_row_per_line() {
	tui.md.style_lines "" "a" "" "**b**"
	eq 3 "${#TUI_MD_ROWS[@]}"
	eq "" "${TUI_MD_ROWS[1]}"
}

t_md_slice_cuts_columns_and_keeps_the_open_style() {
	local s=${_TUI_MD_SGR[strong]}
	_tui_md.slice "${s}abcdef${R}" 2 3
	eq "${s}cde${R}" "$_SL"
}

t_md_slice_pads_after_closing_the_style() {
	local s=${_TUI_MD_SGR[strong]}
	_tui_md.slice "${s}ab${R}" 0 5
	eq "${s}ab${R}   " "$_SL"
}

t_md_slice_of_plain_text_is_a_substring() {
	_tui_md.slice "abcdef" 1 3
	eq "bcd" "$_SL"
}

t_md_paint_draws_the_cursor_cell_plain_over_the_style() {
	local s=${_TUI_MD_SGR[strong]}
	_tui_text.paint_md "${s}abc${R}" 0 5 -1 -1 1 ""
	eq "${s}a${R}"$'\e[7mb\e[27m'"${s}c${R}  " "$_PV"
}

t_md_paint_restores_the_widget_style_after_every_reset() {
	local s=${_TUI_MD_SGR[strong]}
	_tui_text.paint_md "${s}a${R}b" 0 3 -1 -1 -1 $'\e[44m'
	eq "${s}a${R}"$'\e[44m'"b " "$_PV"
}

t_md_textarea_mode_applies_to_textareas_only() {
	_foc_pane
	tui.textarea ta p 0 "" 3 ""
	tui.input inp p 4 "" "" ""
	tui.text.mode ta markdown
	eq 0 $?
	eq 1 "${_TXMD[ta]}"
	tui.text.mode inp markdown
	eq 1 $?
	tui.text.mode ta bogus
	eq 1 $?
	tui.text.mode ta plain
	eq "" "${_TXMD[ta]:-}"
}

t_md_textarea_draw_styles_the_source_in_markdown_mode() {
	_foc_pane
	tui.textarea ta p 0 "" 3 ""
	_TUI_W_VALUE[ta]=$'# Title\nplain'
	tui.text.mode ta markdown
	_TUI_FRAME=""
	_tui_text.draw_area ta 1 1 20 3 0 "" p
	[[ "$_TUI_FRAME" == *"${_TUI_MD_SGR[h1]}Title"* ]] || _t_fail "heading style missing: $_TUI_FRAME"
	tui.text.mode ta plain
	_TUI_FRAME=""
	_tui_text.draw_area ta 1 1 20 3 0 "" p
	[[ "$_TUI_FRAME" != *"${_TUI_MD_SGR[h1]}"* ]] || _t_fail "plain mode must not style"
}

# ── panes (tui.md.show) ───────────────────────────────────────────────

t_md_show_renders_into_the_pane_at_its_width() {
	_foc_pane
	tui.md.show p $'# Hi\n\naaa bbb ccc ddd eee fff ggg hhh'
	local -n rows=_TUI_PANE_CONTENT_p
	tui.md.strip "${rows[0]}" s
	eq "Hi" "$s"
	eq 4 "${#rows[@]}"
}

t_md_refit_re_renders_when_the_width_changes() {
	_foc_pane
	tui.md.show p "aaa bbb ccc ddd eee fff ggg hhh"
	local -n rows=_TUI_PANE_CONTENT_p
	eq 2 "${#rows[@]}"
	_TUI_P_W[p]=12
	_tui_md.refit
	eq 4 "${#rows[@]}"
}

t_md_refit_forgets_panes_that_left() {
	_foc_pane
	tui.md.show p "x"
	unset '_TUI_P_W[p]'
	_tui_md.refit
	eq 0 "${#_TUI_MD_SHOWN[@]}"
}

t_md_forget_stops_the_pane_from_being_re_rendered() {
	_foc_pane
	tui.md.show p "aaa bbb ccc ddd eee fff ggg hhh"
	tui.md.forget p
	local -n rows=_TUI_PANE_CONTENT_p
	rows=("other content")
	_TUI_P_W[p]=12
	_tui_md.refit
	eq "other content" "${rows[0]}"
	eq 0 "${#_TUI_MD_SHOWN[@]}"
}

t_md_show_file_reads_the_file() {
	_foc_pane
	printf '# From file\n' >"$_T_ROOT/doc.md"
	tui.md.show_file p "$_T_ROOT/doc.md"
	local -n rows=_TUI_PANE_CONTENT_p
	tui.md.strip "${rows[0]}" s
	eq "From file" "$s"
	tui.md.show_file p "$_T_ROOT/missing.md"
	eq 1 $?
}

# ── markup ────────────────────────────────────────────────────────────

ti_md_markdown_tag_and_textarea_mode_pass_the_validator() {
	mkdir -p "$_T_ROOT/mdpage"
	printf '# doc\n' >"$_T_ROOT/mdpage/doc.md"
	cat >"$_T_ROOT/mdpage/home.xml" <<'XML'
<tui>
  <pane id="root" split="h" border="none">
    <pane id="left" border="single">
      <textarea id="ta" mode="markdown" rows="0"/>
    </pane>
    <pane id="doc" border="single" scroll="v"/>
  </pane>
  <markdown pane="doc" src="doc.md"/>
</tui>
XML
	tui.validate.files "$_T_ROOT/mdpage/home.xml"
	eq "0" "$TUI_V_ERRORS"
}

ti_md_validator_rejects_a_bad_textarea_mode_and_a_missing_file() {
	mkdir -p "$_T_ROOT/mdbad"
	cat >"$_T_ROOT/mdbad/home.xml" <<'XML'
<tui>
  <pane id="root" border="none">
    <textarea id="ta" mode="rich" rows="0"/>
  </pane>
  <markdown pane="root" src="nope.md"/>
</tui>
XML
	tui.validate.files "$_T_ROOT/mdbad/home.xml"
	eq "2" "$TUI_V_ERRORS"
}

ti_md_settings_and_docs_pages_pass_the_validator() {
	tui.validate.files "$REPO/share/defaults/pages/settings.xml" "$REPO/share/defaults/pages/plugins.xml" \
		"$REPO/share/demo/docu.xml" "$REPO/share/demo/case_study.xml"
	eq "0" "$TUI_V_ERRORS"
}

# ── headings, code, spans ─────────────────────────────────────────────

t_md_setext_equals_makes_a_level_1_heading() {
	_md_flat $'Title\n=====\n\npara' 40
	eq "Title||para" "$_F"
	eq "1|Title|0|0|1" "${TUI_MD_HEADS[0]}"
}

t_md_setext_dashes_make_a_level_2_heading() {
	_md_flat $'Sub\n---' 40
	eq "Sub" "$_F"
	eq "2|Sub|0|0|1" "${TUI_MD_HEADS[0]}"
}

t_md_dashes_after_a_blank_line_are_still_a_rule() {
	_md_flat $'a\n\n---' 3
	eq "a||───" "$_F"
}

t_md_indented_code_is_a_code_block() {
	_md_flat $'para\n\n    code' 8
	eq "para||code    " "$_F"
}

t_md_indented_code_keeps_blank_lines_inside() {
	_md_flat $'    a\n\n    b' 4
	eq "a   |    |b   " "$_F"
}

t_md_strikethrough_uses_the_strike_class() {
	tui.md.render "a ~~b~~ c" 40
	eq "a ${_TUI_MD_SGR[strike]}b${R} c" "${TUI_MD_ROWS[0]}"
}

t_md_single_tilde_is_literal() {
	_md_flat "a ~b~ c" 40
	eq "a ~b~ c" "$_F"
}

t_md_task_list_items_get_checkboxes() {
	_md_flat $'- [ ] a\n- [x] b' 40
	eq "☐ a|☑ b" "$_F"
}

t_md_autolink_shows_its_url_and_is_collected() {
	TUI_MD_LINK_URL=hidden
	_md_flat "see <https://x.y/z> now" 40
	eq "see https://x.y/z now" "$_F"
	eq "https://x.y/z" "${TUI_MD_LINK_URLS[0]}"
}

t_md_email_autolink_becomes_mailto() {
	tui.md.render "<me@host.org>" 40
	eq "mailto:me@host.org" "${TUI_MD_LINK_URLS[0]}"
}

t_md_reference_links_use_their_definition() {
	TUI_MD_LINK_URL=hidden
	_md_flat $'[t][r] and [r] and [r][]\n\n[r]: https://u "Title"' 40
	eq "t and r and r" "$_F"
	eq "https://u https://u https://u" "${TUI_MD_LINK_URLS[*]}"
}

t_md_reference_definition_lines_are_not_shown() {
	_md_flat $'text\n\n[r]: https://u' 40
	eq "text" "${_F%%|*}"
}

t_md_unknown_reference_is_literal() {
	_md_flat "[a][zz]" 40
	eq "[a][zz]" "$_F"
}

t_md_image_is_a_placeholder_and_not_a_link() {
	_md_flat "![logo](a.png) x" 40
	eq "[img: logo] x" "$_F"
	eq 0 "${#TUI_MD_LINK_URLS[@]}"
}

t_md_image_modes() {
	tui.md.images alt
	_md_flat "![logo](a.png) x" 40
	eq "logo x" "$_F"
	tui.md.images hidden
	_md_flat "![logo](a.png) x" 40
	eq "x" "$_F"
	tui.md.images bogus
	eq 1 $?
}

t_md_image_inside_a_link_keeps_the_link() {
	TUI_MD_LINK_URL=hidden
	_md_flat "[![b](i.png)](https://u)" 40
	eq "[img: b]" "$_F"
	eq "https://u" "${TUI_MD_LINK_URLS[0]}"
}

# ── html subset ───────────────────────────────────────────────────────

t_md_html_br_breaks_the_line() {
	_md_flat "a<br/>b" 40
	eq "a|b" "$_F"
}

t_md_html_tags_are_dropped_and_their_text_kept() {
	_md_flat '<div align="center">hi</div>' 40
	eq "hi" "$_F"
}

t_md_html_img_becomes_a_placeholder() {
	_md_flat '<img src="x.png" alt="Logo">' 40
	eq "[img: Logo]" "$_F"
}

t_md_html_anchor_becomes_a_link() {
	TUI_MD_LINK_URL=hidden
	_md_flat 'go <a href="https://u">here</a>' 40
	eq "go here" "$_F"
	eq "https://u" "${TUI_MD_LINK_URLS[0]}"
}

t_md_html_bold_maps_to_a_strong_span() {
	tui.md.render "<b>x</b>" 40
	eq "${_TUI_MD_SGR[strong]}x${R}" "${TUI_MD_ROWS[0]}"
}

t_md_html_comment_is_removed_and_line_numbers_hold() {
	tui.md.render $'a\n<!-- x\n y -->\n\nb' 40
	eq "1 5" "${TUI_MD_MAP[0]} ${TUI_MD_MAP[-1]}"
}

t_md_html_in_a_fence_or_code_span_is_literal() {
	_md_flat $'```\n<b>x</b>\n```' 10
	eq "<b>x</b>   " "$_F"
	_md_flat 'a `<b>` c' 40
	eq "a <b> c" "$_F"
}

t_md_html_entities_are_decoded() {
	_md_flat "a&nbsp;&amp;&lt;b" 40
	eq "a &<b" "$_F"
}

t_md_html_heading_and_rule() {
	_md_flat $'<h2>Title</h2>\n<hr>' 5
	eq "Title||─────" "$_F"
}

# ── tables ────────────────────────────────────────────────────────────

_md_table_src=$'| Name | Description |\n|---|---|\n| apple | a quite long description of an apple |\n| pear | short |'

t_md_table_draws_a_grid_and_wraps_cells() {
	_md_flat "$_md_table_src" 34
	eq "┌───────┬────────────────────────┐|│ Name  │ Description            │|├───────┼────────────────────────┤|│ apple │ a quite long           │|│       │ description of an      │|│       │ apple                  │|│ pear  │ short                  │|└───────┴────────────────────────┘" "$_F"
}

t_md_table_aligns_columns() {
	_md_flat $'| a | b |\n|:--|--:|\n| x | 1 |' 40
	eq "┌───┬───┐|│ a │ b │|├───┼───┤|│ x │ 1 │|└───┴───┘" "$_F"
	_md_flat $'| left | right |\n|:-----|------:|\n| l | r |' 40
	eq "┌──────┬───────┐|│ left │ right │|├──────┼───────┤|│ l    │     r │|└──────┴───────┘" "$_F"
}

t_md_table_styles() {
	tui.md.tables rounded
	_md_flat $'| a |\n|---|\n| x |' 40
	eq "╭───╮|│ a │|├───┤|│ x │|╰───╯" "$_F"
	tui.md.tables plain
	_md_flat $'| a |\n|---|\n| x |' 40
	eq "  a  |─────|  x  " "$_F"
	tui.md.tables stacked
	_md_flat $'| a | b |\n|---|---|\n| x | y |' 40
	eq "a: x|b: y" "$_F"
	tui.md.tables bogus
	eq 1 $?
}

t_md_table_that_cannot_fit_is_stacked() {
	_md_flat $'| Name | Qty |\n|---|---|\n| apple | 3 |' 8
	eq "Name:|apple|Qty: 3" "$_F"
}

t_md_table_overflow_truncate_cuts_with_an_ellipsis() {
	tui.md.table_overflow truncate
	_md_flat "$_md_table_src" 30
	eq "┌───────┬────────────────────┐|│ Name  │ Description        │|├───────┼────────────────────┤|│ apple │ a quite long desc… │|│ pear  │ short              │|└───────┴────────────────────┘" "$_F"
}

t_md_pipe_line_without_a_delimiter_row_is_a_paragraph() {
	_md_flat "| a | b |" 40
	eq "| a | b |" "$_F"
}

t_md_table_link_is_collected_with_the_table_row() {
	tui.md.render $'para\n\n| a |\n|---|\n| [x](u) |' 40
	eq "u" "${TUI_MD_LINK_URLS[0]}"
	eq 2 "${TUI_MD_LINK_ROWS[0]}"
}

# ── wide characters ───────────────────────────────────────────────────

t_md_wide_characters_count_two_cells() {
	local old=$LC_ALL u=$'\xc3\xa9'
	LC_ALL=C.UTF-8
	if ((${#u} == 1)); then
		_tui_md.cells "日本"
		eq 4 "$_VL"
		_tui_md.cells "a😀b"
		eq 4 "$_VL"
	fi
	LC_ALL=$old
}

t_md_wide_characters_wrap_by_cells() {
	local old=$LC_ALL u=$'\xc3\xa9'
	LC_ALL=C.UTF-8
	if ((${#u} == 1)); then
		_md_flat "日本語 日本語" 6
		eq "日本語|日本語" "$_F"
	fi
	LC_ALL=$old
}

# ── highlighting ──────────────────────────────────────────────────────

t_md_bash_fence_is_highlighted() {
	tui.md.render $'```bash\nif x; then\n```' 20
	[[ "${TUI_MD_ROWS[0]}" == *"${_TUI_MD_SGR[hl_keyword]}if${R}"* ]] || _t_fail "no keyword span: ${TUI_MD_ROWS[0]}"
	[[ "${TUI_MD_ROWS[0]}" == *"${_TUI_MD_SGR[hl_keyword]}then${R}"* ]] || _t_fail "no second keyword span"
}

t_md_bash_comments_and_strings() {
	tui.md.render $'```sh\necho "a b" # note\n```' 30
	[[ "${TUI_MD_ROWS[0]}" == *"${_TUI_MD_SGR[hl_string]}\"a b\"${R}"* ]] || _t_fail "string: ${TUI_MD_ROWS[0]}"
	[[ "${TUI_MD_ROWS[0]}" == *"${_TUI_MD_SGR[hl_comment]}# note${R}"* ]] || _t_fail "comment"
}

t_md_unknown_fence_language_is_plain() {
	tui.md.render $'```cobol\nif x\n```' 6
	eq "${_TUI_MD_SGR[codeblock]}if x  ${R}" "${TUI_MD_ROWS[0]}"
}

t_md_custom_highlighter() {
	_hl_up() { TUI_MD_HL="${1^^}"; }
	tui.md.highlight foo _hl_up
	_md_flat $'```foo\nabc\n```' 5
	eq "ABC  " "$_F"
}

t_md_highlighted_row_keeps_its_width() {
	tui.md.render $'```json\n{"a": 1}\n```' 12
	tui.md.strip "${TUI_MD_ROWS[0]}" s
	eq '{"a": 1}    ' "$s"
}

# ── links, anchors, outline ───────────────────────────────────────────

t_md_link_rows_point_at_the_row_of_each_link() {
	tui.md.render $'[a](u1)\n\ntext\n\n[b](u2)' 40
	eq "0 4" "${TUI_MD_LINK_ROWS[*]}"
}

t_md_link_row_follows_a_wrapped_paragraph() {
	tui.md.render "aaaa bbbb [l](u)" 8
	eq 1 "${TUI_MD_LINK_ROWS[0]}"
}

t_md_headings_are_recorded_with_their_rows() {
	tui.md.render $'# One\n\ntext\n\n## Two' 40
	eq "1|One|0|0|1" "${TUI_MD_HEADS[0]}"
	eq "2|Two|4|4|5" "${TUI_MD_HEADS[1]}"
}

t_md_anchors_follow_github_slugs() {
	tui.md.render $'# Hello, World!\n\n## Hello, World!' 40
	eq 0 "${TUI_MD_ANCHORS[hello-world]}"
	eq 2 "${TUI_MD_ANCHORS[hello-world-1]}"
}

t_md_focused_link_uses_the_focus_style() {
	TUI_MD_LINK_URL=hidden
	_TUI_MD_FOCUS_LINK=1
	tui.md.render "[a](u) [b](v)" 40
	eq "${_TUI_MD_SGR[link]}a${R} ${_TUI_MD_SGR[link_focus]}b${R}" "${TUI_MD_ROWS[0]}"
	_TUI_MD_FOCUS_LINK=-1
}

# ── backgrounds, profiles ─────────────────────────────────────────────

t_md_spec_takes_a_background() {
	tui.md.style_spec code "white/#102030:bold"
	eq $'\e[1;37;48;2;16;32;48m' "${_TUI_MD_SGR[code]}"
	tui.md.style_spec em "default/blue"
	eq $'\e[44m' "${_TUI_MD_SGR[em]}"
	tui.md.style_spec em "red/nocolor"
	eq 1 $?
}

t_md_spec_of_reads_the_background_back() {
	local v
	tui.md.style_spec quote "yellow/#102030:dim"
	tui.md.style_spec_of quote v
	eq "yellow/#102030:dim" "$v"
}

t_md_page_background_pads_every_row() {
	tui.md.style_spec page "default/#101018"
	tui.md.render $'a\n\nb' 4
	local pg=$'\e[48;2;16;16;24m' r
	eq "${pg}a   ${R}" "${TUI_MD_ROWS[0]}"
	eq "${pg}    ${R}" "${TUI_MD_ROWS[1]}"
}

t_md_code_block_default_has_a_background() {
	[[ "${_TUI_MD_SGR[codeblock]}" == *48* ]] || _t_fail "no background: ${_TUI_MD_SGR[codeblock]}"
}

t_md_code_block_is_shaded_from_the_panel() {
	_TUI_CLASS_BG[panel]="#282a36"
	tui.md.style_reset
	eq $'\e[48;2;56;58;70m' "${_TUI_MD_SGR[codeblock]}"
	_TUI_CLASS_BG[panel]="#f0f0f0"
	tui.md.style_reset
	eq $'\e[48;2;224;224;224m' "${_TUI_MD_SGR[codeblock]}"
	unset '_TUI_CLASS_BG[panel]'
}

t_md_theme_profile_uses_the_md_classes_of_the_theme() {
	_TUI_CLASS_FG[md_strong]="#ff0000"
	tui.md.profile theme
	eq $'\e[38;2;255;0;0m' "${_TUI_MD_SGR[strong]}"
	eq $'\e[3m' "${_TUI_MD_SGR[em]}" # not in the theme: DABT's own
	tui.md.profile dabt
	eq $'\e[1m' "${_TUI_MD_SGR[strong]}"
	unset '_TUI_CLASS_FG[md_strong]'
}

t_md_own_style_wins_over_the_theme_profile() {
	_TUI_CLASS_FG[md_strong]="#ff0000"
	tui.md.style_spec strong "green"
	tui.md.profile theme
	eq $'\e[32m' "${_TUI_MD_SGR[strong]}"
	unset '_TUI_CLASS_FG[md_strong]'
}

t_md_profile_and_image_protocol() {
	tui.md.profile nope
	eq 1 $?
	local p KITTY_WINDOW_ID="" GHOSTTY_RESOURCES_DIR="" TMUX="" TERM_PROGRAM="" LC_TERMINAL="" TERM=dumb TUI_MD_IMAGE_PROTOCOL=""
	KITTY_WINDOW_ID=1 tui.md.image_protocol p
	eq kitty "$p"
	TERM_PROGRAM=iTerm.app tui.md.image_protocol p
	eq iterm2 "$p"
	TMUX=/tmp/x KITTY_WINDOW_ID=1 tui.md.image_protocol p
	eq none "$p"
}

t_md_config_apply_reads_profile_tables_and_images() {
	_TUI_CFG[md.profile]=theme
	_TUI_CFG[md.tables]=rounded
	_TUI_CFG[md.table_overflow]=truncate
	_TUI_CFG[md.images]=alt
	_TUI_CFG[md.style.page]="default/#000000"
	tui.md.config_apply
	eq theme "$TUI_MD_PROFILE"
	eq rounded "$TUI_MD_TABLES"
	eq truncate "$TUI_MD_TABLE_OVERFLOW"
	eq alt "$TUI_MD_IMAGES"
	eq $'\e[48;2;0;0;0m' "${_TUI_MD_SGR[page]}"
	unset '_TUI_CFG[md.profile]' '_TUI_CFG[md.tables]' '_TUI_CFG[md.table_overflow]' '_TUI_CFG[md.images]' '_TUI_CFG[md.style.page]'
}

# ── the viewer (links, history, search, folds, copy) and scroll reset ─

t_scroll_reset_returns_a_pane_to_the_top() {
	_foc_pane
	_TUI_P_SOFF_V[p]=5
	_TUI_P_SOFF_H[p]=3
	tui.scroll.reset p
	eq "0 0" "${_TUI_P_SOFF_V[p]} ${_TUI_P_SOFF_H[p]}"
	tui.scroll.reset no_such_pane
	eq 1 $?
}

t_md_show_of_a_different_document_resets_the_scroll() {
	_foc_pane
	tui.md.show p "first"
	_TUI_P_SOFF_V[p]=4
	tui.md.show p "first"
	eq 4 "${_TUI_P_SOFF_V[p]}"
	tui.md.show p "second"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_md_link_navigation_wraps_and_opens() {
	_foc_pane
	tui.md.show p "[a](u1) [b](u2)"
	tui.md.link_next p
	eq 0 "${_TUI_MD_V[p.focus]}"
	tui.md.link_next p
	tui.md.link_next p
	eq 0 "${_TUI_MD_V[p.focus]}"
	tui.md.link_prev p
	eq 1 "${_TUI_MD_V[p.focus]}"
	_hit() { GOT="$1|$2|$3"; return 0; }
	tui.md.on_link _hit
	tui.md.link_open p
	eq "u2|b|p" "$GOT"
}

t_md_anchor_link_scrolls_and_back_returns() {
	_foc_pane
	local doc="[go](#later)"$'\n\n' i
	for ((i = 0; i < 30; i++)); do doc+="line $i"$'\n\n'; done
	doc+="## Later"$'\n\n'"tail"
	tui.md.show p "$doc"
	tui.md.link_next p
	tui.md.link_open p
	((${_TUI_P_SOFF_V[p]:-0} > 0)) || _t_fail "did not scroll"
	tui.md.back p
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_md_search_marks_matches_and_steps_through_them() {
	_foc_pane
	local info
	tui.md.show p $'one two\n\nthree two'
	tui.md.search p two
	tui.md.search_info p info
	eq "1/2" "$info"
	local -n rows=_TUI_PANE_CONTENT_p
	[[ "${rows[0]}" == *$'\e[7m'* ]] || _t_fail "match not marked"
	tui.md.search_next p
	tui.md.search_info p info
	eq "2/2" "$info"
	tui.md.search p ""
	tui.md.search_info p info
	eq "" "$info"
}

t_md_fold_hides_the_rows_of_a_section() {
	_foc_pane
	tui.md.show p $'# A\n\ntext\n\n# B\n\nmore'
	tui.md.fold_toggle p 0
	local -n rows=_TUI_PANE_CONTENT_p
	local all="${rows[*]}"
	[[ "$all" == *"▸"* && "$all" != *text* && "$all" == *more* ]] || _t_fail "fold: $all"
	tui.md.fold_toggle p 0
	all="${rows[*]}"
	[[ "$all" == *text* ]] || _t_fail "unfold"
}

t_md_copy_section_sends_the_source_of_the_section_at_the_top() {
	_foc_pane
	local saved_notify saved_copy
	saved_notify=$(declare -f tui.notify)
	saved_copy=$(declare -f tui.clipboard.copy)
	tui.notify() { :; }
	tui.clipboard.copy() { CLIP=$1; }
	tui.md.show p $'# A\n\ntext\n\n# B\n\nmore'
	tui.md.copy p section
	eq $'# A\n\ntext\n\n' "$CLIP"
	tui.md.copy p doc
	eq $'# A\n\ntext\n\n# B\n\nmore' "$CLIP"
	eval "$saved_notify"
	eval "$saved_copy"
}

t_md_table_outline_and_header_have_their_own_classes() {
	tui.md.render $'| a |\n|---|\n| x |' 40
	eq "${_TUI_MD_SGR[table]}┌───┐${R}" "${TUI_MD_ROWS[0]}"
	[[ "${TUI_MD_ROWS[1]}" == "${_TUI_MD_SGR[table]}│${R} ${_TUI_MD_SGR[table_head]}a${R}"* ]] || _t_fail "header: ${TUI_MD_ROWS[1]}"
}

t_md_table_outline_follows_a_style_spec() {
	tui.md.style_spec table "cyan/#101018"
	tui.md.render $'| a |\n|---|\n| x |' 40
	eq $'\e[36;48;2;16;16;24m┌───┐\e[0m' "${TUI_MD_ROWS[0]}"
}

t_md_show_listens_for_layout_changes() {
	_foc_pane
	tui.md.show p "x"
	[[ " ${_TPL_HOOK[layout]:-} " == *" _tui_md.refit_soon "* ]] || _t_fail "no layout hook: ${_TPL_HOOK[layout]:-}"
	[[ " ${_TPL_HOOK[resize]:-} " == *" _tui_md.refit_soon "* ]] || _t_fail "no resize hook"
}

t_md_layout_change_rewraps_the_shown_pane() {
	_foc_pane
	tui.md.show p "aaa bbb ccc ddd eee fff ggg hhh"
	local -n rows=_TUI_PANE_CONTENT_p
	eq 2 "${#rows[@]}"
	_TUI_P_W[p]=12 # a divider was dragged: the pane is narrower
	_tui_md.refit_timer
	eq 4 "${#rows[@]}"
	_TUI_P_W[p]=40 # and wider again
	_tui_md.refit_timer
	eq 1 "${#rows[@]}"
}

# ── pictures through the kitty protocol ───────────────────────────────

# _md_png - a file with just a PNG signature and an IHDR header of 90 x 54 pixels (all the renderer reads)
_md_png() {
	printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x5a\x00\x00\x00\x36' >"$_T_ROOT/p.png"
}

t_md_b64_matches_known_values() {
	_tui_md.b64 ""
	eq "" "$_B64"
	_tui_md.b64 "a"
	eq "YQ==" "$_B64"
	_tui_md.b64 "ab"
	eq "YWI=" "$_B64"
	_tui_md.b64 "abc"
	eq "YWJj" "$_B64"
	_tui_md.b64 "/tmp/a.png"
	eq "L3RtcC9hLnBuZw==" "$_B64"
}

t_md_utf8_encodes_the_placeholder_and_a_diacritic() {
	_tui_md.utf8 $((0x10EEEE))
	eq $'\xf4\x8e\xbb\xae' "$_U8"
	_tui_md.utf8 $((0x305))
	eq $'\xcc\x85' "$_U8"
}

t_md_row_diacritics_are_zero_cells_wide() {
	_tui_md.charw $((16#${_TUI_MD_DIA[40]}))
	eq 0 "$_CW"
	eq 128 "${#_TUI_MD_DIA[@]}"
}

t_md_png_size_reads_the_header() {
	_md_png
	_tui_md.png_size "$_T_ROOT/p.png"
	eq "90 54" "$_PW $_PH"
	printf 'not a png at all, 24 bytes' >"$_T_ROOT/n.png"
	_tui_md.png_size "$_T_ROOT/n.png"
	eq 1 $?
}

t_md_graphics_image_becomes_placeholder_rows() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render $'before\n\n![shot](p.png)\n\nafter' 40
	eq 7 "${#TUI_MD_ROWS[@]}"
	eq "1 2 3 3 3 4 5" "${TUI_MD_MAP[*]}"
	local ph=$'\xf4\x8e\xbb\xae' row=${TUI_MD_ROWS[2]} n=0
	while [[ "$row" == *"$ph"* ]]; do
		row=${row#*"$ph"}
		((n++))
	done
	eq 10 "$n" # 90 pixels: 10 cells wide, 3 rows by the 1:2 cell aspect
	eq 1 "${#TUI_MD_IMAGE_IDS[@]}"
}

t_md_graphics_image_command_transmits_the_path() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render "![shot](p.png)" 40
	local id=${TUI_MD_IMAGE_IDS[0]}
	_tui_md.b64 "$_T_ROOT/p.png"
	eq $'\e_Ga=T,U=1,f=100,t=f,i='"$id"$',c=10,r=3,q=2;'"$_B64"$'\e\\' "${TUI_MD_IMAGE_CMD[$id]}"
}

t_md_graphics_row_names_its_row_and_column_in_the_first_cell() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render "![shot](p.png)" 40
	local id=${TUI_MD_IMAGE_IDS[0]} ph=$'\xf4\x8e\xbb\xae'
	local fg=$'\e[38;2;'"$((id >> 16 & 255));$((id >> 8 & 255));$((id & 255))m"
	[[ "${TUI_MD_ROWS[1]}" == "$fg$ph${_TUI_MD_DIAC[1]}${_TUI_MD_DIAC[0]}$ph$ph"* ]] || _t_fail "row 1: $(printf %q "${TUI_MD_ROWS[1]}")"
}

t_md_graphics_image_is_limited_by_the_width() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render "![shot](p.png)" 5
	local id=${TUI_MD_IMAGE_IDS[0]}
	[[ "${TUI_MD_IMAGE_CMD[$id]}" == *",c=5,r=2,q=2;"* ]] || _t_fail "size: $(printf %q "${TUI_MD_IMAGE_CMD[$id]}")"
}

t_md_graphics_falls_back_to_the_placeholder() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_BASE_DIR=$_T_ROOT
	TUI_MD_IMAGE_PROTOCOL=none
	_md_flat "![shot](p.png)" 40
	eq "[img: shot]" "$_F"
	TUI_MD_IMAGE_PROTOCOL=kitty
	_md_flat "![a](https://host/x.png)" 40
	eq "[img: a]" "$_F"
	_md_flat "![a](missing.png)" 40
	eq "[img: a]" "$_F"
	_md_flat "![a](p.jpg)" 40
	eq "[img: a]" "$_F"
	_md_flat "text ![shot](p.png) inline" 40
	eq "text [img: shot] inline" "$_F"
}

t_md_image_protocol_names_the_terminal_family() {
	local p KITTY_WINDOW_ID="" GHOSTTY_RESOURCES_DIR="" TMUX="" TERM_PROGRAM="" LC_TERMINAL="" TERM=dumb TUI_MD_IMAGE_PROTOCOL=""
	TERM_PROGRAM=ghostty tui.md.image_protocol p
	eq kitty "$p"
	TERM_PROGRAM=WezTerm tui.md.image_protocol p
	eq iterm2 "$p"
	TUI_MD_IMAGE_PROTOCOL=none KITTY_WINDOW_ID=1 tui.md.image_protocol p
	eq none "$p"
}

t_md_graphics_images_share_a_row_and_wrap() {
	_md_png
	cp "$_T_ROOT/p.png" "$_T_ROOT/q.png"
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render $'![a](p.png)\n![b](q.png)' 40
	eq 3 "${#TUI_MD_ROWS[@]}" # two 10-cell pictures side by side: 3 rows
	local ph=$'\xf4\x8e\xbb\xae' row=${TUI_MD_ROWS[0]} n=0
	while [[ "$row" == *"$ph"* ]]; do
		row=${row#*"$ph"}
		((n++))
	done
	eq 20 "$n"
	tui.md.render $'![a](p.png)\n![b](q.png)' 15
	eq 6 "${#TUI_MD_ROWS[@]}" # too narrow for both: one under the other
}

t_md_graphics_linked_image_registers_its_link() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render "[![shot](p.png)](https://example.org)" 40
	eq "https://example.org" "${TUI_MD_LINK_URLS[0]}"
	eq "shot" "${TUI_MD_LINK_TEXTS[0]}"
	eq 0 "${TUI_MD_LINK_ROWS[0]}"
}

t_md_graphics_paragraph_with_text_is_not_a_strip() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	_md_flat "![a](p.png) caption" 40
	eq "[img: a] caption" "$_F"
}

t_md_graphics_unreadable_image_inside_a_strip_is_a_placeholder_cell() {
	_md_png
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render $'![a](p.png)\n![b](missing.png)' 40
	eq 3 "${#TUI_MD_ROWS[@]}"
	tui.md.strip "${TUI_MD_ROWS[0]}" s
	[[ "$s" == *"[img: b]" ]] || _t_fail "placeholder cell missing: $s"
}

t_md_remote_image_is_a_placeholder_unless_fetch_is_on() {
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_IMAGE_FETCH=0
	_md_flat "![b](https://example.org/x.svg)" 40
	eq "[img: b]" "$_F"
}

t_md_non_png_image_converts_with_an_installed_tool() {
	command -v rsvg-convert >/dev/null 2>&1 || return 0
	local old=$XDG_CACHE_HOME
	XDG_CACHE_HOME=$_T_ROOT/cache
	printf '<svg xmlns="http://www.w3.org/2000/svg" width="90" height="54"><rect width="90" height="54" fill="red"/></svg>' >"$_T_ROOT/i.svg"
	TUI_MD_IMAGES=graphics TUI_MD_IMAGE_PROTOCOL=kitty TUI_MD_BASE_DIR=$_T_ROOT
	tui.md.render "![r](i.svg)" 40
	eq 1 "${#TUI_MD_IMAGE_IDS[@]}"
	XDG_CACHE_HOME=$old
}

t_md_is_png_checks_the_signature() {
	_md_png
	_tui_md.is_png "$_T_ROOT/p.png"
	eq 0 $?
	printf 'GIF89a' >"$_T_ROOT/g.gif"
	_tui_md.is_png "$_T_ROOT/g.gif"
	eq 1 $?
}

t_md_config_apply_reads_fetch() {
	_TUI_CFG[md.fetch]=1
	tui.md.config_apply
	eq 1 "$TUI_MD_IMAGE_FETCH"
	unset '_TUI_CFG[md.fetch]'
}
