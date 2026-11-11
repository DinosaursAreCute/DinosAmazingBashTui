# Collapsible panes, details and accordions

A pane can fold away. Its space goes to its siblings, and a small button on its border brings it back.

```xml
<pane id="side" weight="30" split="v" collapsible="true" collapse_to="0" collapse_key="alt+b">
  ...
</pane>
```

```bash
tui.collapse side          # toggle
tui.collapse side on       # collapse   (off = expand)
```

## Attributes

| Attribute | What it does |
|---|---|
| `collapsible="true"` | adds the collapse button. The pane must sit in an `h` or `v` split. |
| `collapse_to` | what stays when collapsed: `title` (one row or column, the default), `0` (nothing), `rail` (a narrow strip of buttons) |
| `collapsed="true"` | start collapsed |
| `collapse_key` | a key that toggles the pane from anywhere on the page, **also while a text input has focus** |
| `on_toggle` | `FN PANE STATE` after a change; `STATE` is `collapsed` or `expanded` |
| `collapse_class` | theme class of the button: `.name`, `.name:hover`, `.name:collapsed` |

## Details and accordion

`<details>` is a collapsible pane with a title. `<accordion>` is a split of them where opening one closes the others (`multiple="true"` lets several stay open).

```xml
<accordion id="info" weight="40">
  <details id="d_selected" title="Selected" border="single">
    <label id="lbl_name" text=""/>
  </details>
  <details id="d_prompt" title="System prompt" border="single">
    <label id="lbl_prompt" text=""/>
  </details>
</accordion>
```

## Quirks

- **`alt+c` does nothing while a text input has focus**, because the input owns it. Use `collapse_key` for apps with an input (a chat, a filter).
- **`collapsed="true"` on a `<details>` inside an `<accordion>` is not applied on the first build** (nor is `default="collapsed"`). Collapse it from `on_visit`: `tui.collapse d_prompt on`. On a plain `collapsible` pane the attribute works.
- **A scrolling pane inside a collapsed `<details>` draws over its title strip.** Put a label or another plain widget inside.
- A pane that contains panes needs `split="h|v|grid|fixed"`, collapsible or not. The page refuses to start otherwise, and says which pane.
- `tui.collapse` returns 1 when nothing changed (it already was in that state). That is not an error.
- Each collapse button is drawn on a pane corner. To hide it, give its `collapse_class` the panel's own colours.

## Performance

- Every `tui.collapse` lays the page out again. Switching a deck of four panes (four calls plus refreshing the tab that opens) measured about 35 ms in the Chatty app. Keep decks small.
- In an exclusive accordion one call closes the siblings as well. `on_toggle` runs for every pane that changed, so keep it light.
- A collapsed pane keeps its widgets, so reopening it costs only the layout.
