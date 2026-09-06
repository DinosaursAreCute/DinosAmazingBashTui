#!/usr/bin/env bash
source tui.sh
# This file is dynamically sourced by tui_config_parser.sh

on_submit() {
    local name email
    name=$(tui.get "inp_name")
    email=$(tui.get "inp_email")
    
    tui.update "out1" "Name:  ${name:-<empty>}"
    tui.update "out2" "Email: ${email:-<empty>}"
    tui.update "out3" "✔ Submitted!"
}

on_clear() {
    tui.set "inp_name" ""
    tui.set "inp_email" ""
    tui.update "out1" ""
    tui.update "out2" ""
    tui.update "out3" "Cleared."
    tui.render
}

on_quit() {
    tui.stop
}

on_lsh() {
    tui.exec "lsh" "output" "actions"
}