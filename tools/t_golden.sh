#!/usr/bin/env bash
# t_golden.sh [--check] - records (or checks) a golden frame of every
# share/demo/*.xml page at 80x24, via tools/frame.sh. Run once before a
# render-path conversion (stage 0.3) to prove the converted renderer still
# produces byte-identical output.
#
#   tools/t_golden.sh          # (re)record every golden frame
#   tools/t_golden.sh --check  # compare current output against the recorded frames
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GOLDEN_DIR="$REPO/tools/golden"
mkdir -p "$GOLDEN_DIR"

_TG_CHECK=0
[[ "$1" == "--check" ]] && _TG_CHECK=1

# Pages that cannot give a stable frame headlessly: on_visit starts background work (tui.exec, ticks) that never
# returns without a real event loop (components_live), or the page shows live or environment data - system
# statistics (monitor), a block-font clock (settings), the list of files under docs/ (docu), the addon files the
# user applied (compose), the templates file (no page of its own: _templates).
_TG_SKIP=(components_live monitor settings docu compose _templates)
_tg_is_skipped() {
	local name="$1" s
	for s in "${_TG_SKIP[@]}"; do [[ "$name" == "$s" ]] && return 0; done
	return 1
}

# The frame as the byte stream the renderer wrote (cursor moves and colours included, so a moved widget or a changed
# colour is a change), with wall-clock times blanked.
_tg_frame() {
	timeout 20 "$REPO/tools/frame.sh" "$1" --sgr | sed -E 's/[0-9]{2}:[0-9]{2}:[0-9]{2}/HH:MM:SS/g'
}

_TG_FAIL=0
for _tg_page in "$REPO"/share/demo/*.xml; do
	_tg_name="$(basename "$_tg_page" .xml)"
	_tg_is_skipped "$_tg_name" && continue
	_tg_out="$GOLDEN_DIR/$_tg_name.frame"
	if ((_TG_CHECK)); then
		if [[ ! -r "$_tg_out" ]]; then
			printf 'G4\t%s\tno golden frame recorded\n' "$_tg_out"
			_TG_FAIL=1
			continue
		fi
		_tg_now="$(_tg_frame "$_tg_page")"
		if [[ "$_tg_now" != "$(cat "$_tg_out")" ]]; then
			printf 'G4\t%s\tframe changed\n' "$_tg_page"
			_TG_FAIL=1
		fi
	else
		_tg_frame "$_tg_page" >"$_tg_out" || {
			printf 'G4\t%s\ttimed out or failed, no golden frame recorded\n' "$_tg_page" >&2
			rm -f "$_tg_out"
		}
	fi
done
unset _tg_page _tg_name _tg_out _tg_now

exit "$_TG_FAIL"
