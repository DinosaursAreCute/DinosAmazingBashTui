#!/usr/bin/env bash
# gate.sh [G1..G8] - the single command for stage reviews. Runs the global hard gates
# from docs/concepts/markup-v2-implementation-plan.md and prints only failures, one per
# line: gate<TAB>file:line<TAB>message. Exit 0 when clean.
#
# G3 (bench) and G6 (fork counter) have no pass/fail check yet and are skipped silently, not failed. G7 (real terminal)
# and G8 (LOC report) are human/reporting gates, not pass/fail checks - also skipped.
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO" || exit 1

_G_REQUESTED=("$@")
((${#_G_REQUESTED[@]} == 0)) && _G_REQUESTED=(G1 G2 G3 G4 G5 G6 G7 G8)

_g_wanted() {
	local g
	for g in "${_G_REQUESTED[@]}"; do [[ "$g" == "$1" ]] && return 0; done
	return 1
}

_G_FAIL=0
_g_report() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3"
	_G_FAIL=1
}

# G1/G2 share one run: bats (integration) + tools/t.sh (unit, in-process, timed)
if _g_wanted G1 || _g_wanted G2; then
	if _g_wanted G1; then
		# -j N (N explicit, never a bare -j right before a glob/file-list -
		# bats-core's semaphore.bash then grabs the first expanded path as
		# its job count and divides by it, "division by 0 (error token is
		# ...)"): bats -j needs GNU parallel, runs whole .bats FILES
		# concurrently (163 cases across 10 files - this is the dominant
		# cost of the gate, not tools/t.sh's in-process suite).
		_g_bats_jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
		((_g_bats_jobs > 8)) && _g_bats_jobs=8
		((_g_bats_jobs < 1)) && _g_bats_jobs=1
		_g_bats_out="$(bats -j "$_g_bats_jobs" tests/ tests/dapk/ --tap 2>&1)"
		_g_bats_rc=$?
		if ((_g_bats_rc != 0)); then
			while IFS= read -r _g_line; do
				[[ "$_g_line" == "not ok "* ]] && _g_report G1 "tests/:0" "$_g_line"
			done <<<"$_g_bats_out"
		fi
	fi

	_g_t_out="$(tools/t.sh 2>&1)"
	_g_t_rc=$?
	if _g_wanted G1 && ((_g_t_rc != 0)) && ! grep -q 'speed budget exceeded' <<<"$_g_t_out"; then
		while IFS= read -r _g_line; do
			[[ "$_g_line" == *$'\t'*$'\t'* ]] && _g_report G1 "${_g_line#*$'\t'}" "$_g_line"
		done <<<"$_g_t_out"
	fi
	if _g_wanted G2 && grep -q 'speed budget exceeded' <<<"$_g_t_out"; then
		_g_report G2 "tools/t.sh:0" "$(grep 'speed budget exceeded' <<<"$_g_t_out")"
	fi
fi

# G4: the golden frame of every renderable demo page is byte-identical (tools/t_golden.sh --check)
if _g_wanted G4; then
	while IFS=$'\t' read -r _g_gate _g_file _g_msg; do
		[[ -n "$_g_gate" ]] && _g_report G4 "$_g_file:0" "$_g_msg"
	done < <(tools/t_golden.sh --check)
fi

# G5: generated files stay in sync with their sources: the API docs and the module load order (tools already exist)
if _g_wanted G5; then
	_g_docs_out="$(tools/gen_api_docs.sh --check 2>&1)"
	_g_docs_rc=$?
	((_g_docs_rc != 0)) && _g_report G5 "tools/gen_api_docs.sh:0" "$(head -1 <<<"$_g_docs_out")"
	_g_load_out="$(tools/gen_load_order.sh --check 2>&1)" || _g_report G5 "tools/gen_load_order.sh:0" "$(head -1 <<<"$_g_load_out")"
fi

exit "$_G_FAIL"
