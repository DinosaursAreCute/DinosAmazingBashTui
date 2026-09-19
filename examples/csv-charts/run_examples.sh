#!/usr/bin/env bash
# run_examples.sh - a tour of terminal_renderer.sh's CSV-driven charts.
# Run it directly: bash examples/csv-charts/run_examples.sh

EX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$EX_DIR/../../bin" && pwd)"
DATA="$EX_DIR/data"

source "$BIN_DIR/terminal_renderer.sh"

section() {
    echo
    divider "$1"
    echo
}

banner "CHARTS"
echo
box "Every chart below is rendered straight from a plain .csv file in\nexamples/csv-charts/data/ using terminal_renderer.sh - no other\ntools involved."

section "Quarterly Revenue by Region (\$K) - csv_hbar"
csv_hbar -c "BRIGHT_CYAN,BRIGHT_MAGENTA,BRIGHT_GREEN,BRIGHT_YELLOW" "$DATA/quarterly_revenue.csv"

section "Language Popularity, Dev Survey % - csv_hbar"
csv_hbar -c "YELLOW,BLUE,BLUE,BRIGHT_WHITE,RED,CYAN,BRIGHT_RED,MAGENTA" "$DATA/language_popularity.csv"

section "Server CPU Load - csv_vbar"
csv_vbar -h 10 -c "GREEN,YELLOW,RED,GREEN,YELLOW" "$DATA/server_cpu.csv"

section "Disk Usage by Mount - csv_vbar"
csv_vbar -h 8 -c "GREEN,RED,YELLOW,GREEN" "$DATA/disk_usage.csv"

section "Weekly Website Traffic vs Signups - csv_linechart"
csv_linechart -h 12 -c "BRIGHT_CYAN,BRIGHT_MAGENTA" "$DATA/website_traffic.csv"

section "Stock Price Comparison - csv_linechart"
csv_linechart -h 12 -c "GREEN,RED,BRIGHT_YELLOW" "$DATA/stock_prices.csv"

section "Disk Usage as single-element gauges - reading the CSV by hand"
while IFS=',' read -r drive pct; do
    [[ -z "$drive" ]] && continue
    gauge -l "$(printf '%-6s' "$drive")" -w 30 "$pct"
done < "$DATA/disk_usage.csv"

echo
quote -a "terminal_renderer.sh" "Same data, five different shapes - pick whichever tells the story best."
echo
