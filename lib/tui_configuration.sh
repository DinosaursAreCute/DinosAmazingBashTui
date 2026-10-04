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

# Spinner character sequence (braille progression)
declare -ga TUI_JOB_SPINNER_GLYPHS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# ═══════════════════════════════════════════════════════════════════════════
#  PERFORMANCE MONITORING
# ═══════════════════════════════════════════════════════════════════════════

# Ring buffer size per timing span (higher = more history, higher memory use)
declare -gi TUI_PERF_RING_MAX="${TUI_PERF_RING_MAX:-500}"

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
declare -g TUI_DEFAULTS_DIR=""

# Framework version (read from $TUI_ROOT/VERSION at runtime)
declare -g TUI_VERSION="0.0.0"

# 1 if installation is complete
declare -g TUI_INSTALLED=0
