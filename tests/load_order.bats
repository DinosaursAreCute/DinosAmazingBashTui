#!/usr/bin/env bats
# tools/gen_load_order.sh: lib/ modules sorted on their "# requires:" headers (the order tui.sh sources them in).
load helpers
setup() {
    setup_env
    LIBDIR="$BATS_TEST_TMPDIR/lib"
    mkdir -p "$LIBDIR"
}

module() { # NAME REQUIRES...
    local name="$1"
    shift
    printf '#!/usr/bin/env bash\n# requires: %s\n' "$*" >"$LIBDIR/$name.sh"
}
gen() { LIB="$LIBDIR" "$REPO/tools/gen_load_order.sh" "$@" 2>&1; }

@test "requirements load first" {
    module a b c; module b c; module c
    run gen --order
    [ "$status" -eq 0 ]
    [ "$output" = $'c\nb\na' ]
}

@test "a cycle stops the generator and names its members" {
    module a b; module b a
    run gen --order
    [ "$status" -ne 0 ]
    [[ "$output" == *"dependency cycle"* ]]
    [[ "$output" == *"a (requires b)"* ]]
    [[ "$output" == *"b (requires a)"* ]]
}

@test "an unknown requirement is reported by name" {
    module a ghost
    run gen --order
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires 'ghost'"* ]]
}

@test "files without a requires header are not modules" {
    module a
    printf '#!/usr/bin/env bash\n# not a module\n' >"$LIBDIR/plain.sh"
    run gen --order
    [ "$output" = "a" ]
}

@test "--check fails once a header changes after generation" {
    module a
    run gen
    [ "$status" -eq 0 ]
    run gen --check
    [ "$status" -eq 0 ]
    module b a
    run gen --check
    [ "$status" -ne 0 ]
}

@test "the shipped lib/tui_modules.sh is current" {
    run "$REPO/tools/gen_load_order.sh" --check
    [ "$status" -eq 0 ]
}

@test "a shuffled order still lists every module exactly once" {
    run "$REPO/tools/gen_load_order.sh" --order 7
    [ "$status" -eq 0 ]
    [ "$(wc -l <<<"$output")" -eq "$(grep -c '^source ' "$REPO/lib/tui_modules.sh")" ]
}
