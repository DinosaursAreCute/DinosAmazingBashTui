#!/usr/bin/env bash
# layers_callbacks.sh - the Layers demo page (share/demo/layers.xml): buttons that open, close and reset the layers.

on_ly_window() { tui.layer.toggle win_metrics; }
on_ly_modal() { tui.layer.show dlg_confirm; }
on_ly_popup() { tui.layer.toggle pop_menu; }
on_ly_toast() { tui.layer.show toast_saved; }
on_ly_reset() {
	tui.layer.reset win_metrics
	tui.layer.show win_metrics
}
on_ly_confirm() {
	tui.layer.close dlg_confirm
	tui.layer.show toast_saved
}
on_ly_cancel() { tui.layer.close dlg_confirm; }
on_ly_pick() {
	tui.layer.close pop_menu
	tui.set_label ly_status "Picked: $(tui.get_label "$1" 2>/dev/null || echo "$1")"
}
on_ly_detached() { tui.set_label ly_status "Detached $1 - drag its header, resize its corner, ⇲ docks it back"; }
on_ly_docked() { tui.set_label ly_status "Docked $1"; }
