#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load ../helpers
setup() { dapk_setup; source "$REPO/lib/dapk/dapk.sh"; }

parse() { declare -gA P=(); dapk.toml.parse "$1" P; }

@test "toml: scalars, arrays (also multi-line), tables and arrays of tables" {
    cat > "$T/a.toml" <<'X'
# comment
name = "my # app"   # trailing comment
n = 5
flag = true
lit = 'C:\path'
list = ["a", 'b c',
  "d"]
[[include]]
type = "file"
[[include]]
type = "directory"
X
    parse "$T/a.toml"
    [ "${P[name]}" = "my # app" ]; [ "${P[n]}" = 5 ]; [ "${P[flag]}" = true ]; [ "${P[lit]}" = 'C:\path' ]
    [ "${P[include.1.type]}" = file ]; [ "${P[include.2.type]}" = directory ]; [ "${P[@count.include]}" = 2 ]
    dapk.toml.split "${P[list]}" L; [ "${#L[@]}" = 3 ]; [ "${L[1]}" = "b c" ]
}

@test "toml: errors carry the line number" {
    printf 'a = 1\nb = 1.5\n' > "$T/b.toml"
    run parse "$T/b.toml"; [ "$status" -eq 1 ]
    parse "$T/b.toml" || true; [[ "$DAPK_TOML_ERROR" == *"b.toml:2:"* ]]
}

@test "toml: duplicate keys, bad headers, unterminated strings and arrays are rejected" {
    for body in 'a = 1\na = 2' '[x y]' 'a = "open' 'a = [1, 2' 'a = {b = 1}' 'a = "x\nq"'; do
        printf "$body\n" > "$T/c.toml"
        ! parse "$T/c.toml"
    done
}
