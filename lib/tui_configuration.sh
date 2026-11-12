#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  dabt_configuration.sh - Centralized configuration & tunables              ║
# ║                                                                            ║
# ║  All framework tuning parameters in one place. Most can be overridden      ║
# ║  by setting the variable BEFORE sourcing tui.sh.                           ║
# ║                                                                            ║
# ║  Read-only after initialization: _TUI_* paths (computed).                  ║
# ╚════════════════════════════════════════════════════════════════════════════╝
# requires:

# ═══════════════════════════════════════════════════════════════════════════
#  APPLICATION IDENTITY (set by caller before sourcing tui.sh)
# ═══════════════════════════════════════════════════════════════════════════
if [[ -z "${TUI_APP_NAME:-}" ]]; then
	declare -g TUI_APP_NAME="dabt"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  INPUT & EVENT HANDLING TIMEOUTS
# ═══════════════════════════════════════════════════════════════════════════
# Tune these to trade CPU load for responsiveness. Lower timeout = higher
# responsiveness but higher idle CPU usage (read operations fire more often).
# Values in seconds (bash read -t accepts fractional).

# First-byte timeout while a tick function is active (tui.exec running)
declare -g TUI_INPUT_POLL_TIMEOUT="${TUI_INPUT_POLL_TIMEOUT:-0.05}"

# First-byte timeout when fully idle (no background tasks)
declare -g TUI_INPUT_IDLE_TIMEOUT="${TUI_INPUT_IDLE_TIMEOUT:-0.2}"

# Timeout while a pane render is queued (shorter = flush faster)
declare -g TUI_INPUT_SETTLE_TIMEOUT="${TUI_INPUT_SETTLE_TIMEOUT:-0.01}"
declare -gi TUI_CHANGE_DEBOUNCE_MAX="${TUI_CHANGE_DEBOUNCE_MAX:-8}" # a debounced on_change runs at least every this many events

# Per-byte timeout while assembling escape sequence (arrow keys, SGR mouse)
declare -g TUI_ESCSEQ_BYTE_TIMEOUT="${TUI_ESCSEQ_BYTE_TIMEOUT:-0.01}"

# Per-byte timeout for SGR mouse reports specifically (longer to collect full report)
declare -g TUI_ESCSEQ_MOUSE_TIMEOUT="${TUI_ESCSEQ_MOUSE_TIMEOUT:-0.05}"

# Peek timeout during mouse motion coalescing
# ⚠️  Cannot be 0: read -t 0 in bash is a non-consuming probe only
declare -g TUI_MOUSE_DRAIN_PEEK_TIMEOUT="${TUI_MOUSE_DRAIN_PEEK_TIMEOUT:-0.001}"

# Max motion reports to coalesce per frame (safety net against floods)
declare -gi TUI_MOUSE_DRAIN_MAX="${TUI_MOUSE_DRAIN_MAX:-200}"

# ═══════════════════════════════════════════════════════════════════════════
#  PAGE CACHE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

# 1=a start with several uncached pages builds only the first page behind the splash and the rest in background workers
# while the app runs (a page opened before its worker is done is built on the spot), 0=build every page before the first frame
declare -gi TUI_CACHE_LAZY="${TUI_CACHE_LAZY:-1}"

# background workers of the lazy build; 0=half the cores, at least 1
declare -gi TUI_CACHE_LAZY_WORKERS="${TUI_CACHE_LAZY_WORKERS:-12}"

# 1=the background pool prepares the themes and shells of its pages itself, so the first page does not wait for them;
# 0=they are prepared for every page before the first page is built
declare -gi TUI_CACHE_LAZY_PREP="${TUI_CACHE_LAZY_PREP:-1}"

# milliseconds the terminal must stay at one size before the background pool re-fits the cached pages to it (a window drag
# is a burst of sizes: only the last one matters); 0=never re-fit, and no pool driver is started when nothing is to be
# built at start-up; needs TUI_CACHE_LAZY=1
declare -gi TUI_CACHE_RESIZE_DEBOUNCE_MS="${TUI_CACHE_RESIZE_DEBOUNCE_MS:-300}"

# nice value of the background pool, so the app's own input wins the cores while it builds; 0=same priority as the app
declare -gi TUI_CACHE_LAZY_NICE="${TUI_CACHE_LAZY_NICE:-10}"

# parallel page validation (first launch, after an update or a page edit): workers to use; 0=one per core, 1=validate in
# this shell, one page after the other
declare -gi TUI_VALIDATE_JOBS="${TUI_VALIDATE_JOBS:-0}"

# 1=the page validation of a start runs in the background while the first page is prepared and built, and is joined before
# the cache is written or the app starts; 0=validate every page first, then build
declare -gi TUI_VALIDATE_ASYNC="${TUI_VALIDATE_ASYNC:-1}"

# ═══════════════════════════════════════════════════════════════════════════
#  LOGGING CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

# lowest level written to the app log: debug, info, warn, error or off. debug is for developing a page or the framework: it
# logs every build step (about 12 ms per page build, thousands of lines on a first launch). Change it while running with
# tui.log.level.
declare -g TUI_LOG_LEVEL="${TUI_LOG_LEVEL:-info}"

# ═══════════════════════════════════════════════════════════════════════════
#  BACKGROUND JOB & SPINNER CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

# ms: delay before spinner appears (shorter = show sooner for slow tasks)
declare -gi TUI_JOB_SPINNER_MS="${TUI_JOB_SPINNER_MS:-100}"

# 1=run jobs concurrently, 0=wait for each (0 for profiling/debugging)
declare -gi TUI_JOB_BACKGROUND="${TUI_JOB_BACKGROUND:-1}"

# µs: spinner frame rate (one frame every N microseconds)
declare -gi TUI_JOB_FRAME_US="${TUI_JOB_FRAME_US:-80000}"

# UI rows reserved per background job instance (status + buttons + input)
declare -gi TUI_EXEC_CTL_ROWS_PER_INSTANCE="${TUI_EXEC_CTL_ROWS_PER_INSTANCE:-7}"

# How tui.exec gets its child a terminal: auto = a PTY through script(1) when util-linux script is found, else plain pipes;
# on = force script(1) (util-linux or BSD syntax); off = always plain pipes (pure Bash/POSIX, children may buffer or drop colors)
declare -g TUI_EXEC_PTY="${TUI_EXEC_PTY:-auto}"

# Spinner character sequence (braille progression)
declare -ga TUI_JOB_SPINNER_GLYPHS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# ═══════════════════════════════════════════════════════════════════════════
#  PERFORMANCE MONITORING
# ═══════════════════════════════════════════════════════════════════════════

# Ring buffer size per timing span (higher = more history, higher memory use)
declare -gi TUI_PERF_RING_MAX="${TUI_PERF_RING_MAX:-500}"

# Debug mode (dabt --debug): events kept per ring buffer
declare -gi TUI_DEBUG_RING_MAX="${TUI_DEBUG_RING_MAX:-500}"

# ═══════════════════════════════════════════════════════════════════════════
#  WIDGET & INPUT BEHAVIOR DEFAULTS
# ═══════════════════════════════════════════════════════════════════════════

# Keep input widget focused after user submits (unless overridden per-widget)
declare -g TUI_INPUT_RETAIN_ON_SUBMIT="${TUI_INPUT_RETAIN_ON_SUBMIT:-1}"

# ═══════════════════════════════════════════════════════════════════════════
#  APPLICATION PATHS (Computed at initialization; read-only)
# ═══════════════════════════════════════════════════════════════════════════
# Set by tui_home.sh during initialization. Included here for reference.
# Do NOT edit these values below; they are overwritten at startup.

# Root directory of the framework (contains lib/, bin/, share/)
declare -g TUI_ROOT=""

# Config home location (e.g., ~/.config/DABT)
declare -g TUI_HOME=""

# Per-app config folder
declare -g TUI_APP_CONF=""

# Plugin directory
declare -g TUI_PLUGINS_DIR=""

# Log directory
declare -g TUI_LOG_DIR=""

# Default keybinds, theme, commands
declare -g TUI_DEFAULTS_DIR="${TUI_DEFAULTS_DIR:-}" # an exported value wins: run a checkout on its own share/defaults

# Framework version (read from $TUI_ROOT/VERSION at runtime)
declare -g TUI_VERSION="0.0.0"

# 1 if installation is complete
declare -g TUI_INSTALLED=0
