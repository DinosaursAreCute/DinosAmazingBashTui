# chart.t.sh - lib/render/tui_chart.sh: charts as strings, from values or from a dataset.

t_chart_spark_scales_between_the_smallest_and_the_largest_value() {
	tui.chart.spark out 1 5 3 9 2
	eq "▁▄▂█▁" "$out"
	tui.chart.spark out 0 100
	eq "▁█" "$out"
}

t_chart_spark_flat_data_draws_the_middle_glyph() {
	tui.chart.spark out 4 4 4
	eq "▄▄▄" "$out"
}

t_chart_spark_width_keeps_the_newest_values_and_pads_the_left() {
	tui.chart.spark out -w 3 1 2 3 4 5
	eq "▁▄█" "$out"
	tui.chart.spark out -w 5 1 9
	eq "   ▁█" "$out"
}

t_chart_spark_accepts_a_fixed_scale_and_decimals() {
	tui.chart.spark out -n 0 -m 10 5 20 -3
	eq "▄█▁" "$out"
	tui.chart.spark out 0.5 1.5
	eq "▁█" "$out"
}

t_chart_spark_does_not_shadow_the_callers_names() {
	local n=1 w=2 v=3 i=4 _var=5
	tui.chart.spark out 1 2 3
	eq "1 2 3 4" "$n $w $v $i"
	eq "▁▄█" "$out"
}

t_chart_gauge_draws_a_bar_and_the_percent() {
	tui.chart.gauge g 42 100 -w 10
	eq "████░░░░░░ 42%" "$g"
	tui.chart.gauge g 150 100 -w 4
	eq "████ 100%" "$g"
	tui.chart.gauge g -5 100 -w 4
	eq "░░░░ 0%" "$g"
	tui.chart.gauge g 5 20 -w 4
	eq "█░░░ 25%" "$g"
}

t_chart_gauge_without_max_means_a_hundred() {
	tui.chart.gauge g 50 -w 10
	eq "█████░░░░░ 50%" "$g"
}

t_chart_unknown_kind_fails() {
	ok '! tui.chart nothing out "x"'
	ok '! tui.chart sparkline'
}

ti_chart_sparkline_and_hbar_read_a_dataset() {
	tui.data.new ch_lat --cols "host|ms"
	tui.data.append ch_lat "a|1" "b|5" "c|3" "d|9"
	tui.chart sparkline sp --data ch_lat --col ms
	local plain="${sp//$'\e['*([0-9;])m/}"
	eq "▁▄▂█" "${plain//[^▁▂▃▄▅▆▇█]/}"
	tui.chart hbar hb --data ch_lat --col ms --label host -w 20
	local lines=()
	mapfile -t lines <<<"$hb"
	eq 4 "${#lines[@]}"
	match "${lines[3]}" '^d '
	tui.data.drop ch_lat
}

ti_chart_last_limits_the_rows_and_linechart_takes_one_series_per_col() {
	tui.data.new ch_two --cols "a|b"
	tui.data.append ch_two "1|9" "2|8" "3|7" "4|6"
	tui.chart sparkline sp --data ch_two --col a --last 2
	local plain="${sp//$'\e['*([0-9;])m/}"
	eq "▁█" "${plain//[^▁▂▃▄▅▆▇█]/}"
	tui.chart linechart ln --data ch_two --col a --col b -w 30 -h 5
	ok '[[ -n "$ln" ]]'
	ok '! tui.chart box bx --data ch_two --col a'
	tui.data.drop ch_two
}

ti_chart_every_renderer_kind_returns_lines() {
	local k out csv="$_T_ROOT/ch_$RANDOM.csv"
	printf '%s\n' 'x,y' '1,2' '2,4' '3,3' >"$csv"
	TR_WIDTH=60
	local -A args=([box]='hi' [divider]='' [alert]='info|x' [table]='A|B|1|2' [kv]='a: b' [hbar]='A:1|B:2' [vbar]='A:1|B:2'
		[gauge]='50' [sparkline]='1 2 3' [linechart]='S:1,2,3' [csv_hbar]="$csv" [csv_vbar]="$csv" [csv_linechart]="$csv"
		[scatter]='S:1,1 2,2' [boxplot]='A:1,2,3,4' [forest]='A:1,2,3' [heatmap]='|a|b|a|1|0.5|b|0.5|1' [histogram]='1 2 3 4 5'
		[banner]='HI' [tree]='root|  child' [columns]='a|b' [badges]='pass:x' [list]='a|b' [quote]='q')
	local IFS_KEEP="$IFS" parts
	for k in "${!args[@]}"; do
		IFS='|' read -ra parts <<<"${args[$k]}"
		IFS="$IFS_KEEP"
		[[ "$k" == table ]] && parts=("A|B" "1|2")
		[[ "$k" == heatmap ]] && parts=("|a|b" "a|1|0.5" "b|0.5|1")
		out=""
		tui.chart "$k" out "${parts[@]}" || _t_fail "tui.chart $k failed"
		[[ -n "$out" ]] || _t_fail "tui.chart $k gave nothing"
	done
}

ti_chart_of_an_empty_dataset_is_empty_and_never_reads_stdin() {
	tui.data.new ch_empty --cols "v"
	local out="x"
	tui.chart hbar out --data ch_empty --col v --label v </dev/null
	eq "" "$out"
	tui.chart linechart out --data ch_empty --col v </dev/null
	eq "" "$out"
	tui.data.drop ch_empty
}

ti_chart_colours_come_out_as_escapes_not_as_the_text_033() {
	local out
	tui.chart boxplot out "A:1,2,3,4,5" "B:2,3,4,5,9" -w 30
	[[ "$out" != *'\033'* ]] || _t_fail "a literal \\033 is left in the boxplot"
	[[ "$out" == *$'\e['* ]] || _t_fail "no real escape in the boxplot"
}

ti_chart_class_puts_the_class_colours_back_after_every_reset() {
	local out sgr
	printf '%s\n' '.ch_cls { fg: red; bg: blue; }' >"$_T_ROOT/ch_cls.css"
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=()
	_tui.theme_parse "$_T_ROOT/ch_cls.css"
	_tui.theme_commit
	tui.class.sgr ch_cls
	sgr="$TUI_SGR"
	tui.chart boxplot out "A:1,2,3,4,5" -w 30 --class ch_cls
	eq "$sgr" "${out:0:${#sgr}}"
	[[ "$out" == *$'\e[0m'"$sgr"* ]] || _t_fail "the class colours do not come back after a reset"
}

t_chart_a_size_flag_that_is_not_a_number_is_refused_not_looped_on() {
	local out="keep"
	tui.chart linechart out "cpu:1,2,3" -w fit -h fit 2>/dev/null
	eq 1 "$?"
	eq "keep" "$out"
	tui.chart hbar out "a:1" -w 20 -m abc 2>/dev/null
	eq 1 "$?"
	tui.chart hbar out "a:1" -w 20 -m 100 -n 0
	eq 0 "$?"
}

ti_chart_list_keeps_its_numbered_flag() {
	local out
	tui.chart list out -n "first" "second"
	eq 0 "$?"
	[[ "$out" == *1* ]] || _t_fail "the list is not numbered"
}
