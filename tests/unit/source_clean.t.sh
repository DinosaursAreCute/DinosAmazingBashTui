# source_clean.t.sh - loading the library only defines things: it parses, prints nothing and never touches the network.
# (A mangled line once made `source lib/tui.sh` run the update check at every start: a request and ~80 ms before the first frame.)

ti_every_lib_file_parses() {
	local f bad=""
	while IFS= read -r f; do bash -n "$f" 2>/dev/null || bad+="${f#"$REPO"/} "; done < <(find "$REPO/lib" -name '*.sh')
	eq "" "$bad"
}

ti_sourcing_the_library_prints_nothing_and_makes_no_request() {
	local d="$_T_ROOT/src_clean" out
	mkdir -p "$d/bin" "$d/home"
	printf '#!/bin/sh\necho "$0 $*" >>"%s/net.log"\nexit 7\n' "$d" >"$d/bin/curl"
	cp "$d/bin/curl" "$d/bin/wget"
	chmod +x "$d/bin/curl" "$d/bin/wget"
	: >"$d/net.log"
	out="$(HOME="$d/home" XDG_CONFIG_HOME="$d/home/.config" TUI_HOME="$d/home/.config/DABT" PATH="$d/bin:$PATH" \
		bash -c 'source "$1/lib/tui.sh"' _ "$REPO" 2>&1)"
	eq "" "$out"
	eq "" "$(<"$d/net.log")"
}
