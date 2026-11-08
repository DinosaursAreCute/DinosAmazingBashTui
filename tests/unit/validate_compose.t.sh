# validate_compose.t.sh - validator vocabulary for the composition and addon tags (lib/markup/tui_validate_rules.sh).
# Reuses _vf_check from validate_focus.t.sh.

ti_validate_compose_tags_are_known() {
	_vf_check '<template name="t">
<label id="l" pane="p" row="0" text="x"/>
</template>
<use template="t" id="u">
<fill slot="s">
<label id="m" pane="p" row="1" text="y"/>
</fill>
</use>
<for each="a b" as="x">
<label id="l_{{@x}}" pane="p" row="2" text="{{@x}}"/>
</for>
<if test="a==a">
<label id="q" pane="p" row="3" text="z"/>
<else>
<label id="r" pane="p" row="4" text="z"/>
</else>
</if>
<component name="box" src="box.xml"/>'
	eq "" "$_VF"
}

ti_validate_missing_required_compose_attributes_are_errors() {
	_vf_check '<template/>
<use/>
<if/>'
	match "$_VF" "template"
	match "$_VF" "test"
}

ti_validate_component_name_becomes_a_tag_for_that_page_only() {
	_vf_check '<component name="box" src="box.xml"/>
<box title="T"/>'
	eq "" "$_VF"
	_vf_check '<box title="T"/>'
	match "$_VF" "unknown tag <box>"
}

ti_validate_widget_inside_a_pane_needs_no_pane_or_row() {
	_vf_check '<label id="a" text="x"/>'
	eq "" "$_VF"
}

ti_validate_widget_directly_under_tui_needs_pane_and_row() {
	printf '<tui>\n<label id="a" text="x"/>\n</tui>\n' >"$HOME/vw.xml"
	tui.validate.files "$HOME/vw.xml"
	match "${_TV_F_MSG[*]}" "missing the required attribute 'pane'"
	match "${_TV_F_MSG[*]}" "missing the required attribute 'row'"
}

ti_validate_addon_file_is_a_document_of_its_own() {
	printf '<addon id="a" target="*">\n<append ref="#x">\n<label id="l" text="x"/>\n</append>\n</addon>\n' >"$HOME/va.xml"
	tui.validate.files "$HOME/va.xml"
	eq "0" "$TUI_V_ERRORS"
}
