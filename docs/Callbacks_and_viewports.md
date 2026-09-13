# Developer Guide: Callbacks and Interactive Viewports

DinosAmazingBashTui (DABT) allows developers to construct sophisticated terminal applications by marrying declarative XML layouts with imperative Bash callbacks. To ensure high performance and maintainable code, it is critical to follow established architectural patterns when modeling these interactions.

## 1. Modeling Callbacks

Callbacks in DABT are standard Bash functions triggered by user interactions (button clicks or input submissions). 

### Separation of Concerns
Never write imperative layout code inside a callback. All UI structural definitions should remain in your `.xml` files. Callbacks should strictly handle:
1. State mutation and data fetching.
2. Form data retrieval (`tui.get`).
3. Widget/Pane updates (`tui.update`, `tui.output`).

### Interacting with Widgets
To read the current value of a text `<input>` field when a button is clicked, use `tui.get "widget_id"`. To push a change back to the screen, use `tui.update "widget_id" "new value"`. `tui.update` automatically triggers a localized redraw of just that component, ensuring maximum efficiency.

```bash
# Example: Form Submission Callback
on_submit_user_form() {
    # 1. Retrieve data
    local username="$(tui.get "inp_username")"
    
    # 2. Mutate state or validate
    if [[ -z "$username" ]]; then
        tui.update "lbl_status" "Error: Username cannot be blank."
        return
    fi
    
    # 3. Apply updates
    tui.update "btn_submit" "[ Saved ]"
    tui.update "lbl_status" "Welcome, $username!"
}

```

### Leveraging the Terminal Renderer Toolkit

For building complex read-only views, rely heavily on `terminal_renderer.sh`. It contains specialized components (tables, key-value grids, horizontal bar charts, alerts, and badges).

Always use the `_string` suffix variants of these commands inside callbacks (e.g., `table_string`, `alert_string`). This instructs the renderer to return a raw, `\n`-delimited string buffer containing exact ANSI formatting, rather than printing directly to `stdout`, preventing terminal tearing.

```bash
on_generate_report() {
    local buffer=""
    
    # Append complex rendered components directly into a string buffer
    buffer+="$(alert_string info "Report generated successfully.")\n\n"
    buffer+="$(table_string "User\vert{}Role\vert{}Status" "admin\vert{}Superuser\vert{}$(badges_string "pass:Active")")\n"
    
    # Output the pre-computed buffer to a pane
    local formatted="$(printf '\%b' "$buffer")"
    tui.output "pane_results" "$formatted"
}

```

## 2. Building Scrolling Viewports

DABT handles text overflow gracefully through a custom, single-pass AWK shader. This enables massive blocks of text, complex tables, and raw logs to be scrolled smoothly using the mouse wheel, jump-to-click scrollbars, or keyboard bindings (`hjkl` / Shift+Arrows).

### Enabling Scrolling

To make a pane scrollable, declare the `scroll` attribute in your XML layout:

```xml
<pane id="log_output" border="heavy" scroll="both" class="panel" />

```

* `scroll="v"`: Vertical scrolling only.
* `scroll="h"`: Horizontal scrolling only.
* `scroll="both"`: Unrestricted multi-axis scrolling.

### Injecting Data into Viewports

Use `tui.output "pane_id" "content"` to replace the contents of a pane, or `tui.output_append` to add to the bottom of the existing stream.

When `tui.output` is called, the framework instantly computes the text boundaries and caches them. The rendering is inherently delayed (debounced) until the user finishes interacting, allowing for flawless framerates even during rapid scrolling.

### Viewport Constraints and Best Practices

1. **Empty Leaves Only:** Scrollable panes **must not** contain child `<pane>` nodes or interactive widgets (`<input>`, `<button>`, `<label>`). They must remain structural leaves.
2. **Memory Considerations:** Do not pipe infinite streams directly into memory unless managing them. The `tui.exec` module manages memory automatically via a capped ring-buffer, but manual `tui.output_append` loops will grow memory indefinitely.
3. **Triggering Formats:** Always ensure your dynamically generated strings resolve their literal escape characters before injection. Use `printf '%b' "$your_string"` before passing it into `tui.output` so the AWK shader can correctly evaluate newlines (`\n`) and ANSI colors.

