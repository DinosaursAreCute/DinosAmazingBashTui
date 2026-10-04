#!/usr/bin/env bash
# order_stress.sh SEED... - proves the "# requires:" headers are complete. For each SEED the lib/ modules are sourced in
# a different random valid order (tools/gen_load_order.sh --order SEED), and every global variable's value is compared
# with the generated order's. A difference means a module reads something at source time that another module sets
# without declaring the dependency (an unset config path, a command table that stayed empty, ...), or a module
# that overrides another module's function loads before it (every function body is compared too).
# Runs in a scratch copy; the repo is not touched. Prints one line per seed; exit 1 on any difference.
set -uo pipefail
REPO="$(cd -P "$(dirname "$0")/../.." && pwd -P)"
cd "$REPO" || exit 1
WORK=$(mktemp -d "${TMPDIR:-/tmp}/order_stress.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cp -r lib share VERSION "$WORK/"
mkdir -p "$WORK/home/.config/DABT/apps/stress"
printf 'theme=%s\nconfirm.quit=1\n' "$REPO/share/defaults/themes/dracula.css" >"$WORK/home/.config/DABT/apps/stress/dabt.conf"

dump() { # one "name<TAB>declaration" line per variable after sourcing the copy, volatile ones dropped
	(
		export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" TUI_APP_NAME=stress TERM=xterm-256color
		unset TUI_HOME DABT_HOME TUI_ROOT TUI_DEFAULTS_DIR TUI_APP_CONF
		# shellcheck disable=SC1091
		source "$WORK/lib/tui.sh" >/dev/null 2>&1
		declare -f | awk '/^[A-Za-z_][A-Za-z0-9_.]* \(\) $/ {name = $1} {body[name] = body[name] "\001" $0} END {for (n in body) print "fn:" n "\t" body[n]}' | sort
		declare -p | grep -av '^declare -[-a-zA-Z]* \(BASH\|EPOCH\|RANDOM\|SECONDS\|SRANDOM\|LINENO\|FUNCNAME\|_=\|PPID\|SHLVL\|OLDPWD\|PWD\|COMP\|DIRSTACK\|GROUPS\|HIST\|UID\|EUID\|SHELLOPTS\|PIPESTATUS\|_TUI_PERF\|_TUI_NOW\|tmp=\|_TUI_BIND_GEN\)' |
			sed -E 's/^declare -[-a-zA-Z]* ([A-Za-z0-9_]+)=?(.*)$/\1\t\2/' | sort
	)
}

declare -A path
for f in lib/*.sh lib/*/*.sh; do
	b=${f##*/}
	path[${b%.sh}]=${f#lib/}
done
dump >"$WORK/base.txt"
bad=0
for seed in "$@"; do
	{
		head -2 lib/tui_modules.sh
		while read -r n; do printf 'source "${SCRIPT_DIR}/%s"\n' "${path[$n]}"; done < <(tools/gen_load_order.sh --order "$seed")
	} >"$WORK/lib/tui_modules.sh"
	dump >"$WORK/seed.txt"
	diffs=$(join -t$'\t' -j1 "$WORK/base.txt" "$WORK/seed.txt" | awk -F'\t' '$2 != $3 {print $1}' | tr '\n' ' ')
	extra=$(comm -3 <(cut -f1 "$WORK/base.txt") <(cut -f1 "$WORK/seed.txt") | tr -d '\t' | tr '\n' ' ')
	printf 'seed %s: %s\n' "$seed" "$([[ -z $diffs$extra ]] && echo ok || echo "differs: $diffs$extra")"
	[[ -n $diffs$extra ]] && bad=1
done
exit $bad
