#!/usr/bin/env bash
# page2_callbacks.sh - stage2_lab page 2 (Hit/Focus + Composition). See page2.xml's header comment.

_S2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

s2_page2_visit() { :; }
s2_goto_page1() { tui.goto "$_S2_DIR/page1.xml"; }
s2_noop() { :; }
