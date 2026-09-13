# Bending the world to your will: Architectural Strategies for High-Performance Viewport Scrolling in Pure-Bash Terminal Interfaces

Terminal User Interfaces (TUIs) built entirely in standard Bash present a
fascinating exercise in working within strict computational constraints. While
modern terminal emulators are fast, the shell environments running inside them
are not natively designed to function as graphical rendering engines. The
fundamental mechanics of scrolling tracking a viewport offset, resolving true
text boundaries against zero-width ANSI escape sequences, and shifting
multi-dimensional text arrays expose the structural limitations of shell
scripting.

### The Bottleneck: Process Forking and Input Flooding

Bash handles integer arithmetic and array lookups natively and with remarkable
efficiency. However, the bottleneck emerges during string manipulation.
Correctly slicing ANSI-colored text inside Bash loops to create a moving
viewport typically requires executing a subshell logic map (spawning child
processes like `awk` or `sed` for every line).

If a UI pane displays 40 lines of text, a single scroll action triggers 40
subshells. When a user interacts fluidly with the interface such as spinning
a mouse wheel rapidly or attempting to drag a scrollbar the terminal is
flooded with positional events. In a synchronous bash loop, this cascades
into hundreds of rapid subshell forks. The resulting overhead causes thread
exhaustion, severe UI lag, screen tearing, and dropped frames. Continuous
mouse tracking (dragging) is fundamentally hostile to synchronous shell
environments.

### The Paradigm Shift: The AWK "Shader" Architecture

To achieve high frames per second and smooth terminal scrolling, the rendering
paradigm must shift. Bash must cease acting as a line-by-line rendering loop
and instead operate purely as a state-manager and data-bus. The mathematical
heavy lifting of text manipulation must be offloaded to a compiled binary.

In this framework, `awk` is utilized not as a simple text parser, but as a
single-pass rendering engine acting effectively as a terminal GPU shader.

This high-performance architecture relies on three core principles:

* **Lazy Pre-computation:** Performance is preserved by doing expensive math
  only once. When text data is first ingested into the TUI, the framework
  measures the maximum line width and total line count via a single, rapid
  `awk` sweep. These dimensions are cached globally in state arrays (e.g.,
  `_TUI_P_MAX_W` and `_TUI_P_LINES`).

* **State Debouncing:** When a user interacts with the UI via mouse or
  keyboard, the event handlers update the viewport offset states instantly by
  reading from the cached bounds. To prevent the terminal from choking on
  input floods, rapid scroll requests are batched into a pending queue
  (`_TUI_PENDING_RENDER`). The actual drawing sequence is delayed until the
  input stream pauses or a strict timeout triggers.

* **Single-Pass Subshell Injection:** Instead of looping line-by-line to
  format text, Bash slices the exact vertical window representing the active
  scroll position directly from memory. This localized array is dumped into a
  singular `awk` process. The `awk` engine applies ANSI-safe horizontal
  slicing, calculates spatial padding, prepends precise terminal cursor
  positioning codes, and returns one continuous, pre-formatted string
  representing a complete frame. Bash then drops this massive string to the
  screen in a single command.

### Interaction Mechanics: The Jump-to-Click Pattern

Because dragging forces continuous, synchronous polling that chokes the event
loop, performant TUIs must adopt alternative interaction models. To maintain
immediate responsiveness, the framework utilizes the **Jump-to-Click**
pattern alongside discrete input events.

Rather than dragging a thumb, clicking anywhere on a pane's horizontal or
vertical border calculates the relative click-depth percentage and instantly
snaps the viewport to that exact offset. Mouse wheels evaluate as standard
up/down events, while keyboard overrides (such as `hjkl` or Shift+Arrow
keys) directly manipulate the cached offset states, routing through the same
debounced queue.

By respecting the limitations of the language; eliminating subshell loops,
debouncing continuous inputs, and consolidating rendering into single-pass
execution blocks; it becomes possible to bend a pure Bash environment into a
fluid, highly responsive graphical interface.

---

### Implementation Architecture: Technical Execution

Achieving this performance requires specific data structures and strict
control over the execution flow.

#### 1. Data Structures: Namerefs and Viewport Offsets

To avoid the overhead of constantly copying massive strings, the framework
stores pane content in dynamically generated global arrays. By utilizing
Bash's nameref feature (`declare -n`), the rendering engine can pass
references to specific arrays (like `_TUI_PANE_CONTENT_${pane}`) in constant
time without duplicating data. The current viewport coordinates for each pane
are tracked via parallel associative arrays: `_TUI_P_SOFF_V` for the vertical
offset and `_TUI_P_SOFF_H` for the horizontal offset.

#### 2. The Render Queue: Debouncing the Event Loop

The main event loop (`tui.run`) processes input continuously using
non-blocking `read` commands. When a scroll event occurs, instead of
directly invoking the drawing function, the framework flags the specific pane
in a sparse associative array (`_TUI_PENDING_RENDER[$pane]=1`) and
initializes a countdown timer (`_TUI_RENDER_TIMEOUT=3`). As the loop
continues to cycle and absorb rapid input events, this timer decrements. The
actual flush to the screen (`_tui._render_output`) only triggers when the
timer hits zero, or when the input buffer is completely empty (`got_char=0`).

#### 3. The AWK Rendering Pipeline: Handling ANSI Safely

The core of the visual rendering logic is encapsulated in
`_tui._render_output`. Bash first iterates from the vertical offset (`v_off`)
to the visible height boundary (`ct_h`) to slice the active vertical window
from the pane's array, passing only this subset to `awk`.

Inside `awk`, a custom `visible_slice` function addresses the horizontal
offset (`hoff`) by scanning each string character by character, explicitly
shielding ANSI control sequences via regex matching
(`\033\[[0-9;?]*[a-zA-Z]`). It bypasses visible characters until the
requested offset is reached, then captures characters up to the pane's
allowed width (`w`), leaving all zero-width color formatting codes fully
intact. Finally, `awk` prepends absolute cursor positioning sequences
(`\033[%d;%dH`) to each processed line. This results in a solitary,
pre-rendered string buffer sent back to Bash, allowing the terminal to draw
the entire updated pane in a single atomic operation.