#!/usr/bin/env bash
source "./terminal_renderer.sh"

docu_path="../docs"
uiMarkup="$docu_path/ui_markup.md"
readme="../README.md"
doc="$docu_path/Beding-The-World-To-Your-Will_architectural-Strategies-for-High-Performance-Viewport Scrolling-in-Pure-Bash-Terminal-Interfaces.md"
callback_viewport="$docu_path/Callbacks_and_viewports.md"
on_tab_readme() {
    load_document "$readme" "README"
}

on_tab_ui_markup() {
    load_document "$uiMarkup" "UI Markup"
}

on_tab_doc() {
    load_document "$doc" "Bending the world to your will"
}

on_tab_callbacks_viewport() {
    load_document "$callback_viewport" "Callbacks And Viewport"
}

load_document() {
    local doc_path=$1
    local raw_doc=""
    tui.clear_pane "content"
    # Prepend a generated banner
    raw_doc+="\n$(banner_string "${2:-$(basename "$doc_path")}")\n\n"
    
    # Dynamically substitute the file content
    if [[ -f "$doc_path" ]]; then
        raw_doc+="$(cat "$doc_path")\n"
    else
        raw_doc+="$(alert_string error "Document not found at: $doc_path")\n"
    fi

    # Evaluate \n escape sequences and push to the scrollable pane
    local formatted_doc="$(printf '%b' "$raw_doc")"
    tui.output "content" "$formatted_doc"
    tui.pane_title "content" "$(basename "$doc_path")"
}