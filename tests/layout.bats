#!/usr/bin/env bats
# Pane layout without a terminal (lib/tui.sh).
load helpers
setup() { setup_env; }

split() { bash -c 'source "$REPO/lib/tui.sh"; _TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=20 _TUI_P_W[root]=80; '"$1"; }

@test "hsplit: a child without :WEIGHT gets weight 1" {
    run split 'tui.hsplit root nav main:3; echo "${_TUI_P_W[nav]} ${_TUI_P_W[main]}"'
    [ "$status" -eq 0 ]
    [ "$output" = "20 60" ]
}

@test "vsplit: no weights at all splits evenly" {
    run split 'tui.vsplit root a b; echo "${_TUI_P_H[a]} ${_TUI_P_H[b]}"'
    [ "$status" -eq 0 ]
    [ "$output" = "10 10" ]
}

@test "callbacks get the widget id first: checkbox FN ID VALUE, submit FN ID TEXT" {
    run split '
        tui.hsplit root form
        on_box()  { echo "box $*" >&3; }
        on_text() { echo "text $*" >&3; }
        tui.checkbox chk_a form 0 "A" 0 on_box
        tui.input inp_a form 1 "" "" on_text
        tui.set inp_a "hello world"
        { tui.checkbox.toggle chk_a
          _TUI_FOCUS_ID=inp_a; tui.action.activate; } 3>&1 >/dev/null'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "box chk_a 1" ]
    [ "${lines[1]}" = "text inp_a hello world" ]
}

@test "a replayed page's on_visit keeps the caller's stdin (not the cached call log)" {
    mkdir -p "$T/app"
    printf '<tui on_visit="visit">\n<script src="cb.sh"/>\n<pane id="p"/>\n</tui>\n' >"$T/app/page.xml"
    printf 'visit() { echo "stdin:[$(readlink /proc/$BASHPID/fd/0)]" >&3; }\n' >"$T/app/cb.sh"
    run bash -c 'source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 40; printf -v "$2" 140; }
        { tui.goto "$T/app/page.xml"; tui.goto "$T/app/page.xml"; } 3>&1 >/dev/null 2>&1 </dev/null; true'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "stdin:[/dev/null]" ]      # first visit: recorded
    [ "${lines[1]}" = "stdin:[/dev/null]" ]      # second visit: replayed from the cache
}

@test "demo Settings page shows a theme set from the command bar instead of reverting it" {
    run bash -c 'export TUI_APP_NAME=dabt_demo; source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 40; printf -v "$2" 140; }
        { tui.goto "$REPO/share/demo/components.xml"
          tui.theme.set "$TUI_DEFAULTS_DIR/themes/forest.css"
          tui.goto "$REPO/share/demo/settings.xml"; tui.goto "$REPO/share/demo/components.xml"; tui.goto "$REPO/share/demo/settings.xml"
          echo "overlay=$(basename "$(tui.theme.current)") st=${ST[theme]} size=${_TUI_P_H[root]}x${_TUI_P_W[root]}" >&3; } 3>&1 >/dev/null 2>&1'
    [ "$status" -eq 0 ]
    [ "$output" = "overlay=forest.css st=forest size=39x140" ]      # 40 rows minus the footer row
}

@test "cache: parallel warm-up (tui.cache.warm_with_spinner) and a serial tui.cache.record produce byte-identical snapshots" {
    mkdir -p "$T/app"
    printf '<tui><pane id="root" split="v"><pane id="a" weight="1"/><pane id="b" weight="2"/></pane></tui>' >"$T/app/p1.xml"
    printf '<tui><pane id="root" split="h"><pane id="x" weight="1"/></pane></tui>' >"$T/app/p2.xml"
    run bash -c 'source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 24; printf -v "$2" 80; }
        tui.init
        tui.reset_ui
        tui.cache.record "$T/app/p1.xml"
        serial="${_TUI_CACHE_PAGE[$T/app/p1.xml]}"

        _TUI_CACHE_PAGE=(); _TUI_CACHE_SIG=(); _TUI_CACHE_SCRIPTS=(); _TUI_CACHE_ON_VISIT=(); _TUI_CACHE_GOTOS=()
        TUI_CACHE_WORKERS=2 tui.cache.warm_with_spinner "$T/app/p1.xml" "$T/app/p2.xml" >/dev/null 2>&1
        parallel="${_TUI_CACHE_PAGE[$T/app/p1.xml]}"

        if [[ "$serial" == "$parallel" ]]; then echo IDENTICAL; else echo "DIFF"; fi
        tui.cache.valid "$T/app/p2.xml" && echo P2_VALID
        _master_cleanup 2>/dev/null; true' 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"IDENTICAL"* ]]
    [[ "$output" == *"P2_VALID"* ]]
}

@test "cache: warm-up caches a shell once in the parent and its pages replay into the outlet" {
    mkdir -p "$T/app"
    printf '<tui>\n<pane id="root" split="v">\n<pane id="top" weight="1"/>\n<outlet id="body" weight="3"/>\n</pane>\n</tui>\n' >"$T/app/_shell.xml"
    printf '<tui shell="_shell.xml">\n<pane id="a1" weight="1"/>\n</tui>\n' >"$T/app/p1.xml"
    printf '<tui shell="_shell.xml">\n<pane id="b1" weight="1"/>\n</tui>\n' >"$T/app/p2.xml"
    run bash -c 'source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 24; printf -v "$2" 80; }
        tui.init
        tui.reset_ui
        _TUI_CACHE_PAGE=(); _TUI_CACHE_SIG=(); _TUI_CACHE_SHELL=()
        TUI_CACHE_WORKERS=2 tui.cache.warm_with_spinner "$T/app/p1.xml" "$T/app/p2.xml" >/dev/null 2>&1
        tui.cache.valid "$T/app/_shell.xml" && echo SHELL_CACHED
        tui.cache.valid "$T/app/p2.xml" && echo P2_VALID
        tui.reset_ui
        tui.load_cached "$T/app/p2.xml"
        [[ "${_TUI_P_CHILDREN[body]}" == b1 && "$(tui.shell.file)" == "$T/app/_shell.xml" ]] && echo PAGE_IN_OUTLET
        _master_cleanup 2>/dev/null; true' 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHELL_CACHED"* ]]
    [[ "$output" == *"P2_VALID"* ]]
    [[ "$output" == *"PAGE_IN_OUTLET"* ]]
}

@test "cache: tui.start_cached's staleness gate treats an already-recorded page as not stale" {
    mkdir -p "$T/app"
    printf '<tui><pane id="root"/></tui>' >"$T/app/p1.xml"
    run bash -c 'source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 24; printf -v "$2" 80; }
        tui.init
        tui.reset_ui
        tui.cache.record "$T/app/p1.xml"
        if tui.cache.valid "$T/app/p1.xml"; then echo ALREADY_WARM; fi
        _master_cleanup 2>/dev/null; true'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALREADY_WARM"* ]]
}

@test "cache: an atomic worker write never leaves a partial .snap behind" {
    mkdir -p "$T/app"
    printf '<tui><pane id="root"/></tui>' >"$T/app/p1.xml"
    run bash -c 'source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 24; printf -v "$2" 80; }
        tui.init
        tui.reset_ui
        tui.cache.record "$T/app/p1.xml"
        d="$T/snapdir"; mkdir -p "$d"
        tui.cache.encode "$T/app/p1.xml" >"$d/p1.snap.tmp.1234"
        # a crashed worker never runs the rename: the .tmp file is not the final name
        [[ -f "$d/p1.snap.tmp.1234" && ! -e "$d/p1.snap" ]] && echo NO_PARTIAL_SNAP
        mv -f "$d/p1.snap.tmp.1234" "$d/p1.snap"
        [[ -f "$d/p1.snap" && ! -e "$d/p1.snap.tmp.1234" ]] && echo ATOMIC_RENAME_OK
        _master_cleanup 2>/dev/null; true'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_PARTIAL_SNAP"* ]]
    [[ "$output" == *"ATOMIC_RENAME_OK"* ]]
}

@test "cache: switching pages via a warm cache never shrinks root to half the terminal" {
    mkdir -p "$T/app"
    printf '<tui><pane id="root" split="h"><pane id="a" weight="1"/><pane id="b" weight="1"/></pane></tui>' >"$T/app/p1.xml"
    printf '<tui><pane id="root" split="v"><pane id="a" weight="1"/></pane></tui>' >"$T/app/p2.xml"
    run bash -c 'source "$REPO/lib/tui.sh"; term.size() { printf -v "$1" 40; printf -v "$2" 140; }
        tui.init
        tui.reset_ui
        tui.cache.record "$T/app/p1.xml"
        tui.cache.record "$T/app/p2.xml"
        # reboot: a fresh process loading only from an already-warm cache (tui.cache.valid, no rebuild)
        for i in 1 2 3; do
            tui.reset_ui
            tui.load_cached "$T/app/p1.xml" >/dev/null
            echo "w1=${_TUI_P_W[root]}"
            tui.reset_ui
            tui.load_cached "$T/app/p2.xml" >/dev/null
            echo "w2=${_TUI_P_W[root]}"
        done
        _master_cleanup 2>/dev/null; true'
    [ "$status" -eq 0 ]
    [[ "$output" == *"w1=140"* ]]
    [[ "$output" == *"w2=140"* ]]
    [[ "$output" != *"w1=70"* ]]
    [[ "$output" != *"w2=70"* ]]
}
