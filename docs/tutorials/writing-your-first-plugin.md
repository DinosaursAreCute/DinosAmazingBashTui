<div align="center">

<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/logo-transparent.png" alt="D.A.B.T" width="420">

<h1><img src="img/plugin-title.svg" alt="Writing Your First Plugin" height="30"></h1>

**A step-by-step tutorial. Ten minutes, one file, no experience with terminal UIs needed.**

</div>

<h2 id="what-you-will-build"><img src="img/plugin-what.svg" alt="What you will build" height="30"></h2>

A **Stretch reminder**: every 30 minutes a message pops up telling you to stand up. It also adds commands to the command bar (`ctrl+p`), a keyboard shortcut (`alt+s`), and remembers how often you want to be reminded.

The best part: **it works in every DABT app** - the demo, the File Explorer, the app you wrote in [Writing Your First App](writing-your-first-app.md) - without touching any of them. That is what a plugin is.

The finished file is [`examples/plugins/stretch.plugin.sh`](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/examples/plugins/stretch.plugin.sh).

<h2 id="the-big-ideas"><img src="img/plugin-ideas.svg" alt="The big ideas" height="30"></h2>

**An app is a program; a plugin is an add-on for programs.** An app has its own screens. A plugin has none of its own - it *adds behaviour* to whichever DABT app is running: extra commands, keys, timers, reactions to events. Think of a browser extension.

**A plugin is one bash file.** Named `something.plugin.sh`. Comments at the top say what it is; bash functions below say what it does.

**A plugin costs nothing while it is off.** DABT only *reads* your file when someone switches the plugin on. Until then it is just a line in a list.

**Switching off cleans up after itself.** Everything a plugin registers - commands, keys, timers, hooks - is written down as it happens. When the plugin is turned off, DABT undoes all of it for you. You never write "un-register my command" code.

**Plugins are trusted code.** They run inside the app's shell with the same rights as you. That is why DABT can [scan a plugin](#step-9-scan-it) before you enable it, and why you should only install plugins you have read.

Vocabulary:

| Word | Meaning |
|---|---|
| **enable / disable** | switch the plugin on / off while the app runs |
| **command** | an entry in the `ctrl+p` command bar |
| **keybinding** | a key that calls a function |
| **timer** | a function DABT calls again and again on an interval |
| **hook** | a function DABT calls when something happens (page changed, window resized, app quitting) |

<h2 id="step-1-the-file"><img src="img/plugin-1.svg" alt="Step 1: The file" height="30"></h2>

Create **`stretch.plugin.sh`**. Start with only its "business card" - comments in the first lines:

```bash
# plugin: stretch
# title: Stretch reminder
# version: 1.0
# description: Reminds you to stand up and stretch every few minutes.
# author: you
# default: off
```

| Line | Means |
|---|---|
| `plugin:` | the plugin's **id**. Lowercase letters, digits and `_`. It names your functions in the next step. |
| `title`, `description`, `author`, `version` | shown in Settings > Plugins |
| `default: off` | it starts switched off; the user turns it on. (`on` = on for everyone the first time; after that, the user's choice is remembered.) |
| `requires: other_plugin` | *(optional)* enable that plugin first, disable it last |

<h2 id="step-2-on-enable"><img src="img/plugin-2.svg" alt="Step 2: On enable" height="30"></h2>

Add the most important function. DABT looks for one named **`plugin.<id>.on_enable`** and calls it when the plugin is switched on. This is where you *register* what the plugin adds:

```bash
plugin.stretch.on_enable() {
    STRETCH_COUNT=0 STRETCH_TICKS=0
    # (we will fill this in over the next steps)
}
```

The name follows from your id: `# plugin: stretch` → `plugin.stretch.on_enable`. If they do not match, DABT never calls it and nothing happens.

<h2 id="step-3-a-command"><img src="img/plugin-3.svg" alt="Step 3: A command" height="30"></h2>

Every DABT app has a **command bar** (press `ctrl+p`): a searchable list of things to do. Add an entry to it. First write what should happen, as a plain bash function:

```bash
stretch_remind() {
    (( STRETCH_COUNT++ ))
    tui.notify "Stand up and stretch! (reminder #$STRETCH_COUNT)" warn 8
}
```

`tui.notify MESSAGE LEVEL SECONDS` shows a toast in the corner (levels: `info`, `success`, `warn`, `error`). Then register it inside `on_enable`:

```bash
    tui.cmd.add stretch.now "Stretch: remind me now" stretch_remind \
        --group Stretch --desc "Shows the reminder right away"
```

`tui.cmd.add ID TITLE FUNCTION` - an id, the text the user sees and searches, and the function to run. `--group` and `--desc` are decoration for the list.

<h2 id="step-4-a-key"><img src="img/plugin-4.svg" alt="Step 4: A key" height="30"></h2>

One more line in `on_enable` binds a key to the same function:

```bash
    tui.bind alt+s stretch_remind --desc "Stretch reminder"
```

Key names are written like `ctrl+e`, `alt+s`, `f5`, `shift+tab`. A key you bind replaces the built-in default for that key while the plugin is on (and the default returns when it is off).

> **Heads up:** your *terminal program* sees keys before DABT does, and some terminals keep certain combinations for themselves (tab switching, for example). If a key never arrives, try another one; the built-in `terminal_shortcuts` plugin can even show you which ones are taken.

<h2 id="step-5-a-timer"><img src="img/plugin-5.svg" alt="Step 5: A timer" height="30"></h2>

The reminder itself: call a function every N seconds with `tui.every SECONDS FUNCTION ID`.

```bash
    tui.every $(( 30 * 60 )) stretch_tick stretch_timer      # every 30 minutes
```

There is one thing to know about `tui.every`: **it also runs the function once, right away**, and then on every interval. A reminder that pops up the moment you start the app would be annoying, so we skip the first call:

```bash
stretch_tick() {
    (( STRETCH_TICKS++ )) || return 0     # first call: the counter was 0 -> "false" -> leave
    stretch_remind
}
```

(`(( X++ ))` is *false* when `X` was 0. So the first call returns early; every later call reaches `stretch_remind`.)

The third argument, `stretch_timer`, is the timer's **name**. You need it to cancel or restart the timer later.

<h2 id="step-6-settings"><img src="img/plugin-6.svg" alt="Step 6: Settings" height="30"></h2>

Hard-coding "30 minutes" is not friendly. A plugin can keep settings that survive restarts - DABT stores them as `plugin.<id>.<key>` in the app's `dabt.conf`.

```bash
tui.config.get plugin.stretch.minutes 30        # read; 30 if it was never set
tui.plugin.config stretch minutes 15            # write (3 arguments = save)
```

Use it at the top of `on_enable`, replacing the fixed 30:

```bash
    STRETCH_MINUTES="$(tui.config.get plugin.stretch.minutes 30)"
    tui.every $(( STRETCH_MINUTES * 60 )) stretch_tick stretch_timer
```

And two more commands to change the setting. Setting a new interval means: remember it, cancel the timer, start it again.

```bash
stretch_set() {                                   # MINUTES
    STRETCH_MINUTES="$1"
    tui.plugin.config stretch minutes "$1"
    tui.every.cancel stretch_timer
    STRETCH_TICKS=0; tui.every $(( STRETCH_MINUTES * 60 )) stretch_tick stretch_timer
    tui.notify "Reminding you every $STRETCH_MINUTES minute(s)" info 3
}
stretch_more() { stretch_set $(( STRETCH_MINUTES > 1 ? STRETCH_MINUTES / 2 : 1 )); }
stretch_less() { stretch_set $(( STRETCH_MINUTES * 2 )); }
```

```bash
    tui.cmd.add stretch.more "Stretch: remind more often" stretch_more --group Stretch --desc "Halves the interval"
    tui.cmd.add stretch.less "Stretch: remind less often" stretch_less --group Stretch --desc "Doubles the interval"
```

<h2 id="step-7-clean-up"><img src="img/plugin-7.svg" alt="Step 7: Clean up" height="30"></h2>

What happens when the user switches the plugin off? **You do not need to write anything.** The commands, the key and the timer are all removed by DABT because they were registered through `tui.cmd.add`, `tui.bind` and `tui.every`.

You may still add an *optional* `on_disable` for your own goodbye:

```bash
plugin.stretch.on_disable() { tui.notify "Stretch reminders off" info 2; }
```

If your plugin does something DABT cannot see (starts a background process, changes a file), register the undo yourself: `tui.plugin.own run 'command that undoes it'`.

<h2 id="step-8-try-it"><img src="img/plugin-8.svg" alt="Step 8: Try it" height="30"></h2>

Put the file where DABT looks for plugins - your plugin folder:

```bash
cp stretch.plugin.sh ~/.config/DABT/plugins/
```

(An app can also ship its own in `<app folder>/plugins/`. For quick experiments: `TUI_PLUGIN_DIRS=/path/to/folder bash myapp.sh`.)

Then start any DABT app - for example the one from the first tutorial - and:

1. Open **Settings → Plugins** (or `ctrl+p` → "DABT: Plugins"). **Stretch reminder** is in the list. Press Enter on it, or use the **On / Off** button.
2. Press **`alt+s`**. The toast appears. Press `ctrl+p`, type `stretch` - your three commands are listed.
3. Pick "Stretch: remind more often" and watch the toast confirm the new interval.
4. Switch it off again: the commands vanish from `ctrl+p` and `alt+s` does nothing. The cleanup worked.

You can also install from the Plugins page with **Install file / folder** (it asks for a path), which copies the plugin into your plugin folder.

If it misbehaves: the Plugins page shows a plugin's **state** and any error, and its **Details** show how many commands, keys, hooks and timers it registered. Common causes: the `# plugin:` id and the `plugin.<id>.on_enable` name do not match, or the file has a bash syntax error (`bash -n stretch.plugin.sh` finds it).

<h2 id="step-9-scan-it"><img src="img/plugin-9.svg" alt="Step 9: Scan it" height="30"></h2>

Before you enable somebody else's plugin - or publish yours - run the built-in security scan:

```bash
dabt scan stretch.plugin.sh
```

or, inside the app: **Settings → Plugins →** select the plugin **→ [ Scan ]**. The result opens in a scrollable window: a verdict (*no findings*, *warnings*, or *HIGH RISK*) and every suspicious line with its file and line number - things like downloading and running code, editing system files, or `eval` on variables.

A clean scan is not a guarantee - it is a list of *red flags*, checked by simple rules. It is one more reason to read a plugin before you trust it. Yours should come back clean.

<h2 id="recap"><img src="img/plugin-recap.svg" alt="Recap" height="30"></h2>

```bash
# plugin: stretch                       <- the id, and what the functions are named after
# title / version / description / ...  <- the business card
plugin.stretch.on_enable() {            # switched on: register what you add
    tui.cmd.add ...                     #   a command-bar entry
    tui.bind alt+s ...                  #   a key
    tui.every SECONDS FN NAME           #   a timer (runs once immediately, then every interval)
}
plugin.stretch.on_disable() { ... }     # optional; registrations are undone automatically
```

| You want to... | Use |
|---|---|
| add something to `ctrl+p` | `tui.cmd.add ID TITLE FN` |
| react to a key | `tui.bind KEY FN` |
| do something every N seconds / once later | `tui.every SEC FN NAME` / `tui.after SEC FN NAME` |
| react to events (page change, resize, quit) | `tui.hook.on EVENT FN` |
| show a message | `tui.notify MSG [LEVEL] [SEC]` |
| remember a setting | `tui.plugin.config ID KEY VALUE` / `tui.config.get plugin.ID.KEY DEFAULT` |
| undo something DABT cannot see | `tui.plugin.own run 'undo command'` |

<h2 id="where-next"><img src="img/plugin-next.svg" alt="Where next?" height="30"></h2>

- **Hooks:** `tui.hook.on page my_fn` runs `my_fn FILE` after every page switch; also `init`, `ready`, `resize`, `key`, `quit`, `exit`. A `key` hook that returns 0 *consumes* the key. Full list: [../guide/plugins.md](../guide/plugins.md#hooks).
- **A plugin with files:** make a folder `NAME/plugin.sh` and keep assets next to it (find them with `tui.plugin.dir NAME`).
- **Read real ones:** [`examples/plugins/hello.plugin.sh`](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/examples/plugins/hello.plugin.sh) (the smallest possible) and [`share/plugins/terminal_shortcuts.plugin.sh`](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/share/plugins/terminal_shortcuts.plugin.sh).
- **Write your own app:** [Writing Your First App](writing-your-first-app.md), and the technical guide [../guide/writing-an-app.md](../guide/writing-an-app.md).
- **Every function:** [../api/plugin.md](../api/plugin.md#plugins).
