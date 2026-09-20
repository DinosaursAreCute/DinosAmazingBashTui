#!/usr/bin/bash
# ShellCheck source=./*
source ./cursor_controls.sh
source ./terminal_controls.sh
source ./colors.sh
source ./terminal_renderer.sh

finally() {
    mouse.any_off
    
    clear
}

trap 'mouse.any_off; exit 1' EXIT
term.soft_reset
clear

rgb="ff00/0000/0000"


cursor_test(){
while true; do
    osc.cursor_color "rgb:$rgb" 
    incriment_rgb
    sleep 0.1
done

}

color_test(){
    tput clear
    tput civis  # hide cursor
    local cols=$(tput cols)
    local rows=$(tput lines)
    local total=$((cols * rows))
    
    for ((pos=0; pos<total; pos++)); do
        
        local hue=$((pos * 360 / total))
        local sector=$((hue / 60))
        local f=$((( hue % 60) * 255 / 60))
        local q=$((255 - f))

        local r g b
        case $sector in
            0) r=255; g=$f;   b=0   ;;
            1) r=$q;  g=255;  b=0   ;;
            2) r=0;   g=255;  b=$f  ;;
            3) r=0;   g=$q;   b=255 ;;
            4) r=$f;  g=0;    b=255 ;;
            *) r=255; g=0;    b=$q  ;;
        esac

        printf "\e[38;2;%d;%d;%dm█" "$r" "$g" "$b"
	
        done

    printf "\e[0m"
    tput cnorm 
    read -r -n1
}
spectrum_test(){
    tput clear
    tput civis
    local cols=$(tput cols)
    local rows=$(tput lines)

    for ((y=0; y<rows; y++)); do
        local v=$(( (rows - 1 - y) * 255 / (rows - 1) ))
        for ((x=0; x<cols; x++)); do
            local hue=$((x * 360 / cols))
            local sector=$((hue / 60))
            local f=$(( (hue % 60) * 255 / 60 ))
            local q=$((255 - f))

            local r g b
            case $sector in
                0) r=255; g=$f;   b=0   ;;
                1) r=$q;  g=255;  b=0   ;;
                2) r=0;   g=255;  b=$f  ;;
                3) r=0;   g=$q;   b=255 ;;
                4) r=$f;  g=0;    b=255 ;;
                *) r=255; g=0;    b=$q  ;;
            esac

            r=$((r * v / 255))
            g=$((g * v / 255))
            b=$((b * v / 255))

            printf "\e[38;2;%d;%d;%dm█" "$r" "$g" "$b"
        done
    done

    printf "\e[0m"
    tput cnorm
    read -r -n1
}

mouse_spectrum(){
    tput clear
    tput civis
    local cols=$(tput cols)
    local rows=$(tput lines)
    local old_stty
    old_stty=$(stty -g)
    stty -echo -icanon min 1 time 0

    # enable mouse tracking (SGR extended mode, button-event tracking)
    printf "\e[?1002h"  # button-event tracking (reports press + drag, not bare motion)
    printf "\e[?1006h"  # SGR extended coordinates

    cleanup(){
        printf "\e[?1002l"
        printf "\e[?1006l"
        printf "\e[0m"
        stty "$old_stty"
        tput cnorm
        tput clear
    }

    trap 'cleanup; return' INT TERM

    while IFS= read -rsn1 char; do
        if [[ "$char" == $'\e' ]]; then
            local seq=""
            while IFS= read -rsn1 -t 0.01 c; do
                seq+="$c"
                [[ "$c" == "M" || "$c" == "m" ]] && break
            done

            if [[ "$seq" == "[<"* ]]; then
                seq="${seq#\[<}"
                local end="${seq: -1}"
                seq="${seq%[Mm]}"

                IFS=';' read -r btn mx my <<< "$seq"

                [[ "$end" == "m" ]] && continue           
                (( btn != 0 && btn != 32 )) && continue   

                local hue=$((mx * 360 / cols))
                local v=$(( (rows - my) * 255 / rows ))
                (( v < 0 )) && v=0
                (( v > 255 )) && v=255

                local sector=$((hue / 60))
                local f=$(( (hue % 60) * 255 / 60 ))
                local q=$((255 - f))

                local r g b
                case $sector in
                    0) r=255; g=$f;   b=0   ;;
                    1) r=$q;  g=255;  b=0   ;;
                    2) r=0;   g=255;  b=$f  ;;
                    3) r=0;   g=$q;   b=255 ;;
                    4) r=$f;  g=0;    b=255 ;;
                    *) r=255; g=0;    b=$q  ;;
                esac

                r=$((r * v / 255))
                g=$((g * v / 255))
                b=$((b * v / 255))

                tput cup "$((my - 1))" "$((mx - 1))"
                printf "\e[38;2;%d;%d;%dm█\e[0m" "$r" "$g" "$b"
            fi
        elif [[ "$char" == "q" ]]; then
            break
        fi
    done

    cleanup
}



spectrum_test
color_test
