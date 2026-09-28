#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_parse.sh                                                         ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui.parse.file FILE -> _P_ROOT   tokenizes FILE (and every <include src>
#                                  it pulls in) into lib/markup/tui_node.sh's
#                                  node store; _P_ROOT is the document node.
#
# Fork-free single-pass scan (markup-v2 stage 1.1): the whole file is read
# once with `read -d ''` (a builtin, no fork), then walked by string index -
# no per-line `read`, no per-attribute regex pass over the raw line the way
# tui_markup.sh's `_markup_attr` used to. A tag can now span multiple
# physical lines, use either quote style, and a comment can appear anywhere
# (not just as a whole line or a fixed trailing suffix). Every node records
# the file and line its opening tag started on, for error messages.
#
# `<include src="…"/>` is expanded inline while scanning: the included
# file's top-level tags become children of the *current* parent, exactly
# where the include tag stood - no "include" node is ever created. A cycle
# (a file including itself, directly or through others) is reported and
# skipped rather than hung on.
#
# This module only builds the tree. Nothing here calls a single tui.* API -
# that dispatch is lib/markup/tui_build.sh's job (stage 1.2).

declare -g _P_ROOT=""
declare -gA _P_SEEN=()
declare -ga _P_ERRORS=()

# tui.parse.file FILE -> _P_ROOT : resets the node store and parses FILE
# (and its includes) into a fresh tree. _P_ROOT is a synthetic "document"
# node whose children are the file's top-level tags.
tui.parse.file() {
	local file="$1"
	tui_node.reset
	_P_SEEN=()
	_P_ERRORS=()
	tui_node.create document
	_P_ROOT=$_N
	_tui_parse.include "$file" "$_P_ROOT"
}

# _tui_parse.include FILE PARENT - reads FILE and scans it into PARENT's
# children, recursing into any <include> it finds. Cycle-guarded by
# _tui_path_canon's fork-free absolute-path string (lib/markup/tui_markup.sh).
_tui_parse.include() {
	local file="$1" parent="$2" dir key content
	_tui_path_canon "$file"
	key="$_CANON"
	if [[ -n "${_P_SEEN[$key]:-}" ]]; then
		_P_ERRORS+=("$file:0: include cycle detected at '$key'")
		return 0
	fi
	_P_SEEN[$key]=1
	if [[ ! -r "$key" ]]; then
		_P_ERRORS+=("$file:0: cannot read '$key'")
		return 1
	fi
	dir="${key%/*}"
	content=""
	IFS= read -r -d '' content <"$key" || true
	_tui_parse.scan "$content" "$key" "$dir" "$parent"
}

# _tui_parse.scan CONTENT FILE DIR PARENT - the actual tokenizer: walks
# CONTENT by index once, creating one node per opening/self-closing tag
# (nested under whichever tag is currently open), skipping comments and
# closing tags, and splicing <include> targets in place.
_tui_parse.scan() {
	local content="$1" file="$2" dir="$3" parent="$4"
	local pos=0 len=${#content} line=1
	local -a stack=("$parent")

	while ((pos < len)); do
		local rest="${content:pos}"
		local before="${rest%%<*}"
		if [[ -n "$before" ]]; then
			local trimmed="${before//[$' \t\r\n']/}"
			if [[ -n "$trimmed" ]]; then
				tui_node.create text "" "${stack[-1]}"
				tui_node.attr_set "$_N" text "$before"
				tui_node.attr_set "$_N" __file "$file"
				tui_node.attr_set "$_N" __line "$line"
			fi
			local nl="${before//[!$'\n']/}"
			line=$((line + ${#nl}))
			pos=$((pos + ${#before}))
			continue
		fi
		((pos >= len)) && break

		if [[ "$rest" == '<!--'* ]]; then
			local after="${rest:4}"
			local head="${after%%'-->'*}"
			local consumed=$((4 + ${#head} + 3))
			((consumed > ${#rest})) && consumed=${#rest} # unterminated: consume to EOF
			local nlcount="${rest:0:consumed}"
			nlcount="${nlcount//[!$'\n']/}"
			line=$((line + ${#nlcount}))
			pos=$((pos + consumed))
			continue
		fi

		if [[ "$rest" == '</'* ]]; then
			local head="${rest%%'>'*}"
			local consumed=$((${#head} + 1))
			((consumed > ${#rest})) && consumed=${#rest}
			((${#stack[@]} > 1)) && unset 'stack[-1]'
			local nlcount="${rest:0:consumed}"
			nlcount="${nlcount//[!$'\n']/}"
			line=$((line + ${#nlcount}))
			pos=$((pos + consumed))
			continue
		fi

		if [[ "$rest" =~ ^\<([a-zA-Z_][a-zA-Z0-9_-]*) ]]; then
			local tagname="${BASH_REMATCH[1]}"
			local start_line=$line
			local i=1 n=${#rest} qc=""
			while ((i < n)); do
				local c="${rest:i:1}"
				if [[ -n "$qc" ]]; then
					[[ "$c" == "$qc" ]] && qc=""
				elif [[ "$c" == '"' || "$c" == "'" ]]; then
					qc="$c"
				elif [[ "$c" == '>' ]]; then
					break
				fi
				((i++))
			done
			if ((i >= n)); then
				_P_ERRORS+=("$file:$start_line: unterminated tag <$tagname>")
				pos=$((pos + n))
				continue
			fi
			local selfclose=0
			[[ "${rest:i-1:1}" == '/' ]] && selfclose=1
			local tagbody="${rest:1:i-1}"
			local attrtext="${tagbody:${#tagname}}"
			((selfclose)) && attrtext="${attrtext%/}"

			if [[ "$tagname" == "include" ]]; then
				local src
				src="$(_tui_parse.attr_value "$attrtext" src)"
				if [[ -n "$src" ]]; then
					local resolved="$src"
					[[ "$resolved" != /* ]] && resolved="${dir}/${src}"
					_tui_parse.include "$resolved" "${stack[-1]}"
				fi
			else
				tui_node.create "$tagname" "" "${stack[-1]}"
				local node=$_N
				tui_node.attr_set "$node" __file "$file"
				tui_node.attr_set "$node" __line "$start_line"
				_tui_parse.attrs "$node" "$attrtext"
				local idv
				if tui_node.attr_get "$node" id; then
					idv="$_N_ATTR_V"
					_N_ID[$node]="$idv"
					[[ -n "$idv" ]] && _N_BY_ID[$idv]=$node
				fi
				((selfclose == 0)) && stack+=("$node")
			fi

			local consumed=$((i + 1))
			local nlcount="${rest:0:consumed}"
			nlcount="${nlcount//[!$'\n']/}"
			line=$((line + ${#nlcount}))
			pos=$((pos + consumed))
			continue
		fi

		pos=$((pos + 1)) # stray '<' not starting a tag name: literal text, skip one char
	done
}

# _tui_parse.attrs NODE ATTRTEXT - parses every name="value"/name='value'
# pair in ATTRTEXT (both quote styles, XML entities decoded) and stores
# each with tui_node.attr_set.
_tui_parse.attrs() {
	local node="$1" body="$2" name val
	while [[ "$body" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_:-]*)[[:space:]]*=[[:space:]]*(\"([^\"]*)\"|\'([^\']*)\') ]]; do
		name="${BASH_REMATCH[1]}"
		if [[ -n "${BASH_REMATCH[3]}" || "${BASH_REMATCH[2]:0:1}" == '"' ]]; then
			val="${BASH_REMATCH[3]}"
		else
			val="${BASH_REMATCH[4]}"
		fi
		[[ "$val" == *"&"* ]] && val="$(_tui_parse.decode_entities "$val")"
		tui_node.attr_set "$node" "$name" "$val"
		body="${body:${#BASH_REMATCH[0]}}"
	done
}

# _tui_parse.attr_value ATTRTEXT NAME -> stdout : single-attribute lookup,
# used only for <include src="…"> before its target node (it has none) exists.
_tui_parse.attr_value() {
	local body="$1" name="$2"
	if [[ "$body" =~ $name[[:space:]]*=[[:space:]]*(\"([^\"]*)\"|\'([^\']*)\') ]]; then
		if [[ "${BASH_REMATCH[1]:0:1}" == '"' ]]; then
			printf '%s' "${BASH_REMATCH[2]}"
		else
			printf '%s' "${BASH_REMATCH[3]}"
		fi
	fi
}

_tui_parse.decode_entities() {
	local v="$1"
	v="${v//&lt;/<}"
	v="${v//&gt;/>}"
	v="${v//&quot;/\"}"
	v="${v//&apos;/\'}"
	v="${v//&amp;/\&}" # unescaped & in a replacement is a bash no-op, not a literal ampersand
	printf '%s' "$v"
}
