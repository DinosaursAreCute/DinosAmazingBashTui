#!/usr/bin/env bash
# profile_all.sh - full headless profile of the DABT demo (no terminal needed)
#   bin/debug/profile_all.sh [-d PAGES_DIR] [-r ROWSxCOLS] [-n ITER] [-s SECTIONS] [PAGE...]
# PAGE defaults to every page in PAGES_DIR that is not a fragment (_*.xml). SECTIONS = comma list of
#   startup,pages,render,calls,cache,state,overlay,resize   (default: all)
#
# WHAT IS PROFILED
#  startup  time to source tui.sh; RSS after source
#  pages    per page: cold load (cache empty: parse + record) | warm goto split into reset / load_cached / render
#           | total | forks in the warm path | widgets, leaves, recorded-cache bytes, output bytes of one frame
#  render   per page: layout (_tui._layout) | full tui.render (mean+min+max of N) | bytes emitted per frame
#           | forks per frame | idle redraw (render with nothing changed)
#  calls    us/call + forks/call of hot framework calls: theme/class sgr, style lookup, tui.output, key reverse map,
#           footer build/draw, command palette build, getters, renderers (box/table/gauge/hbar/kv/alert)
#  cache    tui.cache.valid | replay | record | dump_dir | load_dir | path canon | mtime | on-disk size
#  state    array/assoc entry counts of the big _TUI_* tables, RSS, cache bytes, binding counts
#  overlay  cost + bytes of one overlay pass (footer/kill-switch/palette), and bytes per simulated 100 idle ticks
#  resize   relayout time at several terminal sizes (+ render at each)
# Forks are counted through the last-PID field of /proc/loadavg (0 = fork-free).
DIR="$(cd "$(dirname "$0")/.." && pwd)"; PAGES_DIR="$DIR/../config/DABT_demo"; ROWS=45; COLS=150; N=20; SECT=all
while [[ "$1" == -* ]]; do
    case "$1" in -d) PAGES_DIR="$2"; shift 2 ;; -r) ROWS="${2%x*}"; COLS="${2#*x}"; shift 2 ;;
        -n) N="$2"; shift 2 ;; -s) SECT=",$2,"; shift 2 ;; -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;; *) break ;; esac
done
want() { [[ "$SECT" == all || "$SECT" == *",$1,"* ]]; }
export XDG_CONFIG_HOME="$(mktemp -d)"; SINK="$XDG_CONFIG_HOME/sink"; trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
us() { local t=${EPOCHREALTIME/[.,]/}; printf -v "${1:-_US}" '%s' "$t"; }
pid() { local a; read -r a a a a _pid < /proc/loadavg; }              # sets _pid = last pid created
rss() { local l; while read -r l; do [[ "$l" == VmRSS:* ]] && { _RSS="${l//[^0-9]/}"; return; }; done < /proc/self/status; }
hdr() { printf '\n== %s ==\n' "$1"; }

# T LABEL CMD - run CMD N times (output to sink), print mean/min/max us and forks per call
T() {
    local label="$1" cmd="$2" i t0 t1 tot=0 mn=999999999 mx=0 d p0 p1
    pid; p0=$_pid
    for (( i = 0; i < N; i++ )); do
        us t0; eval "$cmd" >>"$SINK" 2>&1; us t1
        d=$(( t1 - t0 )); (( tot += d )); (( d < mn )) && mn=$d; (( d > mx )) && mx=$d
    done
    pid; p1=$_pid
    printf '  %-44s mean=%7d us  min=%7d  max=%7d  forks/call=%s\n' "$label" $(( tot / N )) "$mn" "$mx" \
        "$(( (p1 - p0 - 1) / N ))"    # -1: the pid() call itself never forks; eval redirections do not either
}

us S0; cd "$DIR" && source ./tui.sh; us S1; rss
PAGES_DIR="$(cd "$PAGES_DIR" && pwd)"
_TUI_ROWS=$ROWS; _TUI_COLS=$COLS
_TUI_P_ROW[root]=1; _TUI_P_COL[root]=1; _TUI_P_H[root]=$ROWS; _TUI_P_W[root]=$COLS
home="${TUI_PROFILE_HOME:-home}"
if (( $# )); then pages=("$@"); else pages=(); for f in "$PAGES_DIR"/*.xml; do b="${f##*/}"; [[ "$b" == _* || "$b" == commands.xml ]] || pages+=("${b%.xml}"); done; fi

want startup && { hdr startup; printf '  source tui.sh: %d ms   RSS after source: %d kB   bash %s\n' $(( (S1-S0)/1000 )) "$_RSS" "$BASH_VERSION"; }

tui.load "$PAGES_DIR/$home.xml" >/dev/null 2>&1
_TUI_RUNNING=1
frame() { tui.render; }

if want pages; then
    hdr "pages (warm = cache hit)"
    printf '  %-16s %8s | %6s %11s %7s | %6s | %5s | %5s %5s %6s %8s %8s\n' page cold_ms reset load_cach render total forks widgets leaves panes cacheB frameB
    for p in "${pages[@]}"; do
        f="$PAGES_DIR/$p.xml"; [[ -f "$f" ]] || { echo "  $p: missing"; continue; }
        tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
        if declare -p _TUI_CACHE_PAGE >/dev/null 2>&1; then _TUI_CACHE_PAGE=(); _TUI_CACHE_SIG=(); fi
        us a; tui.goto "$f" >/dev/null 2>&1; us b; cold=$(( (b-a)/1000 ))          # cold: parse + record + on_visit
        tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
        pid; p0=$_pid
        us t0; tui.reset_ui >/dev/null 2>&1; us t1; tui.load_cached "$f" >/dev/null 2>&1; us t2; tui.render >"$SINK" 2>&1; us t3
        pid; p1=$_pid
        key="${f}"; cb=0; for k in "${!_TUI_CACHE_PAGE[@]}"; do [[ "$k" == *"/$p.xml" ]] && cb=${#_TUI_CACHE_PAGE[$k]}; done
        fb=$(wc -c < "$SINK")
        printf '  %-16s %8d | %4dms %9dms %5dms | %4dms | %5d | %5d %5d %6d %8d %8d\n' "$p" "$cold" $(( (t1-t0)/1000 )) $(( (t2-t1)/1000 )) \
            $(( (t3-t2)/1000 )) $(( (t3-t0)/1000 )) $(( p1 - p0 - 1 )) "${#_TUI_W_ORDER[@]}" "${#_TUI_P_LEAVES[@]}" "${#_TUI_P_ALL[@]}" "$cb" "$fb"
        tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
    done
fi

if want render; then
    hdr "render (per page, N=$N frames)"
    for p in "${pages[@]}"; do
        f="$PAGES_DIR/$p.xml"; [[ -f "$f" ]] || continue
        tui.goto "$f" >/dev/null 2>&1
        echo " $p"
        T "layout (_tui._layout root)" '_tui._layout root'
        T "tui.render (full frame)" 'tui.render'
        T "tui.render (idle repeat)" 'tui.render'
        declare -F _tui._draw_widgets_now >/dev/null && T "draw widgets only" '_tui._draw_widgets_now'
        tui.render >"$SINK" 2>&1; printf '  %-44s %d bytes\n' "bytes per frame" "$(wc -c < "$SINK")"
    done
    tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
fi

if want calls; then
    hdr "calls (home page state)"
    tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
    first_pane="${_TUI_P_LEAVES[0]:-root}"; first_w="${_TUI_W_ORDER[0]:-}"
    T "tui.class.sgr footer"            'tui.class.sgr footer'
    T "tui.class.sgr footer_key"        'tui.class.sgr footer_key'
    declare -F _tui._style_v >/dev/null && T "_tui._style_v (pane)" "_tui._style_v $first_pane"
    T "tui.get.dimensions"              "tui.get.dimensions $first_pane"
    T "tui.get.border"                  "tui.get.border $first_pane"
    T "tui.get.children root"           'tui.get.children root'
    T "tui.output (append line)"        "tui.output $first_pane 'profile line'"
    T "tui.clear_output"                "tui.clear_output $first_pane"
    T "_tui_input.reverse_keys"         '_tui_input.reverse_keys'
    T "_tui_footer.build"               '_tui_footer.build'
    T "_tui_footer.draw"                '_tui_footer.draw'
    T "_tui_path_canon"                 "_tui_path_canon '$PAGES_DIR/../DABT_demo/./home.xml'"
    T "_tui_cache_relayout"             '_tui_cache_relayout'
    declare -F tui.palette.open >/dev/null && { T "palette open+close" 'tui.palette.open; tui.modal.close'; }
    for r in box alert table kv hbar gauge divider banner; do
        declare -F "${r}_string" >/dev/null || continue
        case "$r" in
            box) a="'Title' 'body line one' 'body line two'" ;; alert) a="info 'message'" ;;
            table) a="'a,b,c' '1,2,3' '4,5,6'" ;; kv) a="'key' 'value'" ;; hbar) a="'label' 50 100" ;;
            gauge) a="'label' 50 100" ;; divider) a="" ;; banner) a="'DABT'" ;;
        esac
        T "${r}_string" "${r}_string $a"
    done
fi

if want cache; then
    hdr cache
    f="$PAGES_DIR/components.xml"; [[ -f "$f" ]] || f="$PAGES_DIR/${pages[0]}.xml"
    tui.goto "$f" >/dev/null 2>&1; tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
    T "tui.cache.valid"                 "tui.cache.valid '$f'"
    T "tui.cache.replay (no render)"    "tui.reset_ui; tui.cache.replay '$f'"
    T "tui.load_cached (hit)"           "tui.reset_ui; tui.load_cached '$f'"
    T "tui.cache.record (miss)"         "tui.reset_ui; tui.cache.record '$f'"
    d="$XDG_CONFIG_HOME/dump"
    T "tui.cache.dump_dir"              "tui.cache.dump_dir '$d'"
    T "tui.cache.load_dir"              "tui.cache.load_dir '$d'"
    declare -F _tui_cache_mtime >/dev/null && T "_tui_cache_mtime"  "_tui_cache_mtime '$f'"
    printf '  cached pages: %d   in-memory bytes: ' "${#_TUI_CACHE_PAGE[@]}"; tot=0; for k in "${!_TUI_CACHE_PAGE[@]}"; do (( tot += ${#_TUI_CACHE_PAGE[$k]} )); done; echo "$tot"
    printf '  on-disk dump: %s bytes in %s files\n' "$(cat "$d"/* 2>/dev/null | wc -c)" "$(ls "$d" 2>/dev/null | wc -l)"
    if declare -F _tui.theme_load_file >/dev/null && [[ -f "$PAGES_DIR/theme.css" ]]; then
        T "theme load (memoized)"       "_tui.theme_load_file '$PAGES_DIR/theme.css'"
    fi
    for p in "${pages[@]}"; do
        cb="$PAGES_DIR/${p}_callbacks.sh"; [[ -f "$cb" ]] || continue
        T "re-source ${p}_callbacks.sh" "source '$cb'"
    done
fi

if want state; then
    hdr state
    rss; printf '  RSS: %d kB\n' "$_RSS"
    for v in $(compgen -A variable _TUI_ | sort); do
        decl="$(declare -p "$v" 2>/dev/null)"
        case "$decl" in
            "declare -a"*|"declare -A"*|"declare -ga"*|"declare -gA"*)
                local_n=$(eval "echo \${#$v[@]}"); (( local_n > 20 )) && printf '  %-34s %6d entries\n' "$v" "$local_n" ;;
        esac
    done
    printf '  functions defined: %d   panes: %d   widgets: %d   keybinds(code/user/default): %d/%d/%d\n' \
        "$(compgen -A function | wc -l)" "${#_TUI_P_ALL[@]}" "${#_TUI_W_ORDER[@]}" "${#_TUI_BIND[@]}" "${#_TUI_UBIND[@]}" "${#_TUI_BIND_DEF[@]}"
fi

if want overlay; then
    hdr overlay
    tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
    printf '  registered overlays: %s\n' "${_TUI_OVERLAY_FNS[*]}"
    T "_tui_overlay.draw_all"           '_tui_overlay.draw_all'
    : > "$SINK"; _tui_overlay.draw_all >"$SINK" 2>&1; printf '  bytes per overlay pass: %d\n' "$(wc -c < "$SINK")"
    # simulated idle loop: same gate as tui.run (redraw only when a flush happened since the last pass)
    : > "$SINK"; _TUI_FLUSH_GEN=0; _TUI_OVL_GEN=0
    for (( i = 0; i < 100; i++ )); do
        (( ${#_TUI_OVERLAY_FNS[@]} && _TUI_FLUSH_GEN != _TUI_OVL_GEN )) && { _TUI_OVL_GEN=$_TUI_FLUSH_GEN; _tui_overlay.draw_all; }
    done >>"$SINK" 2>&1
    printf '  bytes over 100 idle ticks (target 0): %d\n' "$(wc -c < "$SINK")"
fi

if want resize; then
    hdr "resize (home page)"
    tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
    for sz in 24x80 45x150 60x200 24x120 45x150; do
        _TUI_ROWS=${sz%x*}; _TUI_COLS=${sz#*x}; _TUI_P_W[root]=$_TUI_COLS; _tui._root_h
        us a; _tui._layout root >/dev/null 2>&1; us b; tui.render >"$SINK" 2>&1; us c
        printf '  %-8s layout=%4dms  render=%4dms  bytes=%d\n' "$sz" $(( (b-a)/1000 )) $(( (c-b)/1000 )) "$(wc -c < "$SINK")"
    done
fi
echo
