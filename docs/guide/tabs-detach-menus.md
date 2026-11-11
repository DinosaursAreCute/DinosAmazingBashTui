# Tabs you can detach, and right-click menus

A tab strip on top, a **deck** of panes below with one open at a time, and any tab can float away as a window. The Chatty app (`DinosAmazingScripts/DinosChattyChat`) is the worked example.

## 1. Tab strip and deck

`<tabs>` only calls your action when a header is clicked. Showing the content is up to you. Collapsing the other panes to nothing keeps every tab's widgets alive.

```xml
<pane id="tabs_header" height="clamp(1,1,1)" border="none"/>
<pane id="deck" height="1fr" split="v" border="none">
  <pane id="tab_chat" title="Chat" height="1fr" split="v" border="single"
        collapsible="true" collapse_to="0">
    ...
  </pane>
  <pane id="tab_speed" title="Speed" height="1fr" split="v" border="single"
        collapsible="true" collapsed="true" collapse_to="0"
        detachable="true" on_detach="on_detach" on_dock="on_dock">
    ...
  </pane>
</pane>

<tabs id="tabs" header_pane="tabs_header" content_pane="deck" style="compact">
  <tab id="t_chat"  text="Chat"  action="on_tab" default="true"/>
  <tab id="t_speed" text="Speed" action="on_tab"/>
</tabs>
```

```bash
declare -A TAB_PANE=([t_chat]=tab_chat [t_speed]=tab_speed)
on_tab() {                       # $1 = the clicked header's id
  local id
  for id in "${!TAB_PANE[@]}"; do
    if [[ $id == "$1" ]]; then tui.collapse "${TAB_PANE[$id]}" off; else tui.collapse "${TAB_PANE[$id]}" on; fi
  done
}
```

## 2. Detach and dock

A pane with `detachable="true"` in an `h` or `v` split gets a **⇱** button. A click floats it as a window with **⇲** (dock back), **↺** (reset) and **✕** (close). From code: `tui.layer.detach PANE` and `tui.layer.dock PANE`.

`on_detach` and `on_dock` receive the pane id. Use them to keep the page coherent:

```bash
on_detach() { DETACHED[$1]=1; tui.set_label t_speed "Speed ⧉"; show_tab tab_chat; }   # the deck needs another tab
on_dock()   { unset "DETACHED[$1]"; tui.set_label t_speed "Speed"; show_tab "$1"; }
```

When someone clicks the header of a detached tab, raise its window instead: `tui.layer.raise PANE`.

## 3. Right-click menu

Bind the right button, read where it happened, fill a `<contextmenu>` and show it at the pointer.

```xml
<contextmenu id="menu" x="0" y="0" width="30" height="8" open="false" border="single">
  <button id="m0" text="" action="on_menu" align="left"/>
  <button id="m1" text="" action="on_menu" align="left"/>
</contextmenu>
```

```bash
tui.bind mouse:right on_right --always
on_right() {
  local x y widget
  tui.get.event                                # sets TUI_EVENT_X, _Y, _PANE, _WIDGET
  x=$TUI_EVENT_X y=$TUI_EVENT_Y widget=$TUI_EVENT_WIDGET
  tui.set_label m0 " Detach"                   # the items depend on what was clicked
  tui.set_label m1 ""
  tui.layer.size menu 3 30                     # HEIGHT WIDTH
  tui.layer.show menu                          # show first ...
  tui.layer.move menu "$y" "$x"                # ... then move: ROW COL
}
```

`TUI_EVENT_WIDGET` is the clicked tab header's id (for example `t_speed`), so one handler can build a different menu for a tab, the transcript or a list. The menu closes on an outside click or Esc. A click on a button runs its action.

## Quirks

- **`tui.layer.move` takes ROW then COL**, the opposite of `x`/`y` in markup, and only works **while the layer is visible**: show it first.
- **An empty widget id is an error as an associative-array key.** A click on a gap in the header sets no widget, so write `[[ -n $widget && -n ${MAP[$widget]:-} ]]`.
- **Each element goes on its own line.** A child written on the same line as its parent's opening tag has its attributes merged with the parent's, and the page is refused ("attribute 'id' given twice").
- **A detached pane draws widgets, not pane text.** Text set with `tui.output` or `tui.set_text`, and the output of `tui.exec`, vanishes from a floating window (the framework's own detachable log panes are made of labels). Build content that may be detached from labels. Two consequences: a log that streams into a pane (a `tui.exec` console) should not be `detachable`, and a multi-line chart becomes one label per row.
- **Labels measure colour escapes as visible text.** A coloured chart line put into a label made the pane report `min space = 467x12` and draw nothing. Strip the escapes (`${line//$'\e'\[*([0-9;])m/}` with `shopt -s extglob`) before filling labels.
- **The active tab is the focused header button.** Switching tabs from a key does not move focus there, so the strip shows no active tab. Mark the open one in its label instead (`▸ Speed`).
- **Do not use `alt+d`, `alt+c`, `alt+x`, `alt+v`, `alt+z` or `alt+y` for app-wide keys.** A text input uses them (delete word, copy, cut, paste, undo, redo) and a binding without `--always` loses to it. `alt+w` and `alt+t` were free.
- After a detach the framework floats the window at the deck's exact size and place, so it hardly looks detached. Resize and move it in `on_detach` (`tui.layer.size PANE 18 70`, `tui.layer.move PANE 8 44`).
- Factory widgets (`tui.factory.*`) of a pane that gets detached are lost with the old pane. Build them again in `on_detach`.
- A pane that contains panes needs `split=`.
- A page with `<tabs>` cannot be refreshed in place (`tui.page.refresh` rebuilds it).
- Hide the collapse buttons of the deck panes with `collapse_class` (see [Collapsible panes](collapsible-panes.md)).

## Performance

Measured in Chatty, per tab switch: Speed about 35 ms, Chat about 42 ms, Server about 53 ms. The Settings tab took 94 ms the first time (it builds a form) and about 41 ms afterwards, because the form is built once per agent and only its values are refreshed. The right-click menu is built when it is opened and costs nothing otherwise.
