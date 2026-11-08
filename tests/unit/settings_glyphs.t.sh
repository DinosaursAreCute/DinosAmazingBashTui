# settings_glyphs.t.sh - the Glyphs part of the default Settings page (share/defaults/pages/settings_callbacks.sh).

_sg_load() {
	source "$REPO/share/defaults/pages/settings_callbacks.sh"
	_TUI_G=() _TUI_G_USER=() _TUI_V_DEFAULT=() _TUI_W_VARIANT=()
}

ti_settings_glyphs_sample_shows_each_type_with_the_custom_design() {
	_sg_load
	tui.glyph.user progress fill "#"
	tui.glyph.user progress empty "-"
	_dset_gl_sample progress
	eq "#######-----  60%" "$_DSET_SAMPLE"
	tui.glyph.user checkbox left "("
	tui.glyph.user checkbox on "*"
	tui.glyph.user checkbox right ")"
	_dset_gl_sample checkbox
	eq "(*) on   ( ) off" "$_DSET_SAMPLE" # custom left and right brackets apply to both marks
	tui.glyph.user select arrow "v"
	_dset_gl_sample select
	eq "[ two v ]" "$_DSET_SAMPLE"
	_dset_gl_sample scrollbar
	eq "▐ ▐    " "$_DSET_SAMPLE"
	_dset_gl_sample panebar
	eq "v: " "${_DSET_SAMPLE:0:3}"
	_TUI_G_USER=()
}

ti_settings_glyphs_a_choice_step_does_not_redraw_the_page() {
	_sg_load
	local redraws=0 saved
	saved="$(declare -f tui.redraw tui.list.selected tui.update tui.list.set tui.list.select tui.after)" # put back below: ti_ tests are not restored
	tui.redraw() { redraws=$((redraws + 1)); }
	tui.list.selected() { printf -v "$2" '%s' 1; }
	tui.update() { :; }
	tui.list.set() { :; }
	tui.list.select() { :; }
	tui.after() { :; }
	DSET_GL_TYPE=progress DSET_GL_KEY=fill DSET_GL_FILLING=0
	dset_gl_choice
	eq 0 "$redraws"
	eval "$saved"
	_TUI_G_USER=()
}
