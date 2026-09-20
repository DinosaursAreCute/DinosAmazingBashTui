#!/usr/bin/env bash
# gen_terminal_controls_doc.sh - regenerate docs/api/terminal-controls.md from lib/terminal_controls.sh
# (function name, arguments used, and the trailing "# comment"). Run from anywhere: tools/gen_terminal_controls_doc.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/lib/terminal_controls.sh"; OUT="$ROOT/docs/api/terminal-controls.md"
{
cat <<'HDR'
# Terminal controls reference

Generated from `lib/terminal_controls.sh` by `tools/gen_terminal_controls_doc.sh` - do not edit by hand.

Stateless helpers that print escape sequences (`echo -ne`). They are usable on their own (`source lib/terminal_controls.sh`) and are what the TUI core is built on. Arguments are positional; `[N]` = optional (defaults to 1 where relevant). Functions whose Description is empty are queries or wrappers: read the source next to the function.

HDR
awk '
function args(body,   a, i, m, s, seen) {           # positional params referenced in the body, in order
    s = ""; delete seen
    while (match(body, /\$\{?[1-9]/)) {
        m = substr(body, RSTART, RLENGTH); gsub(/[^0-9]/, "", m)
        if (!(m in seen)) { seen[m] = 1; s = s (s ? " " : "") "$" m }
        body = substr(body, RSTART + RLENGTH)
    }
    return s
}
/^[a-z][a-z0-9_]*(\.[a-z0-9_]+)?\(\)[ \t]*\{/ {
    name = $1; sub(/\(\).*/, "", name)
    line = $0; cmt = ""
    if (match(line, /#[^\n]*$/)) { cmt = substr(line, RSTART + 1); sub(/^ +/, "", cmt); line = substr(line, 1, RSTART - 1) }
    gsub(/\|/, "\\|", cmt)
    ns = name; if (index(name, ".")) sub(/\..*/, "", ns); else ns = "(misc)"
    if (!(ns in rows)) order[++n] = ns
    rows[ns] = rows[ns] sprintf("| `%s` | %s | %s |\n", name, args(line), cmt)
}
END {
    for (i = 1; i <= n; i++) {
        ns = order[i]
        printf "\n## %s\n\n| Function | Args | Description |\n|---|---|---|\n%s", (ns == "(misc)" ? "Misc helpers" : ns ".*"), rows[ns]
    }
}' "$SRC"
} > "$OUT"
echo "wrote $OUT ($(grep -c '^| `' "$OUT") functions)"
