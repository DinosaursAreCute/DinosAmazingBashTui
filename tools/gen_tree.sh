#!/usr/bin/env bash
# tools/gen_tree.sh - regenerates a directory tree of bin/, lib/ and share/
# using lib/terminal_renderer.sh's own `tree` renderer, so the README's
# "Project Structure" section can be kept accurate by running this and
# pasting its output, instead of hand-editing a tree that silently drifts
# out of sync every time a file is added, renamed, or removed.
#
# Usage:
#   tools/gen_tree.sh              # print bin/, lib/ and share/ trees
#   tools/gen_tree.sh bin lib share   # same, explicit
#   tools/gen_tree.sh some/dir     # tree any other directory
#
# The structure (file names, nesting, ordering) is always read live from
# the filesystem. Per-file descriptions come from the DESCRIPTIONS table
# below - a file not listed there just shows its bare name, so adding a
# new file never breaks this script; it just means the description table
# is worth extending next time this is run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# terminal_renderer.sh sources colors.sh with a bare relative path, so it
# only works with bin/ as the cwd - matches how every page callback that
# sources it is itself run from bin/. cd there just to source it, then
# back, since the rest of this script uses absolute ($REPO_ROOT) paths.
pushd "$REPO_ROOT/lib" > /dev/null
source terminal_renderer.sh
popd > /dev/null

declare -A DESCRIPTIONS=(
    # bin/
    ["tui.sh"]="Core framework - layout, widgets, event loop"
    ["tui_markup.sh"]="XML config loader"
    ["tui_style.sh"]="CSS-like theme engine"
    ["terminal_controls.sh"]="Low-level terminal escape sequences"
    ["colors.sh"]="Color helpers (named + hex)"
    ["terminal_renderer.sh"]="Runtime text rendering utilities"
    ["DABT_demo.sh"]="Entry point for the demo"
    ["callbacks.sh"]="Legacy imperative demo callbacks"
    ["mouse_integration.sh"]="Standalone mouse-tracking/color test harness"
    ["test.sh"]="Ad-hoc terminal color/cursor test script"

    # config/
    ["home.xml"]="entry point"
    ["_nav.xml"]="reusable navigation pane"
    ["demo_callbacks.sh"]="base callbacks"
    ["features.xml"]="features page"
    ["styles.xml"]="style page"
    ["theme.css"]="css-like style sheet"
    ["terminal.xml"]="live terminal demo"
    ["terminal_init.sh"]="terminal page callback"
    ["settings.xml"]="settings/forms page"
    ["components.xml"]="renderer components showcase page"
    ["showcase_callbacks.sh"]="callbacks for the components showcase page"
    ["scrolling.xml"]="scrolling page"
    ["scroll_callbacks.sh"]="scrolling page callbacks"
    ["case_study.xml"]="case study page"
    ["case_study_callbacks.sh"]="callbacks for the case study page"
    ["docu.xml"]="documentation page (tabs built dynamically from docs/*.md)"
    ["docu_callbacks.sh"]="callbacks for the documentation page"
    ["debug.xml"]="hover/focus/input observability page"
    ["debug_callbacks.sh"]="callbacks for the debug page"
    ["tui.xsd"]="DABT xml syntax xsd"
)

_describe() {
    local name="$1" desc="${DESCRIPTIONS[$1]:-}"
    if [[ -n "$desc" ]]; then
        printf '%s|%s' "$name" "$desc"
    else
        printf '%s' "$name"
    fi
}

# Renders one directory as a tree, one file per line, name/description
# columns aligned - matches the README's existing hand-written style.
gen_dir_tree() {
    local dir="$1"
    [[ -d "$REPO_ROOT/$dir" ]] || { echo "gen_tree: no such directory: $dir" >&2; return 1; }

    local -a raw=()
    local f base
    for f in "$REPO_ROOT/$dir"/*; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        raw+=("$(_describe "$base")")
    done

    # Column-align "name|description" pairs before handing them to tree,
    # since tree() only prefixes whatever text it's given - it doesn't
    # know these lines are two columns.
    local maxlen=0 name desc
    for r in "${raw[@]}"; do
        name="${r%%|*}"
        (( ${#name} > maxlen )) && maxlen=${#name}
    done

    local -a items=("${dir}/")
    for r in "${raw[@]}"; do
        if [[ "$r" == *"|"* ]]; then
            name="${r%%|*}"; desc="${r#*|}"
            printf -v r "%-*s # %s" "$maxlen" "$name" "$desc"
        fi
        items+=("  $r")
    done

    tree "${items[@]}"
}

targets=("$@")
[[ ${#targets[@]} -eq 0 ]] && targets=(bin lib share)

for dir in "${targets[@]}"; do
    gen_dir_tree "$dir"
    echo
done
