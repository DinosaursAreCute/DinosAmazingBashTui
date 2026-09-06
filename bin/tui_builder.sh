#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  tui_builder.sh — Master orchestrator for the declarative TUI            ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# 1. Reliably calculate absolute paths regardless of where the script is called from
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TUI_PROJECT_ROOT="$(dirname "$BIN_DIR")"

# 2. Source the core engine and the configuration parser
source "${BIN_DIR}/tui.sh"
source "${BIN_DIR}/tui_config_parser.sh"

tui.build_and_run() {
    local config_file="$TUI_PROJECT_ROOT/config/$1"

    if [[ ! -f "$config_file" ]]; then
        echo "tbError: Configuration file not found at '$config_file'." >&2
        exit 1
    fi

    # Initialize the raw terminal state
    tui.init

    # Parse the YAML/JSON and build the layout in memory
    tui.load_config "$config_file"

    # Start the event loop (blocking)
    tui.run
}

# Allow direct execution: ./tui_builder.sh ../config/layout.yaml
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ -z "$1" ]]; then
        echo "Usage: $0 <path_to_config.yaml>" >&2
        exit 1
    fi
    tui.build_and_run "$1"
fi