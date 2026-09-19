#!/usr/bin/env bash

# ============================================================================
# TUI FONT DICTIONARY (Seamless Box-Drawing, A-Z)
# ============================================================================
declare -gA TUI_FONT

# Standard 3-width letters
TUI_FONT['A']=$'╭─╮\n├─┤\n╵ ╵'
TUI_FONT['B']=$'┌─╮\n├─┤\n└─╯'
TUI_FONT['C']=$'╭──\n│  \n╰──'
TUI_FONT['D']=$'┌─╮\n│ │\n└─╯'
TUI_FONT['E']=$'┌──\n├──\n└──'
TUI_FONT['F']=$'┌──\n├──\n│  '
TUI_FONT['G']=$'╭──\n│ ┬\n╰─╯'
TUI_FONT['H']=$'╷ ╷\n├─┤\n╵ ╵'
TUI_FONT['I']=$' ╷ \n │ \n ╵ '
TUI_FONT['J']=$'  ╷\n  │\n╰─╯'
TUI_FONT['K']=$'╷╱\n├ \n╵╲'
TUI_FONT['L']=$'╷  \n│  \n└──'
TUI_FONT['O']=$'╭─╮\n│ │\n╰─╯'
TUI_FONT['P']=$'┌─╮\n├─╯\n│  '
TUI_FONT['R']=$'┌─╮\n├─╯\n│ ╲'
TUI_FONT['S']=$'╭──\n╰─╮\n──╯'
TUI_FONT['U']=$'╷ ╷\n│ │\n╰─╯'
TUI_FONT['V']=$'╷ ╷\n╲ ╱\n ╵ '
TUI_FONT['X']=$'╲ ╱\n ╳ \n╱ ╲'
TUI_FONT['Y']=$'╷ ╷\n╰┬╯\n ╵ '
TUI_FONT['Z']=$'──╮\n ╱ \n╰──'

# Proportional widths (4, 5, and 6 columns)
TUI_FONT['M']=$'╭─╮╭─╮\n│ ╰╯ │\n╵    ╵'
TUI_FONT['N']=$'╷  ╷\n│╲ │\n╵ ╲╵'
TUI_FONT['Q']=$'╭─╮ \n│ │ \n╰─╯╲'
TUI_FONT['T']=$'──┬──\n  │  \n  ╵  '
TUI_FONT['W']=$'╷ ╷ ╷\n│ │ │\n╰─┴─╯'

# Space padding
TUI_FONT[' ']="   \n   \n   "

# ============================================================================
# STRING RENDERER
# ============================================================================
render_banner() {
    # Automatically convert input to uppercase to match the dictionary
    local input_string="${1^^}"
    local out1="" out2="" out3=""
    local char
    local -a lines
    local _idx

    for (( _idx=0; _idx<${#input_string}; _idx++ )); do
        char="${input_string:$_idx:1}"
        
        # Fallback to space if character is missing
        if [[ -z "${TUI_FONT[$char]+x}" ]]; then
            char=" "
        fi
        
        # Safely split the 3-line string block
        readarray -t lines <<< "${TUI_FONT[$char]}"
        
        # Build the rows, adding 1 space gap between characters
        out1+="${lines[0]} "
        out2+="${lines[1]} "
        out3+="${lines[2]} "
    done

    printf "%s\n%s\n%s\n" "$out1" "$out2" "$out3"
}

# --- Example Usage ---

char_upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
char_lower="abcdefghijklmnopqrstuvwxyz"
numbers="0123456789"
punctuation="!\"#$%&'()*+,-./:;<=>?@[\\]^_\`{|}~"
render_banner $char_upper
render_banner $char_lower