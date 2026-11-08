# glyph_catalog.t.sh - share/defaults/glyphs/available.txt: the glyphs the Settings page offers, one list shared by every slot of a group.

_gcat_load() {
	TUI_DEFAULTS_DIR="$REPO/share/defaults"
	_TUI_G_AVAIL=() _TUI_G_AVAIL_LOADED=0
}

ti_catalog_every_slot_has_a_list() {
	_gcat_load
	local slot bad=""
	for slot in "${!_TUI_G_DEFAULT[@]}"; do
		tui.glyph.available "${slot%%.*}" "${slot#*.}"
		((${#TUI_GLYPHS[@]} > 1)) || bad+="$slot "
	done
	eq "" "$bad"
}

ti_catalog_slots_of_a_group_share_one_list() {
	_gcat_load
	local a b
	tui.glyph.available checkbox on
	a="${TUI_GLYPHS[*]}"
	tui.glyph.available checkbox off
	b="${TUI_GLYPHS[*]}"
	eq "$a" "$b"
	tui.glyph.available progress fill
	a="${TUI_GLYPHS[*]}"
	tui.glyph.available progress empty
	b="${TUI_GLYPHS[*]}"
	eq "$a" "$b"
	tui.glyph.available checkbox left
	a="${TUI_GLYPHS[*]}"
	tui.glyph.available select right
	b="${TUI_GLYPHS[*]}"
	eq "$a" "$b"
}

ti_catalog_a_slot_without_an_entry_has_an_empty_list() {
	_gcat_load
	tui.glyph.available nosuch slot
	eq 0 "${#TUI_GLYPHS[@]}"
}

ti_catalog_missing_file_gives_empty_lists() {
	TUI_DEFAULTS_DIR=/nonexistent _TUI_G_AVAIL=() _TUI_G_AVAIL_LOADED=0
	tui.glyph.available progress fill
	eq 0 "${#TUI_GLYPHS[@]}"
}

ti_catalog_none_is_offered_only_where_a_slot_may_be_blank() {
	_gcat_load
	local slot bad="" g
	for slot in "${!_TUI_G_DEFAULT[@]}"; do
		tui.glyph.available "${slot%%.*}" "${slot#*.}"
		for g in "${TUI_GLYPHS[@]}"; do
			[[ "$g" == none && -z "${_TUI_G_EMPTY_OK[$slot]+x}" ]] && bad+="$slot "
		done
	done
	eq "" "$bad"
}

ti_catalog_every_offered_glyph_is_accepted_by_its_slot() {
	local LC_ALL=C.UTF-8 u=$'\xc3\xa9'
	((${#u} == 1)) || return 0 # no UTF-8 locale on this host: the width cannot be measured
	_gcat_load
	local slot bad="" g v
	for slot in "${!_TUI_G_DEFAULT[@]}"; do
		tui.glyph.available "${slot%%.*}" "${slot#*.}"
		for g in "${TUI_GLYPHS[@]}"; do
			v=$g
			[[ "$g" == none ]] && v=""
			[[ "$g" == space ]] && v=" "
			_tui.glyph_ok "$v" "$slot" || bad+="$slot:$g "
		done
	done
	eq "" "$bad"
}
