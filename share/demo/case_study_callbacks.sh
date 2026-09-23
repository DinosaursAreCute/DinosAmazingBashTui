#!/usr/bin/env bash

# Source the renderer to gain access to all _string functions
tui.require terminal_renderer

on_tab_doc() {
	local doc_path="$TUI_ROOT/docs/design/viewport-scrolling.md"
	local raw_doc=""

	# Prepend a generated banner
	raw_doc+="\n$(banner_string "Bending The World To Your Will")\n\n"

	# Dynamically substitute the file content
	if [[ -f "$doc_path" ]]; then
		raw_doc+="$(cat "$doc_path")\n"
	else
		raw_doc+="$(alert_string error "Document not found at: $doc_path")\n"
	fi

	# Evaluate \n escape sequences and push to the scrollable pane
	local formatted_doc="$(printf '%b' "$raw_doc")"
	tui.output "content" "$formatted_doc"
	tui.pane_title "content" "Technical Document"
}

on_tab_tbl() {
	local raw_content=""

	raw_content+="$(banner_string "METRICS")\n\n"
	raw_content+="$(divider_string "System Fleet Status")\n\n"

	raw_content+="$(alert_string info "Cluster 01 has been rebalanced successfully.")\n\n"

	# Complex nested table combining strings, badges, and hbars
	hbar_24="$(printf '%b' "$(hbar_string -w 20 -m 100 " :24")")"
	raw_content+="$(
		table_string "Hostname|Status|CPU Usage|Memory|Uptime|Load Avg" \
			"sv-web-01|$(badges_string "pass:Online")|$hbar_24|16GB|42 days|0.45" \
			"sv-web-02|$(badges_string "pass:Online")|$(hbar_string -w 20 -m 100 " :38")|16GB|42 days|0.88" \
			"sv-db-01|$(badges_string "warn:High Load")|$(hbar_string -w 20 -m 100 " :92")|64GB|110 days|4.12" \
			"sv-db-02|$(badges_string "pass:Online")|$(hbar_string -w 20 -m 100 " :45")|64GB|110 days|1.15" \
			"sv-cache-01|$(badges_string "skip:Maintenance")|$(hbar_string -w 20 -m 100 " :0")|32GB|0 days|0.00"
	)\n\n"

	raw_content+="$(divider_string "Detailed Node Properties")\n\n"

	raw_content+="$(kv_string "Architecture: x86_64" "OS: Arch Linux" "Kernel: 6.6.1-arch1-1" "Filesystem: btrfs")\n\n"

	# Nested columns holding lists
	raw_content+="$(
		columns_string -h "Active Processes" -h "Network Conns" \
			"$(list_string "nginx (pid 1023)" "postgres (pid 990)" "redis-server (pid 404)")" \
			"$(list_string "ESTABLISHED 450" "TIME_WAIT 120" "LISTEN 3")"
	)\n\n"

	# An incredibly long line to strictly test horizontal scrolling
	raw_content+="$(divider_string "Raw Log Output (Scroll Horizontally to View Full Trace)")\n"
	raw_content+="[2026-09-13T10:21:11] DEBUG: connection pool initialized with 50 workers. listening on 0.0.0.0:8080. metrics daemon started at port 9090. tracer running and exporting to datadog agent at localhost:8126. payload configuration loaded from /etc/config/payload.yaml. no errors detected during startup phase.\n"
	raw_content+="[2026-09-13T10:21:12] INFO: inbound request from 192.168.1.45 mapped to handler func(req, res). response generated in 45ms. status 200 OK. content-length: 1024 bytes. x-request-id: 9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d\n"

	local formatted_content="$(printf '%b' "$raw_content")"
	tui.output "content" "$formatted_content"
	tui.pane_title "content" "Live Metrics Table"
}
