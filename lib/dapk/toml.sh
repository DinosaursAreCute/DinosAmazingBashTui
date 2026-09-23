#!/usr/bin/env bash
# toml.sh - strict TOML subset parser (awk). Every accepted file is valid TOML.
#
# Supported: # comments, bare and "quoted" keys, "basic" strings (escapes \" \\ \t) and 'literal' strings, true/false, integers, arrays of
# strings/integers/booleans (may span lines), [table] and [[array-of-tables]]. Anything else is an error with its line number.
#
# dapk.toml.parse FILE ASSOC : fills the associative array ASSOC (nameref). Keys are flat:
#     name                     top-level key            dependency.check     [dependency] table key
#     include.2.source         2nd [[include]] table    @count.include       number of [[include]] tables
#   Arrays are stored joined with the unit separator (US, $'\x1f'): use dapk.toml.split to get them back.
# rc 1 and DAPK_TOML_ERROR set on a syntax error.   dapk.toml.split VALUE ARRAY : split a stored array value.

declare -g DAPK_TOML_ERROR=""

dapk.toml.split() {
	local -n _out="$2"
	_out=()
	[[ -n "$1" ]] && IFS=$'\x1f' read -r -a _out <<<"$1"
	return 0
}

_dapk.toml.awk() {
	awk '
    function fail(msg) { printf "ERR\t%d: %s\n", NR, msg; bad = 1; exit 1 }
    function strip_comment(s,   i, c, q, out, n) {
        q = ""; out = ""; n = length(s)
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (q != "") {
                out = out c
                if (q == "\"" && c == "\\") { i++; out = out substr(s, i, 1); continue }
                if (c == q) q = ""
                continue
            }
            if (c == "\"" || c == "\x27") { q = c; out = out c; continue }
            if (c == "#") break
            out = out c
        }
        return out
    }
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    # parse a quoted string at s[pos]; sets VAL and POS (index after the closing quote)
    function pstring(s, pos,   q, c, v, n) {
        q = substr(s, pos, 1); v = ""; n = length(s); pos++
        while (pos <= n) {
            c = substr(s, pos, 1)
            if (q == "\"" && c == "\\") {
                pos++; c = substr(s, pos, 1)
                if (c == "\"" || c == "\\") v = v c
                else if (c == "t") v = v "\t"
                else fail("unsupported escape \\" c " (only \\\" \\\\ \\t)")
                pos++; continue
            }
            if (c == q) { VAL = v; POS = pos + 1; return 1 }
            v = v c; pos++
        }
        fail("unterminated string")
    }
    # parse a scalar (string, bool, int) at s[pos]
    function pscalar(s, pos,   c, rest, tok) {
        c = substr(s, pos, 1)
        if (c == "\"" || c == "\x27") return pstring(s, pos)
        rest = substr(s, pos)
        if (match(rest, /^(true|false)/)) { VAL = substr(rest, 1, RLENGTH); POS = pos + RLENGTH; return 1 }
        if (match(rest, /^[+-]?[0-9_]+/))  { VAL = substr(rest, 1, RLENGTH); gsub(/_/, "", VAL); POS = pos + RLENGTH; return 1 }
        fail("unsupported value (strings, booleans, integers and arrays of them only)")
    }
    function skipws(s, pos) { while (pos <= length(s) && substr(s, pos, 1) ~ /[ \t\r]/) pos++; return pos }
    function balanced(s,   i, c, q, d, n) {   # is the array bracket depth back to 0?
        q = ""; d = 0; n = length(s)
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (q != "") { if (q == "\"" && c == "\\") { i++; continue } if (c == q) q = ""; continue }
            if (c == "\"" || c == "\x27") { q = c; continue }
            if (c == "[") d++; else if (c == "]") d--
        }
        return d <= 0
    }
    function parray(s,   pos, out, first) {   # s starts with [
        pos = 2; out = ""; first = 1
        while (1) {
            pos = skipws(s, pos)
            if (substr(s, pos, 1) == "]") { pos++; break }
            if (!first) { if (substr(s, pos, 1) != ",") fail("expected , or ] in array"); pos = skipws(s, pos + 1); if (substr(s, pos, 1) == "]") { pos++; break } }
            if (substr(s, pos, 1) == "[") fail("nested arrays are not supported")
            pscalar(s, pos); out = out (first ? "" : "\x1f") VAL; pos = POS; first = 0
        }
        if (trim(substr(s, pos)) != "") fail("unexpected text after array")
        VAL = out
    }
    function emit(k, v) {
        if ((k in seen)) fail("duplicate key " k)
        seen[k] = 1; printf "%s=%s\n", k, v
    }
    BEGIN { prefix = ""; pending = ""; }
    {
        line = $0
        if (NR == 1) sub(/^\xef\xbb\xbf/, "", line)
        if (pending != "") { buf = buf " " strip_comment(line); if (!balanced(buf)) next
            parray_src = trim(buf); pending = ""; parray(parray_src); emit(pkey, VAL); next }
        line = trim(strip_comment(line))
        if (line == "") next
        if (line ~ /^\[\[/) {
            if (line !~ /^\[\[[A-Za-z0-9_-]+\]\]$/) fail("bad [[table]] header")
            t = substr(line, 3, length(line) - 4); cnt[t]++; prefix = t "." cnt[t] "."
            if (t in tables) fail("[" t "] is already a plain table")
            arrays[t] = 1; next
        }
        if (line ~ /^\[/) {
            if (line !~ /^\[[A-Za-z0-9_-]+\]$/) fail("bad [table] header")
            t = substr(line, 2, length(line) - 2)
            if (t in arrays) fail("[" t "] is already an array of tables")
            if (t in tables) fail("duplicate table [" t "]")
            tables[t] = 1; prefix = t "."; next
        }
        eq = index(line, "=")
        if (eq == 0) fail("expected key = value")
        key = trim(substr(line, 1, eq - 1)); val = trim(substr(line, eq + 1))
        if (key ~ /^"[^"=]*"$/) key = substr(key, 2, length(key) - 2)
        else if (key !~ /^[A-Za-z0-9_-]+$/) fail("bad key \"" key "\"")
        if (val == "") fail("missing value for " key)
        if (substr(val, 1, 1) == "[") {
            if (!balanced(val)) { pending = 1; buf = val; pkey = prefix key; next }
            parray(val); emit(prefix key, VAL); next
        }
        pscalar(val, 1)
        if (trim(substr(val, POS)) != "") fail("unexpected text after value")
        emit(prefix key, VAL)
    }
    END {
        if (bad) exit 1
        if (pending != "") { printf "ERR\t%d: unterminated array\n", NR; exit 1 }
        for (t in cnt) printf "@count.%s=%d\n", t, cnt[t]
    }' "$1"
}

dapk.toml.parse() {
	local file="$1" line k v
	local -n _tt="$2"
	DAPK_TOML_ERROR=""
	[[ -r "$file" ]] || {
		DAPK_TOML_ERROR="cannot read $file"
		return 1
	}
	while IFS= read -r line; do
		if [[ "$line" == ERR$'\t'* ]]; then
			DAPK_TOML_ERROR="${file##*/}:${line#ERR$'\t'}"
			return 1
		fi
		k="${line%%=*}"
		v="${line#*=}"
		_tt[$k]="$v"
	done < <(_dapk.toml.awk "$file")
	[[ -z "$DAPK_TOML_ERROR" ]]
}
