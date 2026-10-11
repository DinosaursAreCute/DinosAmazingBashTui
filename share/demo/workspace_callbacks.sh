#!/usr/bin/env bash
# workspace_callbacks.sh - "Workspace" demo page: a small operations console (services, logs, events, host details, a
# command prompt). Everything is SIMULATED and fork-free: the service table below is the only data, a seeded LCG
# makes the log lines, /proc is read with read only, and no command ever touches the host.
#   _ws_*   private helpers        on_ws_*   page actions (markup action= / submit= / on_change= / <bind>)

declare -g _WS_PROC=/proc          # where the host readers look (tests point it elsewhere)
declare -g _WS_SEED=20240607 _WS_R=0 _WS_SEL=0 _WS_TICKS=0 _WS_LINE="" _WS_IDX=-1 _WS_NOTE=""
declare -ga _WS_NAMES=(api-gateway auth-service orders-svc billing-queue cache-redis search-index notifier)
declare -gA _WS_SVC=() _WS_LOGS=() _WS_LOGN=() _WS_TPL=()
declare -ga _WS_EVENTS=()
declare -g _WS_LOAD="n/a" _WS_UP="n/a" _WS_MEMTXT="n/a" _WS_MEMPCT=0

# NAME|STATE|VERSION|REPLICAS(ready/want)|OWNER|ERR%|P95ms|LAST DEPLOY
_WS_TABLE=(
	'api-gateway|ok|v2.14.3|4/4|platform|0.2|42|2h ago'
	'auth-service|ok|v1.9.0|3/3|identity|0.1|18|1d ago'
	'orders-svc|ok|v3.2.1|6/6|commerce|0.6|87|5h ago'
	'billing-queue|down|v0.8.7|0/2|payments|31.4|0|35m ago'
	'cache-redis|warn|v7.2.4|3/3|platform|1.9|3|9d ago'
	'search-index|ok|v5.1.2|2/2|discovery|0.4|120|3d ago'
	'notifier|warn|v1.3.5|1/2|growth|2.7|240|12h ago'
)
# per service: INFO, WARN and ERROR line templates ('|' separated); %i = request id, %m = latency ms, %n = number
_WS_TPL=(
	[api-gateway.INFO]='GET /v1/orders 200 %mms req=%i|POST /v1/login 200 %mms req=%i|GET /v1/items/%n 200 %mms req=%i|GET /healthz 200 1ms'
	[api-gateway.WARN]='GET /v1/search 200 %mms slow upstream req=%i|rate limit near for client acme-%n'
	[api-gateway.ERROR]='upstream timeout after 3000ms route=/v1/billing req=%i|502 from billing-queue req=%i'
	[auth-service.INFO]='token issued sub=u%n ttl=900s|session refreshed sub=u%n|jwks cache hit keys=3'
	[auth-service.WARN]='failed login sub=u%n attempts=%n|token near expiry sub=u%n'
	[auth-service.ERROR]='ldap bind failed host=ldap-2 rc=49|signing key rotation failed'
	[orders-svc.INFO]='order o-%n created items=%n total=%n.90|order o-%n paid|inventory reserved sku=%n'
	[orders-svc.WARN]='slow query orders_by_user %mms rows=%n|retry 2/3 payment callback o-%n'
	[orders-svc.ERROR]='deadlock detected table=orders o-%n|publish failed topic=order.created'
	[billing-queue.INFO]='invoice batch %n picked up|charge ch_%n captured'
	[billing-queue.WARN]='queue depth %n above threshold 50|card network latency %mms'
	[billing-queue.ERROR]='connection refused db-billing:5432|invoice %n failed: upstream timeout|worker exited code=1, restarting'
	[cache-redis.INFO]='keyspace hit ratio 0.%n|bgsave finished in %mms|replica sync ok lag=%mms'
	[cache-redis.WARN]='used_memory 91%% of maxmemory|evicted %n keys policy=allkeys-lru'
	[cache-redis.ERROR]='MISCONF cannot persist to disk|replica link down for 30s'
	[search-index.INFO]='segment merge done in %mms|query q="shoes" hits=%n %mms|refresh interval 1s'
	[search-index.WARN]='slow query "red sneakers" %mms|shard 3 yellow, 1 replica pending'
	[search-index.ERROR]='shard 2 unassigned|bulk index rejected: queue full'
	[notifier.INFO]='email queued to=u%n tpl=welcome|push sent device=d%n %mms|digest scheduled %n users'
	[notifier.WARN]='smtp relay slow %mms|push token expired device=d%n'
	[notifier.ERROR]='smtp 451 try again later|webhook delivery failed hook=%n'
)

# ── data ────────────────────────────────────────────────────────────────────

# _ws_rand N -> _WS_R in 0..N-1 (LCG: same seed, same sequence)
_ws_rand() {
	_WS_SEED=$(((_WS_SEED * 1103515245 + 12345) & 0x7fffffff))
	_WS_R=$(((_WS_SEED >> 8) % $1))
}

_ws_stamp() { printf -v _WS_STAMP '%(%H:%M:%S)T' -1; }

# _ws_init - reset the whole simulation to its seeded start
_ws_init() {
	local row n
	_WS_SEED=20240607 _WS_SEL=0 _WS_TICKS=0
	_WS_SVC=() _WS_LOGS=() _WS_LOGN=() _WS_EVENTS=()
	for row in "${_WS_TABLE[@]}"; do
		n="${row%%|*}"
		IFS='|' read -r _ _WS_SVC["$n.state"] _WS_SVC["$n.ver"] _WS_SVC["$n.rep"] _WS_SVC["$n.owner"] \
			_WS_SVC["$n.err"] _WS_SVC["$n.p95"] _WS_SVC["$n.deploy"] <<<"$row"
		_WS_SVC["$n.ack"]=0
		_WS_LOGS[$n]="" _WS_LOGN[$n]=0
	done
	_WS_EVENTS=(
		"09:58 ▲ cache-redis    memory >90%"
		"10:02 ↻ orders-svc     deployed v3.2.1"
		"10:15 ✖ billing-queue crash loop"
		"10:15 ▲ notifier       smtp relay slow"
		"10:21 ✓ search-index   shard 3 healthy"
	)
	# a little history so every log has content on the first frame
	local i
	for n in "${_WS_NAMES[@]}"; do
		for ((i = 0; i < 14; i++)); do _ws_logline "$n" "$((14 - i))"; done
	done
}

# _ws_logline SVC [BACK] - append one generated line to SVC's log (BACK = seconds ago, for the seeded history)
_ws_logline() {
	local n="$1" st="${_WS_SVC[$1.state]}" lvl tpl
	local -a pool=()
	_ws_rand 100
	case "$st" in
		ok) ((_WS_R < 88)) && lvl=INFO || { ((_WS_R < 98)) && lvl=WARN || lvl=ERROR; } ;;
		warn) ((_WS_R < 55)) && lvl=INFO || { ((_WS_R < 88)) && lvl=WARN || lvl=ERROR; } ;;
		*) ((_WS_R < 10)) && lvl=INFO || { ((_WS_R < 30)) && lvl=WARN || lvl=ERROR; } ;;
	esac
	IFS='|' read -ra pool <<<"${_WS_TPL[$n.$lvl]}"
	_ws_rand "${#pool[@]}"
	tpl="${pool[_WS_R]}"
	_ws_rand 4000
	local hex
	printf -v hex '%04x' "$((_WS_SEED & 0xffff))"
	tpl="${tpl//%i/$hex}"
	tpl="${tpl//%m/$((_WS_R % 300 + 3))}"
	_ws_rand 900
	tpl="${tpl//%n/$((_WS_R + 100))}"
	tpl="${tpl//%%/%}"
	_ws_stamp
	local t="$_WS_STAMP" sgr
	case "$lvl" in INFO) sgr=$'\e[32m' ;; WARN) sgr=$'\e[33m' ;; *) sgr=$'\e[1;31m' ;; esac
	[[ -n "${2:-}" ]] && printf -v t '%(%H:%M:%S)T' "$((EPOCHSECONDS - ${2} * 7))"
	printf -v _WS_LINE '\e[90m%s\e[0m %s%-5s\e[0m %s' "$t" "$sgr" "$lvl" "$tpl"
	_ws_logadd "$n" "$_WS_LINE"
}

# _ws_logadd SVC LINE - append, keeping the newest 200 lines
_ws_logadd() {
	local n="$1"
	_WS_LOGS[$n]+="$2"$'\n'
	((++_WS_LOGN[$n] > 200)) && {
		_WS_LOGS[$n]="${_WS_LOGS[$n]#*$'\n'}"
		((_WS_LOGN[$n]--))
	}
	return 0
}

# _ws_glyph STATE -> _WS_G
_ws_glyph() {
	case "$1" in ok) _WS_G="●" ;; warn) _WS_G="▲" ;; *) _WS_G="✖" ;; esac
}

# _ws_event SVC GLYPH TEXT - newest event last, keeps the newest 100 (GLYPH "-" = the service's state glyph)
_ws_event() {
	local n="$1" g="$2"
	if [[ "$g" == - ]]; then
		_ws_glyph "${_WS_SVC[$n.state]}"
		g="$_WS_G"
	fi
	_ws_stamp
	printf -v _WS_LINE '%s %s %-13s %s' "${_WS_STAMP%:*}" "$g" "$n" "$3"
	_WS_EVENTS+=("$_WS_LINE")
	((${#_WS_EVENTS[@]} > 100)) && _WS_EVENTS=("${_WS_EVENTS[@]: -100}")
	return 0
}

# _ws_resolve ARG -> _WS_IDX : exact name or unique prefix (empty ARG = the selected service); 1 if unknown
_ws_resolve() {
	local a="$1" i hit=-1 cnt=0
	if [[ -z "$a" ]]; then
		_WS_IDX=$_WS_SEL
		return 0
	fi
	for i in "${!_WS_NAMES[@]}"; do
		[[ "${_WS_NAMES[i]}" == "$a" ]] && {
			_WS_IDX=$i
			return 0
		}
		[[ "${_WS_NAMES[i]}" == "$a"* ]] && {
			hit=$i
			((cnt++))
		}
	done
	((cnt == 1)) || return 1
	_WS_IDX=$hit
}

# ── host metrics: /proc via `read`, "n/a" when a file is missing ─────────────

_ws_host() {
	local a b c k v u total=0 avail=0 up
	_WS_LOAD="n/a" _WS_UP="n/a" _WS_MEMTXT="n/a" _WS_MEMPCT=0
	if [[ -r "$_WS_PROC/loadavg" ]]; then
		read -r a b c _ <"$_WS_PROC/loadavg" && _WS_LOAD="$a $b $c"
	fi
	if [[ -r "$_WS_PROC/uptime" ]]; then
		read -r up _ <"$_WS_PROC/uptime"
		up="${up%%.*}"
		if [[ "$up" =~ ^[0-9]+$ ]]; then
			printf -v _WS_UP '%dd %02dh %02dm' $((up / 86400)) $((up % 86400 / 3600)) $((up % 3600 / 60))
		fi
	fi
	if [[ -r "$_WS_PROC/meminfo" ]]; then
		while read -r k v u; do
			case "$k" in
				MemTotal:) total=$v ;;
				MemAvailable:)
					avail=$v
					break
					;;
			esac
		done <"$_WS_PROC/meminfo"
		if ((total > 0)); then
			local used=$((total - avail))
			_WS_MEMPCT=$((used * 100 / total))
			printf -v _WS_MEMTXT '%d.%d/%d.%d GiB' $((used / 1048576)) $((used * 10 / 1048576 % 10)) \
				$((total / 1048576)) $((total * 10 / 1048576 % 10))
		fi
	fi
	return 0
}

# ── UI refresh (every helper is a no-op when the page is not loaded) ──────────

_ws_ui() { [[ -n "${_TUI_W_TYPE[ws_list]:-}" ]]; }

_ws_say() { # TEXT [LEVEL]
	_WS_NOTE="$1"
	_ws_ui && tui.notify "$1" "${2:-info}"
	return 0
}

_ws_put() { # WIDGET TEXT - label update, only when it changed
	[[ "${_TUI_W_VALUE[$1]-}" == "$2" ]] || tui.update "$1" "$2"
}

_ws_list_items() {
	local -a items=()
	local n s mark
	for n in "${_WS_NAMES[@]}"; do
		s="${_WS_SVC[$n.state]}"
		_ws_glyph "$s"
		mark=""
		((_WS_SVC[$n.ack])) && mark="*"
		printf -v mark '%s %-13s %s%s' "$_WS_G" "$n" "$s" "$mark"
		items+=("$mark")
	done
	_WS_ITEMS=("${items[@]}")
}

_ws_refresh_list() {
	_ws_ui || return 0
	_ws_list_items
	tui.list.set ws_list "${_WS_ITEMS[@]}"
	tui.list.select ws_list "$_WS_SEL"
}

_ws_at_tail() { # PANE - true when the viewport shows the last line (or everything)
	tui.pane_size "$1"
	((${_TUI_P_SOFF_V[$1]:-0} + TUI_PANE_ROWS >= ${_TUI_P_LINES[$1]:-0}))
}

_ws_refresh_logs() {
	_ws_ui || return 0
	local n="${_WS_NAMES[_WS_SEL]}" tail=1
	_ws_at_tail logs || tail=0
	tui.pane_title logs "Logs · $n"
	tui.set_text logs "${_WS_LOGS[$n]}"
	((tail)) && tui.scroll.to logs bottom
	return 0
}

_ws_refresh_events() {
	_ws_ui || return 0
	local text tail=1
	_ws_at_tail events || tail=0
	printf -v text '%s\n' "${_WS_EVENTS[@]}"
	tui.set_text events "$text"
	((tail)) && tui.scroll.to events bottom
	return 0
}

_ws_refresh_details() {
	_ws_ui || return 0
	local n="${_WS_NAMES[_WS_SEL]}" s r ack
	s="${_WS_SVC[$n.state]}" ack=""
	((_WS_SVC[$n.ack])) && ack=" (ack)"
	_ws_put ws_d_load "load $_WS_LOAD"
	_ws_put ws_d_up "up    $_WS_UP"
	_ws_put ws_d_mem "mem   $_WS_MEMTXT"
	tui.progress.set ws_mem "$_WS_MEMPCT"
	_ws_glyph "$s"
	_ws_put ws_d_name "$_WS_G $n"
	_ws_put ws_d_state "state     $s${ack}"
	_ws_put ws_d_owner "owner     ${_WS_SVC[$n.owner]}"
	_ws_put ws_d_ver "version   ${_WS_SVC[$n.ver]}"
	_ws_put ws_d_rep "replicas  ${_WS_SVC[$n.rep]}"
	_ws_put ws_d_deploy "deployed  ${_WS_SVC[$n.deploy]}"
	_ws_put ws_d_err "errors    ${_WS_SVC[$n.err]}%"
	_ws_put ws_d_p95 "p95       ${_WS_SVC[$n.p95]} ms"
	r="met"
	[[ "$s" == ok ]] || r="at risk"
	[[ "$s" == down ]] && r="BREACHED"
	_ws_put ws_d_slo "SLO 99.9%  $r"
}

_ws_refresh_all() {
	_ws_refresh_list
	_ws_refresh_logs
	_ws_refresh_events
	_ws_refresh_details
}

# ── commands (simulated) ────────────────────────────────────────────────────

_ws_restart() { # IDX
	local n="${_WS_NAMES[$1]}" rep
	rep="${_WS_SVC[$n.rep]}"
	_WS_SVC[$n.state]=ok _WS_SVC[$n.ack]=0 _WS_SVC[$n.err]=0.1 _WS_SVC[$n.deploy]="just now"
	_WS_SVC[$n.rep]="${rep#*/}/${rep#*/}"
	[[ "${_WS_SVC[$n.p95]}" == 0 ]] && _WS_SVC[$n.p95]=35
	_ws_stamp
	printf -v _WS_LINE '\e[90m%s\e[0m \e[32mINFO \e[0m restart requested, draining connections' "$_WS_STAMP"
	_ws_logadd "$n" "$_WS_LINE"
	printf -v _WS_LINE '\e[90m%s\e[0m \e[32mINFO \e[0m ready, %s replicas healthy' "$_WS_STAMP" "${_WS_SVC[$n.rep]#*/}"
	_ws_logadd "$n" "$_WS_LINE"
	_ws_event "$n" ↻ "restarted ${_WS_SVC[$n.rep]} ready"
}

_ws_ack() { # IDX
	local n="${_WS_NAMES[$1]}"
	if [[ "${_WS_SVC[$n.state]}" == ok ]]; then
		_ws_say "$n is healthy, nothing to acknowledge" warn
		return 1
	fi
	_WS_SVC[$n.ack]=1
	_ws_event "$n" ✓ "acknowledged"
}

_ws_clear() { # IDX
	local n="${_WS_NAMES[$1]}"
	_WS_LOGS[$n]="" _WS_LOGN[$n]=0
}

# _ws_exec LINE - the command interpreter behind the prompt
_ws_exec() {
	local cmd arg rest
	read -r cmd arg rest <<<"$1"
	[[ -n "$cmd" ]] || return 0
	case "$cmd" in
		help)
			_ws_say "help | status | logs <svc> | restart <svc> | ack <svc> | clear" info
			return 0
			;;
		status)
			local n ok=0 warn=0 down=0
			for n in "${_WS_NAMES[@]}"; do
				case "${_WS_SVC[$n.state]}" in ok) ((ok++)) ;; warn) ((warn++)) ;; *) ((down++)) ;; esac
			done
			_ws_say "${#_WS_NAMES[@]} services: $ok ok, $warn warn, $down down" info
			return 0
			;;
		clear)
			_ws_clear "$_WS_SEL"
			_ws_say "cleared the log of ${_WS_NAMES[_WS_SEL]}" success
			_ws_refresh_logs
			return 0
			;;
		logs | restart | ack) ;;
		*)
			_ws_say "unknown command: $cmd (try help)" error
			return 1
			;;
	esac
	if ! _ws_resolve "$arg"; then
		_ws_say "unknown service: ${arg:-?} (try status)" error
		return 1
	fi
	local n="${_WS_NAMES[_WS_IDX]}"
	case "$cmd" in
		logs)
			_WS_SEL=$_WS_IDX
			_ws_event "$n" ▸ "viewing logs"
			_ws_say "showing logs of $n" info
			;;
		restart)
			_ws_restart "$_WS_IDX"
			_WS_SEL=$_WS_IDX
			_ws_say "restarted $n" success
			;;
		ack) _ws_ack "$_WS_IDX" && _ws_say "acknowledged $n" success ;;
	esac
	_ws_refresh_all
	return 0
}

# ── page actions ────────────────────────────────────────────────────────────

on_ws_submit() { # WIDGET TEXT
	tui.set ws_cmd ""
	_ws_exec "${2:-}"
	return 0
}

on_ws_select() { # the list moved
	tui.list.selected ws_list _WS_SEL
	((_WS_SEL < 0)) && _WS_SEL=0
	_ws_event "${_WS_NAMES[_WS_SEL]}" ▸ "inspecting"
	_ws_refresh_logs
	_ws_refresh_events
	_ws_refresh_details
}

on_ws_restart() {
	_ws_restart "$_WS_SEL"
	_ws_say "restarted ${_WS_NAMES[_WS_SEL]}" success
	_ws_refresh_all
}

on_ws_ack() {
	_ws_ack "$_WS_SEL" && _ws_say "acknowledged ${_WS_NAMES[_WS_SEL]}" success
	_ws_refresh_all
}

on_ws_clear() { _ws_exec clear; }

on_ws_focus_cmd() { tui.focus ws_cmd; }

# footer WHEN: the one-letter keys only work (and are only listed) while the prompt does not have the keyboard
_ws_not_typing() {
	local id="${_TUI_FOCUS_ID:-}"
	[[ -n "$id" ]] || return 0 # nothing focused (or a pane): not typing
	[[ "${_TUI_W_TYPE[$id]:-}" != input ]]
}

# every 2 s: a fresh line for the selected service, now and then one for another, and slow state drift
_ws_tick() {
	((++_WS_TICKS))
	_ws_logline "${_WS_NAMES[_WS_SEL]}"
	_ws_rand "${#_WS_NAMES[@]}"
	((_WS_R != _WS_SEL)) && _ws_logline "${_WS_NAMES[_WS_R]}"
	if ((_WS_TICKS % 9 == 0)); then
		_ws_rand "${#_WS_NAMES[@]}"
		local n="${_WS_NAMES[_WS_R]}"
		case "${_WS_SVC[$n.state]}" in
			warn)
				_WS_SVC[$n.state]=ok _WS_SVC[$n.ack]=0
				_ws_event "$n" ✓ "recovered, normal"
				;;
			ok)
				_WS_SVC[$n.state]=warn
				_ws_event "$n" - "latency above SLO"
				;;
		esac
		_ws_refresh_list
	fi
	_ws_refresh_logs
	_ws_refresh_events
	_ws_refresh_details
	return 0
}

on_ws_visit() {
	_ws_init
	_ws_host
	_ws_refresh_all
	tui.every 2 _ws_tick ws_tick_job
	tui.every 5 _ws_host ws_host_job
	tui.footer.add "r" "Restart" _ws_not_typing
	tui.footer.add "a" "Ack" _ws_not_typing
	tui.footer.add "c" "Clear" _ws_not_typing
	tui.footer.add "/" "Command" _ws_not_typing
	tui.focus ws_list
}
