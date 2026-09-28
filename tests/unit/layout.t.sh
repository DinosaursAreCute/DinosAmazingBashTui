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
