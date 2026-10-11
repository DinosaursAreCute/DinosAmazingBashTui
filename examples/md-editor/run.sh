#!/usr/bin/env bash
# run.sh - starts the Markdown editor from this DABT checkout.
#
#   examples/md-editor/run.sh [FILE.md [STATIC.md]]
#       FILE.md    loaded into the editor (default: scratch.md); nothing is written back
#       STATIC.md  the document alt+o opens (default: static.md)
#
# Keys: alt+m source rendered / plain, alt+p split preview, alt+f heading block fonts, alt+b literal line breaks,
#       alt+o open / close the static document (esc also closes it), ctrl+q quits.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

case "${1:-}" in
	-h | --help)
		sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
esac

if [[ -n "${1:-}" ]]; then
	[[ -r "$1" ]] || {
		echo "run.sh: cannot read '$1'" >&2
		exit 1
	}
	MD_EDITOR_FILE="$(cd -P "$(dirname "$1")" && pwd -P)/$(basename "$1")"
	export MD_EDITOR_FILE
fi

if [[ -n "${2:-}" ]]; then
	[[ -r "$2" ]] || {
		echo "run.sh: cannot read '$2'" >&2
		exit 1
	}
	MD_STATIC_FILE="$(cd -P "$(dirname "$2")" && pwd -P)/$(basename "$2")"
	export MD_STATIC_FILE
fi

export TUI_ROOT="$HERE/../.."
exec bash "$HERE/md_editor.sh"
