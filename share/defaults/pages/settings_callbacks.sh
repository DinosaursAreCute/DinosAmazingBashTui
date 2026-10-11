#!/usr/bin/env bash
# settings_callbacks.sh - DABT default Settings page. Only public tui.* calls (plus the input-binding tables the page already read).
#
# Every setting is one row: a category, a key, a title, a kind and a description. The visible rows are the chosen category's, or,
# while the search field holds text, every setting whose category, title or description contains all the words typed. Enter or a
# double-click changes the row under the cursor: a toggle flips, a choice opens a picker, an action runs.

declare -ga DSET_CATS=(appearance input keybinds notifications markdown plugins)
declare -gA DSET_CAT_LABEL=([appearance]="Appearance" [input]="Input" [keybinds]="Keybinds" [notifications]="Notifications" [markdown]="Markdown" [plugins]="Plugins")
declare -g DSET_CUR # category on show; kept across the reload a theme change causes (no initial value: the page is re-sourced)
: "${DSET_CUR:=appearance}"
declare -g DSET_QUERY=""
declare -ga S_CAT=() S_KEY=() S_TITLE=() S_KIND=() S_DESC=() # one entry per setting
declare -gA DSET_THEME_FILE=()                               # theme name -> css file
declare -g DSET_KEEP_SEL=0                                   # list row to select after the reload a theme change causes
declare -ga DSET_VIS=()                                      # indexes into S_* of the rows on show
declare -g DSET_PICK="" DSET_FILLING=0

# ── the settings ─────────────────────────────────────────────────────────

_dset_add() { # CAT KEY TITLE KIND DESC
	S_CAT+=("$1")
	S_KEY+=("$2")
	S_TITLE+=("$3")
	S_KIND+=("$4")
	S_DESC+=("$5")
}

_dset_pretty() { # hello_kitty -> Hello kitty
	local t=${1//_/ }
	printf '%s' "${t^}"
}

_dset_build() {
	S_CAT=() S_KEY=() S_TITLE=() S_KIND=() S_DESC=()
	DSET_THEME_FILE=()
	local g n f st v src title i cls
	_dset_add appearance theme. "Page default" radio "Each page keeps its own theme."
	while IFS=$'\t' read -r n f; do
		[[ -n "$n" ]] || continue
		_dset_add appearance "theme.$n" "$(_dset_pretty "$n")" radio "Restyles every page. Themes come from DABT's themes directory and the app's."
		DSET_THEME_FILE[$n]=$f
	done < <(tui.theme.list)

	_dset_add input retain "Keep focus in an input after Enter" toggle "After Enter the input keeps focus so you can type the next line."
	_dset_add input coalesce "Merge fast repeated scroll events" toggle "Fast wheel or key repeats are merged into one scroll step per frame."
	_dset_add input confirmq "Ask before quitting" toggle "Shows a confirmation before the app quits."
	_dset_add input tsfree "Free terminal shortcuts while DABT runs" toggle "Needs the *Terminal shortcuts* plugin: hands ctrl+c, ctrl+z and friends back to the terminal's own bindings while DABT runs."

	_dset_add keybinds kb.editor "Keybind editor ..." action "See every keybind; add, remove and save your own."
	_dset_add keybinds chord.palette "Command palette" info "Opens the command bar."
	_dset_add keybinds chord.suspend "Keybinds off" info "Kill switch: turns every keyboard binding off and on."
	_dset_add keybinds chord.terminal "Terminal mode" info "Passes keys straight to the terminal."
	_dset_add keybinds chord.back "Back" info "Returns to the previous page."
	local -A seen=()
	local k
	for k in "${!_TUI_BIND_DEF_GROUP[@]}"; do seen[${_TUI_BIND_DEF_GROUP[$k]}]=1; done
	_tui_input.sorted_ids seen
	for g in "${_SIDS[@]}"; do
		_dset_add keybinds "grp.$g" "Default keys: $g" toggle "Built-in keys of the *$g* group. Off removes them; your own bindings stay."
	done

	_dset_add notifications npos "Position" choice "Where toasts appear on screen."
	_dset_add notifications nsec "Stay for" choice "How long a toast stays. *until dismissed* keeps it until you close it."

	_dset_add markdown md.profile "Profile" choice "**DABT default**: the built-in look. **Theme default**: the active theme's own Markdown styles, defined like any class as *.md_h1*, *.md_strong*, *.md_codeblock*, *.md_page* ... (classes the theme does not define keep the DABT look). Your styles below always go on top."
	_dset_add markdown md.mode "Headings" choice "**fonts**: headings with a font are drawn as block letters. **pure style**: no fonts anywhere, only the heading styles (bold, underline, color)."
	for i in 1 2 3 4 5 6; do
		_dset_add markdown "md.h$i" "Heading $i" choice "The font of level $i headings. **style** draws them as plain text in the heading style, which you can customize below."
	done
	_dset_add markdown md.link "Link URLs" choice "**inline** shows *text (url)*, **hidden** shows only the text."
	_dset_add markdown md.breaks "Literal line breaks" toggle "On: every newline inside a paragraph breaks the line. Off: a single newline is a space."
	_dset_add markdown md.tables "Tables" choice "**grid**: box lines. **rounded**: the same with round corners. **plain**: no frame, a rule under the header. **stacked**: every row as *Header: value* lines, which also happens when the pane is too narrow for the columns."
	_dset_add markdown md.tover "Table cells that do not fit" choice "**wrap**: the cell grows taller. **truncate**: the cell is cut with an ellipsis, rows stay one line."
	_dset_add markdown md.images "Images" choice "What *![alt](file)* shows: **placeholder** *[img: alt]*, only the **alt** text, **hidden**, or **graphics**: the picture itself, when the terminal is kitty or Ghostty and a paragraph holds only images (several share a row, like badges). PNG is drawn as it is; SVG, GIF, JPEG and WebP are converted once when rsvg-convert, ImageMagick or ffmpeg is installed. Anything else stays a placeholder."
	_dset_add markdown md.fetch "Fetch remote images" toggle "Only for the *graphics* image mode: http(s) images (the README badges) are downloaded in the background with curl or wget into ~/.cache/DABT/md-images and show up when they arrive; until then they are placeholders. Off by default: it uses the network. SVG needs *rsvg-convert*, GIF/JPEG/WebP need ImageMagick or ffmpeg (first frame)."
	_dset_add markdown md.imgproto "Terminal image support" info "The inline image protocol this terminal appears to speak, judged from the environment. **kitty**: kitty and Ghostty, which the *graphics* image mode draws. **iterm2**: iTerm2 and WezTerm speak another protocol, not drawn yet. **none**: placeholders only (also inside tmux)."
	local -a labels=("Heading 1" "Heading 2" "Heading 3" "Heading 4" "Heading 5" "Heading 6" "Bold" "Italic" "Inline code" "Code block" "Quote" "List bullet" "Link" "Rule" "Delimiters" "Strikethrough" "Code: keyword" "Code: string" "Code: comment" "Code: number" "Code: variable" "Document background" "Table outline" "Table header")
	for i in "${!TUI_MD_CLASSES[@]}"; do
		cls=${TUI_MD_CLASSES[i]}
		_dset_add markdown "md.st.$cls" "Style: ${labels[i]} ..." action "Color and text attributes of this element. Opens the style editor."
	done

	while IFS=$'\t' read -r n st v src title; do
		[[ -n "$n" ]] || continue
		_dset_add plugins "plg.$n" "${title:-$n}" toggle "$(tui.plugin.get "$n" description)"
	done < <(tui.plugin.list)
	_dset_add plugins plg.browser "Plugin browser ..." action "Files and contents of every detected plugin."
}

# _dset_value KEY -> _DSET_V : the value column of a row
_dset_value() {
	local k=$1 f
	case "$k" in
		theme.)
			[[ -z "${_TUI_THEME_OVERLAY:-}" ]] && _DSET_V="●" || _DSET_V=" "
			;;
		theme.*)
			[[ -n "${_TUI_THEME_OVERLAY:-}" && "${_TUI_THEME_OVERLAY##*/}" == "${DSET_THEME_FILE[${k#theme.}]##*/}" ]] && _DSET_V="●" || _DSET_V=" "
			;;
		retain) _dset_onoff "$TUI_INPUT_RETAIN_ON_SUBMIT" ;;
		coalesce) _dset_onoff "$TUI_INPUT_COALESCE" ;;
		confirmq) _dset_onoff "$(tui.config.get confirm.quit 0)" ;;
		tsfree) _dset_onoff "$(tui.config.get plugin.terminal_shortcuts.auto_free 0)" ;;
		chord.palette) _DSET_V="ctrl+p" ;;
		chord.suspend) _DSET_V="$TUI_KEYS_SUSPEND_KEY" ;;
		chord.terminal) _DSET_V="$TUI_PASSTHROUGH_KEY" ;;
		chord.back) _DSET_V="alt+backspace" ;;
		grp.*) _dset_onoff "$([[ -n "${_TUI_DEF_OFF[${k#grp.}]:-}" ]] && echo 0 || echo 1)" ;;
		npos) _DSET_V="$(tui.notify.position)" ;;
		nsec)
			f="$(tui.notify.seconds)"
			[[ "$f" == 0 ]] && _DSET_V="until dismissed" || _DSET_V="${f} s"
			;;
		md.profile) [[ "$TUI_MD_PROFILE" == theme ]] && _DSET_V="Theme default" || _DSET_V="DABT default" ;;
		md.mode) [[ "$TUI_MD_FONTS" == 1 ]] && _DSET_V=fonts || _DSET_V="pure style" ;;
		md.tables) _DSET_V=$TUI_MD_TABLES ;;
		md.tover) _DSET_V=$TUI_MD_TABLE_OVERFLOW ;;
		md.images) _DSET_V=$TUI_MD_IMAGES ;;
		md.imgproto) tui.md.image_protocol _DSET_V ;;
		md.h[1-6]) tui.md.heading_font_of "${k#md.h}" _DSET_V ;;
		md.link) _DSET_V="$TUI_MD_LINK_URL" ;;
		md.breaks) _dset_onoff "$TUI_MD_BREAKS" ;;
		md.fetch) _dset_onoff "$TUI_MD_IMAGE_FETCH" ;;
		md.st.*) tui.md.style_spec_of "${k#md.st.}" _DSET_V ;;
		plg.browser | kb.editor) _DSET_V="" ;;
		plg.*)
			_DSET_V=$(tui.plugin.get "${k#plg.}" state)
			[[ "$_DSET_V" == enabled ]] && _DSET_V=on
			[[ "$_DSET_V" == disabled ]] && _DSET_V=off
			;;
		*) _DSET_V="" ;;
	esac
}
_dset_onoff() { [[ "$1" == 1 ]] && _DSET_V=on || _DSET_V=off; }

# _dset_choices KEY -> _DSET_CH (array), _DSET_SEL (index of the current value)
_dset_choices() {
	local k=$1 name f cur i
	_DSET_CH=()
	case "$k" in
		npos) _DSET_CH=(bottom-right bottom-center bottom-left top-right top-center top-left) ;;
		nsec) _DSET_CH=("3 s" "5 s" "8 s" "12 s" "until dismissed") ;;
		md.profile) _DSET_CH=("DABT default" "Theme default") ;;
		md.mode) _DSET_CH=(fonts "pure style") ;;
		md.tables) _DSET_CH=(grid rounded plain stacked) ;;
		md.tover) _DSET_CH=(wrap truncate) ;;
		md.images) _DSET_CH=(placeholder alt hidden graphics) ;;
		md.h[1-6]) _DSET_CH=("${TUI_MD_FONT_NAMES[@]}") ;;
		md.link) _DSET_CH=(inline hidden) ;;
	esac
	_dset_value "$k"
	_DSET_SEL=0
	for i in "${!_DSET_CH[@]}"; do [[ "${_DSET_CH[i]}" == "$_DSET_V" ]] && _DSET_SEL=$i; done
}

# _dset_apply KEY VALUE - applies, saves and reports one picked value
_dset_apply() {
	local k=$1 v=$2
	case "$k" in
		npos)
			tui.notify.position "$v"
			tui.config.set notify.position "$v"
			;;
		nsec)
			v=${v% s}
			[[ "$v" == "until dismissed" ]] && v=0
			tui.notify.seconds "$v"
			tui.config.set notify.seconds "$v"
			;;
		md.profile)
			[[ "$v" == "Theme default" ]] && v=theme || v=dabt
			tui.md.profile "$v"
			tui.config.set md.profile "$v"
			;;
		md.tables)
			tui.md.tables "$v"
			tui.config.set md.tables "$v"
			;;
		md.tover)
			tui.md.table_overflow "$v"
			tui.config.set md.table_overflow "$v"
			;;
		md.images)
			tui.md.images "$v"
			tui.config.set md.images "$v"
			;;
		md.mode)
			if [[ "$v" == fonts ]]; then tui.md.fonts on; else tui.md.fonts off; fi
			tui.config.set md.fonts "$TUI_MD_FONTS"
			;;
		md.h[1-6])
			tui.md.heading_font "${k#md.h}" "$v"
			tui.config.set "md.font.${k#md.h}" "$v"
			;;
		md.link)
			TUI_MD_LINK_URL=$v
			tui.config.set md.link_url "$v"
			;;
	esac
}

# _dset_flip VALUE -> _DSET_N : 1 for anything but 1 (an empty or odd stored value included)
_dset_flip() { [[ "${1:-0}" == 1 ]] && _DSET_N=0 || _DSET_N=1; }

_dset_toggle() { # KEY
	local k=$1 on g off
	case "$k" in
		retain)
			_dset_flip "$TUI_INPUT_RETAIN_ON_SUBMIT"
			on=$_DSET_N
			TUI_INPUT_RETAIN_ON_SUBMIT=$on
			tui.config.set input.retain "$on"
			;;
		coalesce)
			_dset_flip "$TUI_INPUT_COALESCE"
			on=$_DSET_N
			TUI_INPUT_COALESCE=$on
			tui.config.set input.coalesce "$on"
			;;
		confirmq)
			_dset_flip "$(tui.config.get confirm.quit 0)"
			on=$_DSET_N
			tui.config.set confirm.quit "$on"
			;;
		tsfree)
			if ! tui.plugin.enabled terminal_shortcuts; then
				tui.notify "Enable the 'Terminal shortcuts' plugin first (Settings > Plugins)" warn 5
				return
			fi
			_dset_flip "$(tui.config.get plugin.terminal_shortcuts.auto_free 0)"
			on=$_DSET_N
			tui.plugin.config terminal_shortcuts auto_free "$on"
			if [[ "$on" == 1 ]]; then tui.cmd.run ts.free; else tui.cmd.run ts.restore; fi
			;;
		grp.*)
			g=${k#grp.}
			if [[ -n "${_TUI_DEF_OFF[$g]:-}" ]]; then tui.defaults.on "$g"; else tui.defaults.off "$g"; fi
			off=""
			for g in "${!_TUI_DEF_OFF[@]}"; do off+="${off:+ }$g"; done
			if [[ -n "$off" ]]; then tui.config.set defaults.off "$off"; else tui.config.unset defaults.off; fi
			;;
		md.breaks)
			tui.md.breaks toggle
			tui.config.set md.breaks "$TUI_MD_BREAKS"
			;;
		md.fetch)
			_dset_flip "$TUI_MD_IMAGE_FETCH"
			TUI_MD_IMAGE_FETCH=$_DSET_N
			tui.config.set md.fetch "$_DSET_N"
			;;
		plg.*)
			g=${k#plg.}
			if tui.plugin.enabled "$g"; then
				tui.plugin.disable "$g"
			elif ! tui.plugin.enable "$g"; then
				tui.notify "Could not enable $g: ${TUI_PLUGIN_ERROR:-unknown error}" error 6
			fi
			;;
	esac
}

# ── the lists ────────────────────────────────────────────────────────────

# _dset_matches INDEX -> rc 0 when the setting contains every word of DSET_QUERY (case-insensitive)
_dset_matches() {
	local hay w
	hay="${DSET_CAT_LABEL[${S_CAT[$1]}]} ${S_TITLE[$1]} ${S_DESC[$1]}"
	hay=${hay,,}
	for w in $DSET_QUERY; do
		[[ "$hay" == *"$w"* ]] || return 1
	done
	return 0
}

# _dset_show - fills the settings list: the search results, or the chosen category
_dset_show() {
	local keep=${1:-0} i row val
	local -a rows=()
	DSET_VIS=()
	for i in "${!S_KEY[@]}"; do
		if [[ -n "$DSET_QUERY" ]]; then _dset_matches "$i" || continue; else [[ "${S_CAT[i]}" == "$DSET_CUR" ]] || continue; fi
		DSET_VIS+=("$i")
		_dset_value "${S_KEY[i]}"
		val=$_DSET_V
		case "${S_KIND[i]}" in
			toggle) val="[$([[ "$val" == on ]] && echo x || echo ' ')] $val" ;;
			radio) val="($val)" ;;
			choice) val="< $val >" ;;
			action) val="..." ;;
		esac
		row=${S_TITLE[i]}
		[[ -n "$DSET_QUERY" ]] && row="${DSET_CAT_LABEL[${S_CAT[i]}]}: $row"
		printf -v row '%-34s %s' "${row:0:34}" "$val"
		rows+=("$row")
	done
	DSET_FILLING=1
	if ((${#rows[@]})); then
		tui.list.set lst_items "${rows[@]}"
		((keep >= ${#rows[@]})) && keep=$((${#rows[@]} - 1))
		tui.list.select lst_items "$keep"
	else
		tui.list.clear lst_items
	fi
	DSET_FILLING=0
	if [[ -n "$DSET_QUERY" ]]; then
		tui.pane_title items "Search: ${#rows[@]} match(es)"
	else
		tui.pane_title items "${DSET_CAT_LABEL[$DSET_CUR]}"
	fi
	_dset_details
}

# _dset_selected_index -> _DSET_I : the S_* index of the row under the cursor, -1 for none
_dset_selected_index() {
	local sel
	tui.list.selected lst_items sel
	_DSET_I=-1
	((sel >= 0 && sel < ${#DSET_VIS[@]})) && _DSET_I=${DSET_VIS[sel]}
}

# _dset_details - the right pane: the description (Markdown) and, for Markdown settings, the live preview
_dset_details() {
	local text="" k info
	_dset_selected_index
	if ((_DSET_I < 0)); then
		tui.md.show desc "*No setting matches.*"
		return
	fi
	k=${S_KEY[_DSET_I]}
	text="**${S_TITLE[_DSET_I]}**"$'\n\n'"${S_DESC[_DSET_I]}"$'\n'
	case "$k" in
		plg.browser | kb.editor | chord.* | md.imgproto) ;;
		plg.*)
			info=$(tui.plugin.info "${k#plg.}" 2>/dev/null)
			text+=$'\n'"${info//$'\n'/  $'\n'}"$'\n'
			;;
		md.*) text+=$'\n---\n\n'"$DSET_SAMPLE" ;;
	esac
	tui.md.show desc "$text"
}

# the preview of the Markdown category: everything the renderer draws
read -r -d '' DSET_SAMPLE <<'MD'
# Header 1
## Header 2
### Header 3
#### Header 4
##### Header 5
###### Header 6

*italic*, **bold**, ***bold italic*** and `inline code`.
A [link](https://example.com "title"), an escaped \*star\* and a
second line of the same paragraph.

> a quote
> > nested

- bullet
  - nested bullet
1. numbered
2. list

```bash
echo "code block"
```

| Table | Aligned |
|:------|--------:|
| cell  | right   |

![an image](logo.png), ~~strike~~ and a task list:

- [x] done
- [ ] open

---
MD

# ── page callbacks ───────────────────────────────────────────────────────

dset_visit() {
	DSET_QUERY=""
	_dset_build
	tui.bind / dset_focus_search --page --desc "Search settings"
	tui.update inp_search ""
	_dset_show "$DSET_KEEP_SEL"
	DSET_KEEP_SEL=0
	tui.focus lst_items
}

dset_focus_search() { tui.focus inp_search; }

dset_cat() { # a sidebar button: cat_<category>
	DSET_CUR=${1#cat_}
	DSET_QUERY=""
	tui.update inp_search ""
	_dset_show 0
	tui.focus lst_items
}

# dset_search ID - every edit of the search field: the list filters while you type
dset_search() {
	local q
	tui.get inp_search q
	q=${q,,}
	q=${q//[[:space:]]/ }
	DSET_QUERY=${q# }
	DSET_QUERY=${DSET_QUERY% }
	_dset_show 0
}

dset_search_enter() { tui.focus lst_items; }

dset_moved() { ((DSET_FILLING)) || _dset_details; }

# dset_activate ID - Enter or a double-click on a setting
dset_activate() {
	local sel k name
	tui.list.selected lst_items sel
	_dset_selected_index
	((_DSET_I >= 0)) || return 0
	k=${S_KEY[_DSET_I]}
	case "${S_KIND[_DSET_I]}" in
		toggle)
			_dset_toggle "$k"
			_dset_show "$sel"
			;;
		choice)
			_dset_choices "$k"
			DSET_PICK=$k
			tui.choose "${S_TITLE[_DSET_I]}" dset_picked "${_DSET_CH[@]}" --selected "$_DSET_SEL"
			;;
		radio)
			name=${k#theme.}
			DSET_KEEP_SEL=$sel
			tui.theme.pick "$name" # applies, remembers and reloads this page ("" = page default)
			tui.notify "Theme: $(_dset_pretty "${name:-page default}")" success 2.5
			;;
		action) _dset_act "$k" ;;
	esac
}

dset_picked() { # INDEX ITEM
	local sel
	tui.list.selected lst_items sel
	_dset_apply "$DSET_PICK" "$2"
	_dset_show "$sel"
}

_dset_act() {
	case "$1" in
		kb.editor) tui.action.goto_default keybinds ;;
		plg.browser) tui.action.goto_default plugins ;;
		md.st.*) _dset_open_style "${1#md.st.}" ;;
	esac
}

# ── the Markdown style editor (modal) ────────────────────────────────────

declare -g DSET_MS_CLASS=h1 DSET_MS_COLOR=default DSET_MS_BG=default DSET_MS_FILLING=0
declare -gi DSET_MS_EDIT_BG=0 # 1: the color list and the hex field edit the background

# _dset_ms_target - the list and the hex field show the color of what is being edited (text or background)
_dset_ms_target() {
	local color=$DSET_MS_COLOR i
	((DSET_MS_EDIT_BG)) && color=$DSET_MS_BG
	DSET_MS_FILLING=1
	if [[ "$color" == \#* ]]; then
		tui.update ms_hex "$color"
		tui.list.select ms_colors -1
	else
		tui.update ms_hex ""
		for i in "${!TUI_MD_COLORS[@]}"; do
			[[ "${TUI_MD_COLORS[i]}" == "$color" ]] && tui.list.select ms_colors "$i"
		done
	fi
	DSET_MS_FILLING=0
}

# _dset_ms_fill - shows the current style of DSET_MS_CLASS in the modal's widgets
_dset_ms_fill() {
	local spec color mods m
	tui.md.style_spec_of "$DSET_MS_CLASS" spec
	color=${spec%%:*}
	mods=""
	[[ "$spec" == *:* ]] && mods=${spec#*:}
	DSET_MS_BG=default
	if [[ "$color" == */* ]]; then
		DSET_MS_BG=${color#*/}
		color=${color%%/*}
	fi
	DSET_MS_COLOR=$color
	DSET_MS_EDIT_BG=0
	DSET_MS_FILLING=1
	tui.update ms_elem_lbl "Style of: $DSET_MS_CLASS"
	tui.update ms_bgmode 0
	for m in "${TUI_MD_MODS[@]}"; do
		tui.update "ms_$m" "$([[ ",$mods," == *",$m,"* ]] && echo 1 || echo 0)"
	done
	DSET_MS_FILLING=0
	_dset_ms_target
}

_dset_open_style() { # CLASS
	DSET_MS_CLASS=$1
	_dset_ms_fill
	tui.layer.show dlg_md_style
}

# _dset_ms_apply - builds the spec from the modal's widgets, applies and saves it
_dset_ms_apply() {
	((DSET_MS_FILLING)) && return 0
	local m v mods="" spec sel
	for m in "${TUI_MD_MODS[@]}"; do
		tui.get "ms_$m" v
		[[ "$v" == 1 ]] && mods+="${mods:+,}$m"
	done
	spec=$DSET_MS_COLOR
	[[ -n "$DSET_MS_BG" && "$DSET_MS_BG" != default ]] && spec+="/$DSET_MS_BG"
	spec+=${mods:+:$mods}
	if tui.md.style_spec "$DSET_MS_CLASS" "$spec"; then
		tui.config.set "md.style.$DSET_MS_CLASS" "$spec"
	fi
	tui.list.selected lst_items sel
	_dset_show "$sel"
}

dset_ms_color() {
	((DSET_MS_FILLING)) && return 0
	local i
	tui.list.selected ms_colors i
	((i >= 0)) || return 0
	if ((DSET_MS_EDIT_BG)); then DSET_MS_BG=${TUI_MD_COLORS[i]}; else DSET_MS_COLOR=${TUI_MD_COLORS[i]}; fi
	tui.update ms_hex ""
	_dset_ms_apply
}

dset_ms_hex() { # ID TEXT
	if [[ "${2:-}" =~ ^#[0-9a-fA-F]{6}$ ]]; then
		if ((DSET_MS_EDIT_BG)); then DSET_MS_BG=$2; else DSET_MS_COLOR=$2; fi
		tui.list.select ms_colors -1
		_dset_ms_apply
	else
		tui.notify "Hex color looks like #ff8000" warn 3
	fi
}

dset_ms_mod() { _dset_ms_apply; }

dset_ms_target() { # ID VALUE - the "Edit the background" box
	DSET_MS_EDIT_BG=$2
	_dset_ms_target
}

dset_ms_reset() {
	local sel
	tui.md.style_reset "$DSET_MS_CLASS"
	tui.config.unset "md.style.$DSET_MS_CLASS"
	_dset_ms_fill
	tui.list.selected lst_items sel
	_dset_show "$sel"
}

dset_ms_close() { tui.layer.close dlg_md_style; }
