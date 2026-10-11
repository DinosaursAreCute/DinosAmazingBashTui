#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_compose.sh                                                       ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui_compose.expand ROOT   rewrites the parsed tree under ROOT in place so only plain tags are left:
#
#   <template name="t" p="default">…{{@p}}…<slot name="s">default</slot>…</template>   defined, never drawn
#   <use template="t" id="x" p="v"><fill slot="s">…</fill>loose children</use>          instance of t
#   <component name="box" src="box.xml"/>   <box p="v">…</box>                           a template read from a file, used as a tag
#   <for each="a b c" as="x" index="i">…{{@x}}…</for>    <for count="3" index="i">…</for>
#   <if test="A==B|A!=B|VALUE">…<else>…</else></if>      VALUE is false when empty, "false" or "0"
#   <include src="f.xml" p="v"/>   (expanded by the parser: tui_parse.sh substitutes {{@p}} in the included nodes)
#
# A use with an id prefixes every id of its copy with "ID_", so two uses coexist; without an id the ids stay as written.
# Fill content and loose children are moved, not copied, so keep their ids as written. Everything works on the node
# store through lib/markup/tui_ops.sh; nothing here builds widgets (that is tui_build.sh).
#
# Templates may use other templates. A template that reaches itself is reported in _P_ERRORS and the use is dropped.
# Each copied node remembers the templates it came from in its __via attribute; that is the recursion check.
# requires:

declare -gA _TC_TPL=() # template/component name -> its node (detached from the tree, children are the body)

# tui_compose.expand ROOT - register every template/component under ROOT, then expand directives in document order.
tui_compose.expand() {
	_TC_TPL=()
	_tui_compose.collect "$1"
	_tui_compose.kids "$1"
}

# _tui_compose.collect ROOT - detach each <template>/<component> and remember it under its name.
_tui_compose.collect() {
	local n name src dir file
	local -a list
	_tui_ops.collect "$1"
	list=("${_OP_LIST[@]}")
	for n in "${list[@]}"; do
		case "${_N_TYPE[$n]}" in
			template) ;;
			component) ;;
			*) continue ;;
		esac
		tui_node.attr_get "$n" name && name="$_N_ATTR_V" || name=""
		if [[ -z "$name" ]]; then
			_tui_compose.error "$n" "<${_N_TYPE[$n]}> needs a name"
		else
			_TC_TPL[$name]=$n
			if [[ "${_N_TYPE[$n]}" == component ]]; then
				tui_node.attr_get "$n" src && src="$_N_ATTR_V" || src=""
				tui_node.attr_get "$n" __file && file="$_N_ATTR_V" || file=""
				dir="${file%/*}"
				[[ "$src" == /* || -z "$dir" ]] || src="$dir/$src"
				[[ -n "$src" ]] && _tui_parse.include "$src" "$n"
			fi
		fi
		_tui_ops.detach "$n"
	done
}

# _tui_compose.error NODE MSG - append "file:line: MSG" to _P_ERRORS.
_tui_compose.error() {
	local file="" line=0
	tui_node.attr_get "$1" __file && file="$_N_ATTR_V"
	tui_node.attr_get "$1" __line && line="$_N_ATTR_V"
	_P_ERRORS+=("$file:$line: $2")
}

# _tui_compose.kids P - walks P's children by position and re-reads the list each step, so a directive that
# replaced itself with new nodes has those nodes expanded next, at the same position.
_tui_compose.kids() {
	local p="$1" i=0 k
	local -a kids
	while :; do
		kids=(${_N_KIDS[$p]:-})
		((i < ${#kids[@]})) || break
		k="${kids[i]}"
		if _tui_compose.directive "$k"; then continue; fi
		_tui_compose.kids "$k"
		i=$((i + 1))
	done
}

# _tui_compose.directive N - rc 0 if N was a use/for/if/component tag and has been replaced (and removed), else 1.
_tui_compose.directive() {
	case "${_N_TYPE[$1]}" in
		use) _tui_compose.use "$1" ;;
		for) _tui_compose.for "$1" ;;
		if) _tui_compose.if "$1" ;;
		*)
			[[ -n "${_TC_TPL[${_N_TYPE[$1]}]:-}" ]] || return 1
			_tui_compose.use "$1"
			;;
	esac
}

# _tui_compose.use N - instantiate the template named by N (<use template=…> or a component's own tag).
_tui_compose.use() {
	local n="$1" name via prefix="" tpl k r s slotname
	local -a roots slots
	if [[ "${_N_TYPE[$n]}" == use ]]; then
		tui_node.attr_get "$n" template && name="$_N_ATTR_V" || name=""
	else
		name="${_N_TYPE[$n]}"
	fi
	tpl="${_TC_TPL[$name]:-}"
	if [[ -z "$tpl" ]]; then
		_tui_compose.error "$n" "unknown template '$name'"
		tui_ops.remove "$n"
		return 0
	fi
	via=""
	tui_node.attr_get "$n" __via && via="$_N_ATTR_V"
	if [[ " $via " == *" $name "* ]]; then
		_tui_compose.error "$n" "template recursion: ${via// / -> } -> $name"
		tui_ops.remove "$n"
		return 0
	fi
	via="${via:+$via }$name"
	[[ -n "${_N_ID[$n]:-}" ]] && prefix="${_N_ID[$n]}_"

	_OP_PARAMS=()
	tui_ops.params "$tpl" name src __file __line
	tui_ops.params "$n" template id
	tui_ops.clone_all "$prefix" ${_N_KIDS[$tpl]:-}
	roots=("${_OP_CLONES[@]}")
	tui_ops.subst_all "${roots[@]}"
	for k in "${roots[@]}"; do tui_ops.insert before "$n" "$k"; done
	for r in "${roots[@]}"; do
		_tui_ops.collect "$r"
		for s in "${_OP_LIST[@]}"; do
			case "${_N_TYPE[$s]}" in
				slot) slots+=("$s") ;;
				use | for | if) tui_ops.set "$s" __via "$via" ;; # only a node that can expand again needs the recursion mark
				*) [[ -n "${_TC_TPL[${_N_TYPE[$s]}]:-}" ]] && tui_ops.set "$s" __via "$via" ;;
			esac
		done
	done
	for s in "${slots[@]}"; do
		slotname=""
		tui_node.attr_get "$s" name && slotname="$_N_ATTR_V"
		_tui_compose.fill "$n" "$s" "$slotname"
	done
	tui_ops.remove "$n"
	return 0
}

# _tui_compose.fill USE SLOT NAME - SLOT is replaced by what USE supplies for NAME (a <fill slot=NAME>, or for the
# unnamed slot its loose children), else by SLOT's own default content.
_tui_compose.fill() {
	local use="$1" slot="$2" name="$3" k f sn supplied=0
	local -a content=()
	for k in ${_N_KIDS[$use]:-}; do
		if [[ "${_N_TYPE[$k]}" == fill ]]; then
			sn=""
			tui_node.attr_get "$k" slot && sn="$_N_ATTR_V"
			[[ "$sn" == "$name" ]] || continue
			supplied=1
			content+=(${_N_KIDS[$k]:-})
		elif [[ -z "$name" && "${_N_TYPE[$k]}" != fill ]]; then
			supplied=1
			content+=("$k")
		fi
	done
	((supplied)) || content=(${_N_KIDS[$slot]:-})
	for f in "${content[@]}"; do tui_ops.insert before "$slot" "$f"; done
	tui_ops.remove "$slot"
}

# _tui_compose.for N - one copy of N's body per item, {{@AS}} (default item) and {{@INDEX}} substituted.
_tui_compose.for() {
	local n="$1" each="" count="" as=item idx="" i k pos=0 item
	local -a items=() body
	tui_node.attr_get "$n" each && each="$_N_ATTR_V"
	tui_node.attr_get "$n" count && count="$_N_ATTR_V"
	tui_node.attr_get "$n" as && as="$_N_ATTR_V"
	tui_node.attr_get "$n" index && idx="$_N_ATTR_V"
	if [[ -n "$each" ]]; then
		read -ra items <<<"$each"
	elif [[ "$count" =~ ^[0-9]+$ ]]; then
		for ((i = 0; i < count; i++)); do items+=("$i"); done
	fi
	body=(${_N_KIDS[$n]:-})
	for item in "${items[@]}"; do
		_OP_PARAMS=([$as]="$item")
		[[ -n "$idx" ]] && _OP_PARAMS[$idx]="$pos"
		for k in "${body[@]}"; do
			tui_ops.clone "$k" ""
			tui_ops.subst "$_N"
			tui_ops.insert before "$n" "$_N"
		done
		pos=$((pos + 1))
	done
	tui_ops.remove "$n"
	return 0
}

# _tui_compose.if N - keep N's children when the test holds, else the children of its <else>; N itself goes.
_tui_compose.if() {
	local n="$1" expr="" k
	local -a keep=() other=()
	tui_node.attr_get "$n" test && expr="$_N_ATTR_V"
	for k in ${_N_KIDS[$n]:-}; do
		if [[ "${_N_TYPE[$k]}" == else ]]; then other+=(${_N_KIDS[$k]:-}); else keep+=("$k"); fi
	done
	_tui_compose.truthy "$expr" || keep=("${other[@]}")
	for k in "${keep[@]}"; do tui_ops.insert before "$n" "$k"; done
	tui_ops.remove "$n"
	for k in "${keep[@]}"; do _tui_compose.reindex "$k"; done # both branches may use one id (say a footer): the kept one must own it
	return 0
}

# _tui_compose.reindex N - make every id under N point at its own node in the by-id index again.
_tui_compose.reindex() {
	local s
	_tui_ops.collect "$1"
	for s in "${_OP_LIST[@]}"; do [[ -n "${_N_ID[$s]:-}" ]] && _N_BY_ID[${_N_ID[$s]}]=$s; done
}

# _tui_compose.truthy EXPR - rc 0 for "A==B" with A equal B, "A!=B" with A different, else for a value that is not
# empty, "false" or "0".
_tui_compose.truthy() {
	local e="$1" l r
	e="${e#"${e%%[![:space:]]*}"}"
	e="${e%"${e##*[![:space:]]}"}"
	case "$e" in
		*"!="*)
			l="${e%%!=*}" r="${e#*!=}"
			[[ "$l" != "$r" ]]
			;;
		*"=="*)
			l="${e%%==*}" r="${e#*==}"
			[[ "$l" == "$r" ]]
			;;
		'' | false | 0) return 1 ;;
		*) return 0 ;;
	esac
}
