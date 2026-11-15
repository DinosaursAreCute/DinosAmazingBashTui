# data.t.sh - lib/state/tui_data.sh: datasets that code appends to, changes and removes (no page, no terminal).

_dt_drop() {
	local n
	for n in "$@"; do tui.data.drop "$n" 2>/dev/null; done
	return 0
}

t_data_append_count_get_and_at_by_index() {
	tui.data.new dt_a --cols "n|ms"
	tui.data.append dt_a "1|10" "2|20"
	tui.data.count dt_a n
	tui.data.get dt_a 1 row
	eq "2 2|20" "$n $row"
	tui.data.cell dt_a 0 ms ms
	eq 10 "$ms"
	_dt_drop dt_a
}

t_data_the_callers_variable_names_are_not_shadowed() {
	tui.data.new dt_b --cols "x|y"
	tui.data.append dt_b "1|2"
	local c=keep i=keep n=keep out=keep rows=keep
	tui.data.count dt_b n
	tui.data.col dt_b y c
	tui.data.rows dt_b rows
	tui.data.get dt_b 0 out
	eq "1 2 1|2" "$n ${c[*]} $out"
	eq "1|2" "${rows[*]}"
	_dt_drop dt_b
}

t_data_keyed_append_replaces_the_row_with_that_key() {
	tui.data.new dt_k --cols "host|ms" --key host
	tui.data.append dt_k "a|1" "b|2"
	tui.data.append dt_k "a|9"
	tui.data.count dt_k n
	tui.data.cell dt_k a ms v
	eq "2 9" "$n $v"
	ok 'tui.data.has dt_k b'
	ok '! tui.data.has dt_k zzz'
	_dt_drop dt_k
}

t_data_set_changes_one_cell_and_replace_a_whole_row() {
	tui.data.new dt_s --cols "id|a|b" --key id
	tui.data.append dt_s "x|1|2"
	tui.data.set dt_s x b 7
	tui.data.get dt_s x row
	eq "x|1|7" "$row"
	tui.data.replace dt_s x "y|5|6"
	ok '! tui.data.has dt_s x'
	tui.data.get dt_s y row
	eq "y|5|6" "$row"
	ok '! tui.data.set dt_s nope a 1'
	ok '! tui.data.set dt_s y zzz 1'
	_dt_drop dt_s
}

t_data_set_pads_a_short_row() {
	tui.data.new dt_p --cols "a|b|c"
	tui.data.append dt_p "1"
	tui.data.set dt_p 0 c 3
	tui.data.get dt_p 0 row
	eq "1||3" "$row"
	_dt_drop dt_p
}

t_data_remove_by_key_and_by_index_rebuilds_the_index() {
	tui.data.new dt_r --cols "id|v" --key id
	tui.data.append dt_r "a|1" "b|2" "c|3" "d|4"
	tui.data.remove dt_r b c nope
	tui.data.count dt_r n
	tui.data.cell dt_r d v v
	eq "2 4" "$n $v"
	tui.data.new dt_r2
	tui.data.append dt_r2 x y z
	tui.data.remove dt_r2 1
	tui.data.rows dt_r2 all
	eq "x z" "${all[*]}"
	_dt_drop dt_r dt_r2
}

t_data_max_drops_the_oldest_row_and_its_key() {
	tui.data.new dt_m --cols "id" --key id --max 3
	tui.data.append dt_m 1 2 3 4 5
	tui.data.rows dt_m all
	eq "3 4 5" "${all[*]}"
	ok '! tui.data.has dt_m 1'
	ok 'tui.data.has dt_m 5'
	tui.data.rows dt_m last --last 2
	eq "4 5" "${last[*]}"
	_dt_drop dt_m
}

t_data_max_keeps_working_after_many_appends() {
	local i saved=$_TD_COMPACT_AT
	_TD_COMPACT_AT=20 # the head moves past it several times
	tui.data.new dt_big --max 5
	for ((i = 0; i < 120; i++)); do tui.data.append dt_big "$i"; done
	tui.data.rows dt_big all
	eq "115 116 117 118 119" "${all[*]}"
	tui.data.get dt_big 0 row
	eq 115 "$row"
	_TD_COMPACT_AT=$saved
	_dt_drop dt_big
}

t_data_clear_empties_but_keeps_the_dataset() {
	tui.data.new dt_c
	tui.data.append dt_c a b
	tui.data.clear dt_c
	tui.data.count dt_c n
	eq 0 "$n"
	tui.data.append dt_c z
	tui.data.get dt_c 0 row
	eq z "$row"
	_dt_drop dt_c
}

t_data_find_returns_the_key_or_the_index() {
	tui.data.new dt_f --cols "id|n" --key id
	tui.data.append dt_f "a|x" "b|y"
	tui.data.find dt_f n y found
	eq b "$found"
	ok '! tui.data.find dt_f n nothing found'
	tui.data.new dt_f2
	tui.data.append dt_f2 p q
	tui.data.find dt_f2 0 q found
	eq 1 "$found"
	_dt_drop dt_f dt_f2
}

t_data_stat_handles_decimals_and_skips_text() {
	tui.data.new dt_n --cols "v"
	tui.data.append dt_n 10 2.5 abc 7.25
	tui.data.stat dt_n v sum s
	tui.data.stat dt_n v min lo
	tui.data.stat dt_n v max hi
	tui.data.stat dt_n v avg av
	tui.data.stat dt_n v count c
	eq "19.75 2.5 10 6.583 3" "$s $lo $hi $av $c"
	_dt_drop dt_n
}

t_data_stat_of_nothing_is_empty_and_fails_except_sum_and_count() {
	tui.data.new dt_e --cols "v"
	tui.data.stat dt_e v sum s
	tui.data.stat dt_e v count c
	ok '! tui.data.stat dt_e v max m'
	eq "0 0 " "$s $c $m"
	ok '! tui.data.stat dt_e v nope x'
	_dt_drop dt_e
}

t_data_sort_by_text_numbers_and_descending_is_stable() {
	tui.data.new dt_o --cols "k|v"
	tui.data.append dt_o "b|10" "a|9" "c|100" "a|8"
	tui.data.sort dt_o k
	tui.data.col dt_o v vs
	eq "9 8 10 100" "${vs[*]}"
	tui.data.sort dt_o v --num
	tui.data.col dt_o v vs
	eq "8 9 10 100" "${vs[*]}"
	tui.data.sort dt_o v --num --desc
	tui.data.col dt_o v vs
	eq "100 10 9 8" "${vs[*]}"
	_dt_drop dt_o
}

t_data_sort_keeps_the_key_index_right() {
	tui.data.new dt_ok --cols "id|v" --key id
	tui.data.append dt_ok "a|3" "b|1" "c|2"
	tui.data.sort dt_ok v --num
	tui.data.cell dt_ok c v v
	tui.data.get dt_ok 0 row 2>/dev/null
	eq 2 "$v"
	_dt_drop dt_ok
}

t_data_generation_grows_with_every_change() {
	tui.data.new dt_g
	tui.data.gen dt_g g0
	tui.data.append dt_g a
	tui.data.gen dt_g g1
	tui.data.remove dt_g 0
	tui.data.gen dt_g g2
	ok '((g1 > g0 && g2 > g1))'
	_dt_drop dt_g
}

t_data_new_on_an_existing_dataset_keeps_its_rows() {
	tui.data.new dt_x --cols a
	tui.data.append dt_x 1
	tui.data.new dt_x --cols a
	tui.data.count dt_x n
	eq 1 "$n"
	ok '! tui.data.new "bad name"'
	ok '! tui.data.new dt_y --scope nowhere'
	_dt_drop dt_x
}

t_data_unknown_dataset_fails_every_call() {
	ok '! tui.data.append nothing_here x'
	ok '! tui.data.count nothing_here'
	ok '! tui.data.get nothing_here 0 v'
	ok '! tui.data.remove nothing_here 0'
}

t_data_disk_scope_round_trips_rows_with_odd_characters() {
	local saved_home="${TUI_HOME:-}"
	TUI_HOME="$_T_ROOT/data_home_$RANDOM"
	tui.data.new dt_d --cols "a|b" --scope disk
	tui.data.append dt_d 'x\y|1' 'two|3'
	tui.data.save dt_d
	tui.data.clear dt_d
	tui.data.load dt_d
	tui.data.rows dt_d all
	eq 'x\y|1 two|3' "${all[*]}"
	_dt_drop dt_d
	tui.data.new dt_d --cols "a|b" --scope disk
	tui.data.count dt_d n
	eq 2 "$n" # a new dataset of disk scope reads its file
	_dt_drop dt_d
	TUI_HOME="$saved_home"
}

t_data_page_scope_goes_when_the_page_does() {
	tui.data.new dt_pg --scope page
	tui.data.new dt_ss --scope session
	tui.data.append dt_pg a
	tui.data.append dt_ss a
	_td.reset
	ok '! tui.data.has dt_pg 0'
	ok 'tui.data.has dt_ss 0'
	_dt_drop dt_ss
}

# ── widgets bound to a dataset ────────────────────────────────────────────

_dt_page() { # XML -> loads it as a page at 80x24
	local d="$_T_ROOT/dt_page_$RANDOM$RANDOM"
	mkdir -p "$d"
	printf '%s\n' "$1" >"$d/p.xml"
	tui.reset_ui >/dev/null
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_MARKUP_DIR="$d"
	tui.load "$d/p.xml" >"$d/out" 2>"$d/err"
	_DT_ERR="$(<"$d/err")"
}

ti_data_markup_binds_label_spark_gauge_list_and_table() {
	_dt_page '<tui>
  <data name="dm_lat" cols="host|ms" key="host"/>
  <pane id="root" split="v">
    <label id="dm_l" from="dm_lat" col="ms" format="now %s ms"/>
    <spark id="dm_s" from="dm_lat" col="ms" last="4"/>
    <gauge id="dm_g" from="dm_lat" col="ms" max="10" width="10"/>
    <list id="dm_list" from="dm_lat" col="host"/>
    <table id="dm_t" from="dm_lat"/>
  </pane>
</tui>'
	eq "" "$_DT_ERR"
	tui.data.append dm_lat "a|2" "b|8"
	tui.data.flush
	eq "now 8 ms" "${_TUI_W_LABEL[dm_l]}"
	eq "▁█" "${_TUI_W_LABEL[dm_s]}"
	eq "████████░░ 80%" "${_TUI_W_LABEL[dm_g]}"
	tui.data.append dm_lat "c|5"
	tui.data.flush
	eq "now 5 ms" "${_TUI_W_LABEL[dm_l]}"
	tui.data.drop dm_lat
	tui.reset_ui >/dev/null
}

ti_data_flush_redraws_only_when_the_shown_text_changed() {
	_dt_page '<tui>
  <data name="dm_one" cols="v"/>
  <pane id="root" split="v"><label id="dm_o" from="dm_one" col="v"/></pane>
</tui>'
	tui.data.append dm_one 5
	tui.data.flush
	local calls=0 saved_fn
	saved_fn="$(declare -f tui.set_label)"
	tui.set_label() { ((calls++)); }
	tui.data.set dm_one 0 v 5 # same text
	tui.data.flush
	eq 0 "$calls"
	tui.data.set dm_one 0 v 6
	tui.data.flush
	eq 1 "$calls"
	eval "$saved_fn"
	tui.data.drop dm_one
	tui.reset_ui >/dev/null
}

ti_data_callback_changes_show_after_the_callback_returns() {
	_dt_page '<tui>
  <data name="dm_cb" cols="v"/>
  <pane id="root" split="v"><label id="dm_c" from="dm_cb" col="v"/></pane>
</tui>'
	dm_cb_fn() {
		tui.data.append dm_cb 1
		tui.data.append dm_cb 2
	}
	_tui.batch_call dm_cb_fn
	eq 2 "${_TUI_W_LABEL[dm_c]}"
	unset -f dm_cb_fn
	tui.data.drop dm_cb
	tui.reset_ui >/dev/null
}

ti_data_chart_tag_fills_a_pane_with_the_rendered_chart() {
	_dt_page '<tui>
  <data name="dm_ch" cols="v"/>
  <pane id="root" split="v"><chart id="dm_chart" from="dm_ch" type="hbar" col="v" label="v" args="-w 20"/></pane>
</tui>'
	eq "" "$_DT_ERR"
	tui.data.append dm_ch 3 7
	tui.data.flush
	ok '(( ${#_TUI_PANE_CONTENT_dm_chart[@]} == 2 ))'
	tui.data.drop dm_ch
	tui.reset_ui >/dev/null
}

ti_data_declaration_survives_a_page_replay_and_page_scope_does_not() {
	_dt_page '<tui>
  <data name="dm_ses" cols="v"/>
  <data name="dm_pg" cols="v" scope="page"/>
  <pane id="root" split="v"><label id="dm_x" from="dm_ses" col="v"/></pane>
</tui>'
	tui.data.append dm_ses 1
	tui.data.append dm_pg 1
	_td.reset
	ok 'tui.data.has dm_ses 0'
	ok '! tui.data.has dm_pg 0'
	tui.data.drop dm_ses
	tui.reset_ui >/dev/null
}

ti_data_validator_knows_the_tags_and_their_options() {
	local d="$_T_ROOT/dt_val_$RANDOM"
	mkdir -p "$d"
	printf '%s\n' '<tui>' '  <data name="v" cols="a" scope="page"/>' '  <pane id="root" split="v">' '    <spark id="s" from="v"/>' '    <gauge id="g" from="v" max="9"/>' '    <chart id="c" from="v" type="hbar"/>' '  </pane>' '</tui>' >"$d/ok.xml"
	printf '%s\n' '<tui>' '  <data cols="a" scope="nowhere"/>' '  <pane id="root" split="v">' '    <spark id="s"/>' '    <chart id="c" from="v" type="pie"/>' '  </pane>' '</tui>' >"$d/bad.xml"
	tui.validate.files "$d/ok.xml"
	tui.validate.messages
	eq "" "${_TV_LINES[*]}"
	tui.validate.files "$d/bad.xml"
	tui.validate.messages
	local out="${_TV_LINES[*]}"
	ok '[[ "$out" == *"name"* && "$out" == *"scope"* && "$out" == *"type"* ]]'
}

ti_data_chart_binding_takes_several_columns_and_a_later_binding() {
	_dt_page '<tui>
  <data name="dm_two" cols="cpu|mem"/>
  <pane id="root" split="v"><chart id="dm_c2" type="linechart" args="-w 20 -h 4"/></pane>
</tui>'
	eq "" "$_DT_ERR"
	tui.data.append dm_two "10|20" "30|40" "20|60"
	tui.data.bind dm_two dm_c2 chart type=linechart col=cpu,mem 'args=-w 20 -h 4'
	tui.data.flush
	ok '(( ${#_TUI_PANE_CONTENT_dm_c2[@]} > 3 ))'
	ok '[[ "${_TUI_PANE_CONTENT_dm_c2[*]}" == *cpu* && "${_TUI_PANE_CONTENT_dm_c2[*]}" == *mem* ]]'
	tui.data.drop dm_two
	tui.reset_ui >/dev/null
}

ti_data_table_binding_can_show_some_of_the_columns() {
	_dt_page '<tui>
  <data name="dm_sh" cols="name|state|cpu" key="name"/>
  <pane id="root" split="v"><table id="dm_tsh" from="dm_sh" show="name,cpu"/></pane>
</tui>'
	tui.data.append dm_sh "a|up|10" "b|down|20"
	tui.data.flush
	tui.table.row dm_tsh 1 row
	eq "b|20" "$row"
	tui.data.drop dm_sh
	tui.reset_ui >/dev/null
}

ti_data_gauge_levels_restyle_by_the_value() {
	_dt_page '<tui>
  <data name="dm_lv" cols="v"/>
  <pane id="root" split="v"><gauge id="dm_gl" from="dm_lv" max="100" width="10" levels="60,85"/></pane>
</tui>'
	tui.data.append dm_lv 10
	tui.data.flush
	eq "gauge_ok" "${_TD_CLASS[dm_gl]}"
	tui.data.append dm_lv 70
	tui.data.flush
	eq "gauge_warn" "${_TD_CLASS[dm_gl]}"
	tui.data.append dm_lv 90
	tui.data.flush
	eq "gauge_crit" "${_TD_CLASS[dm_gl]}"
	tui.data.drop dm_lv
	tui.reset_ui >/dev/null
}

ti_data_table_heat_option_reaches_tui_table_heat_by_header_name() {
	_dt_page '<tui>
  <data name="dm_ht" cols="name|cpu|mem"/>
  <pane id="root" split="v"><table id="dm_th" from="dm_ht" show="name,mem" heat="mem:60:85"/></pane>
</tui>'
	local calls="" saved
	saved="$(declare -f tui.table.heat)"
	tui.table.heat() { calls+="$*;"; }
	tui.data.append dm_ht "a|1|90"
	tui.data.flush
	eval "$saved"
	eq "dm_th 1 60 85;" "$calls" # mem is column 1 of the shown header (name|mem)
	tui.data.drop dm_ht
	tui.reset_ui >/dev/null
}

t_data_fit_is_the_pane_content_width_less_the_padding() {
	local saved
	saved="$(declare -f _tui._content_rect)"
	_tui._content_rect() { _CR_W=40 _CR_H=12; }
	_TUI_W_PANE[dm_fw]=dm_fp
	_td.fit dm_fw
	eq 38 "$_TDF"
	_td.fit dm_fw 5
	eq 35 "$_TDF"
	_td.fit_h dm_fp
	eq 9 "$_TDF"
	eval "$saved"
	unset '_TUI_W_PANE[dm_fw]'
}

ti_data_label_and_gauge_can_show_one_row_of_a_keyed_dataset() {
	_dt_page '<tui>
  <data name="dm_kd" cols="name|cpu" key="name"/>
  <pane id="root" split="v">
    <label id="dm_kl" from="dm_kd" col="cpu" key="b" format="cpu %s"/>
    <gauge id="dm_kg" from="dm_kd" col="cpu" key="b" max="100" width="10"/>
  </pane>
</tui>'
	tui.data.append dm_kd "a|10" "b|50" "c|90"
	tui.data.flush
	eq "cpu 50" "${_TUI_W_LABEL[dm_kl]}"
	eq "█████░░░░░ 50%" "${_TUI_W_LABEL[dm_kg]}"
	tui.data.set dm_kd b cpu 80
	tui.data.flush
	eq "cpu 80" "${_TUI_W_LABEL[dm_kl]}"
	tui.data.drop dm_kd
	tui.reset_ui >/dev/null
}
