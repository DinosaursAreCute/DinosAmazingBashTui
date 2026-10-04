#!/usr/bin/env bash
# bench_ab.sh [RUNS] [REF] - A/B bench: REF (default HEAD, checked out as a throwaway worktree) against the working
# tree, interleaved so machine drift hits both. Prints name, ref mean, tree mean, delta and a verdict per bench:
# <= +2% noise, <= +5% WARN, > +5% FAIL. Exit 1 when any bench fails.
set -uo pipefail
REPO="$(cd -P "$(dirname "$0")/../.." && pwd -P)"
RUNS=${1:-3} REF=${2:-HEAD}
WT=$(mktemp -d "${TMPDIR:-/tmp}/bench_ab.XXXXXX")
trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WT"' EXIT
git -C "$REPO" worktree add -q --detach "$WT" "$REF" || exit 1

rows() { "$1/tools/bench/run.sh" 2>/dev/null | grep -a $'\t' | awk -F'\t' -v l="$2" '{print l "\t" $1 "\t" $2}'; }
{
	for ((i = 0; i < RUNS; i++)); do
		rows "$WT" ref
		rows "$REPO" tree
	done
} | awk -F'\t' '
	{ s[$1, $2] += $3; n[$1, $2]++; names[$2] = 1 }
	END {
		fail = 0
		for (k in names) {
			r = s["ref", k] / n["ref", k]; t = s["tree", k] / n["tree", k]; d = (t - r) * 100 / r
			v = d > 5 ? "FAIL" : d > 2 ? "WARN" : "ok"
			if (v == "FAIL") fail = 1
			printf "%s\t%d\t%d\t%+.1f%%\t%s\n", k, r, t, d, v
		}
		exit fail
	}' | sort
