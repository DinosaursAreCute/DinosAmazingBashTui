#!/usr/bin/env bash
# terminal_plugin_tests.sh - tests of the terminal_shortcuts plugin: detection, kitty's REAL keymap (needs kitty installed),
# freeing / restoring through a kitty include file, GNOME Terminal (fake gsettings) and tmux (fake tmux). Exit status = failures.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"; DIR="$ROOT/lib"
export XDG_CONFIG_HOME="$(mktemp -d)"; T="$XDG_CONFIG_HOME"; trap 'rm -rf "$XDG_CONFIG_HOME"; kill $USR1PID 2>/dev/null' EXIT
stty() { [[ "$1" == size ]] && echo "30 100"; }
FAIL=0; N=0
ok() { (( N++ )); [[ "$2" == "$3" ]] || { (( FAIL++ )); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "$2" "$3" >&3; }; }
cd "$DIR" && source ./tui.sh
exec 3>&1 1>/dev/null
tui.config.load; TUI_DEFAULTS_DIR="$ROOT/share/defaults"; _TPL_DIRS=("$ROOT/share/plugins"); tui.plugin.scan
_TUI_RUNNING=1; tui.bind.defaults >/dev/null 2>&1
ok "plugin found as built-in" "$(tui.plugin.get terminal_shortcuts source)" "builtin"
ok "default on" "$(tui.plugin.get terminal_shortcuts state)" "disabled"; tui.plugin.startup
ok "enabled at startup" "$(tui.plugin.get terminal_shortcuts state)" "enabled"
ok "commands registered" "${_TUI_CMD_TITLE[ts.free]:-}" "Terminal: free shortcuts while DABT runs"
# ── detection ──
det() { ( unset KITTY_WINDOW_ID KITTY_PID TMUX STY WEZTERM_PANE GHOSTTY_RESOURCES_DIR ALACRITTY_SOCKET ALACRITTY_LOG TERM_PROGRAM WT_SESSION KONSOLE_VERSION GNOME_TERMINAL_SCREEN GNOME_TERMINAL_SERVICE VTE_VERSION XTERM_VERSION; export TERM=xterm; eval "$1"; _ts_detect; echo "$TS_TERM/$TS_MUX" ); }
ok "detect kitty"     "$(det 'export KITTY_WINDOW_ID=1')" "kitty/"
ok "detect wezterm"   "$(det 'export WEZTERM_PANE=3')" "wezterm/"
ok "detect ghostty"   "$(det 'export TERM_PROGRAM=ghostty')" "ghostty/"
ok "detect konsole"   "$(det 'export KONSOLE_VERSION=240800')" "konsole/"
ok "detect gnome-terminal" "$(det 'export GNOME_TERMINAL_SERVICE=:1.5 VTE_VERSION=7600')" "gnome-terminal/"
ok "detect tmux inside kitty" "$(det 'export KITTY_WINDOW_ID=1 TMUX=/tmp/x,1,0')" "kitty/tmux"
# ── kitty: the real effective keymap ──
if command -v kitty >/dev/null; then
    K="$T/kitty"; mkdir -p "$K"; export KITTY_CONFIG_DIRECTORY="$K"
    printf 'map ctrl+c copy_or_interrupt\nmap page_up scroll_page_up\n' > "$K/kitty.conf"
    bash -c 'trap : USR1; sleep 300 & wait' >/dev/null 2>&1 & USR1PID=$!; sleep 0.3
    export KITTY_WINDOW_ID=1 KITTY_PID=$USR1PID
    _ts_detect; ok "kitty strategy" "$TS_STRATEGY" "kitty"
    _ts_collect_used; _ts_kitty_conflicts
    conf="$(printf '%s\n' "${TS_CONF[@]}" | cut -f1 | sort | tr '\n' ' ')"; NBEFORE=${#TS_CONF[@]}
    for c in ctrl+shift+left ctrl+shift+right ctrl+shift+up ctrl+c pgup; do
        [[ " $conf " == *" $c "* ]] && r=yes || r=no; ok "kitty takes $c" "$r" "yes"
    done
    ok "kitty does not take plain 'left'" "$([[ " $conf " == *" left "* ]] && echo yes || echo no)" "no"
    tui.plugin.config terminal_shortcuts kitty_include 1
    _ts_kitty_free quiet
    ok "include line added once, kitty.conf backed up" "$(grep -c 'include dabt-shortcuts.conf' "$K/kitty.conf") $([[ -f $K/kitty.conf.dabt-backup ]] && echo backup)" "1 backup"
    ok "map lines written" "$(grep -c '^map .* no_op$' "$K/dabt-shortcuts.conf")" "$NBEFORE"
    _ts_collect_used; _ts_kitty_conflicts; ok "nothing left taken after freeing (kitty re-reads the file)" "${#TS_CONF[@]}" "0"
    ok "freed flag" "$_TS_FREED" "kitty"
    _ts_restore quiet
    ok "restore empties the file" "$(grep -c '^map' "$K/dabt-shortcuts.conf")" "0"
    _ts_collect_used; _ts_kitty_conflicts; ok "taken again after restore" "$(( ${#TS_CONF[@]} > 5 ))" "1"
    unset KITTY_WINDOW_ID KITTY_PID KITTY_CONFIG_DIRECTORY; kill $USR1PID 2>/dev/null
else echo "(kitty not installed: kitty tests skipped)" >&3; fi
# ── GNOME Terminal with a fake gsettings ──
G="$T/gs"; mkdir -p "$G/bin"
printf "%s\n" "<Primary><Shift>c" "<Primary><Shift>Left" "<Alt>1" "F1" "<Primary><Shift>t" > "$G/keys"
cat > "$G/bin/gsettings" <<'GS'
#!/usr/bin/env bash
S="$GSDIR/state"
[[ -f "$S" ]] || printf '%s\n' "copy	<Primary><Shift>c" "prev-tab	<Primary><Shift>Left" "switch-to-tab-1	<Alt>1" "help	F1" "new-tab	<Primary><Shift>t" "unused	disabled" > "$S"
case "$1" in
  list-keys) cut -f1 "$S" ;;
  list-recursively) while IFS=$'\t' read -r k v; do echo "org.gnome.Terminal.Legacy.Keybindings $k '$v'"; done < "$S" ;;
  set) k="$3"; v="$4"; awk -F'\t' -v k="$k" -v v="$v" 'BEGIN{OFS="\t"} $1==k{$2=v}1' "$S" > "$S.n" && mv "$S.n" "$S" ;;
esac
GS
chmod +x "$G/bin/gsettings"
export GSDIR="$G" PATH="$G/bin:$PATH"
export GNOME_TERMINAL_SERVICE=:1.1 VTE_VERSION=7600
_ts_detect; ok "gnome strategy" "$TS_STRATEGY" "gnome"
_ts_collect_used; _ts_gnome_conflicts
ok "gnome conflicts: prev-tab (ctrl+shift+left) and help (f1)" "$(printf '%s\n' "${TS_CONF[@]}" | cut -f1 | sort | tr '\n' ' ')" "ctrl+shift+left f1 "
_ts_gnome_free quiet
ok "gnome keys disabled" "$(awk -F'\t' '$2=="disabled"{n++} END{print n}' "$G/state")" "3"
ok "backup written" "$(wc -l < "$TUI_APP_CONF/terminal_shortcuts.gnome.backup")" "2"
_TS_FREED=gnome; _ts_restore quiet
ok "gnome restored exactly" "$(awk -F'\t' '$1=="prev-tab"{print $2} $1=="help"{print $2}' "$G/state" | tr '\n' ' ')" "<Primary><Shift>Left F1 "
ok "backup removed" "$([[ -f "$TUI_APP_CONF/terminal_shortcuts.gnome.backup" ]] && echo left)" ""
# crash recovery: a stale backup is restored at enable
_ts_gnome_free quiet; ok "freed again" "$(awk -F'\t' '$1=="help"{print $2}' "$G/state")" "disabled"
_TS_FREED=""; tui.plugin.reload terminal_shortcuts
ok "reload/enable restored a stale backup (crash recovery)" "$(awk -F'\t' '$1=="help"{print $2}' "$G/state")" "F1"
unset GNOME_TERMINAL_SERVICE VTE_VERSION
# ── tmux with a fake tmux ──
M="$T/tm"; mkdir -p "$M/bin"
printf '%s\n' 'bind-key    -T root         C-S-Left     send-keys foo' 'bind-key    -T root         PageUp       copy-mode -eu' 'bind-key    -T root         MouseDown1Pane select-pane -t =' > "$M/state"
cat > "$M/bin/tmux" <<'TM'
#!/usr/bin/env bash
S="$TMDIR/state"
case "$1" in
  list-keys) cat "$S" ;;
  unbind-key) grep -v -E "root +$4 " "$S" > "$S.n"; mv "$S.n" "$S" ;;
  source-file) cat "$2" >> "$S" ;;
esac
TM
chmod +x "$M/bin/tmux"; export TMDIR="$M" PATH="$M/bin:$PATH" TMUX=/tmp/x,1,0
_ts_detect; ok "tmux strategy" "$TS_STRATEGY" "tmux"
_ts_collect_used; _ts_tmux_conflicts
ok "tmux conflicts" "$(printf '%s\n' "${TS_CONF[@]}" | cut -f1 | sort | tr '\n' ' ')" "ctrl+shift+left pgup "
_ts_tmux_free quiet; ok "tmux keys unbound" "$(grep -c -E 'C-S-Left|PageUp' "$M/state")" "0"
_TS_FREED=tmux; _ts_restore quiet; ok "tmux keys replayed" "$(grep -c -E 'C-S-Left|PageUp' "$M/state")" "2"
unset TMUX
# ── snippets ──
TS_TERM=ghostty; tui.plugin.config terminal_shortcuts blocked "ctrl+shift+left pgup"
ok "ghostty snippet" "$(_ts_snippet_chords; for c in $_SC; do echo "keybind = ${c/pgup/page_up}=unbind"; done | tr '\n' ' ')" "keybind = ctrl+shift+left=unbind keybind = page_up=unbind "
# ── disabling gives everything back ──
tui.plugin.disable terminal_shortcuts; ok "commands removed on disable" "${_TUI_CMD_TITLE[ts.free]:-gone}" "gone"; ok "hooks removed on disable" "${_TPL_HOOK[exit]:-none}" "none"
echo "$N checks, $FAIL failed" >&3
exit $FAIL
