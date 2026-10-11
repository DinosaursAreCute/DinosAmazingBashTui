# Design: layers (stage 3B)

How floating windows, modals, popups and toasts fit the engine, and why.

## A layer is a pane outside the split tree

`<window>` and its siblings run the pane handler (children, borders, widgets, styles all work as for any pane) and then register the pane as a layer instead of adding it to a split. Its rectangle comes from `x`, `y`, `width`, `height` and `anchor`, clamped to the screen, and is written into the pane's own geometry before `_tui._layout_r` lays out what is inside.

## One list of panes, three places that look at the difference

`_TUI_P_ALL` holds the page's panes and then the visible layers' panes, bottom layer first, so every loop over panes (scrollbars, content fit, collapse buttons, hit zones) works for layers without a second code path. `_TUI_P_LAYER[pane]` names the layer a pane belongs to. Only three places consult it:

- **Render.** `tui.render` skips layer panes and widgets; `_tui_layer.draw` paints them as an overlay, so they are redrawn whenever something painted under them. The overlay bytes are appended to the page's frame, so the screen gets one write per full render. A synchronized update cannot be nested, and two writes were visible as the page appearing before its layers.
- **Hit index.** After the normal rebuild, `_tui_layer.rank_rows` reorders every row's zone list: highest layer first, inside a layer its header, button and corner zones, then its widgets, then a zone that covers its whole rectangle and stops the scan (the page under it is never looked at). Tooltips skip that zone.
- **Focus order.** A modal layer is the focus scope: widgets outside it are not in Tab order, and the widget that had focus is remembered and restored on close.

## Repaint without erase

A move, resize, show or hide repaints the page and the layers in one write and does not erase the screen. The page paints every cell above the footer row, so what a layer vacated is covered; the footer (which an erase would blank and redraw) stays put.

## Detach and dock

Detaching removes the pane from its h or v split (children and size specs), records its neighbours, registers it as a layer, and (with `leave="placeholder"`) leaves an empty pane of the same spec. Docking puts it between the neighbours it had, falling back to its old index, and removes or replaces the placeholder wherever it has moved to. The pane keeps its id and widgets throughout, so the store, styles and callbacks do not notice.

## State

Layers are page state: `_TUI_L_*` is part of the page cache and `tui.reset_ui` clears it. On a shell page the layers a page declares leave with it and the shell's stay. `persist="layout"` stores a window's rectangle and visibility, or a detachable pane's floating state, as the store field `layout`.

## The stack, function layers and background painters

There is one stack and no separate overlay registry. Pane layers (the markup tags) and function layers (a draw function: the footer, the job spinner, toasts, the command palette, dialogs, a plugin's `tui.overlay.add`) are drawn in this order, bottom to top: ambient function layers, pane layers, the other function layers in the order they were added (`tui.layer.fn_add FN [ambient]`, `lib/chrome/tui_layer.sh`). An ambient layer owns cells no page paint reaches (the footer row), so it is drawn with the page and never after a repaint. `tui.modal.*` (`lib/chrome/tui_modal.sh`) is the modal preset: a function layer plus the input capture and the saved-frame replay of `tui.modal.dismiss`.

`_tui._flush` appends the stack (pane layers and the non-ambient function layers) to any write that repaints the page under them, so a clock tick or an animation frame never shows the page over a layer or the palette, not even for one frame. Background painters (`tui.async.*`, lib/render/tui_async.sh) are processes that draw straight to the terminal; while a modal or a layer is open, and while a resize is applied, a "covered" flag tells them to draw nothing, so they never write over what is on top.

## Not done

There is no main-loop redraw of the stack any more: it rides on page writes (`_tui._flush`, the standalone `_tui._draw_pane` / `_tui._draw_widget`) and is drawn alone only when a function layer itself changes (`_tui_layer.draw_all`). A drag repaints the whole page; a damage rectangle would cut that cost.
