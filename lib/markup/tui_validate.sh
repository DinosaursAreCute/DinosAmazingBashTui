#!/usr/bin/env bash
# tui_validate.sh - markup validation engine: walks a page (following <include>s, keeping file/line/col),
# runs every registered rule and collects the findings. It never builds UI and never forks per line.
#
# The rules themselves live in tui_validate_rules.sh. Two ways to add one:
#   declarative   tui.validate.tag / .container / .require / .enum / .int / .conflict / .needs /
#                 .parent / .parent_split / .self_closing   (tables, checked for every element)
#   custom        tui.validate.rule page|element|end FN     (FN reads the TUI_V_* context below and
#                 reports with tui.validate.error / .warn / .error_at)
#
# Context a custom rule sees (read-only):
#   element  TUI_V_FILE TUI_V_LINE TUI_V_COL TUI_V_TAG TUI_V_RAW TUI_V_SELFCLOSE TUI_V_DEPTH (open containers around it)
#            TUI_V_PARENT_TAG TUI_V_PARENT_ID TUI_V_PARENT_SPLIT TUI_V_GRANDPARENT_SPLIT (empty at top level)
#            tui.validate.attr NAME -> REPLY (status 1 when the attribute is absent)
#   end      TUI_V_PAGE, TUI_V_PANES[id]=loc, TUI_V_PANE_SPLIT[id], TUI_V_WIDGETS[id]=loc,
#            TUI_V_WIDGET_PANE[id]=pane, TUI_V_WIDGET_PANE_AT[id]=loc   (loc = "file|line|col")
#
# Running: tui.validate.files PAGE...  (status 1 when any error was found), then tui.validate.report
# (stderr-ready text) and tui.validate.log (into the app log through tui.log, see tui.log.file).

# ── rule tables ─────────────────────────────────────────────────────────
declare -gA _TV_TAGS=() _TV_CONTAINER=() _TV_WIDGET=() _TV_SELFCLOSE=()
declare -gA _TV_REQ=()       # tag -> "attr attr ..."
declare -gA _TV_ENUM=()      # "tag.attr" or "*.attr" -> "a|b|c"
declare -gA _TV_INT=()       # "tag.attr" or "*.attr" -> minimum
declare -gA _TV_CONFLICT=()  # tag -> "a,b a,c ..."   _TV_WHY["tag.a,b"] -> reason
declare -gA _TV_NEEDS=()     # "tag.attr" -> "other=value"
declare -gA _TV_PARENT=()    # tag -> "parenttag ..." ("-" = top level of the page)
declare -gA _TV_PSPLIT=()    # "tag.attr" -> parent split the attribute requires
declare -gA _TV_WHY=()
declare -ga _TV_RULES_PAGE=() _TV_RULES_ELEMENT=() _TV_RULES_END=()

# ── findings ────────────────────────────────────────────────────────────
declare -ga _TV_F_SEV=() _TV_F_LOC=() _TV_F_MSG=()
declare -g TUI_V_ERRORS=0 TUI_V_WARNINGS=0

# ── walk state / rule context ───────────────────────────────────────────
declare -gA _TV_A=() _TV_AC=() _TV_SEEN=() _TV_READ=()
declare -ga _TV_ST_TAG=() _TV_ST_ID=() _TV_ST_SPLIT=() _TV_ST_LOC=()
declare -gA TUI_V_PANES=() TUI_V_PANE_SPLIT=() TUI_V_WIDGETS=() TUI_V_WIDGET_PANE=() TUI_V_WIDGET_PANE_AT=()
declare -g TUI_V_PAGE="" TUI_V_FILE="" TUI_V_LINE=0 TUI_V_COL=1 TUI_V_TAG="" TUI_V_RAW="" TUI_V_SELFCLOSE=0
declare -g TUI_V_DEPTH=0 TUI_V_PARENT_TAG="" TUI_V_PARENT_ID="" TUI_V_PARENT_SPLIT="" TUI_V_GRANDPARENT_SPLIT=""

# ═══ registration API ═══════════════════════════════════════════════════

# tui.validate.tag TAG...            tags the loader understands (anything else is reported)
tui.validate.tag() { local t; for t; do _TV_TAGS[$t]=1; done; }
# tui.validate.container TAG...      tags that may have children (<tag>…</tag>); implies tui.validate.tag
tui.validate.container() { local t; for t; do _TV_TAGS[$t]=1; _TV_CONTAINER[$t]=1; done; }
# tui.validate.widget TAG...         widget tags: their id/pane are recorded for cross-reference rules
tui.validate.widget() { local t; for t; do _TV_TAGS[$t]=1; _TV_WIDGET[$t]=1; done; }
# tui.validate.self_closing TAG...   must be written <tag … />
tui.validate.self_closing() { local t; for t; do _TV_SELFCLOSE[$t]=1; done; }
# tui.validate.require TAG ATTR...   attributes that must be present and non-empty
tui.validate.require() { local t="$1"; shift; _TV_REQ[$t]="${_TV_REQ[$t]:+${_TV_REQ[$t]} }$*"; }
# tui.validate.enum TAG|* ATTR "a|b|c"
tui.validate.enum() { _TV_ENUM["$1.$2"]="$3"; }
# tui.validate.int TAG|* ATTR MIN    whole number >= MIN (MIN may be negative)
tui.validate.int() { _TV_INT["$1.$2"]="$3"; }
# tui.validate.conflict TAG ATTR_A ATTR_B [WHY]   the two may not be given together
tui.validate.conflict() { _TV_CONFLICT[$1]="${_TV_CONFLICT[$1]:+${_TV_CONFLICT[$1]} }$2,$3"; _TV_WHY["$1.$2,$3"]="${4:-}"; }
# tui.validate.needs TAG ATTR OTHER VALUE         ATTR only has an effect when OTHER="VALUE"
tui.validate.needs() { _TV_NEEDS["$1.$2"]="$3=$4"; }
# tui.validate.parent TAG PARENT...               allowed enclosing tags ("-" = directly in the page)
tui.validate.parent() { local t="$1"; shift; _TV_PARENT[$t]="$*"; }
# tui.validate.parent_split TAG ATTR SPLIT        ATTR only has an effect inside a <pane split="SPLIT">
tui.validate.parent_split() { _TV_PSPLIT["$1.$2"]="$3"; }
# tui.validate.rule page|element|end FN          custom check (see the header for its context)
tui.validate.rule() {
	case "$1" in
		page) _TV_RULES_PAGE+=("$2") ;;
		element) _TV_RULES_ELEMENT+=("$2") ;;
		end) _TV_RULES_END+=("$2") ;;
		*) echo "tui.validate.rule: kind must be page|element|end, got '$1'" >&2; return 1 ;;
	esac
}

# ═══ rule-side helpers ══════════════════════════════════════════════════

# tui.validate.attr NAME -> REPLY
tui.validate.attr() { [[ -n "${_TV_A[$1]+x}" ]] || { REPLY=""; return 1; }; REPLY="${_TV_A[$1]}"; }
# tui.validate.here [ATTR] -> REPLY = "file|line|col" of the current element (or of ATTR on it)
tui.validate.here() {
	local col="$TUI_V_COL"
	[[ -n "${1:-}" && -n "${_TV_AC[$1]:-}" ]] && col="${_TV_AC[$1]}"
	REPLY="$TUI_V_FILE|$TUI_V_LINE|$col"
}
# tui.validate.error MSG [ATTR] / tui.validate.warn MSG [ATTR]   report on the current element
tui.validate.error() { tui.validate.here "${2:-}"; tui.validate.error_at "$REPLY" "$1"; }
tui.validate.warn() { tui.validate.here "${2:-}"; tui.validate.warn_at "$REPLY" "$1"; }
# tui.validate.error_at LOC MSG / tui.validate.warn_at LOC MSG   LOC = "file|line|col" (col may be empty)
tui.validate.error_at() { _TV_F_SEV+=(error); _TV_F_LOC+=("$1"); _TV_F_MSG+=("$2"); ((TUI_V_ERRORS++)); return 0; }
tui.validate.warn_at() { _TV_F_SEV+=(warn); _TV_F_LOC+=("$1"); _TV_F_MSG+=("$2"); ((TUI_V_WARNINGS++)); return 0; }

# ═══ engine ═════════════════════════════════════════════════════════════

# _tui_validate.attrs RAW -> _TV_A[name]=value, _TV_AC[name]=1-based column (same entity decoding as _markup_attr)
_tui_validate.attrs() {
	local rest="$1" off=0 col pre sp t v name
	# plain expansions only: a regex here is recompiled on every match and costs several times more
	_TV_A=() _TV_AC=()
	while [[ "$rest" == *=*\"*\"* ]]; do
		pre="${rest%%=*}"
		rest="${rest:${#pre}+1}"
		sp="${rest%%\"*}" # between = and the opening quote
		[[ "$sp" == *[![:space:]]* ]] && break
		rest="${rest:${#sp}+1}"
		v="${rest%%\"*}"
		rest="${rest:${#v}+1}"
		t="${pre%"${pre##*[![:space:]]}"}"
		name="${t##*[[:space:]]}"
		col=$((off + ${#t} - ${#name} + 1))
		off=$((off + ${#pre} + ${#sp} + ${#v} + 3))
		[[ -n "$name" && "$name" != *[!a-zA-Z0-9_:.-]* ]] || continue
		if [[ -n "${_TV_A[$name]+x}" ]]; then
			tui.validate.error_at "$TUI_V_FILE|$TUI_V_LINE|$col" "attribute '$name' given twice on <$TUI_V_TAG> (the loader uses the first one)"
		else
			[[ "$v" == *"&"* ]] && { v="${v//&lt;/<}"; v="${v//&gt;/>}"; v="${v//&quot;/\"}"; v="${v//&amp;/\&}"; }
			_TV_A[$name]="$v" _TV_AC[$name]=$col
		fi
	done
}

# _tui_validate.tables - the declarative checks for the current element
_tui_validate.tables() {
	local t="$TUI_V_TAG" a k v min num pair why want parents
	for a in ${_TV_REQ[$t]:-}; do
		[[ -n "${_TV_A[$a]:-}" ]] || tui.validate.error "<$t> is missing the required attribute '$a'"
	done
	for a in "${!_TV_A[@]}"; do
		v="${_TV_A[$a]}"
		k="$t.$a"; [[ -n "${_TV_ENUM[$k]+x}" ]] || k="*.$a"
		if [[ -n "${_TV_ENUM[$k]+x}" && "|${_TV_ENUM[$k]}|" != *"|$v|"* ]]; then
			tui.validate.error "$a=\"$v\" is not valid on <$t> (expected one of: ${_TV_ENUM[$k]//|/, })" "$a"
		fi
		k="$t.$a"; [[ -n "${_TV_INT[$k]+x}" ]] || k="*.$a"
		if [[ -n "${_TV_INT[$k]+x}" ]]; then
			min="${_TV_INT[$k]}"
			if [[ ! "$v" =~ ^-?[0-9]+$ ]]; then
				tui.validate.error "$a=\"$v\" on <$t> must be a whole number" "$a"
			else
				num=$((10#${v#-}))
				[[ "$v" == -* ]] && num=$((-num))
				((num < min)) && tui.validate.error "$a=\"$v\" on <$t> must be at least $min" "$a"
			fi
		fi
		want="${_TV_NEEDS[$t.$a]:-}"
		if [[ -n "$want" && "${_TV_A[${want%%=*}]:-}" != "${want#*=}" ]]; then
			tui.validate.error "$a on <$t> only applies together with ${want%%=*}=\"${want#*=}\"" "$a"
		fi
		want="${_TV_PSPLIT[$t.$a]:-}"
		if [[ -n "$want" && "$TUI_V_PARENT_SPLIT" != "$want" ]]; then
			tui.validate.error "$a on <$t> only applies to a direct child of a <pane split=\"$want\">${TUI_V_PARENT_ID:+ (parent '$TUI_V_PARENT_ID' is split=\"$TUI_V_PARENT_SPLIT\")}" "$a"
		fi
	done
	for pair in ${_TV_CONFLICT[$t]:-}; do
		if [[ -n "${_TV_A[${pair%,*}]+x}" && -n "${_TV_A[${pair#*,}]+x}" ]]; then
			why="${_TV_WHY[$t.$pair]:-}"
			tui.validate.error "<$t> cannot have both '${pair%,*}' and '${pair#*,}'${why:+ - $why}" "${pair#*,}"
		fi
	done
	parents="${_TV_PARENT[$t]:-}"
	if [[ -n "$parents" && " $parents " != *" ${TUI_V_PARENT_TAG:--} "* ]]; then
		tui.validate.error "<$t> is not allowed ${TUI_V_PARENT_TAG:+inside <$TUI_V_PARENT_TAG>}${TUI_V_PARENT_TAG:-at the top level} (allowed in: ${parents//-/the page})"
	fi
	if [[ -n "${_TV_SELFCLOSE[$t]:-}" ]] && ((!TUI_V_SELFCLOSE)); then
		tui.validate.error "<$t> must be self-closing: write <$t … />"
	fi
}

# _tui_validate.walk FILE - one file of a page; recurses into <include>s (fragments share the tag stack)
_tui_validate.walk() {
	local file="$1" raw lead line tag closing lno=0 incomment=0 fn
	_tui_path_canon "$file"
	file="$_CANON"
	if [[ -n "${_TV_SEEN[$file]:-}" ]]; then
		tui.validate.error_at "$TUI_V_FILE|$TUI_V_LINE|$TUI_V_COL" "include cycle: '$file' is already being included"
		return 0
	fi
	_TV_SEEN[$file]=1
	_TV_READ[$file]=1
	while IFS= read -r raw || [[ -n "$raw" ]]; do
		((lno++))
		lead="${raw%%<*}"
		line="${raw#"${raw%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		if ((incomment)); then
			[[ "$line" == *"-->"* ]] && incomment=0
			if [[ "$line" =~ ^\</?[a-zA-Z_] ]]; then
				tui.validate.error_at "$file|$lno|$((${#lead} + 1))" "a tag on a comment line is still read by the loader (it only skips lines that start with <!--)"
			fi
			continue
		fi
		if [[ "$line" == \<!--* ]]; then
			[[ "$line" == *"-->"* ]] || incomment=1
			continue
		fi
		if [[ "$line" == *"<!--"* ]]; then # trailing comment, dropped like the loader does: <pane … />  <!-- note -->
			[[ "${line#*<!--}" == *"-->"* ]] || incomment=1
			raw="${raw%%<!--*}"
			line="${line%%<!--*}"
			line="${line%"${line##*[![:space:]]}"}"
		fi
		[[ "$line" == \<[a-zA-Z_]* || "$line" == \</[a-zA-Z_]* ]] || continue # same tags the loader sees (no regex: it is recompiled per line)
		tag="${line#<}" closing=0
		[[ "$tag" == /* ]] && closing=1 tag="${tag#/}"
		tag="${tag%%[!a-zA-Z0-9_-]*}"
		TUI_V_FILE="$file" TUI_V_LINE=$lno TUI_V_COL=$((${#lead} + 1)) TUI_V_TAG="$tag" TUI_V_RAW="$raw"
		if ((closing)); then
			_tui_validate.close
			continue
		fi
		TUI_V_SELFCLOSE=0
		[[ "$line" == *"/>" ]] && TUI_V_SELFCLOSE=1
		_tui_validate.attrs "$raw"
		local n=${#_TV_ST_TAG[@]}
		TUI_V_DEPTH=$n TUI_V_PARENT_TAG="" TUI_V_PARENT_ID="" TUI_V_PARENT_SPLIT="" TUI_V_GRANDPARENT_SPLIT=""
		if ((n > 0)); then
			TUI_V_PARENT_TAG="${_TV_ST_TAG[n - 1]}" TUI_V_PARENT_ID="${_TV_ST_ID[n - 1]}" TUI_V_PARENT_SPLIT="${_TV_ST_SPLIT[n - 1]}"
			((n > 1)) && TUI_V_GRANDPARENT_SPLIT="${_TV_ST_SPLIT[n - 2]}"
		fi
		[[ "$TUI_V_PARENT_TAG" == tui ]] && TUI_V_PARENT_TAG="" # directly in the page

		if [[ -z "${_TV_TAGS[$tag]:-}" ]]; then
			tui.validate.error "unknown tag <$tag> - the loader ignores it"
			continue
		fi
		_tui_validate.tables
		_tui_validate.record
		for fn in "${_TV_RULES_ELEMENT[@]}"; do "$fn"; done

		if [[ "$tag" == include ]]; then
			local src="${_TV_A[src]:-}" inc
			[[ -n "$src" ]] || continue
			inc="$src"
			[[ "$inc" != /* ]] && inc="${file%/*}/$src"
			if [[ -r "$inc" ]]; then
				_tui_validate.walk "$inc"
			else
				tui.validate.error "included file '$src' not found (looked for $inc)" src
			fi
			continue
		fi
		if ((!TUI_V_SELFCLOSE)) && [[ -n "${_TV_CONTAINER[$tag]:-}" ]]; then
			_TV_ST_TAG+=("$tag") _TV_ST_ID+=("${_TV_A[id]:-}") _TV_ST_SPLIT+=("${_TV_A[split]:-}") _TV_ST_LOC+=("$file|$lno|$TUI_V_COL")
		fi
	done <"$file"
	unset '_TV_SEEN[$file]'
	if ((incomment)); then tui.validate.error_at "$file|$lno|" "comment opened in this file is never closed (missing -->)"; fi
}

# _tui_validate.close - a </tag> line
_tui_validate.close() {
	local n=${#_TV_ST_TAG[@]} top
	if ((n == 0)); then
		tui.validate.error "closing </$TUI_V_TAG> has no matching opening tag"
		return
	fi
	top="${_TV_ST_TAG[n - 1]}"
	if [[ "$top" != "$TUI_V_TAG" ]]; then
		local loc="${_TV_ST_LOC[n - 1]}"
		loc="${loc#*|}"
		tui.validate.error "closing </$TUI_V_TAG> does not match the open <$top> from line ${loc%%|*}"
		return
	fi
	unset '_TV_ST_TAG[n-1]' '_TV_ST_ID[n-1]' '_TV_ST_SPLIT[n-1]' '_TV_ST_LOC[n-1]'
}

# _tui_validate.record - built-in bookkeeping the cross-reference (end) rules read
_tui_validate.record() {
	local id="${_TV_A[id]:-}"
	[[ -n "$id" ]] || return 0
	tui.validate.here id
	if [[ "$TUI_V_TAG" == pane ]]; then
		if [[ -n "${TUI_V_PANES[$id]:-}" ]]; then
			local p="${TUI_V_PANES[$id]}"
			_tui_validate.where "$p"
			tui.validate.error "pane id '$id' is already used $REPLY" id
		else
			TUI_V_PANES[$id]="$REPLY"
			TUI_V_PANE_SPLIT[$id]="${_TV_A[split]:-}"
		fi
	elif [[ -n "${_TV_WIDGET[$TUI_V_TAG]:-}" ]]; then
		if [[ -n "${TUI_V_WIDGETS[$id]:-}" ]]; then
			local w="${TUI_V_WIDGETS[$id]}"
			_tui_validate.where "$w"
			tui.validate.error "widget id '$id' is already used $REPLY" id
		else
			TUI_V_WIDGETS[$id]="$REPLY"
			TUI_V_WIDGET_PANE[$id]="${_TV_A[pane]:-}"
			tui.validate.here pane
			TUI_V_WIDGET_PANE_AT[$id]="$REPLY"
		fi
	fi
}
# _tui_validate.show PATH -> REPLY: relative to $PWD, or ~/…
_tui_validate.show() {
	REPLY="$1"
	[[ "$REPLY" == "$PWD/"* ]] && REPLY="${REPLY#"$PWD/"}"
	[[ "$REPLY" == "$HOME/"* ]] && REPLY="~/${REPLY#"$HOME/"}"
}
# _tui_validate.where LOC -> REPLY: "at line N" (same file) or "in FILE line N"
_tui_validate.where() {
	local f="${1%%|*}" r="${1#*|}"
	if [[ "$f" == "$TUI_V_FILE" ]]; then REPLY="at line ${r%%|*}"; else _tui_validate.show "$f"; REPLY="in $REPLY line ${r%%|*}"; fi
}

# tui.validate.page FILE - validate one page (its ids are independent of other pages)
tui.validate.page() {
	local fn
	_tui_path_canon "$1"
	TUI_V_PAGE="$_CANON" TUI_V_FILE="$_CANON" TUI_V_LINE=0 TUI_V_COL=1
	_TV_ST_TAG=() _TV_ST_ID=() _TV_ST_SPLIT=() _TV_ST_LOC=() _TV_SEEN=()
	TUI_V_PANES=() TUI_V_PANE_SPLIT=() TUI_V_WIDGETS=() TUI_V_WIDGET_PANE=() TUI_V_WIDGET_PANE_AT=()
	[[ -r "$TUI_V_PAGE" ]] || { tui.validate.error_at "$TUI_V_PAGE|0|" "page file cannot be read"; return; }
	for fn in "${_TV_RULES_PAGE[@]}"; do "$fn"; done
	_tui_validate.walk "$TUI_V_PAGE"
	local i
	for ((i = ${#_TV_ST_TAG[@]} - 1; i >= 0; i--)); do
		tui.validate.error_at "${_TV_ST_LOC[i]}" "<${_TV_ST_TAG[i]}${_TV_ST_ID[i]:+ id=\"${_TV_ST_ID[i]}\"}> is never closed"
	done
	for fn in "${_TV_RULES_END[@]}"; do "$fn"; done
}

# tui.validate.files PAGE... - clears earlier findings, validates every page; status 1 on any error
tui.validate.files() {
	_TV_F_SEV=() _TV_F_LOC=() _TV_F_MSG=()
	_TV_READ=()
	TUI_V_ERRORS=0 TUI_V_WARNINGS=0
	local f
	for f; do tui.validate.page "$f"; done
	((TUI_V_ERRORS == 0))
}

# tui.validate.messages -> _TV_LINES: one formatted sentence per finding, in file/line order of discovery
tui.validate.messages() {
	local i loc file line col shown
	_TV_LINES=()
	for i in "${!_TV_F_MSG[@]}"; do
		loc="${_TV_F_LOC[i]}"
		file="${loc%%|*}" loc="${loc#*|}" line="${loc%%|*}" col="${loc#*|}"
		_tui_validate.show "$file"
		shown="$REPLY"
		if [[ "${_TV_F_SEV[i]}" == error ]]; then
			_TV_LINES+=("erroneous configuration in $shown line $line${col:+ col $col}: ${_TV_F_MSG[i]}")
		else
			_TV_LINES+=("questionable configuration in $shown line $line${col:+ col $col}: ${_TV_F_MSG[i]}")
		fi
	done
}
declare -ga _TV_LINES=()

# tui.validate.report - print every finding plus a summary (callers pick the stream)
tui.validate.report() {
	tui.validate.messages
	((${#_TV_LINES[@]})) || return 0
	local l red="" yel="" off=""
	[[ -t 2 ]] && red=$'\e[1;31m' yel=$'\e[33m' off=$'\e[0m'
	local i=0
	for l in "${_TV_LINES[@]}"; do
		[[ "${_TV_F_SEV[i]}" == error ]] && printf '%s%s%s\n' "$red" "$l" "$off" || printf '%s%s%s\n' "$yel" "$l" "$off"
		((i++))
	done
	printf '%d error(s), %d warning(s)\n' "$TUI_V_ERRORS" "$TUI_V_WARNINGS"
}

# tui.validate.log - every finding into the tui.log file (tui.log.file)
tui.validate.log() {
	tui.validate.messages
	local i
	for i in "${!_TV_LINES[@]}"; do tui.log "${_TV_LINES[i]}" "${_TV_F_SEV[i]}"; done
}

# _tui_validate.gate PAGE... - used by tui.start/tui.start_cached before the terminal is taken over.
# Errors abort the start unless TUI_IGNORE_INVALID_XML=1 (dabt --ignore-invalid-xml); then the page runs and
# _tui_validate.notify shows a notification once the UI is up.
declare -g _TV_NOTIFY=""
_tui_validate.gate() {
	[[ "${TUI_VALIDATE:-1}" == 0 ]] && return 0
	local f l
	local -a pages=()
	for f; do # <binds>/<cmds> files sit next to pages (a *.xml sweep finds them) but are not pages
		l=""
		[[ -r "$f" ]] && while IFS= read -r l; do [[ "$l" == *\<[a-zA-Z]* && "$l" != *\<!--* ]] && break; done <"$f"
		[[ "$l" == *\<binds[\ \>]* || "$l" == *\<cmds[\ \>]* ]] || pages+=("$f")
	done
	set -- "${pages[@]}"
	_tui_validate.fresh "$@" && return 0
	tui.validate.files "$@"
	((TUI_V_ERRORS)) || _tui_validate.stamp "$@"
	((TUI_V_ERRORS + TUI_V_WARNINGS)) || return 0
	tui.validate.log
	((TUI_V_ERRORS)) || return 0 # warnings are only logged
	tui.validate.report >&2
	if [[ "${TUI_IGNORE_INVALID_XML:-0}" == 1 ]]; then
		_TV_NOTIFY="$TUI_V_ERRORS configuration error(s) ignored (--ignore-invalid-xml) - see $(tui.log.file)|error"
		return 0
	fi
	printf 'start aborted: fix the configuration above, or run with --ignore-invalid-xml to start anyway\n' >&2
	return 1
}

# A clean run is remembered in $TUI_HOME/cache/validated: the page list, then "mtime path" for every file it read
# (pages, includes, the rules). The next start with the same pages and unchanged files skips the walk - one stat call.
_tui_validate.mtimes() { stat -c '%Y' -- "$@" 2>/dev/null || stat -f '%m' -- "$@" 2>/dev/null; }
_tui_validate.stamp() {
	[[ -n "${TUI_HOME:-}" ]] || return 0
	local IFS=$'\t' f="$TUI_HOME/cache/validated" i=0 m
	local -a files=("${!_TV_READ[@]}" "${BASH_SOURCE[0]}" "${BASH_SOURCE[0]%/*}/tui_validate_rules.sh") times=()
	mapfile -t times < <(_tui_validate.mtimes "${files[@]}")
	((${#times[@]} == ${#files[@]})) || return 0
	mkdir -p "$TUI_HOME/cache" 2>/dev/null || return 0
	{
		printf '%s\n' "$*"
		for m in "${times[@]}"; do printf '%s %s\n' "$m" "${files[i++]}"; done
	} >"$f" 2>/dev/null
}
_tui_validate.fresh() {
	local f="${TUI_HOME:-}/cache/validated" IFS=$'\t' pages l
	[[ -n "${TUI_HOME:-}" && -r "$f" ]] || return 1
	local -a want=() files=() now=()
	{
		IFS= read -r pages
		while IFS= read -r l; do want+=("${l%% *}"); files+=("${l#* }"); done
	} <"$f"
	[[ "$pages" == "$*" ]] && ((${#files[@]})) || return 1
	mapfile -t now < <(_tui_validate.mtimes "${files[@]}")
	[[ "${now[*]}" == "${want[*]}" ]]
}

_tui_validate.notify() {
	[[ -n "$_TV_NOTIFY" ]] || return 0
	tui.notify "${_TV_NOTIFY%|*}" "${_TV_NOTIFY##*|}" 0
	_TV_NOTIFY=""
}

# shellcheck source=tui_validate_rules.sh
source "${BASH_SOURCE[0]%/*}/tui_validate_rules.sh"
