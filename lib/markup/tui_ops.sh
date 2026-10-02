#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_ops.sh                                                           ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui_ops.select ROOT SEL -> _OP_NODES[]   nodes under ROOT matching SEL (document order); false when none
# tui_ops.clone N [PREFIX] -> _N           deep copy of N's subtree, detached; every id gets PREFIX
# tui_ops.clone_all PREFIX N... -> _OP_CLONES[]   the same for several nodes in one pass over the attribute table
# tui_ops.insert MODE TARGET N             MODE append|prepend (N becomes TARGET's first/last kid) or before|after (sibling)
# tui_ops.replace OLD N                    N takes OLD's place; OLD's subtree is freed
# tui_ops.remove N                         detaches N and frees its subtree (ids, attrs)
# tui_ops.set N ATTR VALUE                 sets one attribute (keeps the by-id index right for `id`)
# tui_ops.wrap N TYPE [ID] -> _N           puts a new TYPE node where N stood, N becomes its only kid
# tui_ops.move N MODE TARGET               relocates N (insert already detaches)
# tui_ops.params NODE [SKIP...]            _OP_PARAMS[name]=value from NODE's attributes
# tui_ops.subst N                          replaces {{@name}} from _OP_PARAMS in every attribute value under N
# tui_ops.subst_all N...                   the same for several nodes in one pass
#
# The one mutation API of the node tree (markup-v2 J): composition tags
# (tui_compose.sh) and addons (tui_addon.sh) are built from these. Selectors
# are #id, .class, tag (combinable: tag#id.a.b), space = descendant, `>` = child.
# Everything is fork-free; results come back in globals (_N, _OP_NODES).

declare -gA _OP_PARAMS=() # name -> value for tui_ops.subst
declare -ga _OP_NODES=()  # tui_ops.select result
declare -ga _OP_CLONES=() # tui_ops.clone_all result
declare -gA _OP_SET=()    # scratch: subtree membership, node -> 1 (filled by _tui_ops.collect)
declare -ga _OP_LIST=()   # scratch: subtree in pre-order (filled by _tui_ops.collect)

# _tui_ops.collect N - _OP_LIST/_OP_SET = N and every descendant, pre-order.
_tui_ops.collect() {
	_OP_LIST=()
	_OP_SET=()
	_tui_ops.collect_walk "$1"
}
_tui_ops.collect_walk() {
	local k
	_OP_LIST+=("$1")
	_OP_SET[$1]=1
	for k in ${_N_KIDS[$1]:-}; do _tui_ops.collect_walk "$k"; done
}

# _tui_ops.detach N - removes N from its parent's kid list; N keeps its own subtree.
_tui_ops.detach() {
	local n="$1" p="${_N_PARENT[$1]:-}" kids
	[[ -n "$p" ]] || return 0
	kids=" ${_N_KIDS[$p]} "
	kids="${kids/ $n / }"
	kids="${kids# }"
	_N_KIDS[$p]="${kids% }"
	_N_PARENT[$n]=""
}

# ── selectors ────────────────────────────────────────────────────────────

# _tui_ops.match NODE TAG ID CLASSES -> 0 when NODE has the tag ("" or * = any), id, and every class (space-separated).
_tui_ops.match() {
	local n="$1" tag="$2" id="$3" classes="$4" c
	[[ -z "$tag" || "$tag" == '*' || "${_N_TYPE[$n]}" == "$tag" ]] || return 1
	[[ -z "$id" || "${_N_ID[$n]:-}" == "$id" ]] || return 1
	if [[ -n "$classes" ]]; then
		tui_node.attr_get "$n" class
		for c in $classes; do [[ " $_N_ATTR_V " == *" $c "* ]] || return 1; done
	fi
	return 0
}

# tui_ops.select ROOT SEL -> _OP_NODES[] ; false when nothing matches.
tui_ops.select() {
	local root="$1" sel="$2" tok comb=desc
	if [[ "$sel" =~ ^#([A-Za-z0-9_-]+)$ ]]; then # the common case, a single id: one lookup instead of a walk over the tree
		local hit="${_N_BY_ID[${BASH_REMATCH[1]}]:-}" up
		_OP_NODES=()
		[[ -n "$hit" ]] || return 1
		up="${_N_PARENT[$hit]:-}" # ROOT itself is not a match, only what lies below it
		while [[ -n "$up" ]]; do
			[[ "$up" == "$root" ]] && {
				_OP_NODES=("$hit")
				return 0
			}
			up="${_N_PARENT[$up]:-}"
		done
		return 1
	fi
	local -A ctx=([$root]=1)
	local -A next=()
	local n k tag id classes part
	for tok in $sel; do
		if [[ "$tok" == '>' ]]; then
			comb=child
			continue
		fi
		tag="" id="" classes=""
		part="$tok"
		while [[ "$part" =~ ^([#.]?)([A-Za-z_*][A-Za-z0-9_-]*) ]]; do
			case "${BASH_REMATCH[1]}" in
				'#') id="${BASH_REMATCH[2]}" ;;
				'.') classes+="${classes:+ }${BASH_REMATCH[2]}" ;;
				*) tag="${BASH_REMATCH[2]}" ;;
			esac
			part="${part:${#BASH_REMATCH[0]}}"
		done
		next=()
		for n in "${!ctx[@]}"; do
			if [[ "$comb" == child ]]; then
				for k in ${_N_KIDS[$n]:-}; do
					_tui_ops.match "$k" "$tag" "$id" "$classes" && next[$k]=1
				done
			else
				_tui_ops.collect "$n"
				for k in "${_OP_LIST[@]:1}"; do
					_tui_ops.match "$k" "$tag" "$id" "$classes" && next[$k]=1
				done
			fi
		done
		ctx=()
		for k in "${!next[@]}"; do ctx[$k]=1; done
		comb=desc
	done
	_OP_NODES=()
	((${#ctx[@]})) || return 1
	_tui_ops.collect "$root"
	for k in "${_OP_LIST[@]}"; do [[ -n "${ctx[$k]:-}" ]] && _OP_NODES+=("$k"); done
	((${#_OP_NODES[@]}))
}

# ── mutations ────────────────────────────────────────────────────────────

# tui_ops.clone_all PREFIX N... -> _OP_CLONES[] : detached deep copies of each N, in order. Ids are PREFIX+id; with an
# empty PREFIX they stay identical, so a caller that instantiates twice must pass one. All copies share one pass
# over the attribute table, so cloning twenty siblings costs little more than cloning one.
tui_ops.clone_all() {
	local prefix="$1" src n id node name parent
	local -A map=()
	local -a list=()
	shift
	for src in "$@"; do
		_tui_ops.collect "$src"
		list+=("${_OP_LIST[@]}")
	done
	for n in "${list[@]}"; do
		id="${_N_ID[$n]:-}"
		[[ -n "$id" ]] && id="$prefix$id"
		parent="${_N_PARENT[$n]:-}"
		[[ -n "$parent" ]] && parent="${map[$parent]:-}" # a source root's parent is not part of the copy
		tui_node.create "${_N_TYPE[$n]}" "$id" "$parent"
		map[$n]=$_N
	done
	for n in "${list[@]}"; do
		node="${map[$n]}"
		for name in ${_N_ANAMES[$n]:-}; do
			if [[ "$name" == id ]]; then
				tui_node.attr_set "$node" id "${_N_ID[$node]}"
			else
				tui_node.attr_set "$node" "$name" "${_N_ATTR["$n.$name"]}"
			fi
		done
	done
	_OP_CLONES=()
	for src in "$@"; do _OP_CLONES+=("${map[$src]}"); done
}

# tui_ops.clone N [PREFIX] -> _N : detached deep copy of one node (see tui_ops.clone_all)
tui_ops.clone() {
	tui_ops.clone_all "${2:-}" "$1"
	_N="${_OP_CLONES[0]}"
}

# tui_ops.insert MODE TARGET N - append/prepend: N becomes TARGET's last/first kid;
# before/after: N becomes TARGET's sibling. N is detached from its old parent first.
tui_ops.insert() {
	local mode="$1" target="$2" n="$3" parent kids
	_tui_ops.detach "$n"
	case "$mode" in
		append | prepend) parent="$target" ;;
		before | after) parent="${_N_PARENT[$target]:-}" ;;
		*) return 2 ;;
	esac
	[[ -n "$parent" ]] || return 1
	kids="${_N_KIDS[$parent]:-}"
	case "$mode" in
		append) kids="${kids:+$kids }$n" ;;
		prepend) kids="$n${kids:+ $kids}" ;;
		before)
			kids=" $kids "
			kids="${kids/ $target / $n $target }"
			kids="${kids# }"
			kids="${kids% }"
			;;
		after)
			kids=" $kids "
			kids="${kids/ $target / $target $n }"
			kids="${kids# }"
			kids="${kids% }"
			;;
	esac
	_N_KIDS[$parent]="$kids"
	_N_PARENT[$n]="$parent"
}

# tui_ops.remove N - detach and free N's whole subtree.
tui_ops.remove() {
	local n="$1" node
	_tui_ops.detach "$n"
	_tui_ops.collect "$n"
	for node in "${_OP_LIST[@]}"; do
		[[ -n "${_N_ID[$node]:-}" && "${_N_BY_ID[${_N_ID[$node]}]:-}" == "$node" ]] && unset '_N_BY_ID[${_N_ID[$node]}]'
		unset '_N_TYPE[$node]' '_N_PARENT[$node]' '_N_KIDS[$node]' '_N_ID[$node]'
	done
	for node in "${_OP_LIST[@]}"; do tui_node.attr_unset_all "$node"; done
}

# tui_ops.replace OLD N - N takes OLD's place; OLD's subtree is freed.
tui_ops.replace() {
	tui_ops.insert before "$1" "$2" || return
	tui_ops.remove "$1"
}

# tui_ops.set N ATTR VALUE
tui_ops.set() {
	local n="$1" attr="$2" value="$3" old
	if [[ "$attr" == id ]]; then
		old="${_N_ID[$n]:-}"
		[[ -n "$old" && "${_N_BY_ID[$old]:-}" == "$n" ]] && unset '_N_BY_ID[$old]'
		_N_ID[$n]="$value"
		[[ -n "$value" ]] && _N_BY_ID[$value]=$n
	fi
	tui_node.attr_set "$n" "$attr" "$value"
}

# tui_ops.wrap N TYPE [ID] -> _N : the new wrapper node.
tui_ops.wrap() {
	local n="$1" type="$2" id="${3:-}" w
	tui_node.create "$type" "$id"
	w=$_N
	[[ -n "$id" ]] && tui_node.attr_set "$w" id "$id"
	tui_ops.insert before "$n" "$w" || {
		_N=$w
		return 1
	}
	tui_ops.insert append "$w" "$n"
	_N=$w
}

# tui_ops.move N MODE TARGET
tui_ops.move() { tui_ops.insert "$2" "$3" "$1"; }

# tui_ops.params NODE [SKIP...] - _OP_PARAMS = NODE's attributes (name -> value) minus
# internal __* ones and the SKIP names; merged over what is already in _OP_PARAMS.
tui_ops.params() {
	local node="$1" name skip
	shift
	for name in ${_N_ANAMES[$node]:-}; do
		[[ "$name" == __* ]] && continue
		for skip in "$@"; do [[ "$name" == "$skip" ]] && continue 2; done
		_OP_PARAMS[$name]="${_N_ATTR["$node.$name"]}"
	done
}

# tui_ops.subst_all N... - {{@NAME}} -> _OP_PARAMS[NAME] in every attribute value under each N (an `id` change goes
# through tui_ops.set so the by-id index follows). One pass over the attribute table for all of them; nothing at all
# when there are no parameters.
tui_ops.subst_all() {
	((${#_OP_PARAMS[@]})) || return 0
	local key name attr val node root
	local -a changed=()
	_OP_SET=()
	_OP_LIST=()
	for root in "$@"; do
		_tui_ops.collect_walk "$root" # adds to _OP_SET/_OP_LIST without clearing them
	done
	for node in "${_OP_LIST[@]}"; do
		for attr in ${_N_ANAMES[$node]:-}; do
			key="$node.$attr"
			[[ "${_N_ATTR[$key]}" == *"{{@"* ]] || continue
			val="${_N_ATTR[$key]}"
			# quoted replacement: a value holding & must stay literal (bash 5.2+ patsub_replacement)
			for name in "${!_OP_PARAMS[@]}"; do val="${val//"{{@$name}}"/"${_OP_PARAMS[$name]}"}"; done
			[[ "$val" == "${_N_ATTR[$key]}" ]] && continue
			changed+=("$node" "$attr" "$val")
		done
	done
	set -- "${changed[@]}"
	while (($#)); do
		tui_ops.set "$1" "$2" "$3"
		shift 3
	done
}

# tui_ops.subst N - tui_ops.subst_all for one node
tui_ops.subst() { tui_ops.subst_all "$1"; }
