#!/usr/bin/env bash

# Source the renderer to gain access to all _string functions
tui.require terminal_renderer

on_tab_doc() {
	local doc_path="$TUI_ROOT/docs/design/viewport-scrolling.md"
	local raw_doc="" part formatted_doc

	# Prepend a generated banner
	tui.capture part banner_string "Bending The World To Your Will"
	raw_doc+="\n${part}\n\n"

	# Dynamically substitute the file content
	if [[ -f "$doc_path" ]]; then
		raw_doc+="$(<"$doc_path")\n"
	else
		tui.capture part alert_string error "Document not found at: $doc_path"
		raw_doc+="${part}\n"
	fi

	# Evaluate \n escape sequences and push to the scrollable pane
	printf -v formatted_doc '%b' "$raw_doc"
	formatted_doc="${formatted_doc%"${formatted_doc##*[!$'\n']}"}" # trailing newlines off, as $( ) did
	tui.output "content" "$formatted_doc"
	tui.pane_title "content" "Technical Document"
}

# the metrics tab is static text for a given renderer width: built once per width
declare -gA _CS_TBL_MEMO # no "=()": the script is re-sourced on every visit and must keep the memo

on_tab_tbl() {
	local key="${TR_WIDTH:--}"
	if [[ -z "${_CS_TBL_MEMO[$key]+x}" ]]; then
		_cs_build_tbl
		_CS_TBL_MEMO[$key]="$_CS_TBL"
	fi
	tui.output "content" "${_CS_TBL_MEMO[$key]}"
	tui.pane_title "content" "Live Metrics Table"
}

_cs_build_tbl() {
	local raw_content="" part hbar_24 b1 b2 b3 b4 b5 h2 h3 h4 h5 l1 l2

	tui.capture part banner_string "METRICS"
	raw_content+="${part}\n\n"
	tui.capture part divider_string "System Fleet Status"
	raw_content+="${part}\n\n"

	tui.capture part alert_string info "Cluster 01 has been rebalanced successfully."
	raw_content+="${part}\n\n"

	# Complex nested table combining strings, badges, and hbars
	tui.capture hbar_24 hbar_string -w 20 -m 100 " :24"
	printf -v hbar_24 '%b' "$hbar_24"
	hbar_24="${hbar_24%"${hbar_24##*[!$'\n']}"}"
	tui.capture b1 badges_string "pass:Online"
	tui.capture b2 badges_string "pass:Online"
	tui.capture b3 badges_string "warn:High Load"
	tui.capture b4 badges_string "pass:Online"
	tui.capture b5 badges_string "skip:Maintenance"
	tui.capture h2 hbar_string -w 20 -m 100 " :38"
	tui.capture h3 hbar_string -w 20 -m 100 " :92"
	tui.capture h4 hbar_string -w 20 -m 100 " :45"
	tui.capture h5 hbar_string -w 20 -m 100 " :0"
	tui.capture part table_string "Hostname|Status|CPU Usage|Memory|Uptime|Load Avg" \
		"sv-web-01|${b1}|$hbar_24|16GB|42 days|0.45" \
		"sv-web-02|${b2}|${h2}|16GB|42 days|0.88" \
		"sv-db-01|${b3}|${h3}|64GB|110 days|4.12" \
		"sv-db-02|${b4}|${h4}|64GB|110 days|1.15" \
		"sv-cache-01|${b5}|${h5}|32GB|0 days|0.00"
	raw_content+="${part}\n\n"

	tui.capture part divider_string "Detailed Node Properties"
	raw_content+="${part}\n\n"

	tui.capture part kv_string "Architecture: x86_64" "OS: Arch Linux" "Kernel: 6.6.1-arch1-1" "Filesystem: btrfs"
	raw_content+="${part}\n\n"

	# Nested columns holding lists
	tui.capture l1 list_string "nginx (pid 1023)" "postgres (pid 990)" "redis-server (pid 404)"
	tui.capture l2 list_string "ESTABLISHED 450" "TIME_WAIT 120" "LISTEN 3"
	tui.capture part columns_string -h "Active Processes" -h "Network Conns" "$l1" "$l2"
	raw_content+="${part}\n\n"

	# An incredibly long line to strictly test horizontal scrolling
	tui.capture part divider_string "Raw Log Output (Scroll Horizontally to View Full Trace)"
	raw_content+="${part}\n"
	raw_content+="[2026-09-13T10:21:11] DEBUG: connection pool initialized with 50 workers. listening on 0.0.0.0:8080. metrics daemon started at port 9090. tracer running and exporting to datadog agent at localhost:8126. payload configuration loaded from /etc/config/payload.yaml. no errors detected during startup phase.\n"
	raw_content+="[2026-09-13T10:21:12] INFO: inbound request from 192.168.1.45 mapped to handler func(req, res). response generated in 45ms. status 200 OK. content-length: 1024 bytes. x-request-id: 9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d\n"

	printf -v _CS_TBL '%b' "$raw_content"
	_CS_TBL="${_CS_TBL%"${_CS_TBL##*[!$'\n']}"}" # trailing newlines off, as $( ) did
}
