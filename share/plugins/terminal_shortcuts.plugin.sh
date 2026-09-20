# plugin: terminal_shortcuts
# title: Terminal shortcuts
# version: 1.0
# description: Detects your terminal, checks which keys it keeps for itself (live where it can tell, or by asking you to press them) and frees them while DABT runs: kitty, GNOME Terminal and tmux automatically, config snippets for the rest.
# author: Dino
# default: on
#
# WHY: a terminal emulator sees every key BEFORE the app. ctrl+shift+left is "previous tab" in kitty, alt+1..9 switch tabs
# in GNOME Terminal, page_up may scroll the scrollback, F1 opens help... those keys never reach DABT. No escape sequence can
# override that on purpose, so this plugin works on the terminal's own configuration instead.
#
# WHAT IT DOES (commands in the command bar, group "Terminal")
#   Terminal: what am I running in?          detect terminal, multiplexer, and what can be freed
#   Terminal: shortcuts the terminal takes   live list (kitty: its real effective keymap; GNOME Terminal: gsettings; tmux: root table)
#   Terminal: check shortcuts (press keys)   guided test, works in ANY terminal: press each key, the ones that never arrive are taken
#   Terminal: free shortcuts while DABT runs unmap them now, restored on exit / disable      Terminal: give the shortcuts back
#   Terminal: show config to free shortcuts  the lines to put in your terminal's config (alacritty, wezterm, ghostty, kitty, ...)
#
# HOW EACH ONE IS FREED (only the keys DABT actually uses, only while it runs)
#   kitty           an include file dabt-shortcuts.conf next to kitty.conf with `map KEY no_op` lines (no_op = kitty stops intercepting
#                   the key and passes it to the program), applied with SIGUSR1 (kitty reloads its config). Needs ONE line at the end
#                   of kitty.conf: `include dabt-shortcuts.conf` - the plugin offers to add it (after backing kitty.conf up).
#   GNOME Terminal  gsettings: the matching keys under org.gnome.Terminal.Legacy.Keybindings are set to 'disabled' and put back
#                   afterwards (a backup file makes the restore survive a crash).
#   tmux            `tmux unbind-key -T root KEY` for matching root-table keys, replayed on restore.
# Optional tools: kitty, gsettings, tmux are only used when present. Settings: `tui.plugin.config terminal_shortcuts auto_free 1`
# frees the shortcuts automatically when DABT starts (a checkbox on the default Settings page).

declare -g  TS_TERM="" TS_VER="" TS_MUX="" TS_STRATEGY="" _TS_FREED=""
declare -ga TS_CONF=()                 # "chord<TAB>what the terminal does with it"  (filled by _ts_conflicts)
declare -gA _TS_USED=() _TS_KNAME=() _TS_TKEY=()   # chord DABT listens for -> why ; chord -> the terminal's own name for the key (kitty syntax)

# the chords worth testing / worth freeing beyond what is bound: text editing, scrolling, focus
_TS_TEXT_CHORDS=(ctrl+left ctrl+right ctrl+up ctrl+down ctrl+shift+left ctrl+shift+right ctrl+shift+up ctrl+shift+down
    alt+shift+left alt+shift+right alt+shift+up alt+shift+down shift+home shift+end shift+pgup shift+pgdn shift+up shift+down
    ctrl+home ctrl+end ctrl+shift+home ctrl+shift+end ctrl+a ctrl+c ctrl+x ctrl+v ctrl+z ctrl+y ctrl+k ctrl+u ctrl+w
    ctrl+insert shift+insert shift+delete ctrl+backspace ctrl+delete pgup pgdn home end)
_TS_PROBE_CHORDS=(ctrl+shift+left ctrl+shift+right ctrl+shift+up ctrl+shift+down alt+shift+left alt+shift+right
    ctrl+left ctrl+right ctrl+up ctrl+down shift+left shift+pgup shift+pgdn pgup pgdn home end ctrl+home ctrl+end
    alt+left alt+right alt+up alt+down alt+1 alt+5 f1 f6 ctrl+c ctrl+x ctrl+v ctrl+z ctrl+y
    ctrl+insert shift+insert shift+delete ctrl+backspace ctrl+delete)

plugin.terminal_shortcuts.on_enable() {
    tui.cmd.add ts.detect    "Terminal: what am I running in?"          _ts_cmd_detect    --group Terminal --desc "Terminal, version, multiplexer and what this plugin can free"
    tui.cmd.add ts.conflicts "Terminal: shortcuts the terminal takes"   _ts_cmd_conflicts --group Terminal --desc "Keys DABT uses that the terminal keeps for itself (live where the terminal can tell)"
    tui.cmd.add ts.check     "Terminal: check shortcuts (press keys)"   _ts_cmd_check     --group Terminal --desc "Guided test: press each key; the ones that never arrive are taken by the terminal"
    tui.cmd.add ts.free      "Terminal: free shortcuts while DABT runs" _ts_cmd_free      --group Terminal --desc "Unmap the keys DABT needs in kitty / GNOME Terminal / tmux; restored on exit"
    tui.cmd.add ts.restore   "Terminal: give the shortcuts back"        _ts_cmd_restore   --group Terminal --desc "Undo what 'free shortcuts' changed"
    tui.cmd.add ts.snippet   "Terminal: show config to free shortcuts"  _ts_cmd_snippet   --group Terminal --desc "The lines to add to your terminal's own config"
    tui.hook.on ready _ts_on_ready
    tui.hook.on exit  _ts_on_exit
    _ts_detect
    _ts_recover
    return 0
}

plugin.terminal_shortcuts.on_disable() { _ts_restore quiet; }

# ── detection ────────────────────────────────────────────────────────────

_ts_detect() {
    TS_TERM=""; TS_VER="${TERM_PROGRAM_VERSION:-}"; TS_MUX=""; TS_STRATEGY=""
    [[ -n "${TMUX:-}" ]] && TS_MUX=tmux
    [[ -z "$TS_MUX" && -n "${STY:-}" ]] && TS_MUX=screen
    if   [[ -n "${KITTY_WINDOW_ID:-}" || "$TERM" == xterm-kitty ]]; then TS_TERM=kitty
    elif [[ -n "${WEZTERM_EXECUTABLE:-}${WEZTERM_PANE:-}" || "${TERM_PROGRAM:-}" == WezTerm ]]; then TS_TERM=wezterm
    elif [[ -n "${GHOSTTY_RESOURCES_DIR:-}" || "${TERM_PROGRAM:-}" == ghostty ]]; then TS_TERM=ghostty
    elif [[ -n "${ALACRITTY_SOCKET:-}${ALACRITTY_LOG:-}" || "$TERM" == alacritty* ]]; then TS_TERM=alacritty
    elif [[ "${TERM_PROGRAM:-}" == iTerm.app ]]; then TS_TERM=iterm2
    elif [[ "${TERM_PROGRAM:-}" == Apple_Terminal ]]; then TS_TERM=apple-terminal
    elif [[ -n "${WT_SESSION:-}" ]]; then TS_TERM=windows-terminal
    elif [[ -n "${KONSOLE_VERSION:-}" ]]; then TS_TERM=konsole; TS_VER="$KONSOLE_VERSION"
    elif [[ "$TERM" == foot* ]]; then TS_TERM=foot
    elif [[ -n "${GNOME_TERMINAL_SCREEN:-}${GNOME_TERMINAL_SERVICE:-}" ]]; then TS_TERM=gnome-terminal; TS_VER="${VTE_VERSION:-}"
    elif [[ -n "${VTE_VERSION:-}" ]]; then TS_TERM=vte; TS_VER="$VTE_VERSION"
    elif [[ -n "${XTERM_VERSION:-}" ]]; then TS_TERM=xterm; TS_VER="$XTERM_VERSION"
    elif [[ -n "${TERM_PROGRAM:-}" ]]; then TS_TERM="${TERM_PROGRAM,,}"
    else _ts_xtversion; fi
    [[ -n "$TS_TERM" ]] || TS_TERM=unknown
    # what can be freed at runtime
    if [[ "$TS_TERM" == kitty ]] && command -v kitty >/dev/null && [[ -n "${KITTY_PID:-}" ]]; then TS_STRATEGY=kitty
    elif [[ "$TS_TERM" == gnome-terminal || "$TS_TERM" == vte ]] && _ts_gnome_ok; then TS_STRATEGY=gnome
    elif [[ "$TS_MUX" == tmux ]] && command -v tmux >/dev/null; then TS_STRATEGY=tmux
    fi
}

# XTVERSION: ESC [ > 0 q  ->  DCS > | name(version) ST   (kitty, wezterm, foot, xterm, ghostty answer it)
_ts_xtversion() {
    [[ -t 0 && -t 1 ]] || return 0
    local c buf=""
    printf '\e[>0q'
    while IFS= read -rsn1 -t 0.15 c; do buf+="$c"; [[ "$buf" == *$'\e\\' || ${#buf} -gt 120 ]] && break; done
    [[ "$buf" == *'>|'* ]] || return 0
    buf="${buf#*>|}"; buf="${buf%%$'\e'*}"
    TS_TERM="${buf%%(*}"; TS_TERM="${TS_TERM,,}"
    [[ "$buf" == *"("* ]] && { TS_VER="${buf#*(}"; TS_VER="${TS_VER%)*}"; }
}

# ── which chords does DABT listen for? ───────────────────────────────────

_ts_collect_used() {
    _TS_USED=()
    local k c
    for k in "${!_TUI_BIND_DEF[@]}"; do _ts_note_chord "$k" "default: ${_TUI_BIND_DEF[$k]}"; done
    for k in "${!_TUI_BIND[@]}";     do c="${k#*|}"; _ts_note_chord "$c" "bind: ${_TUI_BIND[$k]}"; done
    for k in "${!_TUI_UBIND[@]}";    do c="${k#*|}"; _ts_note_chord "$c" "your bind: ${_TUI_UBIND[$k]}"; done
    for c in "${_TS_TEXT_CHORDS[@]}"; do _ts_note_chord "$c" "text editing"; done
}
_ts_note_chord() {    # CHORD WHY : only chords a terminal could take (modified keys, navigation, function keys)
    local c="$1"
    case "$c" in mouse:*|wheel:*|drag:*|*+mouse:*|*+wheel:*|*+drag:*|paste|release) return ;; esac
    case "$c" in *+*|pgup|pgdn|home|end|insert|delete|f[0-9]|f1[0-2]|left|right|up|down) ;; *) return ;; esac
    [[ -n "${_TS_USED[$c]:-}" ]] || _TS_USED[$c]="$2"
}

# ── kitty: its REAL effective keymap (defaults + your kitty.conf + includes) ─────────────────────────

_ts_kitty_dir() { _KD="${KITTY_CONFIG_DIRECTORY:-${XDG_CONFIG_HOME:-$HOME/.config}/kitty}"; }

# _ts_kitty_maps -> lines "MODS|NAME|DEFINITION" (kitty's own python does the parsing; nothing of ours is installed into kitty)
_ts_kitty_maps() {
    kitty +runpy '
import os
from kitty.constants import config_dir
from kitty.config import load_config
from kitty.key_encoding import functional_key_number_to_name_map as F
o = load_config(os.path.join(config_dir, "kitty.conf"))          # defaults + your kitty.conf (+ its includes)
for k, v in o.keyboard_modes[""].keymap.items():
    kd = v[-1]                                                     # the last map for a key wins
    print("%d|%s|%s" % (k.mods, F.get(k.key) or chr(k.key), kd.definition))
' 2>/dev/null
}

# kitty key name -> DABT key name
_ts_dabt_key() {
    local n="${1,,}"
    case "$n" in page_up) n=pgup ;; page_down) n=pgdn ;; escape) n=esc ;; return) n=enter ;; esac
    _K="$n"
}
# MODS bitmask (1 shift, 2 alt, 4 ctrl, 8+ super...) NAME -> _CH (DABT chord) _KN (kitty chord); rc 1 when a mod DABT cannot see
_ts_kitty_chord() {
    local m=$1 name="$2" p="" kp=""
    (( m & ~7 )) && return 1
    (( m & 4 )) && { p+="ctrl+"; kp+="ctrl+"; }
    (( m & 2 )) && { p+="alt+"; kp+="alt+"; }
    (( m & 1 )) && { p+="shift+"; kp+="shift+"; }
    _ts_dabt_key "$name"
    _CH="${p}${_K}"; _KN="${kp}${name,,}"
}

_ts_kitty_conflicts() {
    TS_CONF=(); _TS_KNAME=()
    local line m name def
    while IFS='|' read -r m name def; do
        [[ -n "$name" && -n "$def" && "$def" != no_op* ]] || continue        # an empty definition is how kitty stores no_op
        _ts_kitty_chord "$m" "$name" || continue
        [[ -n "${_TS_USED[$_CH]:-}" ]] || continue
        [[ -n "${_TS_KNAME[$_CH]:-}" ]] && continue
        _TS_KNAME[$_CH]="$_KN"
        TS_CONF+=("$_CH"$'\t'"kitty: $def   (DABT: ${_TS_USED[$_CH]})")
    done < <(_ts_kitty_maps)
}

_ts_kitty_free() {   # QUIET
    _ts_kitty_dir; local conf="$_KD/kitty.conf" inc="$_KD/dabt-shortcuts.conf" c
    [[ -f "$conf" ]] || { _ts_msg warn "kitty.conf not found in $_KD"; return 1; }
    if ! grep -qs '^[[:space:]]*include[[:space:]].*dabt-shortcuts\.conf' "$conf"; then
        if [[ "$(tui.plugin.config terminal_shortcuts kitty_include)" != 1 ]]; then
            [[ "$1" == quiet ]] && return 1
            tui.confirm "kitty needs one line at the end of kitty.conf:"$'\n\n'"    include dabt-shortcuts.conf"$'\n\n'"Add it now? (kitty.conf is backed up to kitty.conf.dabt-backup first.)" _ts_kitty_add_include _ts_msg_declined --title "Free kitty shortcuts" --yes "Add it" --no "Not now"
            return 0
        fi
        _ts_kitty_add_include
    fi
    _ts_collect_used; _ts_kitty_conflicts
    (( ${#TS_CONF[@]} )) || { [[ "$1" == quiet ]] || _ts_msg success "Nothing to free: kitty keeps none of the keys DABT uses"; return 0; }
    local n=${#TS_CONF[@]}
    { printf '# Written by DABT (terminal_shortcuts plugin) while DABT runs; emptied when it exits. Safe to delete.\n'
      for c in "${!_TS_KNAME[@]}"; do printf 'map %s no_op\n' "${_TS_KNAME[$c]}"; done; } > "$inc"
    kill -SIGUSR1 "$KITTY_PID" 2>/dev/null || { _ts_msg error "could not signal kitty (KITTY_PID=$KITTY_PID)"; return 1; }
    read -rt 0.5 <> <(:)                                              # kitty reloads asynchronously
    _ts_kitty_conflicts
    _TS_FREED=kitty
    [[ "$1" == quiet ]] || _ts_msg success "Freed $(( n - ${#TS_CONF[@]} )) of $n shortcuts in kitty$( (( ${#TS_CONF[@]} )) && echo " (${#TS_CONF[@]} still taken)")"
}
_ts_kitty_add_include() {
    _ts_kitty_dir; local conf="$_KD/kitty.conf"
    [[ -f "$conf.dabt-backup" ]] || cp "$conf" "$conf.dabt-backup"
    printf '\n# DABT: keys DABT needs are unmapped here while it runs (terminal_shortcuts plugin). Keep this line at the END of the file.\ninclude dabt-shortcuts.conf\n' >> "$conf"
    tui.plugin.config terminal_shortcuts kitty_include 1
    _ts_kitty_free
}
_ts_kitty_restore() {
    _ts_kitty_dir; local inc="$_KD/dabt-shortcuts.conf"
    [[ -f "$inc" ]] || return 0
    printf '# emptied by DABT (terminal_shortcuts plugin)\n' > "$inc"
    [[ -n "${KITTY_PID:-}" ]] && kill -SIGUSR1 "$KITTY_PID" 2>/dev/null
    return 0
}

# ── GNOME Terminal / VTE: gsettings ──────────────────────────────────────

_TS_GS_SCHEMA='org.gnome.Terminal.Legacy.Keybindings:/org/gnome/terminal/legacy/keybindings/'
_ts_gnome_ok() { command -v gsettings >/dev/null && gsettings list-keys "$_TS_GS_SCHEMA" >/dev/null 2>&1; }
_ts_gnome_backup() { _GB="$TUI_APP_CONF/terminal_shortcuts.gnome.backup"; }

# GTK accelerator ('<Primary><Shift>c', '<Alt>1', 'F1') -> DABT chord
_ts_gtk_chord() {
    local a="$1" p="" k
    [[ "$a" == "disabled" || -z "$a" ]] && return 1
    [[ "$a" == *"<Primary>"* || "$a" == *"<Control>"* ]] && p+="ctrl+"
    [[ "$a" == *"<Alt>"* ]] && p+="alt+"
    [[ "$a" == *"<Shift>"* ]] && p+="shift+"
    [[ "$a" == *"<Super>"* || "$a" == *"<Meta>"* ]] && return 1
    k="${a##*>}"; k="${k,,}"
    case "$k" in page_up) k=pgup ;; page_down) k=pgdn ;; escape) k=esc ;; return) k=enter ;; esac
    _CH="$p$k"
}

_ts_gnome_conflicts() {
    TS_CONF=()
    local line key val
    while IFS= read -r line; do                                       # "SCHEMA KEY 'VALUE'"
        key="${line#* }"; val="${key#* }"; key="${key%% *}"; val="${val//\'/}"
        [[ "$val" == \[* ]] && continue
        _ts_gtk_chord "$val" || continue
        [[ -n "${_TS_USED[$_CH]:-}" ]] && TS_CONF+=("$_CH"$'\t'"GNOME Terminal: $key   (DABT: ${_TS_USED[$_CH]})")
    done < <(gsettings list-recursively "$_TS_GS_SCHEMA" 2>/dev/null)
}

_ts_gnome_free() {
    _ts_gnome_backup; local bk="$_GB" line key val n=0
    _ts_collect_used
    mkdir -p "${bk%/*}"
    [[ -f "$bk" ]] || : > "$bk"
    while IFS= read -r line; do
        key="${line#* }"; val="${key#* }"; key="${key%% *}"; val="${val//\'/}"
        [[ "$val" == \[* ]] && continue
        _ts_gtk_chord "$val" || continue
        [[ -n "${_TS_USED[$_CH]:-}" ]] || continue
        printf '%s\t%s\n' "$key" "$val" >> "$bk"
        gsettings set "$_TS_GS_SCHEMA" "$key" disabled && (( n++ ))
    done < <(gsettings list-recursively "$_TS_GS_SCHEMA" 2>/dev/null)
    _TS_FREED=gnome
    [[ "$1" == quiet ]] || _ts_msg success "Disabled $n GNOME Terminal shortcuts (restored when DABT exits)"
}
_ts_gnome_restore() {
    _ts_gnome_backup; local bk="$_GB" key val
    [[ -f "$bk" ]] || return 0
    while IFS=$'\t' read -r key val; do [[ -n "$key" ]] && gsettings set "$_TS_GS_SCHEMA" "$key" "$val"; done < "$bk"
    rm -f "$bk"
}

# ── tmux: root key table ─────────────────────────────────────────────────

# tmux key (C-S-Left, M-Left, PageUp, F1) -> DABT chord
_ts_tmux_chord() {
    local k="$1" p=""
    while [[ "$k" =~ ^([CMS])-(.+)$ ]]; do
        case "${BASH_REMATCH[1]}" in C) p+="ctrl+" ;; M) p+="alt+" ;; S) p+="shift+" ;; esac
        k="${BASH_REMATCH[2]}"
    done
    case "$k" in Left|Right|Up|Down|Home|End|F[0-9]|F1[0-2]) k="${k,,}" ;; PageUp|PPage) k=pgup ;; PageDown|NPage) k=pgdn ;;
                 IC|Insert) k=insert ;; DC|Delete) k=delete ;; BSpace) k=backspace ;; *) k="${k,,}" ;; esac
    # order the modifiers the way DABT names them: ctrl, alt, shift
    local m=""; [[ "$p" == *ctrl+* ]] && m+="ctrl+"; [[ "$p" == *alt+* ]] && m+="alt+"; [[ "$p" == *shift+* ]] && m+="shift+"
    _CH="$m$k"
}
_ts_tmux_conflicts() {
    TS_CONF=(); _TS_TKEY=()
    local line w k
    while IFS= read -r line; do
        read -ra w <<< "$line"
        for k in "${!w[@]}"; do [[ "${w[k]}" == root ]] && { k="${w[k+1]:-}"; break; }; done
        [[ -n "$k" ]] || continue
        _ts_tmux_chord "$k"
        [[ -n "${_TS_USED[$_CH]:-}" ]] || continue
        TS_CONF+=("$_CH"$'\t'"tmux root binding: $k   (DABT: ${_TS_USED[$_CH]})"); _TS_TKEY[$_CH]="$k"
    done < <(tmux list-keys -T root 2>/dev/null)
}
_ts_tmux_free() {
    _ts_collect_used; _ts_tmux_conflicts
    local bk="$TUI_APP_CONF/terminal_shortcuts.tmux.conf" c line
    mkdir -p "${bk%/*}"; : > "$bk"
    for c in "${!_TS_TKEY[@]}"; do
        while IFS= read -r line; do
            [[ "$line" == *" root "*"${_TS_TKEY[$c]} "* ]] && printf '%s\n' "$line" >> "$bk"
        done < <(tmux list-keys -T root 2>/dev/null)
        tmux unbind-key -T root "${_TS_TKEY[$c]}"
    done
    _TS_FREED=tmux
    [[ "$1" == quiet ]] || _ts_msg success "Unbound ${#_TS_TKEY[@]} tmux root keys (restored when DABT exits)"
}
_ts_tmux_restore() {
    local bk="$TUI_APP_CONF/terminal_shortcuts.tmux.conf"
    [[ -f "$bk" ]] || return 0
    tmux source-file "$bk" 2>/dev/null; rm -f "$bk"
}

# ── free / restore ───────────────────────────────────────────────────────

_ts_free() {          # [quiet]
    _ts_detect; _ts_collect_used
    case "$TS_STRATEGY" in
        kitty) _ts_kitty_free "$1" ;;
        gnome) _ts_gnome_free "$1" ;;
        tmux)  _ts_tmux_free "$1" ;;
        *)     [[ "$1" == quiet ]] || { _ts_msg warn "Cannot free shortcuts at runtime in ${TS_TERM}${TS_MUX:+ (in $TS_MUX)}: showing the config to add"; _ts_cmd_snippet; } ;;
    esac
}
_ts_restore() {
    case "$_TS_FREED" in kitty) _ts_kitty_restore ;; gnome) _ts_gnome_restore ;; tmux) _ts_tmux_restore ;; esac
    _TS_FREED=""
    [[ "$1" == quiet ]] || _ts_msg info "Terminal shortcuts restored"
}
# a crash may have left settings changed: put them back before doing anything else
_ts_recover() {
    _ts_gnome_backup; [[ -f "$_GB" ]] && { _TS_FREED=gnome; _ts_restore quiet; }
    local bk="$TUI_APP_CONF/terminal_shortcuts.tmux.conf"
    [[ -f "$bk" && "$TS_STRATEGY" == tmux ]] && { _TS_FREED=tmux; _ts_restore quiet; }
    return 0
}

_ts_on_ready() { [[ "$(tui.plugin.config terminal_shortcuts auto_free)" == 1 ]] && _ts_free quiet; return 1; }
_ts_on_exit()  { [[ -n "$_TS_FREED" ]] && _ts_restore quiet; return 1; }

_ts_msg() { tui.notify "$2" "$1" 5; }
_ts_msg_declined() { _ts_msg info "kitty shortcuts left as they are"; }

# ── reports ──────────────────────────────────────────────────────────────

_ts_report() {
    _ts_detect
    local n; n="$(tui.plugin.config terminal_shortcuts blocked)"
    printf 'Terminal      %s %s\n' "$TS_TERM" "$TS_VER"
    printf 'Multiplexer   %s\n' "${TS_MUX:-none}"
    case "$TS_STRATEGY" in
        kitty) printf 'Can free      yes - kitty include file + SIGUSR1 (KITTY_PID %s)\n' "$KITTY_PID" ;;
        gnome) printf 'Can free      yes - gsettings (org.gnome.Terminal.Legacy.Keybindings)\n' ;;
        tmux)  printf 'Can free      yes - tmux unbind-key -T root\n' ;;
        *)     printf 'Can free      not at runtime - use "show config" for %s\n' "$TS_TERM" ;;
    esac
    printf 'Auto free     %s   (tui.plugin.config terminal_shortcuts auto_free 1)\n' "$([[ "$(tui.plugin.config terminal_shortcuts auto_free)" == 1 ]] && echo on || echo off)"
    printf 'Currently     %s\n' "${_TS_FREED:+freed by DABT ($_TS_FREED)}${_TS_FREED:-shortcuts are as the terminal has them}"
    [[ -n "$n" ]] && printf '\nLast check: these keys never arrived:\n  %s\n' "$n"
}
_ts_cmd_detect() { tui.view "Terminal" "$(_ts_report)"; }

_ts_cmd_conflicts() {
    _ts_detect; _ts_collect_used
    case "$TS_STRATEGY" in
        kitty) _ts_kitty_conflicts ;; gnome) _ts_gnome_conflicts ;; tmux) _ts_tmux_conflicts ;;
        *) tui.view "Shortcuts the terminal takes" "Live listing is not available for ${TS_TERM}."$'\n\n'"Use \"Terminal: check shortcuts\" (works everywhere): press the keys and see which never arrive." ; return ;;
    esac
    local out="" row
    if (( ${#TS_CONF[@]} )); then
        for row in "${TS_CONF[@]}"; do printf -v row '%-24s %s' "${row%%$'\t'*}" "${row#*$'\t'}"; out+="$row"$'\n'; done
    else out="The terminal keeps none of the keys DABT listens for."; fi
    tui.view "Shortcuts $TS_TERM takes (${#TS_CONF[@]})" "${out%$'\n'}"
}

# ── the guided check: works in every terminal because it only asks "did the key arrive?" ─────────────
declare -g  _TSP_I=0 _TSP_JOB=0
declare -gA _TSP_RES=()
declare -ga _TSP_LIST=()

_ts_cmd_check() {
    _TSP_LIST=("${_TS_PROBE_CHORDS[@]}"); _TSP_I=0; _TSP_RES=()
    tui.modal.open ts_probe _ts_probe_key _ts_probe_draw
    _ts_probe_arm
}
_ts_probe_arm() { tui.after 4 _ts_probe_timeout "ts_probe_$(( ++_TSP_JOB ))"; }
_ts_probe_next() {
    (( _TSP_I++ ))
    if (( _TSP_I >= ${#_TSP_LIST[@]} )); then _ts_probe_done; else tui.modal.redraw; _ts_probe_arm; fi
}
_ts_probe_timeout() {            # the key never came: the terminal kept it
    tui.modal.active ts_probe || return 0
    [[ "$1" == "ts_probe_$_TSP_JOB" ]] || return 0
    _TSP_RES[${_TSP_LIST[_TSP_I]}]=blocked
    _ts_probe_next
}
_ts_probe_key() {
    local k="$1" cur="${_TSP_LIST[_TSP_I]}"
    case "$k" in
        q) _ts_probe_done; return ;;
        esc|space|enter) _TSP_RES[$cur]=skipped; _ts_probe_next; return ;;
        "$cur") _TSP_RES[$cur]=ok; _ts_probe_next; return ;;
    esac
    _TSP_LAST="$k"; tui.modal.redraw          # something else arrived: keep waiting
}
_ts_probe_draw() {
    tui.modal.active ts_probe || return 0
    local cur="${_TSP_LIST[_TSP_I]}" w=54 x=$(( (_TUI_COLS - 54) / 2 + 1 ))
    tui.overlay.box $(( _TUI_ROWS / 2 - 3 )) "$x" "$w" "1;97;44" "Check shortcuts  $(( _TSP_I + 1 ))/${#_TSP_LIST[@]}" \
        "" "  Press   $cur" "" "  It arrives -> next.   Nothing happens for 4 s -> the" "  terminal keeps it.   space = skip   q = finish" "  ${_TSP_LAST:+last key seen: $_TSP_LAST}"
}
_ts_probe_done() {
    local c blocked="" ok=0 sk=0 out=""
    tui.modal.close
    for c in "${_TSP_LIST[@]}"; do
        case "${_TSP_RES[$c]:-}" in blocked) blocked+="${blocked:+ }$c" ;; ok) (( ok++ )) ;; skipped) (( sk++ )) ;; esac
    done
    tui.plugin.config terminal_shortcuts blocked "$blocked"
    out+="$ok arrived, $sk skipped, $(wc -w <<< "$blocked") never arrived"$'\n\n'
    if [[ -n "$blocked" ]]; then
        out+="Taken by the terminal (or something above it):"$'\n'
        for c in $blocked; do out+="  $c"$'\n'; done
        out+=$'\n'"Run \"Terminal: free shortcuts while DABT runs\" (kitty, GNOME Terminal, tmux) or \"Terminal: show config to free shortcuts\"."
    else out+="Every key DABT listens for arrives. Nothing to free."; fi
    tui.view "Check result" "${out%$'\n'}"
}

# ── snippets for terminals that only have a config file ──────────────────

_ts_snippet_chords() {          # -> _SC: the chords to free (the last check's result, else the usual suspects)
    local b; b="$(tui.plugin.config terminal_shortcuts blocked)"
    _SC="${b:-ctrl+shift+left ctrl+shift+right ctrl+shift+up ctrl+shift+down shift+pgup shift+pgdn ctrl+shift+home ctrl+shift+end}"
}
# helpers for the snippets
_ts_snippet_split() {      # chord -> _M (list of mod words) _Kx (key)
    _M=(); local w; IFS='+' read -ra w <<< "$1"; _Kx="${w[-1]}"; unset 'w[-1]'; _M=("${w[@]}")
}
_ts_snippet_gtkname() { case "$1" in left) _Gn=Left ;; right) _Gn=Right ;; up) _Gn=Up ;; down) _Gn=Down ;; home) _Gn=Home ;; end) _Gn=End ;;
                            pgup) _Gn=PageUp ;; pgdn) _Gn=PageDown ;; insert) _Gn=Insert ;; delete) _Gn=Delete ;; *) _Gn="${1^^}" ;; esac; }

_ts_cmd_snippet() {
    _ts_detect; _ts_snippet_chords
    local c mods key out="" m
    case "$TS_TERM" in
        kitty)
            out+="# kitty.conf   (kitty passes a key to the program when it is mapped to no_op)"$'\n'
            for c in $_SC; do out+="map ${c/pgup/page_up} no_op"$'\n'; done; out="${out//pgdn/page_down}" ;;
        alacritty)
            out+="# alacritty.toml   (ReceiveChar sends the key to the program)"$'\n[keyboard]\nbindings = [\n'
            for c in $_SC; do _ts_snippet_split "$c"; _ts_snippet_gtkname "$_Kx"; m=""; for mods in "${_M[@]}"; do m+="${m:+|}${mods^}"; done; m="${m/Ctrl/Control}"
                out+="  { key = \"$_Gn\", mods = \"$m\", action = \"ReceiveChar\" },"$'\n'; done; out+="]"$'\n' ;;
        wezterm)
            out+="-- wezterm.lua   (inside config.keys = { ... })"$'\n'
            for c in $_SC; do _ts_snippet_split "$c"; _ts_snippet_gtkname "$_Kx"; m=""; for mods in "${_M[@]}"; do m+="${m:+|}${mods^^}"; done
                case "$_Gn" in Left|Right|Up|Down) _Gn+=Arrow ;; esac
                out+="  { key = '$_Gn', mods = '${m/CTRL/CTRL}', action = wezterm.action.DisableDefaultAssignment },"$'\n'; done ;;
        ghostty)
            out+="# ghostty config"$'\n'
            for c in $_SC; do out+="keybind = ${c/pgup/page_up}=unbind"$'\n'; done; out="${out//pgdn/page_down}" ;;
        windows-terminal)
            out+="// settings.json  ->  \"actions\""$'\n'
            for c in $_SC; do out+="{ \"command\": \"unbound\", \"keys\": \"${c/pgup/pgup}\" },"$'\n'; done ;;
        gnome-terminal|vte) out+="# gsettings works at runtime for GNOME Terminal - run \"Terminal: free shortcuts\"."$'\n'"# Other VTE terminals: Preferences > Shortcuts, set these to Disabled:"$'\n'; for c in $_SC; do out+="  $c"$'\n'; done ;;
        konsole) out+="Konsole: Settings > Configure Keyboard Shortcuts, remove these:"$'\n'; for c in $_SC; do out+="  $c"$'\n'; done ;;
        foot)    out+="foot.ini [key-bindings] / [text-bindings]: set the action that uses each of these to 'none':"$'\n'; for c in $_SC; do out+="  $c"$'\n'; done ;;
        iterm2)  out+="iTerm2: Settings > Keys > Key Bindings: remove or override these:"$'\n'; for c in $_SC; do out+="  $c"$'\n'; done ;;
        *)       out+="Free these keys in ${TS_TERM}'s own settings (no config format known for it):"$'\n'; for c in $_SC; do out+="  $c"$'\n'; done ;;
    esac
    [[ -n "$TS_MUX" ]] && out+=$'\n'"# ${TS_MUX}: also make it pass modified keys through, e.g. in tmux.conf:  set -g extended-keys on"$'\n'
    tui.clipboard.copy "$out"
    tui.view "Config for ${TS_TERM} (copied to the clipboard)" "${out%$'\n'}"
}

_ts_cmd_free()    { _ts_free; }
_ts_cmd_restore() { _ts_restore; }
