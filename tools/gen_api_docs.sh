#!/usr/bin/env bash
# gen_api_docs.sh - builds the function lists of the API module pages from the per-function entries, and checks coverage.
#
#   docs/api/<module>/<fn>.md   one entry per public function (the source of truth), starting with  ### `<fn>`
#                               and a bash signature block; the first paragraph after it is the one-line summary.
#                               It is a page of its own (/api/<module>/<fn>) and is pulled into its module page.
#   docs/api/<module>.md        hand-written prose. Each list of functions sits between markers:
#                                   <!-- api: tui.foo tui.bar ... -->
#                                   <!-- /api -->
#                               and everything between them is generated: a summary table linking to the entry pages,
#                               then the entries themselves via {% include_relative %}.
#
# Usage: tools/gen_api_docs.sh            rewrite the generated blocks
#        tools/gen_api_docs.sh --check    change nothing; exit 1 on stale blocks, undocumented or unlisted functions,
#                                         entries for functions that no longer exist, or broken /api/ links
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

check=0
[[ "${1:-}" == --check ]] && check=1
api=docs/api
err=0
fail() {
	printf 'gen_api_docs: %s\n' "$*" >&2
	err=1
}

# the public surface: every tui.* function defined in lib/ (the packaging module lib/dapk/ has its own CLI docs)
declare -A defined=()
while IFS= read -r fn; do defined[$fn]=1; done < <(
	find lib -name '*.sh' ! -path 'lib/dapk/*' -exec grep -hoE '^[[:space:]]*(function[[:space:]]+)?tui\.[A-Za-z0-9_.]+[[:space:]]*\(\)' {} + |
		sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*\(\)$//' | sort -u
)

# the entries
declare -A entry_mod=() listed=()
for f in "$api"/*/*.md; do
	[[ -e "$f" ]] || continue
	name="${f##*/}"
	name="${name%.md}"
	mod="${f%/*}"
	mod="${mod##*/}"
	[[ -n "${entry_mod[$name]:-}" ]] && fail "$name has two entries ($mod and ${entry_mod[$name]})"
	entry_mod[$name]="$mod"
	IFS= read -r first <"$f"
	[[ "$first" == "### \`$name\`" ]] || fail "$f: first line must be  ### \`$name\`"
	[[ -n "${defined[$name]:-}" ]] || fail "$f: $name is not a function in lib/ (renamed or removed?)"
done
for fn in "${!defined[@]}"; do
	[[ -n "${entry_mod[$fn]:-}" ]] || fail "$fn has no entry (add $api/<module>/$fn.md)"
done

# summary NAME -> first paragraph after the signature block, one line, | escaped for the table
summary() {
	awk '
		/^```/ { fence++; next }
		fence >= 2 && NF { out = out (out ? " " : "") $0; got = 1; next }
		fence >= 2 && got { exit }
		END { gsub(/\|/, "\\|", out); print out }
	' "$api/${entry_mod[$1]}/$1.md"
}

block() { # MOD FN... -> the generated text between the markers
	local mod="$1" fn
	shift
	printf '| Function | Summary |\n|---|---|\n'
	for fn; do printf '| [`%s`](%s/%s.md) | %s |\n' "$fn" "$mod" "$fn" "$(summary "$fn")"; done
	printf '\n<div class="api-entries" data-pagefind-ignore="all" markdown="1">\n'
	for fn; do printf '\n{%% include_relative %s/%s.md %%}\n' "$mod" "$fn"; done
	printf '\n</div>\n'
}

for page in "$api"/*.md; do
	mod="${page##*/}"
	mod="${mod%.md}"
	grep -q '^<!-- api: ' "$page" || continue
	out="" in_block=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" == '<!-- api: '*' -->' ]]; then
			out+="$line"$'\n'
			in_block=1
			read -ra fns <<<"${line#<!-- api: }"
			unset 'fns[${#fns[@]}-1]' # the closing -->
			for fn in "${fns[@]}"; do
				if [[ -z "${entry_mod[$fn]:-}" ]]; then
					fail "$page lists $fn, which has no entry"
					continue
				fi
				[[ "${entry_mod[$fn]}" == "$mod" ]] || fail "$page lists $fn, whose entry is in ${entry_mod[$fn]}/"
				[[ -n "${listed[$fn]:-}" ]] && fail "$fn is listed twice (${listed[$fn]} and $page)"
				listed[$fn]="$page"
			done
			out+="$(block "$mod" "${fns[@]}")"$'\n'
		elif [[ "$line" == '<!-- /api -->' ]]; then
			((in_block)) || fail "$page: <!-- /api --> without an opening marker"
			in_block=0
			out+="$line"$'\n'
		elif ((! in_block)); then
			out+="$line"$'\n'
		fi
	done <"$page"
	((in_block)) && fail "$page: unclosed <!-- api: --> block"
	if ((check)); then
		[[ "$out" == "$(<"$page")"$'\n' ]] || fail "$page is stale (run tools/gen_api_docs.sh)"
	else
		printf '%s' "$out" >"$page"
	fi
done
for fn in "${!entry_mod[@]}"; do
	[[ -n "${listed[$fn]:-}" ]] || fail "$fn is not listed on $api/${entry_mod[$fn]}.md"
done

# root-relative links inside entries (/api/<module>/<fn>.html) must point at an entry
while IFS=: read -r f link; do
	t="${link#/api/}"
	t="${t%%#*}"
	[[ -e "$api/${t%.html}.md" ]] || fail "$f: broken link $link"
done < <(grep -oE '\(/api/[A-Za-z0-9_./-]+\.html(#[A-Za-z0-9_-]*)?\)' -r "$api" --include='*.md' | tr -d '()' | sed 's/:(/:/')

exit "$err"
