# Declarative TUI markup

The project includes a lightweight HTML/XML-like config format for building TUIs
declaratively instead of hand-calling `tui.*` functions. The loader
(`bin/tui_markup.sh`) is pure **bash + POSIX utilities only** — no python, perl,
or XML libraries.

It is sourced automatically by `tui.sh`, so `tui.load` and `tui.goto` are
available anywhere `tui.sh` is sourced.

## Editor autocompletion

[config/tui.xsd](../config/tui.xsd) describes the tag/attribute set for
editors that support XSD-based XML autocompletion and validation (e.g. the
Red Hat XML extension in VS Code). It's purely an editing aid — the loader
doesn't read or enforce it. Reference it from a page's root tag:

```xml
<tui xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="tui.xsd">
```

## Example

```bash
source bin/tui.sh
tui.start "config/home.xml"
```

`tui.start` handles the full lifecycle — `tui.init`, `tui.load`, `tui.run`, and
guaranteed terminal cleanup on exit/error — so a config-driven TUI only needs
to define its markup file. Use `tui.init` + `tui.load` + `tui.run` directly
only if you need to run custom setup between those steps.

Or run the bundled demo:

```bash
bin/markup_demo.sh
```

## Format rules

- One tag per line. Attributes are `name="value"` (double quotes only).
- Tags are either self-closing (`<pane .../>`) or open/close pairs (`<pane ...>` … `</pane>`).
- `<!-- comments -->` on their own line are ignored.

## Supported tags

- `<tui>` – root wrapper (ignored by the parser).
- `<script src="…"/>` – sources a bash file (callbacks) before its actions are used. Path resolves relative to the file it appears in.
- `<theme src="…"/>` – loads a CSS-like stylesheet (see [Styling](#styling) below). Path resolves relative to the file it appears in.
- `<include src="…"/>` – inlines another markup file at parse time (recursion-safe, cycle-detected). Useful for shared fragments like a nav bar.
- `<pane id="x" split="h|v" weight="N" title="…" border="…" align="left|center|right|fill" valign="top|middle|bottom" min_width="N" min_height="N" max_width="N" max_height="N" class="…">` – layout node. `split` on a non-self-closing `<pane>` makes it a container; its `<pane>` children become the `tui.hsplit`/`tui.vsplit` list, in document order, using each child's `weight` (default `1`).
- `<label id="x" pane="p" row="N" text="…" align="…" valign="…" min_width="N" max_width="N" class="…"/>`
- `<input id="x" pane="p" row="N" label="…" placeholder="…" submit="fn" align="…" valign="…" min_width="N" max_width="N" label_align="left|center|right" label_width="N" class="…"/>`
- `<button id="x" pane="p" row="N" text="…" action="fn" align="…" valign="…" min_width="N" max_width="N" class="…"/>`
- `<button id="x" pane="p" row="N" text="…" page="other.xml"/>` – navigates to another page instead of calling a bash function.

## Alignment

`align` (horizontal) and `valign` (vertical) control how a widget's text is
positioned within its row.

- Per **node** (pane): `align`/`valign` on a `<pane>` set the default for
  every widget placed in it (`tui.pane_align`, `tui.pane_valign`).
- Per **element**: `align`/`valign` on a `<label>`/`<input>`/`<button>`
  override that default for just that widget (`tui.align`, `tui.valign`).

Precedence: widget's own value > its pane's value > built-in default
(`center` horizontally for buttons, `left`/`top` for everything else). For
inputs, horizontal alignment only affects the unfocused display of the
value/placeholder — a focused field is always left-aligned with a scrolling
cursor.

`align="fill"` paints the *entire* row width with the element's fg/bg/mods
instead of only the text — e.g. a full-width colored button bar:

```xml
<button id="btn_delete" pane="form" row="5" text="[ Delete ]" action="on_delete" class="danger_button" align="fill"/>
```

`valign` reinterprets a widget's `row` as an offset from the chosen anchor
instead of an absolute line: `top` counts down from the pane's first content
row (the default, unchanged behavior), `bottom` counts up from the last row,
and `middle` offsets from the vertical center.

### Aligning a widget's sub-components (input label vs. field)

An `<input>` is really two components — its label and its editable field.
Use `label_width` to reserve a fixed-width box for the label and `label_align`
to position the label text within that box; the field then fills the
remaining row width:

```xml
<input id="inp_name" pane="form" row="0" label="Name:" label_width="12" label_align="right"/>
```

## Minimum / maximum sizes

- `min_width`/`min_height` on a `<pane>`, and `min_width` on a widget, declare
  the smallest space something is allowed to render into. If the actual
  available space is smaller, a warning is shown in place of the normal
  content: `min space = WxH` for panes, `min space = N` for a widget's row.
- `max_width`/`max_height` on a `<pane>`, and `max_width` on a widget, cap how
  large it is allowed to grow — extra space is simply left blank.

These map to `tui.pane_minsize`/`tui.pane_maxsize` for panes and
`tui.minsize`/`tui.maxsize` for widgets.

## Styling

[bin/tui_style.sh](../bin/tui_style.sh) adds a CSS-like theme system, loaded
with `<theme src="theme.css"/>` (see [config/theme.css](../config/theme.css)):

```css
.danger_button        { fg: white; bg: #b00020; mods: bold; }
.danger_button:focus  { fg: white; bg: #ff3333; mods: bold; }
```

`fg`/`bg` accept a `colors.sh` name (e.g. `red`) or a `#RRGGBB` hex value;
`mods` is a space-separated list of `style.*` modifiers (e.g. `bold underline`).
`:focus`/`:border`/`:title` are optional pseudo-state variants — `:border` and
`:title` only make sense on a `<pane>` class.

Apply a class with `class="danger_button"` on any `<pane>`/`<label>`/`<input>`/`<button>`.
Under the hood this calls `tui.class ID CLASS`, which is just a shortcut for
`tui.style` (set fg/bg/mods for an id's normal/focus/border/title state
directly, bypassing the stylesheet).

## Runtime text expressions

`text`/`label` attributes on `<label>`/`<button>` may embed
`${command args…}` — resolved by running that shell command (with the
framework's `bin/` directory on `PATH`) and substituting its stdout, every
time the widget is redrawn:

```xml
<label id="lbl_rule" pane="output" row="0" text="${terminal_renderer.sh divider 'Section'}"/>
```

Because XML attributes are delimited with `"`, use single quotes for any
quoting *inside* the expression. The command should print a single line —
multi-line output will overflow the widget's one row. Content isn't
re-resolved automatically on a timer; call `tui.redraw` (an alias for
`tui.render`) after changing whatever state the expression depends on to
force a full repaint on demand.

## Multi-page TUIs

Each markup file is a self-contained page (its own `<tui>…</tui>`). A button's
`page` attribute (instead of `action`) wires up an internal handler that calls:

```bash
tui.goto "other.xml"
```

`tui.goto` clears all panes/widgets, resets to a full-screen root pane, loads
the target file (resolved relative to the *current* page's directory), and
re-renders — so linking between files works like anchors between HTML pages,
with no manual cleanup required.

See [config/home.xml](../config/home.xml) and [config/settings.xml](../config/settings.xml)
for a two-page example that also shares a nav bar via `<include src="_nav.xml"/>`
(see [config/_nav.xml](../config/_nav.xml)).

## Callback sourcing

`<script>` files are sourced as plain bash — `tui.sh` is already loaded by the
time they run, so they can call `tui.get`, `tui.update`, `tui.exec`, `tui.stop`,
etc. directly (see [config/demo_callbacks.sh](../config/demo_callbacks.sh)).
