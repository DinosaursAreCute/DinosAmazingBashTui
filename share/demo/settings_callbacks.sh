#!/usr/bin/env bash
# settings_callbacks.sh - Settings page: every control does something real.
#   theme      -> tui.theme.set: the app-wide overlay, the same one the command bar (Theme: ...) and DABT's own
#                 Settings page set; saved as config `theme`, so it applies from the next start on
#   border/pad -> tui.pane_border / tui.pane_pad on the preview pane + tui.relayout (dropdowns: tui.select)
#   glyphs     -> tui.glyph.set progress fill/empty, shown on the sample progress bar
#   font/text  -> banner preview and a live tui.clock in that font
#   clock      -> starts/stops the tui.clock job
#   notify     -> toast via tui.after (auto-clears)
# All values persist to $TUI_APP_CONF/settings.conf (~/.config/DABT/apps/dabt_demo/) and reload on visit.

tui.require terminal_renderer

_ST_FILE="$TUI_APP_CONF/settings.conf"
declare -gA ST=()
_ST_BORDERS=(single double heavy none)
_ST_FONTS=(box3 seg3 block5 blk3 half2)
_ST_PADS=(0 1 2 3 4 5 6 7 8 9)
_ST_PVARS=(default thin dots squares ascii)
_ST_PFILLS=(█ ▓ ■ ● '#' = ━)
_ST_PEMPTYS=(░ ▒ · □ ○ - ─ ━)

_st_defaults() { ST=([theme]=default [border]=single [hpad]=1 [vpad]=1 [font]=box3 [pvar]=default [pfill]= [pempty]= [clock]=1 [notify]=1 [text]=DABT); }

_st_load() {
	_st_defaults
	local k v
	[[ -r "$_ST_FILE" ]] || return 0
	while IFS='=' read -r k v; do [[ -n "${ST[$k]+x}" ]] && ST[$k]="$v"; done <"$_ST_FILE"
}

_st_save() {
	mkdir -p "${_ST_FILE%/*}"
	local k
	for k in "${!ST[@]}"; do printf '%s=%s\n' "$k" "${ST[$k]}"; done | sort >"$_ST_FILE"
	_st_dump
}

_st_toast() { # the "Notifications" checkbox decides whether changes are announced
	[[ "${ST[notify]}" == 1 ]] || return 0
	tui.notify "$1" success 2.5
}
_st_toast_clear() { tui.update lbl_toast ""; }

_st_dump() {
	local rows cols eff theme_file kv
	tui.pane_size preview
	rows=$TUI_PANE_ROWS
	cols=$TUI_PANE_COLS
	tui.capture eff tui.get.border preview
	tui.capture theme_file tui.theme.current
	tui.capture kv kv_string \
		"file: ${_ST_FILE/#$HOME/~}" \
		"theme: ${ST[theme]}   (tui.theme.current = ${theme_file##*/})" \
		"border: ${ST[border]}   (effective now: $eff)" \
		"pad: hpad=${ST[hpad]} vpad=${ST[vpad]}   ->  usable preview area ${cols} x ${rows}" \
		"font: ${ST[font]}   text: ${ST[text]}" \
		"clock: ${ST[clock]}   notifications: ${ST[notify]}"
	tui.output status "${kv//\\n/$'\n'}"
}

# Frame = border/pad props. Content = banner/clock/dump. A change ends with
# tui.relayout preview: repaints ONLY that pane, in one synchronized frame.
_st_frame() {
	tui.pane_border preview "${ST[border]}"
	tui.pane_pad preview "${ST[hpad]}" "${ST[vpad]}"
}

_st_content() {
	local out
	tui.capture out banner_string "${ST[text]}" "${ST[font]}"
	printf -v out '%b' "$out"
	out="${out%"${out##*[!$'\n']}"}" # trailing newlines off, as $( ) did
	tui.output preview "$out"$'\n\n'"border=${ST[border]}  hpad=${ST[hpad]}  vpad=${ST[vpad]}  font=${ST[font]}"
	_st_clock
	_st_dump
}

_st_clock() {
	if [[ "${ST[clock]}" == 1 ]]; then
		tui.clock preview_clock "%H:%M:%S" "${ST[font]}"
	else
		tui.every.cancel clock_preview_clock
		tui.output_clear preview_clock
	fi
}

# _st_select ID VALUE ITEM... - shows VALUE in a dropdown without firing its action
_st_select() {
	local id="$1" value="$2"
	shift 2
	tui.set "$id" "$value"
	tui.select.set "$id" "$@"
}

# The bar's design: its variant, plus the fill / empty glyphs the user picked (stored per variant, empty = whatever the
# theme gives). _TUI_G is cleared by a theme reload, so this runs on every visit; the dropdowns show the glyphs in force.
_st_glyphs() {
	local v="${ST[pvar]}"
	[[ "$v" == default ]] && v=""
	tui.variant prg_demo "$v"
	[[ -n "${ST[pfill]}" ]] && tui.glyph.set progress fill "${ST[pfill]}" "$v"
	[[ -n "${ST[pempty]}" ]] && tui.glyph.set progress empty "${ST[pempty]}" "$v"
	tui.glyph.get progress fill "$v"
	_st_select sel_pfill "$TUI_GLYPH" "${_ST_PFILLS[@]}"
	tui.glyph.get progress empty "$v"
	_st_select sel_pempty "$TUI_GLYPH" "${_ST_PEMPTYS[@]}"
	tui.progress.set prg_demo 60
}

_st_labels() {
	_st_select sel_border "${ST[border]}" "${_ST_BORDERS[@]}"
	_st_select sel_font "${ST[font]}" "${_ST_FONTS[@]}"
	_st_select sel_hpad "${ST[hpad]}" "${_ST_PADS[@]}"
	_st_select sel_vpad "${ST[vpad]}" "${_ST_PADS[@]}"
	_st_select sel_pvar "${ST[pvar]}" "${_ST_PVARS[@]}"
	tui.update inp_text "${ST[text]}"
	tui.update chk_clock "${ST[clock]}"
	tui.update chk_notify "${ST[notify]}"
	local t mark
	for t in default ocean forest sunset light; do
		if [[ "${ST[theme]}" == "$t" ]]; then mark="● $t (active)"; else mark="  $t"; fi
		tui.set_label "btn_th_$t" "$mark"
	done
}

# The overlay is the one source of truth: it may also have been set from the command bar or DABT's Settings page,
# so the page shows what is active instead of forcing its own saved choice back (that fought the command bar and
# reloaded the page from inside on_visit).
_st_theme_current() {
	local f
	tui.capture f tui.theme.current
	f="${f##*/}"
	ST[theme]="${f%.css}"
	[[ -n "${ST[theme]}" ]] || ST[theme]=default
}
# NAME -> the overlay file: the app's themes (TUI_THEMES_DIR) win over the ones shipped with DABT
_st_theme_file() {
	local d
	for d in "${TUI_THEMES_DIR:-}" "$TUI_DEFAULTS_DIR/themes"; do
		[[ -n "$d" && -r "$d/$1.css" ]] && {
			printf '%s' "$d/$1.css"
			return 0
		}
	done
	return 1
}

settings_visit() {
	_st_load
	_st_theme_current
	_st_labels
	_st_glyphs
	_st_frame
	_st_content
}

on_theme_pick() {
	local name="${1#btn_th_}" f
	if [[ "$name" == default ]]; then
		tui.config.unset theme
		tui.theme.clear # reloads this page -> settings_visit shows the new state
		return
	fi
	tui.capture f _st_theme_file "$name" || {
		tui.notify "No theme file for $name" error 4
		return
	}
	tui.config.set theme "$f"
	tui.theme.set "$f"
}
on_border_pick() {
	tui.capture ST[border] tui.get sel_border
	_st_save
	_st_frame
	_st_content
	tui.relayout preview
	_st_toast "border → ${ST[border]}"
}
on_font_pick() {
	tui.capture ST[font] tui.get sel_font
	_st_save
	_st_content
	_st_toast "font → ${ST[font]}"
}
on_pad_pick() {
	tui.capture ST[hpad] tui.get sel_hpad
	tui.capture ST[vpad] tui.get sel_vpad
	_st_save
	_st_frame
	_st_content
	tui.relayout preview
	_st_toast "padding → ${ST[hpad]} x ${ST[vpad]}"
}
on_glyph_pick() { # ID: only the glyph the user touched becomes an override
	local g
	tui.capture g tui.get "$1"
	if [[ "$1" == sel_pfill ]]; then ST[pfill]="$g"; else ST[pempty]="$g"; fi
	_st_save
	_st_glyphs
	_st_toast "progress glyphs → ${ST[pfill]:-theme} ${ST[pempty]:-theme}"
}
on_variant_pick() {
	tui.capture ST[pvar] tui.get sel_pvar
	ST[pfill]="" ST[pempty]=""
	_st_save
	_st_glyphs
	_st_toast "progress variant → ${ST[pvar]}"
}
on_gallery() { tui.goto glyphs.xml; }

on_text_apply() {
	local t
	tui.capture t tui.get inp_text
	[[ -n "$t" ]] && ST[text]="${t:0:12}"
	_st_labels
	_st_save
	_st_content
	_st_toast "text → ${ST[text]}"
}

on_clock_toggle() {
	tui.capture ST[clock] tui.get chk_clock
	_st_save
	_st_clock
	local state=off
	[[ ${ST[clock]} == 1 ]] && state=on
	_st_toast "clock $state"
}
on_notify_toggle() {
	tui.capture ST[notify] tui.get chk_notify
	_st_save
	local state=off
	[[ ${ST[notify]} == 1 ]] && state=on
	tui.notify "Notifications $state" info 2
}

on_reset() { tui.confirm "Reset theme, border, padding, font and every other setting to its default?" st_do_reset --danger --yes Reset --no Keep --title "Reset settings"; }
st_do_reset() {
	rm -f "$_ST_FILE"
	_st_defaults
	_st_save
	tui.config.unset theme
	tui.theme.clear # reloads this page -> settings_visit picks up the defaults
}
