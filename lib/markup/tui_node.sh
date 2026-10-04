#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_node.sh                                                          ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui_node.create TYPE [ID] [PARENT] -> _N   new node, appended to PARENT's kids
# tui_node.attr_set N ATTR VALUE             sets one attribute (always through this: _N_ANAMES lists the names)
# tui_node.attr_get N ATTR -> _N_ATTR_V       reads one attribute
# tui_node.children N -> _N_CHILDREN[]        N's kids, in order
# tui_node.walk N FN                          pre-order: FN NODE for N and every descendant
# tui_node.dump -> stdout                     declare -p of every node table
# tui_node.load DUMP                          restores tables from tui_node.dump's output
# tui_node.reset                              clears every node table
#
# Struct-of-arrays node table (markup-v2 stage 0.5): a plain node handle is
# just an integer index shared across parallel arrays, not an object. This
# is a new, independent tree the future tokenizer/builder (1.1/1.2) will
# populate - the engine keeps its own _TUI_P_*/_TUI_W_* arrays untouched for
# now, so this module has no effect until something starts calling it.
# requires:

declare -gi _N_NEXT=0    # next node number to hand out
declare -ga _N_TYPE=()   # node -> type ("pane", "label", "button", ...)
declare -ga _N_PARENT=() # node -> parent node number (empty for a root)
declare -ga _N_KIDS=()   # node -> space-joined child node numbers, in order
declare -ga _N_ID=()     # node -> markup id (may be empty)
declare -gA _N_ATTR=()   # "node.attr" -> value
declare -ga _N_ANAMES=() # node -> space-joined attribute names it has: lets code visit one node's attributes without scanning all of _N_ATTR
declare -gA _N_BY_ID=()  # markup id -> node number

tui_node.reset() {
	_N_NEXT=0
	_N_TYPE=()
	_N_PARENT=()
	_N_KIDS=()
	_N_ID=()
	_N_ATTR=()
	_N_ANAMES=()
	_N_BY_ID=()
}

# tui_node.create TYPE [ID] [PARENT] -> _N
tui_node.create() {
	local type="$1" id="${2:-}" parent="${3:-}"
	_N=$((_N_NEXT++))
	_N_TYPE[$_N]="$type"
	_N_ID[$_N]="$id"
	_N_PARENT[$_N]="$parent"
	_N_KIDS[$_N]=""
	[[ -n "$id" ]] && _N_BY_ID[$id]=$_N
	if [[ -n "$parent" ]]; then
		_N_KIDS[$parent]="${_N_KIDS[$parent]:+${_N_KIDS[$parent]} }$_N"
	fi
}

tui_node.attr_set() {
	[[ -n "${_N_ATTR["$1.$2"]+x}" ]] || _N_ANAMES[$1]+="${_N_ANAMES[$1]:+ }$2"
	_N_ATTR["$1.$2"]="$3"
}

# tui_node.attr_unset_all N - drop every attribute of node N
tui_node.attr_unset_all() {
	local name
	for name in ${_N_ANAMES[$1]:-}; do unset '_N_ATTR["$1.$name"]'; done
	unset '_N_ANAMES[$1]'
}

# tui_node.attr_get N ATTR -> _N_ATTR_V ; false and empty when unset.
tui_node.attr_get() {
	_N_ATTR_V="${_N_ATTR["$1.$2"]:-}"
	[[ -n "${_N_ATTR["$1.$2"]+x}" ]]
}

# tui_node.children N -> _N_CHILDREN[] (array, possibly empty)
tui_node.children() {
	_N_CHILDREN=(${_N_KIDS[$1]:-})
}

# tui_node.walk N FN - pre-order: FN NODE, once for N and every descendant.
tui_node.walk() {
	local node="$1" fn="$2" kid
	"$fn" "$node"
	for kid in ${_N_KIDS[$node]:-}; do
		tui_node.walk "$kid" "$fn"
	done
}

# tui_node.dump -> stdout : declare -p of every node table, `source`-able
# (or tui_node.load-able) to restore this exact state.
tui_node.dump() {
	declare -p _N_NEXT _N_TYPE _N_PARENT _N_KIDS _N_ID _N_ATTR _N_ANAMES _N_BY_ID
}

# tui_node.load DUMP - restores every node table from tui_node.dump's
# output. `declare -p`'s own output has no -g, so run inside a function it
# would declare function-local shadows instead of touching the real tables -
# every "declare -X" becomes "declare -gX" before eval to land at global scope.
tui_node.load() { eval "${1//declare -/declare -g}"; }
