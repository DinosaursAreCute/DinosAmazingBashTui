# home_anim.t.sh - the Home page hero (share/demo/home_callbacks.sh): dim rain over the whole width, the D A B T banner on it
# with its name typed out, the tagline and the news, all one grid painted with tui.set_canvas.

source "$REPO/share/demo/home_callbacks.sh"

_HA_REAL="$(declare -f tui.set_canvas tui.every tui.every.cancel)"
_ha_setup() { # [RAIN]
	_TUI_P_ROW[home_hero]=1 _TUI_P_COL[home_hero]=1 _TUI_P_H[home_hero]=15 _TUI_P_W[home_hero]=150
	_TUI_P_BORDER[home_hero]=single _TUI_P_BORDER_EXPL[home_hero]=1 _TUI_P_HPAD[home_hero]=0 _TUI_P_VPAD[home_hero]=0 # the content area: 146 x 13
	_HA_OUT="" _HA_EVERY="" _HA_FRAMES=0
	tui.set_canvas() { _HA_OUT="$2" _HA_FRAMES=$((_HA_FRAMES + 1)); } # all three are restored by _ha_done: other tests use the real ones
	tui.every() { _HA_EVERY+="every:$3 "; }
	tui.every.cancel() { _HA_EVERY+="cancel:$1 "; }
	_HOME_TYPED=0 _HOME_WAIT=0 _HOME_CURSOR=1 _HOME_GLINT=4 _HOME_DT=0 _HOME_TIP=0 _HOME_SEED=7 _HOME_W=0 _HOME_H=0 _HOME_RAIN="${1:-0}"
	_home_size
	_home_text_apply
}
_ha_done() { eval "$_HA_REAL"; }
_ha_plain() { sed -E $'s/\x1b\\[C/ /g; s/\x1b\\[[0-9;]*m//g' <<<"$_HA_OUT"; } # a skip cell is one blank cell to the eye
_ha_line() { _ha_plain | sed -n "$1p"; }

t_home_anim_grid_is_the_content_area_with_one_extra_cell_per_row_that_ends_the_line() {
	_ha_setup
	eq "146 13 147" "$_HOME_W $_HOME_H $_HOME_STRIDE"
	_home_paint
	eq 13 "$(_ha_plain | wc -l)"
	eq 1 "$_HA_FRAMES"
	_ha_done
}

t_home_anim_hero_has_the_banner_the_name_row_and_two_pills_in_the_middle_of_the_pane() {
	_ha_setup
	_HOME_CURSOR=0
	_home_text_layer
	_home_text_apply
	_home_paint
	ok '[[ "$(_ha_line 2)" == *"███"* ]]'                                               # the banner starts one row down
	eq "" "$(_ha_line 8 | tr -d ' ')"                                                   # nothing typed yet
	ok '[[ "$(_ha_line 10)" == *"declarative"*"experimental"* ]]'                       # tagline and badge
	ok '[[ "$(_ha_line 11)" == *"NEW"*"${_HOME_TIPS[0]}"* ]]'                           # the news
	ok '[[ "$_HA_OUT" == *"38;2;255;140;191"* && "$_HA_OUT" == *"38;2;255;158;158"* ]]' # D pink ... T red
	ok '[[ "$_HA_OUT" == *"48;2;38;44;66"* ]]'                                          # the pills have a background
	_ha_done
}

t_home_anim_types_a_character_a_tick_quickly_with_short_stops_and_hands_over_to_the_idle_timer() {
	_ha_setup
	local i prev=0 jumps=0
	for ((i = 0; i < 100 && _HOME_TYPED < _HOME_LEN; i++)); do
		_home_type_tick
		((_HOME_TYPED - prev > 1)) && jumps=1
		prev=$_HOME_TYPED
	done
	_home_paint
	eq 0 "$jumps"
	eq 19 "$_HOME_TYPED"
	ok '(( i >= 22 && i <= 45 ))' # fast: about a second and a half at 40 ms a tick
	ok '[[ "$(_ha_line 8)" == *"DinosAmazingBashTui"* ]]'
	eq "cancel:home_type_job every:home_idle_job " "$_HA_EVERY" # the typing timer ends, the cursor / glint timer starts
	_ha_done
}

t_home_anim_each_word_has_its_letters_colour_and_the_idle_tick_blinks_and_glints() {
	_ha_setup
	_HOME_TYPED=19
	_home_text_apply
	_home_paint
	ok '[[ "$_HA_OUT" == *"38;2;255;140;191mD"* ]]' # a cell at a time: the first letter of each word, in its colour
	ok '[[ "$_HA_OUT" == *"38;2;168;216;255mA"* ]]'
	ok '[[ "$_HA_OUT" == *"38;2;255;243;168mB"* ]]'
	ok '[[ "$_HA_OUT" == *"38;2;255;158;158mT"* ]]'
	local cursor=$_HOME_CURSOR glint=$_HOME_GLINT
	_home_idle_tick
	ok '(( _HOME_CURSOR != cursor && _HOME_GLINT != glint ))'
	_ha_done
}

t_home_anim_typed_name_starts_under_the_d_and_ends_under_the_t_of_the_banner() {
	_ha_setup
	_HOME_TYPED=19 _HOME_CURSOR=0
	_home_text_apply
	_home_paint
	local banner name LC_ALL=C.UTF-8 # cells, not bytes
	banner="$(_ha_line 2)" name="$(_ha_line 8)"
	name="${name%"${name##*[! ]}"}" # without the blanks to the pane's edge
	local lead_b=${banner%%[! ]*} lead_n=${name%%[! ]*}
	eq "${#lead_b}" "${#lead_n}"         # the same first column
	eq "$((${#lead_b} + 19))" "${#name}" # exactly as wide as the banner (D A B T and three gaps)
	_ha_done
}

t_home_anim_rain_palette_is_four_dim_colours_of_six_steps_in_256_colour_codes() {
	eq 24 "${#_HR_PAL[@]}"
	local i bad=0
	for i in "${!_HR_PAL[@]}"; do [[ "${_HR_PAL[i]}" =~ ^$'\e'\[38\;5\;([0-9]+)m$ ]] && ((BASH_REMATCH[1] >= 16 && BASH_REMATCH[1] <= 231)) || bad=1; done
	eq 0 "$bad"
	ok '[[ "${_HR_PAL[0]}" != "${_HR_PAL[6]}" && "${_HR_PAL[0]}" != "${_HR_PAL[5]}" ]]' # colours differ by column and fade along the tail
}

t_home_anim_a_new_size_rebuilds_the_grid_and_a_small_pane_is_left_alone() {
	_ha_setup
	_TUI_P_W[home_hero]=100
	_home_on_resize
	eq "96 13 97" "$_HOME_W $_HOME_H $_HOME_STRIDE"
	local maxw=0 row LC_ALL=C.UTF-8
	while IFS= read -r row; do ((${#row} > maxw)) && maxw=${#row}; done < <(_ha_plain)
	ok '(( maxw <= 96 ))' # the frame follows the pane at once
	_HA_FRAMES=0
	_TUI_P_W[home_hero]=20
	_home_type_tick # too small for the hero: no paint, no error
	eq 0 "$_HA_FRAMES"
	_ha_done
}

t_home_anim_tagline_shortens_in_a_narrow_pane_and_the_news_rotates() {
	_ha_setup
	local i
	for ((i = 0; i < ${#_HOME_TIPS[@]}; i++)); do _home_tip_tick; done
	_home_paint
	ok '[[ "$(_ha_line 11)" == *"${_HOME_TIPS[0]}"* ]]' # a full round
	_home_tip_tick
	_home_paint
	ok '[[ "$(_ha_line 11)" == *"${_HOME_TIPS[1]}"* ]]'
	_TUI_P_W[home_hero]=90
	_home_size
	_home_text_apply
	_home_paint
	ok '[[ "$(_ha_line 10)" == *"declarative"*"experimental"* && "$(_ha_line 10)" != *"awk"* ]]'
	_ha_done
}

t_home_anim_tagline_badge_and_news_take_their_colours_from_the_theme_classes() {
	_ha_setup
	_TUI_CLASS_FG[home_tag]="#112233" _TUI_CLASS_BG[home_tag]="#445566"
	_TUI_CLASS_FG[home_badge]="#010203" _TUI_CLASS_BG[home_badge]="#040506"
	_TUI_CLASS_FG[home_new]="#0a0b0c" _TUI_CLASS_BG[home_new]="#0d0e0f"
	_TUI_CLASS_FG[home_news]="#707172" _TUI_CLASS_BG[home_news]="#808182"
	_HOME_W=0 # a new visit builds the parts again, reading the classes
	_home_size
	_home_text_apply
	_home_paint
	ok '[[ "$_HA_OUT" == *"38;2;17;34;51;48;2;68;85;102m"* ]]'      # .home_tag
	ok '[[ "$_HA_OUT" == *"38;2;1;2;3;48;2;4;5;6m"* ]]'             # .home_badge
	ok '[[ "$_HA_OUT" == *"38;2;10;11;12;48;2;13;14;15m"* ]]'       # .home_new
	ok '[[ "$_HA_OUT" == *"38;2;112;113;114;48;2;128;129;130m"* ]]' # .home_news
	ok '[[ "$_HA_OUT" != *"48;2;38;44;66"* ]]'                      # none of the fallback
	unset '_TUI_CLASS_FG[home_tag]' '_TUI_CLASS_BG[home_tag]' '_TUI_CLASS_FG[home_badge]' '_TUI_CLASS_BG[home_badge]' \
		'_TUI_CLASS_FG[home_new]' '_TUI_CLASS_BG[home_new]' '_TUI_CLASS_FG[home_news]' '_TUI_CLASS_BG[home_news]'
	_ha_done
}

# ── the rain painter's frame ──────────────────────────────────────────────

_ha_rain_setup() { # W H - a grid and an empty mask, as the painter has them after reading the published files
	_HOME_W=$1 _HOME_H=$2 _HOME_STRIDE=$(($1 + 1)) _HOME_DT=0 _HOME_SEED=7
	_HR_MASK=()
	_home_rain_init
}

t_home_anim_painter_frame_is_cursor_moves_inside_the_pane_in_one_synchronised_block() {
	_ha_rain_setup 80 13
	local i
	for ((i = 0; i < 40; i++)); do
		_HOME_DT=$((_HOME_DT + 1))
		_home_rain_frame 5 3 $'\e[48;2;1;2;3m'
	done
	ok '[[ "$_HR_OUT" == $'"'"'\e[48;2;1;2;3m'"'"'* ]]' # the style first; tui.async.emit wraps and cuts it
	local -a moves
	local bad=0 m r c
	while IFS=';' read -r r c; do
		[[ -n "$r" ]] || continue
		((r >= 5 && r < 5 + 13 && c >= 3 && c < 3 + 80)) || bad=1
	done < <(grep -o $'\e\\[[0-9]*;[0-9]*H' <<<"$_HR_OUT" | sed -E $'s/\e\\[([0-9]+;[0-9]+)H/\\1/')
	eq 0 "$bad"
}

t_home_anim_painter_frame_sends_only_changes_and_blanks_what_the_rain_left() {
	_ha_rain_setup 80 13
	local i first
	for ((i = 0; i < 40; i++)); do
		_HOME_DT=$((_HOME_DT + 1))
		_home_rain_frame 1 1 ""
	done
	local before=${#_HR_PREV[@]}
	ok '(( before > 20 ))' # a screenful of drops
	_HOME_DT=$((_HOME_DT + 1))
	_home_rain_frame 1 1 ""
	first="$_HR_OUT"
	ok '(( ${#first} < 3500 ))'
	_home_rain_frame 1 1 "" # the same tick again: nothing changed, nothing to send
	eq "" "$_HR_OUT"
	_HR_PREV[5]=$'\e[38;5;100mx' # a cell the rain no longer has
	_home_rain_frame 1 1 ""
	ok '[[ "$_HR_OUT" == *$'"'"'\e[1;6H '"'"'* ]]' # idx 5 is row 0, column 5: blanked at row 1, column 6 of the screen
}

t_home_anim_painter_never_draws_on_the_text_and_the_mask_comes_from_the_published_cells() {
	_ha_rain_setup 80 13
	local i k bad=0
	for ((i = 0; i < 400 && ${#_HR_PREV[@]} == 0; i++)); do
		_HOME_DT=$((_HOME_DT + 1))
		_home_rain_frame 1 1 ""
	done
	for k in "${!_HR_PREV[@]}"; do _HR_MASK[$k]=1; done # the text now covers everything the rain had drawn
	_HR_PREV=()
	for ((i = 0; i < 60; i++)); do
		_HOME_DT=$((_HOME_DT + 1))
		_home_rain_frame 1 1 ""
		for k in "${!_HR_PREV[@]}"; do [[ -n "${_HR_MASK[$k]:-}" ]] && bad=1; done
	done
	eq 0 "$bad"
}

t_home_anim_publish_tells_the_painter_the_rect_the_mask_and_the_style() {
	_ha_setup
	local saved_put saved_active
	saved_put="$(declare -f tui.async.put)" saved_active="$(declare -f tui.async.active)"
	local log=""
	tui.async.active() { return 0; }
	tui.async.put() { log+="$2=$3;"; }
	_TUI_STYLE_BG[home_hero_normal]="#102030"
	_HOME_VER=0
	_home_publish
	ok '[[ "$log" == *"rect=2 3 146 13 147;"*"mask="*"style="*"ver=1;"* ]]'
	eval "$saved_put"
	eval "$saved_active"
	_ha_done
}

t_home_anim_rain_repeats_exactly_every_loop_length_so_the_bake_can_replay_it() {
	_ha_rain_setup 80 13
	local t a b bad=0
	eq 0 $((_HR_ROWS % 6))
	eq $((6 * _HR_ROWS)) "$_HR_L"
	for t in 0 1 7 50 $((_HR_L - 1)); do
		_home_rain_state "$t"
		a="$(declare -p _HR_NOW)"
		_home_rain_state $((t + _HR_L))
		b="$(declare -p _HR_NOW)"
		[[ "$a" == "$b" ]] || bad=1
	done
	eq 0 "$bad"
}

t_home_anim_rain_is_the_same_for_the_same_size_on_every_run_and_moves_between_ticks() {
	_ha_rain_setup 80 13
	local a b
	_home_rain_state 10
	a="$(declare -p _HR_NOW)"
	_ha_rain_setup 80 13
	_home_rain_state 10
	eq "$a" "$(declare -p _HR_NOW)"
	_home_rain_state 12
	ok '[[ "$a" != "$(declare -p _HR_NOW)" ]]'
}

t_home_anim_rain_mask_is_fixed_rectangles_that_do_not_follow_the_text() {
	_ha_setup
	local a
	_home_mask_cells
	a="$_HOME_MASKSTR"
	ok '[[ -n "$a" ]]'
	_HOME_TIP=3 _HOME_TYPED=7
	_home_mask_cells
	eq "$a" "$_HOME_MASKSTR"
	local top=$(((_HOME_H - 11) / 2)) x=$(((_HOME_W - 19) / 2))
	ok '[[ " $a " == *" $((top * _HOME_STRIDE + x)) "* ]]'                 # a cell of the banner
	ok '[[ " $a " == *" $(((top + 8) * _HOME_STRIDE + _HOME_W / 2)) "* ]]' # a cell of the tagline
	_ha_done
}
