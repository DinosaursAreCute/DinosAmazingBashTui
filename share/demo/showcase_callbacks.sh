#!/usr/bin/env bash
# showcase_callbacks.sh - callbacks for the renderer showcase page.
# Each function renders terminal_renderer.sh output into the display
# pane via tui.output - no PTY, no exec controls, just content.

tui.require terminal_renderer

# Every view calls this first: shows its name, records it so a resize / the
# fit checkbox can re-run it, sizes the renderers (TR_WIDTH) to the pane, and
# swaps the Controls box to the options that view actually has.
_SC_VIEW=""
declare -gA _SC_ALL_MEMO # no "=()": the script is re-sourced on every visit and must keep the memo
_SC_W=80
_SC_CTL_VIEW=""
_showcase_set_status() {
	tui.get.type lbl_status &>/dev/null && tui.update "lbl_status" "$1"
	[[ "$1" == "-" ]] && return
	_SC_VIEW="${FUNCNAME[1]}"
	_TUI_ON_RESIZE_FN="_sc_on_resize"
	_sc_fit
	_sc_controls "$_SC_VIEW" "$1"
}

# Fit is on when the page has no chk_fit (Theme page) or it is ticked.
_sc_fit() {
	tui.pane_size output
	_SC_W=$((TUI_PANE_COLS - 1))
	((_SC_W < 20)) && _SC_W=20
	if ! tui.get.type chk_fit &>/dev/null || tui.get.checked chk_fit; then TR_WIDTH=$_SC_W; else unset TR_WIDTH; fi
}

_sc_on_resize() { [[ -n "$_SC_VIEW" ]] && "$_SC_VIEW"; }
on_toggle_fit() { _sc_on_resize; }

# ── Contextual controls (Renderers page): rebuilt only when the view changes,
#    so submitting an input doesn't destroy the input you just used. ────────
_sc_ctl_add() { # kind row args...  (kind: input|button|label)
	local kind="$1" row="$2"
	shift 2
	case "$kind" in
		input) tui.factory.input ctl controls "$row" "$1" "" "$2" ;;
		button)
			tui.factory.button ctl controls "$row" "$1" "$2"
			tui.class "$_TUI_FACTORY_LAST_ID" "${3:-info_button}"
			tui.align "$_TUI_FACTORY_LAST_ID" fill
			;;
		label)
			tui.factory.label ctl controls "$row" "$1"
			tui.class "$_TUI_FACTORY_LAST_ID" "${2:-muted_label}"
			;;
	esac
}

_sc_controls() {
	local view="$1" name="$2"
	tui.get.type btn_clear &>/dev/null || return 0 # only the Renderers page has the contextual box
	[[ "$view" == "$_SC_CTL_VIEW" ]] && return 0
	_SC_CTL_VIEW="$view"
	tui.factory.clear ctl
	_sc_ctl_add label 4 "Options: $name" brand
	case "$view" in
		show_box) _sc_ctl_add input 5 "your text…" on_box_text ;;
		show_divider) _sc_ctl_add input 5 "section label…" on_div_label ;;
		show_alert)
			_sc_ctl_add button 5 "[ info ]" on_alert_type info_button
			_sc_ctl_add button 6 "[ success ]" on_alert_type success_button
			_sc_ctl_add button 7 "[ warn ]" on_alert_type warning_button
			_sc_ctl_add button 8 "[ error ]" on_alert_type danger_button
			;;
		show_gauge) _sc_ctl_add input 5 "value 0-100" on_gauge_value ;;
		show_sparkline | show_vbar | show_linechart)
			_sc_ctl_add button 5 "[ New random data ]" on_randomize success_button
			;;
		*) _sc_ctl_add label 5 "(no options for this view)" ;;
	esac
	((_TUI_RUNNING)) && tui.render
}

on_box_text() {
	_SC_BOX_TEXT="$1"
	show_box
}
on_div_label() {
	_SC_DIV_LABEL="$1"
	show_divider
}
on_gauge_value() {
	[[ "$1" =~ ^[0-9]+$ ]] && _SC_GAUGE=$(($1 > 100 ? 100 : $1))
	show_gauge
}
on_randomize() {
	_SC_SERIES=""
	_SC_RAND=$RANDOM
	_sc_on_resize
}
on_alert_type() {
	local l
	tui.capture l tui.get.label "$1"
	l="${l#\[ }"
	l="${l% \]}"
	_SC_ALERT_TYPE="$l"
	show_alert
}

# _sc_series N MAX -> space list of N values, stable until on_randomize
_sc_series() {
	local n="$1" max="$2" i out=() seed="${_SC_RAND:-0}"
	RANDOM=$((seed + n))
	for ((i = 0; i < n; i++)); do out+=($((RANDOM % max))); done
	RANDOM=${EPOCHREALTIME//[!0-9]/} # runs in the caller's shell (tui.capture): the seeding above must not leave on_randomize's $RANDOM repeating
	printf '%s' "${out[*]}"
}

show_box() {
	_showcase_set_status "Box"
	local _sc_t
	tui.capture _sc_t box "${_SC_BOX_TEXT:-DinosAmazingBashTui - pure bash rendering toolkit. No Python. No Node. No ncurses. Just bash, doing things bash was never meant to do.}"
	tui.output "output" "$_sc_t"
}

show_divider() {
	_showcase_set_status "Divider"
	local out="" _sc_t
	tui.capture _sc_t divider
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t divider "${_SC_DIV_LABEL:-SECTION HEADER}"
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t divider 'ANOTHER SECTION'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t divider
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_alert() {
	_showcase_set_status "Alerts"
	local out="" _sc_t
	if [[ -n "${_SC_ALERT_TYPE:-}" ]]; then
		tui.capture _sc_t alert "$_SC_ALERT_TYPE" "This is an '$_SC_ALERT_TYPE' alert - pick another type in Controls."
		tui.output "output" "$_sc_t"
		return
	fi
	tui.capture _sc_t alert info 'Server started on port 3000'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t alert success 'Deployment complete - 42 containers healthy'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t alert warn 'Disk usage above 90%'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t alert error '\e[31mConnection refused on 10.0.0.5:5432\e[0m '
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_table() {
	_showcase_set_status "Table"
	local _sc_t
	tui.capture _sc_t table 'Name|Role|Status|Uptime' 'Alice|Dev|Active|42d' 'Bob|Ops|Idle|7d' 'Carol|SRE|On-call|120d' 'Dave|QA|Active|30d'
	tui.output "output" "$_sc_t"
}

show_kv() {
	_showcase_set_status "Key-Value"
	local out="" _sc_t
	out+="=== Dot style (default) ==="$'\n'
	tui.capture _sc_t kv 'Host: server-01' 'CPU: AMD Ryzen 9' 'RAM: 64 GB' 'Uptime: 42 days' 'Kernel: 6.8.0-arch1'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="=== Dash style ==="$'\n'
	tui.capture _sc_t kv -t dashes 'Build: passing' 'Coverage: 94%' 'Last deploy: 2 hours ago'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="=== Plain style ==="$'\n'
	tui.capture _sc_t kv -t plain 'User: dino' 'Shell: bash' 'Editor: vim'
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_hbar() {
	_showcase_set_status "Bar Chart"
	local out="" _sc_t
	out+="Revenue by Quarter:"$'\n\n'
	tui.capture _sc_t hbar -w $((_SC_W - 24)) -m 100 'Q1:60' 'Q2:72' 'Q3:98' 'Q4:85'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="Language Popularity:"$'\n\n'
	tui.capture _sc_t hbar -w $((_SC_W - 24)) 'Bash:100' 'Python:88' 'Rust:65' 'Go:58' 'Lua:30'
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_banner() {
	_showcase_set_status "Banner"
	local out="" cols _sc_t
	tui.capture cols tui.get.dimensions -c
	tui.capture _sc_t banner --list $cols
	out+="$_sc_t"$'\n\n'
	tui.output "output" "$out"
}

get_dir_tree() {
	local target="${1:-.}"
	# Normalize target by removing any trailing slash for accurate path trimming
	target="${target%/}"

	# 'sort' ensures parent folders always appear before their children
	find "$target" -mindepth 1 | sort | while IFS= read -r path; do

		# Extract path strictly relative to the target to calculate depth correctly
		local rel="${path#$target/}"

		# Count slashes to determine indentation level
		local slashes="${rel//[^\/]/}"
		local depth="${#slashes}"

		local indent=""
		for ((i = 0; i < depth; i++)); do
			indent+="  "
		done

		local name="${path##*/}"
		if [[ -d "$path" ]]; then
			name="${name}/"
		fi

		printf '%s%s\n' "$indent" "$name"
	done
}

show_tree() {
	_showcase_set_status "Tree"

	local -a items=()
	mapfile -t items < <(get_dir_tree)

	local _sc_t
	tui.capture _sc_t tree "${items[@]}"
	tui.output "output" "$_sc_t"

}

show_columns() {
	_showcase_set_status "Columns"
	local _sc_t
	tui.capture _sc_t columns \
		-h 'Framework' -h 'Language' -h 'Lines' \
		'tui.sh' 'bash' '800+' \
		'tui_markup.sh' 'bash' '300+' \
		'terminal_renderer.sh' 'bash' '1000+' \
		'tui_style.sh' 'bash' '200+' \
		'colors.sh' 'bash' '150+'
	tui.output "output" "$_sc_t"
}

show_badges() {
	_showcase_set_status "Badges"
	local out="" _sc_t
	out+="CI Pipeline:"$'\n'
	tui.capture _sc_t badges 'pass:Build' 'pass:Lint' 'fail:Tests' 'skip:Deploy'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="Service Status:"$'\n'
	tui.capture _sc_t badges 'pass:API' 'pass:DB' 'warn:Cache' 'run:Worker'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="Release:"$'\n'
	tui.capture _sc_t badges 'info:v0.1.0' 'pass:Stable' 'warn:Experimental'
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_list() {
	_showcase_set_status "List"
	local out="" _sc_t
	out+="Bullet list:"$'\n'
	tui.capture _sc_t list \
		'Declarative XML markup' \
		'CSS-like theming engine' \
		'  Hex colors and named colors' \
		'  Focus pseudo-states' \
		'  Border and title variants' \
		'Mouse and keyboard navigation' \
		'Live PTY execution'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="Numbered list:"$'\n'
	tui.capture _sc_t list -n \
		'Source tui.sh' \
		'Write your XML page' \
		'Add callbacks' \
		'Run with tui.start' \
		'Ship it'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	out+="Custom bullet:"$'\n'
	tui.capture _sc_t list -s '▸' \
		'This uses a custom marker' \
		'Set with the -s flag' \
		'Any character works'
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_quote() {
	_showcase_set_status "Quote"
	local out="" _sc_t
	tui.capture _sc_t quote -a 'DABT README' 'Just bash, doing things bash was never meant to do.'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t quote -a 'The Developer' 'No Python. No Node. No ncurses. No abstraction of any kind.'
	out+="$_sc_t"$'\n'
	out+=$'\n'
	tui.capture _sc_t quote 'I use arch btw :D'
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_all() {
	_showcase_set_status "All Renderers"
	local out="" part key="${TR_WIDTH:--}|$_SC_W"
	# static for a given width: the renderers run once per width, later visits and resizes reuse the text
	if [[ -z "${_SC_ALL_MEMO[$key]+x}" ]]; then
		tui.capture part banner 'DABT'
		out+="$part"$'\n\n'
		tui.capture part divider 'BOX'
		out+="$part"$'\n'
		tui.capture part box 'Pure bash terminal rendering'
		out+="$part"$'\n\n'
		tui.capture part divider 'ALERTS'
		out+="$part"$'\n'
		tui.capture part alert success 'All systems go'
		out+="$part"$'\n\n'
		tui.capture part divider 'TABLE'
		out+="$part"$'\n'
		tui.capture part table 'Cmd|Description' 'box|Bordered box' 'alert|Callout' 'table|Data grid'
		out+="$part"$'\n\n'
		tui.capture part divider 'KEY-VALUE'
		out+="$part"$'\n'
		tui.capture part kv 'Framework: DABT' 'Language: bash' 'Deps: zero'
		out+="$part"$'\n\n'
		tui.capture part divider 'BAR CHART'
		out+="$part"$'\n'
		tui.capture part hbar -w $((_SC_W - 24)) 'Bash:100' 'Fun:99' 'Sanity:12'
		out+="$part"$'\n\n'
		tui.capture part divider 'BADGES'
		out+="$part"$'\n'
		tui.capture part badges 'pass:Build' 'pass:Tests' 'info:v0.1.0'
		out+="$part"$'\n\n'
		tui.capture part divider 'LIST'
		out+="$part"$'\n'
		tui.capture part list 'Markup' 'Theming' 'Rendering' 'Execution'
		out+="$part"$'\n\n'
		tui.capture part divider 'TREE'
		out+="$part"$'\n'
		tui.capture part tree 'DABT/' '  bin/' '    tui.sh' '  config/' '    home.xml'
		out+="$part"$'\n\n'
		tui.capture part divider 'QUOTE'
		out+="$part"$'\n'
		tui.capture part quote -a 'DABT' 'I use arch btw :D'
		out+="$part"
		_SC_ALL_MEMO[$key]="$out"
	fi
	tui.output "output" "${_SC_ALL_MEMO[$key]}"
}

on_clear() {
	_showcase_set_status "-"
	tui.output_clear "output"
}
# ── Charts not covered above (all sized from the pane: _SC_W) ─────────────

show_gauge() {
	_showcase_set_status "Gauge"
	local w=$((_SC_W - 16)) out="" _sc_t
	out+="Auto-colored by threshold (red <40, yellow <70, green):"$'\n\n'
	tui.capture _sc_t gauge -w "$w" -lw 6 -l CPU ${_SC_GAUGE:-23}
	out+="$_sc_t"$'\n'
	tui.capture _sc_t gauge -w "$w" -lw 6 -l RAM 64
	out+="$_sc_t"$'\n'
	tui.capture _sc_t gauge -w "$w" -lw 6 -l DISK 91
	out+="$_sc_t"$'\n\n'
	out+="Forced color, custom range:"$'\n\n'
	tui.capture _sc_t gauge -w "$w" -lw 6 -c CYAN -l TEMP -n 20 -m 100 72
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_sparkline() {
	_showcase_set_status "Sparkline"
	local out="" _sc_t _sc_t2
	out+="Resampled to exactly the pane width ($_SC_W cols):"$'\n\n'
	tui.capture _sc_t2 _sc_series 15 10
	tui.capture _sc_t sparkline -w "$_SC_W" -c CYAN "$_sc_t2"
	out+="$_sc_t"$'\n\n'
	out+="Fixed 0-100 scale:"$'\n\n'
	tui.capture _sc_t sparkline -w "$_SC_W" -n 0 -m 100 -c GREEN "12 30 45 60 88 72 40 20 55 95"
	out+="$_sc_t"$'\n\n'
	out+="Fixed 20 cols:"$'\n\n'
	tui.capture _sc_t sparkline -w 20 -c YELLOW "1 4 2 8 5 9 3 7"
	out+="$_sc_t"
	tui.output "output" "$out"
}

show_vbar() {
	_showcase_set_status "Vertical Bars"
	local -a v
	local _sc_t
	tui.capture _sc_t _sc_series 4 100
	read -ra v <<<"$_sc_t"
	tui.capture _sc_t vbar -h 12 -tw $((_SC_W - 4)) -n 0 -m 100 -c 'GREEN,YELLOW,RED,CYAN' "Q1:${v[0]}" "Q2:${v[1]}" "Q3:${v[2]}" "Q4:${v[3]}"
	tui.output "output" "$_sc_t"
}

show_linechart() {
	_showcase_set_status "Line Chart"
	local a b _sc_t
	tui.capture a _sc_series 14 100
	tui.capture b _sc_series 15 100
	tui.capture _sc_t linechart -h 12 -w $((_SC_W - 10)) -n 0 -m 100 -c 'GREEN,RED' "CPU:${a// /,}" "Mem:${b// /,}"
	tui.output "output" "$_sc_t"
}

show_csv() {
	_showcase_set_status "CSV Charts"
	local d="$TUI_ROOT/examples/csv-charts/data" out="" _sc_t
	if [[ ! -d "$d" ]]; then
		tui.capture _sc_t alert error "CSV examples not found at $d"
		tui.output "output" "$_sc_t"
		return
	fi
	out+="csv_hbar — quarterly_revenue.csv"$'\n\n'
	tui.capture _sc_t csv_hbar -w $((_SC_W - 30)) "$d/quarterly_revenue.csv"
	out+="$_sc_t"$'\n\n'
	out+="csv_vbar — disk_usage.csv"$'\n\n'
	tui.capture _sc_t csv_vbar -h 8 -tw $((_SC_W - 4)) "$d/disk_usage.csv"
	out+="$_sc_t"$'\n\n'
	out+="csv_linechart — server_cpu.csv"$'\n\n'
	tui.capture _sc_t csv_linechart -h 10 -w $((_SC_W - 10)) "$d/server_cpu.csv"
	out+="$_sc_t"
	tui.output "output" "$out"
}

# ── Theme: apply theme.css colors to renderer output ──────────────────────

# _sc_tint CLASS TEXT — wraps every line of TEXT (a renderer's output) in
# the theme class's colors, so renderers follow theme.css instead of
# hard-coded palettes.
_sc_tint() {
	local line out="" txt
	tui.class.sgr "$1"
	printf -v txt '%b' "$2"
	while IFS= read -r line; do out+="${TUI_SGR}${line}"$'\e[0m\n'; done <<<"$txt"
	printf '%s' "${out%$'\n'}"
}

show_theme() {
	_showcase_set_status "Theme"
	local out="" cls pad st _sc_t _sc_t2
	tui.capture _sc_t divider_string "THEME CLASSES  (tui.class.names / tui.class.style / tui.class.sgr)"
	out+="$_sc_t"$'\n\n'
	tui.class.names # fork-free getters: no $(...) per class
	for cls in "${TUI_CLASSES[@]}"; do
		case "$cls" in *_focus | *_hover | *_border | *_title) continue ;; esac
		tui.class.sgr "$cls"
		printf -v pad '%-16s' "$cls"
		out+="${pad} ${TUI_SGR} sample text ${TUI_RESET}  fg=${TUI_FG:--} bg=${TUI_BG:--} mods=${TUI_MODS:--}"$'\n'
	done

	tui.capture _sc_t divider_string "PANE STYLE STATES  (tui.style.sgr)"
	out+=$'\n'"$_sc_t"$'\n\n'
	for st in normal border title focus; do
		tui.style.sgr output "$st"
		printf -v pad '%-8s' "$st"
		out+="output:${pad} ${TUI_SGR} ${st} ${TUI_RESET}  fg=${TUI_FG:--} bg=${TUI_BG:--}"$'\n'
	done

	tui.capture _sc_t divider_string "RENDERERS IN THEME COLORS  (_sc_tint = tui.class.sgr per line)"
	out+=$'\n'"$_sc_t"$'\n\n'
	tui.capture _sc_t2 box_string 'info_button colors on a box'
	tui.capture _sc_t _sc_tint info_button "$_sc_t2"
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t2 alert_string success 'success_button colors on an alert'
	tui.capture _sc_t _sc_tint success_button "$_sc_t2"
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t2 alert_string error 'danger_button colors on an alert'
	tui.capture _sc_t _sc_tint danger_button "$_sc_t2"
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t2 table_string 'Class|Used for' 'panel|content panes' 'sidebar|nav / controls' 'brand|accents'
	tui.capture _sc_t _sc_tint sidebar "$_sc_t2"
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t2 kv_string 'Theme: theme.css' 'Applied by: tui.class.sgr' 'Change it: edit the css, revisit'
	tui.capture _sc_t _sc_tint sc_purple "$_sc_t2"
	out+="$_sc_t"
	printf -v out '%b' "$out"
	tui.output "output" "$out"
}

# ── Fit: everything sized from the live pane ──────────────────────────────

show_fit() {
	_showcase_set_status "Fit to Size"
	local w=$_SC_W rule out="" b p _sc_t out2
	printf -v rule '%*s' $((w - 2)) ''
	rule="|${rule// /-}|"
	tui.capture b tui.get.border output
	tui.capture p tui.get.pad output
	out+="Pane content: ${TUI_PANE_COLS} cols x ${TUI_PANE_ROWS} rows   border(output)=${b}   pad(output)=${p}  (hpad vpad)"$'\n'
	out+="Resize the terminal — every block below re-fits ($w cols)."$'\n'
	out+="$rule"$'\n\n'
	tui.capture _sc_t box_string 'box/divider/alert/table follow TR_WIDTH; gauge/sparkline/hbar/vbar/linechart take -w / -tw'
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t divider_string 'DIVIDER'
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t hbar_string -w $((w - 24)) -m 100 'One:40' 'Two:75' 'Three:95'
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t gauge_string -w $((w - 16)) -lw 6 -l LOAD 58
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t sparkline_string -w "$w" -c CYAN '3 5 8 2 9 4 7 1 6 8 3 9'
	out+="$_sc_t"$'\n\n'
	tui.capture _sc_t linechart_string -h 8 -w $((w - 10)) -n 0 -m 100 'A:10,50,30,80,60,90' 'B:70,40,60,20,50,10'
	out+="$_sc_t"$'\n\n'
	out+="$rule"
	printf -v out2 '%b' "$out"
	tui.output "output" "$out2"
}

# ── Tabs ──────────────────────────────────────────────────────────────────

# One page per tab (each keeps only the controls that apply to it). The
# active tab's own action is a no-op; the page's on_visit draws its view.
sc_tab_renderers() { show_all; }
sc_tab_theme() { show_theme; }
sc_tab_fit() { show_fit; }
sc_tab_here() { :; }
sc_goto_renderers() { tui.goto "components.xml"; }
sc_goto_theme() { tui.goto "components_theme.xml"; }
sc_goto_fit() { tui.goto "components_fit.xml"; }
sc_goto_live() { tui.goto "components_live.xml"; }

# Theme page: switch the app-wide overlay (same one the Settings page uses).
sc_theme_pick() {
	local t="${1#btn_sc_th_}" f="$TUI_APP_CONF/settings.conf" page
	mkdir -p "${f%/*}"
	{
		grep -v "^theme=" "$f" 2>/dev/null
		echo "theme=$t"
	} >"$f.tmp" && mv "$f.tmp" "$f"
	if [[ "$t" == default ]]; then tui.theme.clear; else
		tui.capture page tui.get.page
		tui.theme.set "${page%/*}/../defaults/themes/$t.css"
	fi
}

# Fit page: change the output pane's own padding/border and watch every renderer re-fit.
_SC_FIT_BORDERS=(heavy double single none)
on_fit_pad() {
	local h v
	tui.get inp_fh h
	tui.get inp_fv v
	[[ "$h" =~ ^[0-9]$ ]] && tui.pane_pad output "$h" ""
	[[ "$v" =~ ^[0-9]$ ]] && tui.pane_pad output "" "$v"
	tui.relayout
	_sc_on_resize
}
on_fit_border() {
	local cur i _sc_t
	tui.capture cur tui.get.border output
	for i in "${!_SC_FIT_BORDERS[@]}"; do
		[[ "${_SC_FIT_BORDERS[i]}" == "$cur" ]] && {
			cur="${_SC_FIT_BORDERS[(i + 1) % ${#_SC_FIT_BORDERS[@]}]}"
			break
		}
	done
	tui.capture _sc_t tui.get.border output
	[[ "$cur" == "$_sc_t" ]] && cur=heavy
	tui.pane_border output "$cur"
	tui.set_label btn_fit_border "Border: $cur (click)"
	tui.relayout
	_sc_on_resize
}

# ═══════════════════════════════════════════════════════════════════════
#  LIVE TAB (components_live.xml) — everything below updates by itself,
#  using tui_api.sh: no forks per tick, unchanged frames aren't redrawn,
#  the slow command runs off-thread. Stopped automatically on page change.
# ═══════════════════════════════════════════════════════════════════════

live_start() {
	tui.clock live_time "%H:%M:%S" box3
	tui.clock live_date "%d.%m.%Y" seg3
	tui.monitor live_mon 1
	tui.watch live_watch "ps -eo pcpu,pmem,comm --sort=-pcpu | head -14" 2
	tui.every 1 _live_chart live_chart
}

_live_chart() {
	tui.pane_size live_chart
	local n=$((TUI_PANE_COLS - 12))
	((n < 10)) && n=10
	tui.hist.push live_cpu "$TUI_SYS_CPU" "$n"
	tui.hist.push live_mem "$TUI_SYS_MEM_PCT" "$n"
	local c m h=$((TUI_PANE_ROWS - 4))
	((h < 4)) && h=4
	tui.capture c tui.hist.get live_cpu
	tui.capture m tui.hist.get live_mem
	[[ "$c" == *" "* ]] || return 0
	_linechart_build -h "$h" -w "$n" -n 0 -m 100 -c 'GREEN,MAGENTA' "CPU:${c// /,}" "Mem:${m// /,}" || return 0
	local out="" l
	for l in "${TR_RESULT[@]}"; do
		printf -v l '%b' "$l"
		out+="$l"$'\n'
	done
	tui.set_text live_chart "${out%$'\n'}"
}
