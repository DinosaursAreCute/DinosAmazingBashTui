# Does inlining tui_node.attr_get into _tui_build.attrv pay? The call model predicted ~37 ms of the 4.3 s page_switch.sh run (<1%):
# attr_get (11.6k calls) and attrv (10.2k calls) run at stack depth ~20 while a page is built.
#   A original  tools/bench/page_switch.sh in an untouched copy of the repo
#   B inlined   the same script in a copy where attrv reads _N_ATTR directly instead of calling attr_get:
#                   -	tui_node.attr_get "$1" "$2" && _bv_out="$_N_ATTR_V" || _bv_out=""
#                   +	_bv_out="${_N_ATTR["$1.$2"]:-}"
# Both sides are copies under a temp dir, the working tree is never touched. One sample = one page_switch.sh run (20 switches, the first
# visit of each page is a real parse+build, which is where attrv runs).
AB_NAME="inline-attr-get"
AB_DESC="page_switch.sh with and without the attr_get call inside _tui_build.attrv"
AB_SIDES=(original inlined)
AB_CMDS=(run_original run_inlined)
AB_UNITS=20
AB_UNIT_NAME=switch
AB_ROUNDS=40
AB_WARMUP=2

_ia_repo="$(cd -P "$AB_DIR/../../.." && pwd -P)"

ab_setup() {
	_ia_tmp="$(mktemp -d "${TMPDIR:-/tmp}/ab-inline-attr.XXXXXX")" || die "mktemp failed"
	mkdir -p "$_ia_tmp/original" "$_ia_tmp/inlined"
	tar -C "$_ia_repo" --exclude=.git --exclude=logs --exclude=dist --exclude=screenshots --exclude=reports --exclude=release-notes \
		--exclude=runs --exclude=callcounts -cf - . | tar -C "$_ia_tmp/original" -xf - || die "copying the repo failed"
	cp -a "$_ia_tmp/original/." "$_ia_tmp/inlined/"
	python3 -I - "$_ia_tmp/inlined/lib/markup/tui_build.sh" <<'PY' || die "patching the inlined copy failed"
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '\ttui_node.attr_get "$1" "$2" && _bv_out="$_N_ATTR_V" || _bv_out=""\n'
new = '\t_bv_out="${_N_ATTR["$1.$2"]:-}"\n'
if s.count(old) != 1:
	sys.exit("_tui_build.attrv no longer looks like the version this scenario patches")
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
	bash -n "$_ia_tmp/inlined/lib/markup/tui_build.sh" || die "the patched file does not parse"
	grep -q 'tui_node.attr_get "$1" "$2" && _bv_out' "$_ia_tmp/original/lib/markup/tui_build.sh" || die "the original copy is not the unpatched version"
	# both sides must do the same work: one untimed run each, same number of output lines
	local a b
	a="$(bash "$_ia_tmp/original/tools/bench/page_switch.sh" 2 2>&1 | wc -l)"
	b="$(bash "$_ia_tmp/inlined/tools/bench/page_switch.sh" 2 2>&1 | wc -l)"
	[[ $a == "$b" && $a -gt 0 ]] || die "sides disagree or the benchmark printed nothing ($a vs $b lines)"
}
ab_teardown() { rm -rf "$_ia_tmp"; }

run_original() { bash "$_ia_tmp/original/tools/bench/page_switch.sh" 20; }
run_inlined() { bash "$_ia_tmp/inlined/tools/bench/page_switch.sh" 20; }
