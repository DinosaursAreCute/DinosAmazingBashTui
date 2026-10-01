#!/usr/bin/env bash
# settings_callbacks.sh - Settings page: every control does something real.
#   theme      -> tui.theme.set: the app-wide overlay, the same one the command bar (Theme: ...) and DABT's own
#                 Settings page set; saved as config `theme`, so it applies from the next start on
#   border/pad -> tui.pane_border / tui.pane_pad on the preview pane + tui.relayout
#   font/text  -> banner preview and a live tui.clock in that font
#   clock      -> starts/stops the tui.clock job
#   notify     -> toast via tui.after (auto-clears)
# All values persist to $TUI_APP_CONF/settings.conf (~/.config/DABT/apps/dabt_demo/) and reload on visit.

tui.require terminal_renderer

_ST_FILE="$TUI_APP_CONF/settings.conf"
declare -gA ST=()
_ST_BORDERS=(single double heavy none)
_ST_FONTS=(box3 seg3 block5 blk3 half2)

_st_defaults() { ST=([theme]=default [border]=single [hpad]=1 [vpad]=1 [font]=box3 [clock]=1 [notify]=1 [text]=DABT); }

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

_st_next() { # ARRAYNAME CURRENT -> next element (wraps)
	local -n _arr="$1"
	local i
	for i in "${!_arr[@]}"; do
		[[ "${_arr[i]}" == "$2" ]] && {
			printf '%s' "${_arr[(i + 1) % ${#_arr[@]}]}"
			return
		}
	done
	printf '%s' "${_arr[0]}"
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

_st_labels() {
	tui.set_label btn_border "Border: ${ST[border]}  (click to cycle)"
	tui.set_label btn_font "Font: ${ST[font]}  (click to cycle)"
	tui.set inp_hpad "${ST[hpad]}"
	tui.set inp_vpad "${ST[vpad]}"
	tui.set inp_text "${ST[text]}"
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
on_border_cycle() {
	tui.capture ST[border] _st_next _ST_BORDERS "${ST[border]}"
	_st_labels
	_st_save
	_st_frame
	_st_content
	tui.relayout preview
	_st_toast "border → ${ST[border]}"
}
on_font_cycle() {
	tui.capture ST[font] _st_next _ST_FONTS "${ST[font]}"
	_st_labels
	_st_save
	_st_content
	_st_toast "font → ${ST[font]}"
}

on_pad_apply() {
	local h v
	tui.capture h tui.get inp_hpad
	tui.capture v tui.get inp_vpad
	[[ "$h" =~ ^[0-9]$ ]] && ST[hpad]=$h
	[[ "$v" =~ ^[0-9]$ ]] && ST[vpad]=$v
	_st_labels
	_st_save
	_st_frame
	_st_content
	tui.relayout preview
	_st_toast "padding → ${ST[hpad]} x ${ST[vpad]}"
}

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
	_st_toast "clock $([[ ${ST[clock]} == 1 ]] && echo on || echo off)"
}
on_notify_toggle() {
	tui.capture ST[notify] tui.get chk_notify
	_st_save
	tui.notify "Notifications $([[ ${ST[notify]} == 1 ]] && echo on || echo off)" info 2
}

on_reset() { tui.confirm "Reset theme, border, padding, font and every other setting to its default?" st_do_reset --danger --yes Reset --no Keep --title "Reset settings"; }
st_do_reset() {
	rm -f "$_ST_FILE"
	_st_defaults
	_st_save
	tui.config.unset theme
	tui.theme.clear # reloads this page -> settings_visit picks up the defaults
}
