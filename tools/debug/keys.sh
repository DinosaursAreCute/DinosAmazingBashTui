#!/usr/bin/env bash
# keys.sh - what does my terminal actually send? Press a key (or chord) and see the raw bytes and the name DABT gives it.
#   tools/debug/keys.sh        q quits.   Try ctrl+shift+left, alt+shift+left, shift+pgdn, ctrl+backspace ...
# If a chord prints nothing, your terminal (or window manager) keeps it for itself; use the alt+shift alternative or rebind it there.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"; DIR="$ROOT/lib"
source "$DIR/tui.sh" 2>/dev/null
old=$(stty -g); stty -echo -icanon -isig -ixon -iexten min 1 time 0
printf '\e[?1049h'                      # alternate screen, like the app: some terminals only pass chords such as ctrl+shift+up/down there
trap 'printf "\e[?1049l"; stty "$old"' EXIT
printf '\e[1;1Hpress keys; q quits\n'
while IFS= read -rsn1 c; do
    seq=""; raw="$c"
    if [[ "$c" == $'\e' ]]; then
        while IFS= read -rsn1 -t 0.05 n; do seq+="$n"; raw+="$n"; [[ "$n" == [A-Za-z~] && "$seq" != "O" ]] && break; done
        _tui_input.name_seq "$seq"
    else
        [[ "$c" == q ]] && break
        _tui_input.name_char "$c"
    fi
    printf '%-24s -> %s\n' "$(printf '%s' "$raw" | od -An -c | sed 's/^ *//; s/  */ /g')" "${_KEY:-(nothing)}"
done
