# Pages: the markup format

A page is an XML file that says what is on the screen: panes, the widgets in them, which function a button calls, which class styles what. The loader is pure bash. This is the reference for the format; for a first page read the tutorial [Writing Your First App](../tutorials/writing-your-first-app.md).

```xml
<tui on_visit="home_visit">
  <script src="home_callbacks.sh"/>
  <theme src="theme.css"/>

  <pane id="root" split="v" border="none">
    <pane id="head" height="3" title="Tasks" class="panel" hpad="1">
      <label id="lbl_title" text="My tasks" class="brand"/>
    </pane>
    <pane id="body" split="h" border="none">
      <pane id="add" width="38%" title="New task" class="panel" hpad="1">
        <input id="inp_task" label="Task:" label_width="7" submit="on_add"/>
        <button id="btn_add" text="[ Add ]" action="on_add" align="fill"/>
      </pane>
      <pane id="tasks" title="Your tasks" class="panel" hpad="1">
        <list id="lst_tasks"/>
      </pane>
    </pane>
  </pane>
</tui>
```

Run a page with `tui.start_cached "config/home.xml"` (or try the bundled demo: `dabt --demo`). `tui.start_cached` is the one to use: it loads every page of the app once behind the logo screen and serves later page switches from that cache, so switching pages takes a fraction of a parse. `tui.start` skips the cache; use it only if your app rewrites its own page files while it runs.

## The rules of the format

- Tags are `<tag attr="value"/>` or `<tag attr="value">…</tag>`. Values can use `"double"` or `'single'` quotes. A tag may span several lines, and comments (`<!-- … -->`) may stand anywhere.
- `&lt; &gt; &amp; &quot; &apos;` work inside values. A `>` inside a quoted value does not end the tag.
- The root is `<tui>`. Everything on the page is inside it.
- **Every pane and every widget gets an `id`.** Bash finds things by id, addons and `tui.page.refresh` match by id, and error messages quote it. Use a prefix by kind (`lbl_`, `inp_`, `btn_`, `lst_`), it keeps ids unique and readable.
- Pages are checked when the app starts. A mistake is reported with file, line and column (`share/demo/x.xml line 19 col 18: widget id 'foot' is already used at line 17`) and the start is refused; `--ignore-invalid-xml` starts anyway. The same schema is available to your editor: [share/tui.xsd](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/share/tui.xsd) gives completion and validation in editors that read XSD (reference it from the root tag: `<tui xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="tui.xsd">`).

## Panes: the layout

A pane is a rectangle. It either **holds widgets** or **is split into child panes** - never both. `split` says how the children share the space:

| `split` | children are |
|---|---|
| `h` | side by side (left to right) |
| `v` | stacked (top to bottom) |
| `grid` | cells of a grid, see [Grid layouts](grid-layouts-and-tabs.md) |
| `fixed` | rows of fixed-size cells that wrap, see [Grid layouts](grid-layouts-and-tabs.md) |

**Sizes.** A child pane takes its size along the parent's split axis from `width` (in an `h` split) or `height` (in a `v` split). The value is a *size token*:

| Token | Meaning |
|---|---|
| `24` | 24 cells |
| `30%` | 30 % of the available space |
| `2fr` | 2 shares of what is left after the fixed, percent and `auto` children (`fill` = `1fr`) |
| `clamp(20,30%,50)` | prefer 30 %, but never below 20 or above 50 cells (each part may be any token) |

`weight="3"` is the same as `3fr` and is fine for simple splits. Space that `max_width`/`max_height` leaves over goes to the other children; `min_width`/`min_height` are honoured, and a pane that still does not fit shows a `min space = WxH` notice instead of its content. `gap="1"` on a split pane leaves cells between its children. `hpad`/`vpad` keep the content away from the border; `border` is `single`, `double`, `heavy` or `none`; `title` goes into the top border.

Panes can be given `row`, `col`, `group`, `spacer` and `divider` instead of `pane` when that reads better: `row` is a pane with `split="h"`, `col` one with `split="v"`, `divider` one with a border, and `spacer` an empty pane that takes up space.

```xml
<col id="root">
  <pane id="head" height="3" title="Status"/>
  <row id="body">
    <pane id="nav"  width="22" title="Menu"/>
    <spacer id="gap" width="1"/>
    <pane id="main" width="1fr" title="Work"/>
  </row>
</col>
```

## Widgets: what is in a pane

**Write a widget inside the pane it belongs to.** It is placed on the next free line of that pane, in document order, so there is nothing to number:

```xml
<pane id="form" title="Login" hpad="1">
  <input    id="inp_user" label="User:" label_width="7" submit="on_login"/>
  <password id="inp_pass" label="Pass:" label_width="7" submit="on_login"/>
  <button   id="btn_login" text="[ Log in ]" action="on_login" align="fill"/>
</pane>
```

`row="N"` on a widget puts it on line N of its pane instead (lines count from 0); use it to leave a gap. The widgets after it follow document order again, from their own position. If a widget has to live in a pane it is not nested in, `pane="other_id"` places it there; it ties that pane to a full page rebuild (see [Changing a page that is on screen](#changing-a-page-that-is-on-screen)), so reach for it rarely.

| Tag | Shows | Main attributes |
|---|---|---|
| `label` | text | `text` |
| `button` | a button | `text`, `action="fn"` (called as `fn ID`) or `page="other.xml"` |
| `input` | one-line text field | `label`, `label_width`, `label_align`, `placeholder`, `submit="fn"`, `retain_input_on_submit`, `sticky` |
| `checkbox` | on/off | `label`, `checked`, `action="fn"` (called as `fn ID VALUE`) |
| `password`, `textarea`, `select`, `list`, `table`, `progress` | see [Widgets](widgets.md) | `on_change`, `items`, `rows`, `columns`, `data`, `value` |

Attributes every widget has:

| Attribute | |
|---|---|
| `class` | the style (see [Styling](#styling)) |
| `align`, `valign` | text position in its row: `left`, `center`, `right`, `fill` (paint the whole row) / `top`, `middle`, `bottom` |
| `width`, `height` | a size token for the widget itself |
| `min_width`, `max_width`, `min_height`, `max_height` | limits |
| `expand` | `x`, `y` or `both`: fill the pane's content area (lists, tables and text areas already fill it vertically) |
| `padding`, `hpad`, `vpad` | space around the widget's text |
| `focusable`, `tabbable`, `tab_order`, `focus_group`, `focus_nav`, `focus_wrap`, `focus_next`, `focus_prev`, `autofocus` | keyboard focus, see [Input and key bindings](input-bindings.md) |
| `hit_pad`, `hitbox` | a bigger area that counts as a mouse hit |

**Alignment** resolves from the widget's own `align` to its pane's `align` to the built-in default (centred for buttons, left/top for everything else). `valign` reinterprets a widget's row as an offset from the chosen anchor: `top` counts down, `bottom` counts up, `middle` counts from the centre. For an input, `label_width` reserves a fixed box for the label and `label_align` positions the text inside it; the field fills the rest.

```xml
<input id="inp_name" label="Name:" label_width="12" label_align="right"/>
```

## Behaviour

| Tag / attribute | Does |
|---|---|
| `<script src="x.sh"/>` | sources a bash file (your callbacks). The path is relative to the file the tag is in. It is sourced on every page load. |
| `<tui on_visit="fn">` | calls `fn` each time the page opens, once everything is built. Initialise things here. |
| `action`, `submit`, `on_change` | the functions called by a widget, see [Callbacks](callbacks-and-viewports.md) |
| `<button page="other.xml"/>` | goes to another page (`tui.goto`). `tui.action.back` returns. |
| `<bind key="ctrl+e" action="fn" desc="Export"/>` | a key for this page |
| `<footer items="@tui.action.quit"/>` | the key hints in the bottom row |
| `<theme src="theme.css"/>` | the stylesheet |

## Reusing markup

Anything you would otherwise copy between pages is written once and placed. All of the tags below are expanded when the page is loaded, so the built page holds only ordinary panes and widgets and reuse costs nothing while the app runs.

### Templates

A template is a named piece of markup with parameters. It is never drawn by itself; each `<use>` makes a copy. The usual home for the parts every page shares (header, menu) is one file, `_templates.xml`, that each page includes - the demo does exactly this:

```xml
<!-- _templates.xml -->
<template name="dabt_header">
  <footer/>
  <pane id="dabt_hdr" height="5" title="My App"/>
</template>
<template name="card" title="Untitled">
  <pane id="box" title="{{@title}}" border="single">
    <slot/>
  </pane>
</template>

<!-- any page -->
<tui>
  <include src="_templates.xml"/>
  <pane id="root" split="v">
    <use template="dabt_header"/>
    <use template="card" id="a" title="Disk"><label id="msg" text="82 % free"/></use>
    <use template="card" id="b" title="Memory"/>
  </pane>
</tui>
```

- `{{@title}}` is replaced by the `title` given on `<use>`, or by the default written on `<template>`. Any attribute can be a parameter.
- A `<use>` with an `id` puts that id and an underscore in front of every id in its copy (`a_box`, `b_box`), so several uses can coexist. Without an `id` the ids stay as written.
- `<slot/>` marks where the content of the `<use>` goes. Name it (`<slot name="body"/>`) and fill it with `<fill slot="body">…</fill>` when a template has several places. Content inside the `<slot>` is the default.
- A template may `<use>` another template. One that ends up using itself is reported as an error and the `<use>` is dropped.
- `<include src="f.xml" name="value"/>` splices another file in at parse time; extra attributes are parameters for the `{{@name}}` in it.

### Components

A component is a template kept in its own file and used as a tag:

```xml
<component name="card" src="card.xml"/>
<card title="Disk"><label id="msg" text="82 % free"/></card>
```

`card.xml` holds the template body. The validator accepts `<card>` after the `<component>` line on that page.

### Loops and conditions

```xml
<pane id="side">
  <for each="alpha beta gamma" as="name" index="i">
    <button id="b_{{@name}}" text="{{@name}}" action="on_pick"/>
  </for>
</pane>
<for count="3" index="i"> … </for>

<if test="{{@mode}}==compact"> … <else> … </else></if>
```

- `<for each="…">` repeats its content once per word; `{{@name}}` (named by `as`, default `item`) is the word and `{{@i}}` (named by `index`) counts from 0. `count="N"` repeats N times.
- `<if test="…">` keeps its content when the test holds, otherwise the content of `<else>`. A test is `A==B`, `A!=B`, or one value that is false when empty, `false` or `0`. Only one branch survives, but the page is checked before that, so the two branches must not use the same widget id.
- Loops and conditions run once when the page loads, on values written in the file, passed as parameters, or set by an addon. For values that change while the app runs, see the runtime values below.

See it live: the Conditionals tab of the Compose demo page (`dabt --demo`, `alt+-`; source `share/demo/compose.xml`).

### Addons

An addon changes a page without editing its file. A plugin or an app extension uses one to add a button, hide a pane or retitle something; so does the app itself, for content that depends on settings (the demo's *Generated* page).

```xml
<!-- TUI_APP_CONF/addons/stats.xml -->
<addon id="stats" target="home.xml" priority="10">
  <append ref="#sidebar"><button id="go" text="Stats" page="stats.xml"/></append>
  <set ref="#lbl_title" attr="text" value="Welcome back"/>
  <remove ref=".legacy"/>
</addon>
```

| Tag | Does |
|---|---|
| `<append ref>` / `<prepend ref>` | add its content as the last / first child of the match |
| `<before ref>` / `<after ref>` | add its content next to the match |
| `<replace ref>` | put its content where the match was |
| `<remove ref>` | delete every match |
| `<set ref attr value>` | set an attribute on every match |
| `<wrap ref type id>` | put the match inside a new `type` (default `pane`) |

- `ref` is a selector: `#id`, `.class`, `tag`, combined as `tag#id.class`; a space means "somewhere below" and `>` "directly below". Add, replace and wrap use the first match; remove and set use all of them. A `ref` that matches nothing is reported.
- `target` is a page file name or `*` for every page. A lower `priority` runs first, so the higher number has the last word.
- Added content is copied with every id starting `stats_` (the addon id). `prefix="false"` on `<addon>` keeps ids as written.
- Addons are read from `TUI_APP_CONF/addons/*.xml` and from every directory given to [`tui.addon.dir`](../api/core/tui.addon.dir.md), before templates and loops are expanded, so addon content can use them and an addon can set the `count` of a `<for>`. An empty file is a switched-off addon.
- Addon files and their folder count as part of the page for the cache: adding, removing or editing one makes the next load rebuild it.

## Changing a page that is on screen

Everything above is decided when the page loads. To change a page that is already showing (a switched addon, a generated list), call [`tui.page.refresh`](../api/core/tui.page.refresh.md):

```bash
cp "$APP_DIR/addons/banner.xml" "$TUI_APP_CONF/addons/banner.xml"   # switch an addon on
: >"$TUI_APP_CONF/addons/old.xml"                                   # switch one off
tui.page.refresh                                                    # the screen follows
```

A refresh does not parse anything. Every page remembers the tree it was built from; the refresh applies the addons to that tree, compares the result with what is on screen pane by pane, and rebuilds only the panes whose content changed, together with everything below them. It stays within the 100 ms a page switch has, and what you typed or ticked in the panes that did not change stays as it is. See [How pages are built and refreshed](../design/pages-templates-addons-refresh.md) for what it does and when it gives up.

To keep a change refreshable:

- give every pane an addon or a refresh may change an `id`;
- write widgets inside their pane, not elsewhere with `pane="…"`;
- keep `<tabs>` out of the part that changes (a change in a tab set rebuilds the whole page, in the background, with a spinner).

Work that is slow in itself belongs to [`tui.job.run`](../api/core/tui.job.run.md): it runs in a separate process, shows a spinner when it takes longer than 100 ms, and hands the result to a function that puts it on screen in one go. See [Slow work](callbacks-and-viewports.md#4-slow-work-keep-the-interface-running).

## Grid layouts and tabs

`split="grid"` and `split="fixed"` lay out several elements side by side without one hand-written pane per cell; `<tabs>` is a row of header buttons that swap a content pane. Both have their own page: [Grid layouts and tabs](grid-layouts-and-tabs.md).

## Fully dynamic content

When the shape of a page depends on data that only exists at run time (one row per file found, one pane per connected device), there are three tools, from cheapest to most flexible:

1. **A list or table widget.** One widget, any number of rows: `tui.list.set ID ITEM...`, `tui.table.set`. Use this whenever the thing is a list of lines.
2. **Generate the markup.** Write an addon that sets the `count` of a `<for>` or the parameters of a `<use>`, then `tui.page.refresh`. The structure stays declarative and only the changed pane is rebuilt.
3. **`tui.factory.*`.** Create widgets from a callback under a namespace and drop them again with `tui.factory.clear NAMESPACE`. Use it for panes and widgets that are created and destroyed from code.

Tabs known only at run time are built from `on_visit` with `tui.tabs.add` and `tui.tabs.build`; see [Grid layouts and tabs](grid-layouts-and-tabs.md#dynamic-tabs).

## Styling

`<theme src="theme.css"/>` loads a stylesheet; `class="name"` applies a class:

```css
.danger_button        { fg: white; bg: #b00020; mods: bold; }
.danger_button:focus  { fg: white; bg: #ff3333; mods: bold; }
.danger_button:hover  { bg: #d4002a; }
```

`fg`/`bg` take a name from `colors.sh` or `#RRGGBB`; `mods` is a space-separated list (`bold underline`). A widget or pane with no class takes the look of the pane it is in, so you only style what should stand out.

| Pseudo-state | Applies to |
|---|---|
| `:focus` | a widget while it has keyboard focus; a pane's border while a widget in it does |
| `:hover` | a widget while the mouse is over it (a class without `:hover` shows no hover) |
| `:checked`, `:unchecked` | a checkbox by its value; `:focus` and `:hover` win while they apply |
| `:border`, `:title` | a pane's border ring and title |

Prefer a class over anything inline: classes are resolved once and cached, and a theme switch (`tui.theme.set`) restyles every page, cached ones included.

## Values that change while the app runs

Widgets hold their values; read and write them from bash, not from the markup:

```bash
on_save() {
    local name
    tui.get inp_name name          # into a variable: no subshell
    tui.update lbl_status "Saved $name"
}
```

`tui.get ID VAR` stores the value in `VAR`; `$(tui.get ID)` starts a subshell on every call, which matters in key and mouse handlers. `tui.update ID VALUE` changes a value and redraws the widget, `tui.set_label ID TEXT` changes a caption, `tui.set_text PANE TEXT` and `tui.output PANE TEXT` fill a pane.

`text` on a label or button may embed `${command}`, run each time the widget is drawn:

```xml
<label id="lbl_rule" text="${terminal_renderer.sh divider 'Section'}"/>
```

Every redraw starts a process for it, so it suits static text like a divider. For anything that changes, call `tui.update`.

## Scrolling

`scroll="v"`, `"h"` or `"both"` on a pane makes it a scrolling viewport. Such a pane must be a leaf (no child panes); fill it with `tui.output PANE TEXT` or `tui.output_append`, or with widgets (see [Scrolling widgets](#scrolling-widgets)). Wheel, drag on the scrollbar (the bar is drawn one cell wide, and reacts three cells wide) and the page keys scroll it. Details: [Callbacks and viewports](callbacks-and-viewports.md#3-building-scrolling-viewports).

## Scrolling widgets

A pane with `scroll="v"`, `"h"` or `"both"` can also hold widgets. The content height comes from the arranged widgets; scroll follows the mouse wheel and the page keys, and Tab moves it along with the focus. The innermost widget under the pointer gets the scroll event first. When Tab focuses a widget, it is scrolled into view automatically (unless `scroll_into_view="false"` on the pane). Mark a row with `pin="top"` to keep it stuck to the first viewport row (a pinned header):

```xml
<pane id="form" weight="85" border="single" scroll="v" hpad="1">
  <label id="hdr" pin="top" text="Account details" class="brand"/>
  <input id="inp_email"    label="Email:"        label_width="15" submit="on_save"/>
  <input id="inp_phone"    label="Phone:"        label_width="15" submit="on_save"/>
  <checkbox id="chk_news" label="Newsletter"    checked="true" action="on_toggle"/>
</pane>
```

Scroll programmatically with `tui.scroll.to TARGET [top|center|bottom]` where `TARGET` is a widget or pane id (it scrolls the nearest ancestor pane that can scroll to show the target).

## Content fit

Besides explicit `min_width`/`min_height`, a pane's content is checked on every full render: the furthest widget line and the longest widget text, or for an output pane the line count and widest line. A pane that is too small for its own content shows the same `min space` notice. A pane with `scroll` is exempt; `strict_fit="false"` opts a pane out.

## Several pages

Each file is a page with its own `<tui>`. `<button page="other.xml"/>` or `tui.goto other.xml` switches to it; the UI is reset, the page loaded (from the cache when possible) and drawn in one frame. Focus stays on the same widget id when a page is reloaded. `tui.action.back` returns to the previous page.

## Shells

A shell is the chrome that stays while the user moves between pages: a header, a nav, a footer. It is a markup file with exactly one `<outlet/>`, the pane the page content goes into:

```xml
<!-- _shell.xml -->
<tui>
  <pane id="root" split="v">
    <pane id="nav" border="single" weight="1">
      <button id="go_a" text="A" page="a.xml"/>
      <button id="go_b" text="B" page="b.xml"/>
    </pane>
    <outlet id="body" weight="5"/>
  </pane>
</tui>

<!-- a.xml -->
<tui shell="_shell.xml">
  <pane id="a_main" border="single"> ... </pane>
</tui>
```

The page's top-level panes are built inside the outlet (`id` defaults to `outlet`; `split`, `weight`, `border` and `class` work as on a pane). `shell` is resolved against the page's folder.

- **`tui.goto` between pages of one shell** keeps every shell pane and widget: focus on a shell widget, typed values, scroll positions, timers, watches and binds the shell started. Only what the previous page built is removed. A page's `<script>`, `<theme>`, `<bind>` and `<footer>` belong to the page and go with it.
- **A page of another shell, or one without a shell,** is a full `tui.goto`: the UI is reset and built from scratch.
- **Tab order** follows document order of shell and page together: the page's widgets sit where the outlet stands.
- **Ids** are shared between shell and page; the validator reports a page id that repeats a shell id, the outlet's included. Give the outlet a name pages will not pick (`page_outlet`, not `main`).
- **`tui.page.refresh`** works on a page of a shell like on any page.
- **Cache.** A page of a shell is cached as the difference it makes on top of the shell, so replaying it never touches shell state. Switching inside a shell is faster than a full `tui.goto`: `tools/bench/run.sh` compares `goto_pair_shell` with `goto_pair_plain`.
- A shell cannot name another shell, and a page that names a shell cannot contain an `<outlet/>`. `tui.shell.file` tells a callback which shell is live.

## Tools

| | |
|---|---|
| `dabt --demo` | the bundled demo; its pages are the best examples of everything above (templates, conditions and addons: the Compose page, `alt+-`) |
| `share/tui.xsd` | schema for editor completion |
| `tools/frame.sh PAGE [COLSxROWS]` | renders a page to text without a terminal (`--sgr` keeps the styles) |
| `tools/profiler/profile.sh` | times page switches, input and the addon scenarios against the 100 ms budget |
