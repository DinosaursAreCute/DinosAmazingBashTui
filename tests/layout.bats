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
        { tui.goto "$REPO/share/demo/home.xml"
          tui.theme.set "$TUI_DEFAULTS_DIR/themes/forest.css"
          tui.goto "$REPO/share/demo/settings.xml"; tui.goto "$REPO/share/demo/home.xml"; tui.goto "$REPO/share/demo/settings.xml"
          echo "overlay=$(basename "$(tui.theme.current)") st=${ST[theme]} size=${_TUI_P_H[root]}x${_TUI_P_W[root]}" >&3; } 3>&1 >/dev/null 2>&1'
    [ "$status" -eq 0 ]
    [ "$output" = "overlay=forest.css st=forest size=39x140" ]      # 40 rows minus the footer row
}
