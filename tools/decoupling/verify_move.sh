#!/usr/bin/env bash
# verify_move.sh SRC DEST... - checks that a move was pure. Before = HEAD:SRC plus HEAD:DEST for each DEST that already
# existed; after = SRC plus the DESTs now. Every non-blank line must appear as often after as before. Prints the lines
# only before ("lost") or only after ("added"); a pure move adds just a new module's header comment, section comments
# and the source line. Exit 1 when anything is lost.
set -uo pipefail
src=$1
shift
before=$( (
	git show "HEAD:$src"
	for d in "$@"; do git cat-file -e "HEAD:$d" 2>/dev/null && git show "HEAD:$d"; done
) | grep -v '^[[:space:]]*$' | sort)
after=$( (cat "$src" "$@") | grep -v '^[[:space:]]*$' | sort)
lost=$(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
added=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
printf 'lost: %d\n' "$(grep -c . <<<"$lost")"
[[ -n $lost ]] && printf '%s\n' "$lost" | sed 's/^/  - /' | head -20
printf 'added: %d\n' "$(grep -c . <<<"$added")"
[[ -n $added ]] && printf '%s\n' "$added" | sed 's/^/  + /' | head -40
[[ -z $lost ]]
