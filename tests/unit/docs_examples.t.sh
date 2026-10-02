# docs_examples.t.sh - the XML examples in the guides and the tutorial, and the example app, stay valid pages.
# A guide that teaches a page that the validator rejects is worse than no guide.

# _de_blocks FILE -> writes every ```xml block that is a whole page (starts with <tui) to $_T_ROOT/de/NAME.N.xml
_de_blocks() {
	local file="$1" base="${1##*/}" line in=0 n=0 buf=""
	mkdir -p "$_T_ROOT/de"
	while IFS= read -r line; do
		if ((in)); then
			if [[ "$line" == '```' ]]; then
				in=0
				if [[ "$buf" == '<tui'* && "$buf" == *'</tui>' ]]; then # whole pages only, not fragments
					n=$((n + 1))
					printf '%s\n' "$buf" >"$_T_ROOT/de/${base%.md}.$n.xml"
				fi
				buf=""
			else
				buf+="${buf:+$'\n'}$line"
			fi
		elif [[ "$line" == '```xml' ]]; then
			in=1
		fi
	done <"$file"
}

ti_docs_example_app_pages_pass_the_validator() {
	tui.validate.files "$REPO/examples/first-app/config/home.xml"
	eq "0" "$TUI_V_ERRORS"
}

ti_docs_whole_page_examples_pass_the_validator() {
	local f bad=""
	for f in "$REPO/docs/guide/markup.md" "$REPO/docs/guide/writing-an-app.md" "$REPO/docs/guide/widgets.md" "$REPO/docs/tutorials/writing-your-first-app.md"; do
		_de_blocks "$f"
	done
	: >"$_T_ROOT/de/home_callbacks.sh" # the files the examples refer to: empty stand-ins
	: >"$_T_ROOT/de/theme.css"
	: >"$_T_ROOT/de/_templates.xml"
	for f in "$_T_ROOT"/de/*.xml; do
		[[ -e "$f" && "${f##*/}" != _* ]] || continue
		tui.validate.files "$f"
		((TUI_V_ERRORS)) && bad+="${f##*/}(${_TV_F_MSG[0]:0:60}) "
	done
	eq "" "$bad"
}
