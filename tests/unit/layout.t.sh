# Pane layout without a terminal (lib/tui.sh), ported from tests/layout.bats.

_layout_reset_root() {
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=20 _TUI_P_W[root]=80
}

t_hsplit_child_without_weight_gets_weight_1() {
	_layout_reset_root
	tui.hsplit root nav main:3
	eq 20 "${_TUI_P_W[nav]}"
	eq 60 "${_TUI_P_W[main]}"
}

t_vsplit_with_no_weights_splits_evenly() {
	_layout_reset_root
	tui.vsplit root a b
	eq 10 "${_TUI_P_H[a]}"
	eq 10 "${_TUI_P_H[b]}"
}

t_cell_unit_gives_an_exact_number_of_cells_beside_fr_and_bare_weights() {
	_layout_reset_root
	tui.vsplit root head:6c body:1fr foot:3c
	eq "6 11 3" "${_TUI_P_H[head]} ${_TUI_P_H[body]} ${_TUI_P_H[foot]}"
	_layout_reset_root
	tui.hsplit root side:20c main:3
	eq "20 60" "${_TUI_P_W[side]} ${_TUI_P_W[main]}"
}

t_cell_unit_resolves_like_a_plain_cell_count() {
	_tui.layout_resolve 6c 50
	eq 6 "$_LY_R"
	_tui.layout_resolve clamp\(2c,4c,9c\) 50
	eq 4 "$_LY_R"
}
