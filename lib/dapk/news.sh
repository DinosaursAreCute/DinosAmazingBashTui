#!/usr/bin/env bash
# news.sh - loading and filtering News (the "version<TAB>text" lines from a package's NEWS file, a -news.txt sidecar, or a URL).
#
# dapk.news.load SRC          SRC = file or http(s) URL. Fills DAPK_NEWS_VERSIONS[] and DAPK_NEWS_ITEMS[] (parallel arrays). rc 1 on failure.
# dapk.news.since VERSION     keep only items of versions newer than VERSION
# dapk.news.print [INDENT]    print grouped by version to stdout
# dapk.news.count             number of items

declare -ga DAPK_NEWS_VERSIONS=() DAPK_NEWS_ITEMS=()

dapk.news.load() {
	local src="$1" v t data
	DAPK_NEWS_VERSIONS=()
	DAPK_NEWS_ITEMS=()
	if [[ "$src" == http://* || "$src" == https://* ]]; then
		command -v curl >/dev/null 2>&1 || return 1
		data="$(curl -fsSL --max-time 20 "$src" 2>/dev/null)" || return 1
	else
		[[ -r "$src" ]] || return 1
		data="$(<"$src")"
	fi
	while IFS=$'\t' read -r v t; do
		[[ -n "$v" && -n "$t" ]] || continue
		DAPK_NEWS_VERSIONS+=("$v")
		DAPK_NEWS_ITEMS+=("$t")
	done <<<"$data"
	return 0
}

dapk.news.since() {
	local i
	local -a nv=() ni=()
	for i in "${!DAPK_NEWS_ITEMS[@]}"; do
		dapk.version.cmp "${DAPK_NEWS_VERSIONS[i]}" "$1"
		((DAPK_VCMP > 0)) && {
			nv+=("${DAPK_NEWS_VERSIONS[i]}")
			ni+=("${DAPK_NEWS_ITEMS[i]}")
		}
	done
	DAPK_NEWS_VERSIONS=("${nv[@]}")
	DAPK_NEWS_ITEMS=("${ni[@]}")
}

dapk.news.count() { printf '%d' "${#DAPK_NEWS_ITEMS[@]}"; }

dapk.news.print() {
	local ind="${1:-}" i last=""
	for i in "${!DAPK_NEWS_ITEMS[@]}"; do
		[[ "${DAPK_NEWS_VERSIONS[i]}" != "$last" ]] && {
			last="${DAPK_NEWS_VERSIONS[i]}"
			printf '%s%s\n' "$ind" "$last"
		}
		printf '%s  - %s\n' "$ind" "${DAPK_NEWS_ITEMS[i]}"
	done
}
