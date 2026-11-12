# settings_build.t.sh - the item list of the default Settings page (share/defaults/pages/settings_callbacks.sh).

ti_settings_description_keeps_its_backticked_words() {
	source "$REPO/share/defaults/pages/settings_callbacks.sh"
	_dset_build 2>/dev/null # a backtick in a double-quoted description runs as a command and the text vanishes
	local i desc=""
	for i in "${!S_KEY[@]}"; do [[ "${S_KEY[i]}" == pointer ]] && desc=${S_DESC[i]}; done
	match "$desc" 'Themes can set `cursor:` per class'
}

t_settings_pretty_v_makes_a_theme_name_readable_without_a_fork() {
	source "$REPO/share/defaults/pages/settings_callbacks.sh"
	_dset_pretty_v hello_kitty
	eq "Hello kitty" "$_DSET_PRETTY"
}
