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

## 2. Hover and Focus Feedback

`tui.init` enables xterm any-motion mouse tracking (`\e[?1003h`), so the
framework receives a stream of position reports even when no button is
pressed. On every report, `_tui._handle_mouse` recomputes which pane
(`_tui._pane_at`) and which focusable widget (`_tui._hit_test`) sit under the
pointer and hands each to a setter (`_tui._set_hovered_pane` /
`_tui._set_hovered_widget`).

These two setters do very different things, deliberately:

* **`_tui._set_hovered_pane`** just records `_TUI_HOVERED_PANE`. That's it —
  no redraw. It exists purely as routing state so scroll-wheel and
  keyboard-scroll events (`_tui._scroll_kb`, the wheel branch of
  `_tui._handle_mouse`) know which viewport to move. Pane borders never
  react to hover.
* **`_tui._set_hovered_widget`** is change-gated (a no-op unless the hovered
  widget actually differs) and, when it does change, redraws immediately via
  `_tui._draw_widgets_now` — no debounce, no queue. A button redraw is one
  cheap, single-widget write, so there's no fan-out burst to collapse the
  way a multi-pane border sweep once caused; deferring it only added
  latency between "pointer arrives" and "button lights up" for no
  throughput benefit. `_tui._draw_widget` resolves `${id}_hover` from a
  `.class:hover` rule (behind `${id}_focus`, which always wins), falling
  back to the normal look if the class defines no `:hover` state.

A pane's border reacts to *focus* instead of hover. `_tui._draw_pane_border`
checks whether `_TUI_FOCUS_ID` belongs to that pane and resolves
`${id}_focus` (falling back to `${id}_border`) — the same self-contained
style resolution `_tui._draw_widget` already used for its own state, just
keyed off `_TUI_FOCUS_ID` rather than the hover trackers. `tui.focus` and
`_tui._unfocus` redraw the old and new focused widget's panes right after
moving focus, via `_tui._draw_pane_borders_now` — a thin wrapper (shared with
`_tui._draw_widgets_now`) around the generic `_tui._draw_ids_now` helper,
which calls a draw function once per unique id and flushes the result as one
synchronized write. Either way, only the border ring is touched — never the
pane's interior, so it's safe to call without disturbing a live `scroll="…"`
viewport's `tui.output` content.

Give a pane's border a focus color with a `:focus` block, and a widget a
hover color with `:hover`:

```css
.panel:focus { fg: #ffffff; bg: #2c3e50; }
.info_button:hover { fg: white; bg: #3a80ca; mods: bold; }
```

Leaving either pseudo-state out of a class leaves that transition with no
visual effect — the fallback in `_tui._apply_style` resolves straight
through to the normal/border style.

## 3. Building Scrolling Viewports

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

