# Portability: the core path and its exceptions

DABT's claim is **Bash 5 plus POSIX utilities**. This page defines what that covers, so the claim stays checkable.

## Three tiers

| Tier | Files | Rule |
|---|---|---|
| **1. Runtime** (the hot path: every frame, key and page switch) | `lib/` except the folders below, `bin/` is not part of it | Bash 5 builtins first; a POSIX utility only where Bash has no equivalent and never per frame. |
| **2. App lifecycle** (what a user needs to run an app) | `bin/dabt`, `lib/tui_home.sh`, `lib/tui_tmp.sh`, `lib/apps/tui_apps.sh`, `tui_install.sh`, `tui_sync.sh`, and the built-in rules of `tui_scan.sh` | Bash 5 and POSIX only. Each of these works standalone (no `tui.sh`). |
| **3. Release and developer tooling** | `lib/apps/tui_update.sh`, `lib/dapk/*`, ShellCheck/Semgrep in `tui_scan.sh` | May use `curl`/`wget`, `tar`, `git`, `ssh-keygen`, `gzip`. A missing tool is a clear message, never a broken app. |

Tier 1 and 2 are the "core": nothing in them may need a tool outside POSIX, except the exceptions below.

## Exceptions inside the core

| Exception | Tier | Why | Behaviour without it |
|---|---|---|---|
| `script(1)` | 1 (`tui.exec`) | Bash and POSIX cannot allocate a pseudo-terminal | Pipe mode, see below |
| `stat` | 1 (page cache) | no POSIX "mtime" utility | GNU `-c`, then BSD `-f`, then `0` |
| `stty size` | 1 (resize) | not in POSIX `stty` | `$COLUMNS`/`$LINES`, last known size |
| `base64` | 1 (`img.*` helpers only) | binary files cannot go through Bash strings | helpers unavailable |
| a SHA-256 tool (`sha256sum`, `shasum`, `openssl`; `cksum` last) | 2 (`tui_sync.sh`) | no POSIX SHA-256 utility | needs one of them |
| `git` | 2 (`dabt app install <git URL>`) | the transport | local installs work |
| `ln -sfn` | 2 (`tui_install.sh`) | `-n` is not POSIX, GNU/BSD/busybox all have it | none needed |

Everything else that used to be outside the line is gone: `mktemp` (see `lib/tui_tmp.sh`), `tail -n +N`, `tr`, `date +%s%N`, `find -maxdepth` and `-not`, `cp -a`, `readlink -f`, `dirname` in the hot path.

## tui.exec: PTY mode and pipe mode

`tui.exec` streams a child process into a pane.

- **PTY mode** (util-linux `script(1)` found): the child sees a terminal. Line-buffered output, colors, `\r` progress bars.
- **Pipe mode** (no `script`, or `TUI_EXEC_PTY=off`): the child runs on a FIFO for stdin and a file for output. Streaming, stdin and the exit status work the same. The child sees no tty, so:
  - programs that switch to block buffering on a pipe deliver output in chunks (`FORCE_COLOR=1`, `CLICOLOR_FORCE=1` and `stdbuf -oL`, when `stdbuf` exists, soften this);
  - progress bars and colors that need a tty may be off.

The command is Bash/POSIX shell text and runs under the Bash that runs the app (`$BASH`), never the user's login shell (fish, zsh ...).

Neither mode is a terminal emulator. Cursor movement and full-screen programs (`vim`, `top` without `-b`) are not supported; the cleaner keeps SGR colors and drops every other escape sequence. Feed an app's stdin through the pane's input box or the instance's FIFO.

`TUI_EXEC_PTY`: `auto` (default; PTY only with util-linux `script`), `on` (force `script`, util-linux or BSD syntax; the BSD form is untested), `off` (always pipes).

## Keeping it true

- New code in tier 1 or 2 does not add a command outside POSIX without adding it to the table above.
- `tools/gen_load_order.sh --check` keeps the module order honest; a helper both tiers need goes in a standalone module like `lib/tui_tmp.sh`.
