#!/usr/bin/env bash
# frame_ab.sh [REF] - renders every demo page at REF (default HEAD, throwaway worktree) and in the working tree and
# reports pages whose frames differ. Same pages and normalisation as tools/t_golden.sh, but compares two live
# renders, so it still gates a refactor while the recorded frames in tools/golden are stale.
# Prints "FRAME<TAB>page<TAB>differs" per mismatch and a summary line; exit 1 on any mismatch.
set -uo pipefail
REPO="$(cd -P "$(dirname "$0")/../.." && pwd -P)"
REF=${1:-HEAD}
SKIP=" components_live monitor settings docu compose _templates workspace " # t_golden.sh skips all but workspace: its frame carries live load / host / memory values, so two runs of one tree differ
WT=$(mktemp -d "${TMPDIR:-/tmp}/frame_ab.XXXXXX")
trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WT"' EXIT
git -C "$REPO" worktree add -q --detach "$WT" "$REF" || exit 1

frame() { timeout 20 "$1/tools/frame.sh" "$1/share/demo/$2.xml" --sgr 2>/dev/null | sed -E 's/[0-9]{2}:[0-9]{2}:[0-9]{2}/HH:MM:SS/g'; }
checked=0 bad=0
for page in "$REPO"/share/demo/*.xml; do
	name=$(basename "$page" .xml)
	[[ $SKIP == *" $name "* ]] && continue
	((checked++))
	if [[ "$(frame "$WT" "$name")" != "$(frame "$REPO" "$name")" ]]; then
		printf 'FRAME\t%s\tdiffers\n' "$name"
		((bad++))
	fi
done
printf 'frame_ab: %d pages, %d differ\n' "$checked" "$bad"
((bad == 0))
