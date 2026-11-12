# input_sort.t.sh - _tui_input.sorted_ids: the sorted keys of an assoc array, without a fork.

declare -gA _IS_T=()

t_sorted_ids_orders_keys_like_a_string_comparison() {
	_IS_T=([b]=1 [a]=1 [c]=1 [ab]=1 [|x]=1 ["ctrl+a"]=1)
	_tui_input.sorted_ids _IS_T
	eq "a ab b c ctrl+a |x" "${_SIDS[*]}"
}

t_sorted_ids_handles_empty_single_and_odd_sized_tables() {
	_IS_T=()
	_tui_input.sorted_ids _IS_T
	eq "0" "${#_SIDS[@]}" || return
	_IS_T=([only]=1)
	_tui_input.sorted_ids _IS_T
	eq "only" "${_SIDS[*]}" || return
	_IS_T=([e]=1 [d]=1 [c]=1 [b]=1 [a]=1)
	_tui_input.sorted_ids _IS_T
	eq "a b c d e" "${_SIDS[*]}"
}

t_sorted_ids_keeps_keys_with_spaces_whole() {
	_IS_T=(["g h"]=1 ["a b"]=1)
	_tui_input.sorted_ids _IS_T
	eq "2|a b|g h" "${#_SIDS[@]}|${_SIDS[0]}|${_SIDS[1]}"
}
