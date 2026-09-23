#!/usr/bin/env bash
# changelog.sh - Keep-a-Changelog handling: the Unreleased rewrite, News extraction, section extraction. Pure functions over files.
#
# Format:   ## [Unreleased]  /  ## [1.4.2] - 2026-09-21     version sections
#           ### News                                         optional; each line starting with "- " is one bullet (indented lines continue it)
#           ### Fixed ...                                    any other ### section
#
# dapk.changelog.rewrite IN OUT VERSION DATE   OUT = IN with "## [Unreleased]" turned into "## [VERSION] - DATE" and a fresh empty
#                                              "## [Unreleased]" above it. rc 1 when IN has no Unreleased section.
# dapk.changelog.news FILE [DEFAULT_VERSION]   prints "version<TAB>text" per News bullet (a ### News outside any version uses DEFAULT_VERSION)
# dapk.changelog.section FILE VERSION NAME     prints the body of "### NAME" inside "## [VERSION]" (NAME empty: the whole version section)
# dapk.changelog.intro FILE VERSION            prints the paragraph(s) between "## [VERSION]" and its first "###" (the release summary)
# dapk.changelog.unreleased_empty FILE         rc 0 when the Unreleased section holds no entries (or is missing)
# dapk.changelog.previous FILE                 prints the newest released version heading found (after Unreleased)

dapk.changelog.rewrite() {
	local in="$1" out="$2" ver="$3" date="$4"
	grep -qiE '^##[[:space:]]+\[?unreleased\]?' "$in" || return 1
	awk -v ver="$ver" -v date="$date" '
        !done && tolower($0) ~ /^##[ \t]+\[?unreleased\]?/ { print "## [Unreleased]"; print ""; print "## [" ver "] - " date; done = 1; next }
        { print }' "$in" >"$out"
}

dapk.changelog.news() {
	awk -v def="${2:-}" '
        function flush() { if (cur != "") { printf "%s\t%s\n", ver, cur; cur = "" } }
        BEGIN { ver = def; in_news = 0; cur = "" }
        /^#{1,2}[ \t]/ && !/^###/ {
            flush(); in_news = 0
            if (match($0, /\[[^]]+\]/)) ver = substr($0, RSTART + 1, RLENGTH - 2)
            else { t = $0; sub(/^#+[ \t]+/, "", t); sub(/[ \t].*$/, "", t); ver = t }
            if (tolower(ver) == "unreleased") ver = def
            next
        }
        /^###[ \t]/ { flush(); t = $0; sub(/^###[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t); in_news = (tolower(t) == "news"); next }
        !in_news { next }
        /^-[ \t]/ { flush(); cur = $0; sub(/^-[ \t]+/, "", cur); sub(/[ \t\r]+$/, "", cur); next }
        /^[ \t]+[^ \t]/ { if (cur != "") { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t); cur = cur " " t } next }
        /^[ \t\r]*$/ { flush(); next }
        END { flush() }' "$1"
}

dapk.changelog.section() {
	awk -v want="$2" -v name="${3:-}" '
        function ver_of(line) { if (match(line, /\[[^]]+\]/)) return substr(line, RSTART + 1, RLENGTH - 2); t = line; sub(/^#+[ \t]+/, "", t); sub(/[ \t].*$/, "", t); return t }
        /^##[ \t]/ && !/^###/ { in_ver = (ver_of($0) == want); in_sec = 0; next }
        !in_ver { next }
        /^###[ \t]/ {
            t = $0; sub(/^###[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t)
            if (name == "") { print; next }
            in_sec = (tolower(t) == tolower(name)); next
        }
        name == "" || in_sec { print }' "$1" | awk 'NF { started = 1 } started { lines[++n] = $0 } END { while (n > 0 && lines[n] ~ /^[ \t\r]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'
}

dapk.changelog.intro() {
	awk -v want="$2" '
        function ver_of(line) { if (match(line, /\[[^]]+\]/)) return substr(line, RSTART + 1, RLENGTH - 2); t = line; sub(/^#+[ \t]+/, "", t); sub(/[ \t].*$/, "", t); return t }
        /^##[ \t]/ && !/^###/ { in_ver = (ver_of($0) == want); next }
        /^###[ \t]/ { in_ver = 0 }
        in_ver { print }' "$1" | awk 'NF { started = 1 } started { lines[++n] = $0 } END { while (n > 0 && lines[n] ~ /^[ \t\r]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'
}

dapk.changelog.unreleased_empty() {
	[[ -r "$1" ]] || return 0
	local body
	body="$(awk '
        /^##[ \t]/ && !/^###/ { if (tolower($0) ~ /unreleased/) { on = 1; next } else if (on) exit }
        on && !/^###/ && NF { print }' "$1")"
	[[ -z "$body" ]]
}

dapk.changelog.previous() {
	awk '/^##[ \t]/ && !/^###/ && tolower($0) !~ /unreleased/ { if (match($0, /\[[^]]+\]/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit } }' "$1"
}
