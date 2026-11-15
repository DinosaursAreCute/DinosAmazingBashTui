# Components and templates

Markup that appears more than once (a card, a form row, a header) is written once and used many times. This page explains how to build such pieces. For a first look see [Reusing markup](markup.md#reusing-markup).

{% raw %}All of this happens **before the page is built**, when the file is loaded. A `<use>` is replaced by a copy of the template, the `{{@name}}` parameters are filled in, and only plain tags (`pane`, `label`, `button`, …) reach the builder. A component is therefore not a live object: it has no state of its own and cannot be changed afterwards. What changes while the app runs are the widgets inside it, read and written by id (`tui.set`, `tui.get.value`).{% endraw %}

## Which one do I use?

| You want | Use |
|---|---|
| a piece of markup reused on one page, or shared through one file of templates | `<template>` + `<use>` |
| the same, but each piece in its own file and written like a tag (`<card …/>`) | `<component>` |
| to paste a file in once, as it is | `<include src="…"/>` |
| N copies of something, from a list of words or a count | `<for>` ([Loops](markup.md#loops-and-conditions)) |

A component is exactly a template that lives in its own file. Everything below applies to both.

## 1. A template

```xml
<template name="card" title="Untitled" accent="info">
{% raw %}  <pane id="box" title="{{@title}}" border="single" class="{{@accent}}_panel">{% endraw %}
{% raw %}    <label id="msg" text="{{@title}}"/>{% endraw %}
    <slot/>
  </pane>
</template>

<use template="card" id="disk" title="Disk"><label id="free" text="82 % free"/></use>
<use template="card" id="mem" accent="warn"/>
```

- `name` is how the template is used. A template is never drawn where it is written, so it can sit anywhere on the page or in an included file.
- **Parameters are the other attributes of `<template>`.** `title="Untitled"` is a parameter called `title` with the default `Untitled`. A `<use>` overrides a default by writing the same attribute. A parameter without a default is simply an attribute you write on every use.
{% raw %}- `{{@title}}` is replaced by the value, in **attribute values** anywhere inside the template (including `id`, `class`, `text`, `action`). It is not replaced in the text between tags.{% endraw %}
{% raw %}- A parameter nobody gave a value stays as the literal text `{{@name}}`. Give every parameter a default (even an empty one, `suffix=""`), or the page shows it.{% endraw %}
- `name`, `src`, `template` and `id` are reserved: they are never parameters.

## 2. A component

A component keeps the template in its own file and is used as a tag named after it:

```xml
<!-- page.xml -->
<tui>
  <component name="card" src="card.xml" title="Untitled" accent="info"/>
  <pane id="root" split="v">
    <card id="disk" title="Disk"><label id="free" text="82 % free"/></card>
    <card id="mem" accent="warn"/>
  </pane>
</tui>
```

```xml
<!-- card.xml: only the body, no <template> tag around it -->
{% raw %}<pane id="box" title="{{@title}}" border="single" class="{{@accent}}_panel">{% endraw %}
{% raw %}  <label id="msg" text="{{@title}}"/>{% endraw %}
  <slot/>
</pane>
```

- **The file holds the body only.** Do not wrap it in `<template>`: the template tag would become part of the body and nothing would be drawn.
- **The defaults go on the `<component>` tag**, not in the file. They are the parameters of the component.
- `src` is relative to the file that contains the `<component>` tag.
- The body may have several top-level elements; the use is replaced by all of them.
- A component can be declared once in a shared file (`_components.xml`) that every page includes, so the pages only write `<card …/>`.
- The validator knows `<card>` after the `<component>` line of that page.

## 3. Ids: how copies stay apart

A widget or pane id has to be unique on a page. A `<use>` (or component tag) with an `id` puts that id and an underscore in front of **every id inside its copy**:

| in the template | `<card id="disk">` | `<card id="mem">` |
|---|---|---|
| `box` | `disk_box` | `mem_box` |
| `msg` | `disk_msg` | `mem_msg` |

These are the ids your code uses: `tui.set disk_msg "…"`. Uses nest, and the prefixes add up: a `<use id="r1">` inside a template used with `id="c"` gives `c_r1_l`.

Without an `id` on the use, the ids stay as written, which is only safe for a single use.

Three rules follow from that:

1. **Nest widgets in their pane, do not write `pane="…"`.** The prefix is put on the ids, but a `pane="box"` attribute is not rewritten, so the widget would point at a pane that no longer exists under that name. A widget nested in its pane finds the right pane by itself.
{% raw %}2. **Content you put into a slot keeps the ids you wrote.** It is moved into the copy, not copied, so it is not prefixed. Inside a `<for>` that would give every round the same id. Make them unique with the loop variable: `<label id="body_{{@n}}" …/>`.{% endraw %}
{% raw %}3. **An id given to a use may itself be a parameter value**: `id="card_{{@n}}"` inside a `<for>` works, because the loop is expanded first.{% endraw %}

## 4. Slots: where the caller's content goes

`<slot/>` marks where the content of the `<use>` goes. The loose children of the use are put there.

For several places, name them:

```xml
<template name="panel" title="">
{% raw %}  <pane id="p" title="{{@title}}" border="single">{% endraw %}
    <slot name="head"><label id="h" text="(no heading)"/></slot>
    <slot/>
  </pane>
</template>

<use template="panel" id="a" title="Users">
  <fill slot="head"><label id="hh" text="3 online"/></fill>
  <label id="body" text="Anna, Ben, Chris"/>
</use>
```

- `<fill slot="head">…</fill>` supplies the named slot; everything else goes to the unnamed `<slot/>`.
- What is written inside a `<slot>` is its default. It is used when the caller supplies nothing for that slot (above: `a_h` would exist only without the `<fill>`).

## 5. Conditions and loops inside a template

Loops and conditions are expanded with the parameters of the use, so a template can change shape:

```xml
<template name="field" label="" hint="" required="false">
  <pane id="f" split="h" height="1">
{% raw %}    <label id="l" text="{{@label}}" width="14"/>{% endraw %}
{% raw %}    <input id="i" placeholder="{{@hint}}"/>{% endraw %}
{% raw %}    <if test="{{@required}}==true"><label id="star" text="*" width="1"/></if>{% endraw %}
  </pane>
</template>

<for each="name email city" as="what">
{% raw %}  <use template="field" id="f_{{@what}}" label="{{@what}}" required="true"/>{% endraw %}
</for>
```

{% raw %}- A test such as `{{@required}}==true` is settled when the use is expanded, and only the branch that holds is copied. The validator still checks both branches, so they must not use the same widget id.{% endraw %}
{% raw %}- A template can `<use>` another one, and parameters can be passed on (`label="{{@title}}-one"`). A template that ends up using itself is an error and the use is dropped.{% endraw %}

## 6. A complete example

A stat card shown for each disk, with a heading slot:

```xml
<!-- _components.xml -->
<component name="stat" src="stat.xml" title="" value="-" unit="" tone="info"/>
```

```xml
<!-- stat.xml -->
{% raw %}<pane id="card" title="{{@title}}" border="single" class="{{@tone}}_panel" height="5">{% endraw %}
{% raw %}  <label id="value" text="{{@value}}{{@unit}}" align="center"/>{% endraw %}
  <slot/>
</pane>
```

```xml
<!-- page.xml -->
<tui>
  <include src="_components.xml"/>
  <pane id="root" split="h">
    <stat id="cpu" title="CPU" value="12" unit=" %"/>
    <stat id="mem" title="Memory" value="3.4" unit=" GB" tone="warn">
      <label id="mem_note" text="swap in use"/>
    </stat>
  </pane>
</tui>
```

```bash
on_tick() { tui.set cpu_value "$(read_cpu) %"; }   # the ids are cpu_value and mem_value
```

## Mistakes and how they show

| What you see | Cause |
|---|---|
| nothing is drawn where the component is | the component file is wrapped in `<template>`; give the body only |
{% raw %}| the page shows `{{@name}}` | a parameter has no default and the use did not set it |{% endraw %}
| "unknown template 'x'" | the `<component>` or `<template>` is not on this page: add the `<include>` of the file that declares it |
| "template recursion: a -> b -> a" | a template uses itself, directly or through others |
| a widget lands in the wrong pane or the page is refused for a duplicate id | `pane="…"` inside the template, or slot content with the same id in every round of a loop |
| a parameter has no effect | it was written in element text; only attribute values are substituted |

The errors are reported as `file:line: message` when the page loads, so they point at the line of the use.

## See also

- [Reusing markup](markup.md#reusing-markup): the short reference.
- [Loops and conditions](markup.md#loops-and-conditions) and [Addons](markup.md#addons): change the number of copies or their parameters from outside the page.
