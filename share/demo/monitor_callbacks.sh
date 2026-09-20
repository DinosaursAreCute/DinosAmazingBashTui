#!/usr/bin/env bash
# monitor_callbacks.sh - a live, btop-flavored system-monitoring dashboard.
# One quadrant pane per chart shape, each metric independently toggleable
# from the controls row, refresh interval configurable from the same row:
#   cpu_pane   → vbar        per-core CPU usage, tallest column = busiest core
#   mem_pane   → gauge + kv  RAM used/cache/free breakdown, plus swap gauge
#   load_pane  → linechart   1-minute load average, live history vs. nproc*100
#   disk_pane  → hbar+spark  usage % per real mount, plus aggregate disk I/O
#
# Every chart call below is sized from the pane's *actual* rendered content
# area (tui.content_area) rather than guessed constants, and every chart is
# given a fixed -m/-n scale plus a fixed size flag (-tw/-cw/-w/-lw) so it
# renders at exactly the same footprint on every refresh and never trips
# the framework's automatic content-fit warning (docs/guide/markup.md,
# "Automatic content-fit checking").

tui.require terminal_renderer

# ── Config, controlled live from the controls row ───────────────────────
declare -g _MON_ENABLED_CPU=1 _MON_ENABLED_MEM=1 _MON_ENABLED_LOAD=1 _MON_ENABLED_DISK=1
declare -g _MON_TICK_COUNT=0
declare -g _MON_REFRESH_EVERY_TICKS=20   # ≈1s at the default 0.05s poll timeout
declare -g _MON_NPROC; _MON_NPROC="$(nproc 2>/dev/null || echo 1)"

# Canonical pane order (matches monitor.xml's original 2x2) and the
# title/border each carries - tui.grid resets both on every pane it
# (re)creates, "grid"'s own row/cell wrappers included, so a disabled
# pane's title/border have to be reapplied by hand after each rebuild.
declare -ga _MON_PANE_ORDER=(cpu_pane mem_pane load_pane disk_pane)
declare -gA _MON_PANE_TITLE=(
    [cpu_pane]="CPU Cores - vbar"
    [mem_pane]="Memory - gauge"
    [load_pane]="Load Average - linechart"
    [disk_pane]="Disk Usage & I/O - hbar"
)

# Rolling history, oldest first - real live samples, not synthetic data.
declare -ga _MON_LOAD_HISTORY=()
declare -ga _MON_IO_READ_HISTORY=()
declare -ga _MON_IO_WRITE_HISTORY=()
_MON_HISTORY_MAX=60

# Deltas need a previous snapshot to diff against.
declare -gA _MON_PREV_CPU_TOTAL=() _MON_PREV_CPU_IDLE=()
declare -g  _MON_PREV_IO_TS=0 _MON_PREV_IO_READ_SECT=0 _MON_PREV_IO_WRITE_SECT=0

# Render an already-built content string into a pane, trimmed to the
# pane's real height first. Every chart below is already width-correct by
# construction (sized from tui.content_area), but an over-height buffer
# would otherwise trip content-fit checking and show a "min space" warning
# instead of the chart.
_mon_output_fit() {
    local pane="$1" content="$2"
    local cah caw
    tui.pane_size "$pane"; cah=$TUI_PANE_ROWS; caw=$TUI_PANE_COLS
    local -a lines=()
    mapfile -t lines <<< "$content"
    (( cah < 0 )) && cah=0
    if (( ${#lines[@]} > cah )); then
        lines=("${lines[@]:0:cah}")
    fi
    tui.output "$pane" "$(printf '%s\n' "${lines[@]}")"
}

# Re-lay the 2x2 "grid" pane to include only the currently-enabled
# metrics, dropping disabled ones entirely (their cell disappears and the
# survivors stretch to fill the freed space) rather than leaving an empty
# or "disabled" box behind. tui.grid auto-sizes rows/cols from however
# many names it's given (docs/guide/grid-layouts-and-tabs.md), so 3 active
# panes lay out as a 2+1 row, 2 as a 1x2 row, 1 as the full area.
_mon_rebuild_grid() {
    local -a active=()
    local p enabled
    for p in "${_MON_PANE_ORDER[@]}"; do
        case "$p" in
            cpu_pane)  enabled=$_MON_ENABLED_CPU ;;
            mem_pane)  enabled=$_MON_ENABLED_MEM ;;
            load_pane) enabled=$_MON_ENABLED_LOAD ;;
            disk_pane) enabled=$_MON_ENABLED_DISK ;;
        esac
        if (( enabled )); then
            active+=("$p")
        else
            tui.output_clear "$p"
        fi
    done

    tui.grid "grid" "" "" "stretch" "" "" "${active[@]}"

    # tui.grid's own tui.hsplit/vsplit calls reset every pane they touch
    # (including survivors) to border="single" title="" - put this
    # dashboard's heavy border and chart title back on each active cell.
    for p in "${active[@]}"; do
        tui.pane_title "$p" "${_MON_PANE_TITLE[$p]}"
        _TUI_P_BORDER[$p]="heavy"
    done
}

# Kilobytes → gigabytes with one decimal place, used by the memory panel.
_mon_kb_to_gb_v() { local t=$(( ($1 * 10 + 524288) / 1048576 )); _MG="$(( t / 10 )).$(( t % 10 ))"; }
_mon_kb_to_gb() { _mon_kb_to_gb_v "$1"; printf '%s' "$_MG"; }


# Usage-percentage → color name. High = bad for a usage metric (unlike
# gauge's own built-in default, which assumes high = good), so every call
# below passes an explicit color rather than relying on gauge's threshold.
_mon_color_v() { if (( $1 >= 85 )); then _MC=RED; elif (( $1 >= 60 )); then _MC=YELLOW; else _MC=GREEN; fi; }
_mon_color_for_pct() {
    local pct="$1"
    if (( pct >= 85 )); then printf 'RED'
    elif (( pct >= 60 )); then printf 'YELLOW'
    else printf 'GREEN'
    fi
}

# ── CPU: per-core usage → vbar, fixed 0-100 scale, fills pane width ─────
_mon_refresh_cpu() {
    # The pane itself is removed from the grid by _mon_rebuild_grid when
    # disabled, so there's nothing to draw - just bail rather than writing
    # to a pane id that no longer has a place on screen.
    (( _MON_ENABLED_CPU )) || return

    local cah caw
    tui.pane_size cpu_pane; cah=$TUI_PANE_ROWS; caw=$TUI_PANE_COLS

    local -a labels=() colors=()
    local line label u n s idle iw irq sirq steal rest

    while read -r line; do
        read -r label u n s idle iw irq sirq steal rest <<< "$line"
        [[ "$label" == cpu[0-9]* ]] || continue

        local total_idle=$(( idle + iw ))
        local total=$(( u + n + s + idle + iw + irq + sirq + steal ))

        local pct=0
        local prev_total="${_MON_PREV_CPU_TOTAL[$label]:-}"
        local prev_idle="${_MON_PREV_CPU_IDLE[$label]:-}"
        if [[ -n "$prev_total" ]]; then
            local dtotal=$(( total - prev_total ))
            local didle=$(( total_idle - prev_idle ))
            (( dtotal > 0 )) && pct=$(( (dtotal - didle) * 100 / dtotal ))
        fi
        (( pct < 0 )) && pct=0
        (( pct > 100 )) && pct=100

        _MON_PREV_CPU_TOTAL[$label]="$total"
        _MON_PREV_CPU_IDLE[$label]="$total_idle"

        labels+=("C${label#cpu}:${pct}")
        _mon_color_v "$pct"; colors+=("$_MC")
    done < /proc/stat

    # Fixed 4-char columns (fits "C10"/"100"); show as many cores as the
    # pane's actual width allows rather than a hardcoded count.
    local col_width=4
    local max_cores=$(( (caw + 1) / (col_width + 1) ))
    (( max_cores < 1 )) && max_cores=1
    if (( ${#labels[@]} > max_cores )); then
        labels=("${labels[@]:0:max_cores}")
        colors=("${colors[@]:0:max_cores}")
    fi

    # 3 rows reserved below the columns: baseline, label row, value row.
    local vh=$(( cah - 3 ))
    (( vh < 2 )) && vh=2

    local color_arg; color_arg="$(IFS=,; printf '%s' "${colors[*]}")"
    local out; out="$(vbar_string -h "$vh" -m 100 -n 0 -cw "$col_width" -c "$color_arg" "${labels[@]}")"
    local _out_b; printf -v _out_b '%b' "$out"; _mon_output_fit "cpu_pane" "$_out_b"
}

# ── Memory: used/cache/free breakdown + swap, btop-style ────────────────
_mon_refresh_mem() {
    (( _MON_ENABLED_MEM )) || return

    local cah caw
    tui.pane_size mem_pane; cah=$TUI_PANE_ROWS; caw=$TUI_PANE_COLS

    local total avail buffers cached sreclaim shmem swap_total swap_free
    local _k _v _
    total=0; avail=0; buffers=0; cached=0; sreclaim=0; shmem=0; swap_total=0; swap_free=0
    while read -r _k _v _; do            # /proc/meminfo, one pass, no awk
        case "$_k" in
            MemTotal:) total=$_v ;; MemAvailable:) avail=$_v ;; Buffers:) buffers=$_v ;; Cached:) cached=$_v ;;
            SReclaimable:) sreclaim=$_v ;; Shmem:) shmem=$_v ;; SwapTotal:) swap_total=$_v ;; SwapFree:) swap_free=$_v ;;
        esac
    done < /proc/meminfo
    [[ -z "$total" || "$total" -eq 0 ]] && return

    local cache_buff=$(( buffers + cached + sreclaim - shmem ))
    (( cache_buff < 0 )) && cache_buff=0
    local used=$(( total - avail ))
    (( used < 0 )) && used=0
    local shown_free=$(( total - used - cache_buff ))
    (( shown_free < 0 )) && shown_free=0

    local used_pct=$(( used * 100 / total ))
    local used_color; _mon_color_v "$used_pct"; used_color="$_MC"

    # Gauge line length is label_width + gauge_width + 8 (brackets/spacing/
    # pct field) - solve for gauge_width first, and only if that leaves no
    # room at all (a very small quadrant) shrink the label column instead,
    # so the line still fits caw rather than overflowing it.
    local label_width=6
    local gauge_width=$(( caw - label_width - 8 ))
    if (( gauge_width < 4 )); then
        label_width=$(( caw - 8 - 4 ))
        (( label_width < 2 )) && label_width=2
        gauge_width=$(( caw - label_width - 8 ))
        (( gauge_width < 1 )) && gauge_width=1
    fi

    local used_gb cache_gb free_gb total_gb
    _mon_kb_to_gb_v "$used"; used_gb="$_MG"; _mon_kb_to_gb_v "$cache_buff"; cache_gb="$_MG"
    _mon_kb_to_gb_v "$shown_free"; free_gb="$_MG"; _mon_kb_to_gb_v "$total"; total_gb="$_MG"

    local breakdown="  U:${used_gb}G C:${cache_gb}G F:${free_gb}G T:${total_gb}G"
    (( ${#breakdown} > caw )) && breakdown="${breakdown:0:caw}"

    local out=""
    out+="\n"
    out+="$(gauge_string -l "RAM" -lw "$label_width" -w "$gauge_width" -c "$used_color" "$used_pct")\n\n"
    out+="${breakdown}\n\n"

    if [[ -n "$swap_total" && "$swap_total" -gt 0 ]]; then
        local swap_used=$(( swap_total - swap_free ))
        local swap_pct=$(( swap_used * 100 / swap_total ))
        local swap_color; _mon_color_v "$swap_pct"; swap_color="$_MC"
        out+="$(gauge_string -l "Swap" -lw "$label_width" -w "$gauge_width" -c "$swap_color" "$swap_pct")"
    else
        out+="  Swap: not configured"
    fi

    local _out_b; printf -v _out_b '%b' "$out"; _mon_output_fit "mem_pane" "$_out_b"
}

# ── Load average: live history → linechart, scaled against nproc ────────
_mon_refresh_load() {
    (( _MON_ENABLED_LOAD )) || return

    local cah caw
    tui.pane_size load_pane; cah=$TUI_PANE_ROWS; caw=$TUI_PANE_COLS

    local load1 _; read -r load1 _ < /proc/loadavg
    # /proc/loadavg is a float ("0.42") - chart arithmetic is integer-only,
    # so track it in hundredths and label the axis in those units.
    local load_centi="${load1/./}"
    [[ "$load1" != *.* ]] && load_centi="${load1}00"
    load_centi=$((10#$load_centi))

    _MON_LOAD_HISTORY+=("$load_centi")
    if (( ${#_MON_LOAD_HISTORY[@]} > _MON_HISTORY_MAX )); then
        _MON_LOAD_HISTORY=("${_MON_LOAD_HISTORY[@]: -${_MON_HISTORY_MAX}}")
    fi

    # 3 rows reserved: axis line, legend, "current" readout.
    local lh=$(( cah - 3 ))
    (( lh < 3 )) && lh=3
    # y-axis label column eats a few chars; load_max is at most 5 digits
    # (nproc*100, e.g. "3200"), so reserve 4 and leave the rest for the plot.
    local plot_w=$(( caw - 6 ))
    (( plot_w < 4 )) && plot_w=4

    local load_max=$(( _MON_NPROC * 100 ))
    local series; series="$(IFS=,; printf '%s' "${_MON_LOAD_HISTORY[*]}")"
    local out; out="$(linechart_string -h "$lh" -w "$plot_w" -n 0 -m "$load_max" -c "BRIGHT_CYAN" "Load x100:${series}")"

    local current_line="  current: ${load1} (${_MON_NPROC} cores)"
    (( ${#current_line} > caw )) && current_line="${current_line:0:caw}"
    out+="\n${current_line}"
    local _out_b; printf -v _out_b '%b' "$out"; _mon_output_fit "load_pane" "$_out_b"
}

# ── Disk: usage % per real mount → hbar, plus aggregate I/O → sparklines ─
_mon_refresh_disk() {
    (( _MON_ENABLED_DISK )) || return

    local cah caw
    tui.pane_size disk_pane; cah=$TUI_PANE_ROWS; caw=$TUI_PANE_COLS

    # -- I/O throughput: aggregate sectors across whole-disk devices only,
    #    skipping partitions and virtual devices so nothing is double-counted.
    local now_ts; now_ts="$(date +%s)"
    local read_sect=0 write_sect=0
    local dline dname dreads dsect_r dwrites dsect_w drest
    while read -r dline; do
        read -r _ _ dname dreads _ dsect_r _ dwrites _ dsect_w drest <<< "$dline"
        [[ "$dname" =~ ^(loop|ram|dm-|zram|sr) ]] && continue
        [[ "$dname" =~ ^(sd|vd|xvd)[a-z]+[0-9]+$ ]] && continue
        [[ "$dname" =~ ^nvme[0-9]+n[0-9]+p[0-9]+$ ]] && continue
        read_sect=$(( read_sect + dsect_r ))
        write_sect=$(( write_sect + dsect_w ))
    done < /proc/diskstats

    local read_kbps=0 write_kbps=0
    if (( _MON_PREV_IO_TS > 0 )); then
        local elapsed=$(( now_ts - _MON_PREV_IO_TS ))
        if (( elapsed > 0 )); then
            read_kbps=$(( (read_sect - _MON_PREV_IO_READ_SECT) * 512 / 1024 / elapsed ))
            write_kbps=$(( (write_sect - _MON_PREV_IO_WRITE_SECT) * 512 / 1024 / elapsed ))
            (( read_kbps < 0 )) && read_kbps=0
            (( write_kbps < 0 )) && write_kbps=0
        fi
    fi
    _MON_PREV_IO_TS=$now_ts
    _MON_PREV_IO_READ_SECT=$read_sect
    _MON_PREV_IO_WRITE_SECT=$write_sect

    _MON_IO_READ_HISTORY+=("$read_kbps")
    _MON_IO_WRITE_HISTORY+=("$write_kbps")
    if (( ${#_MON_IO_READ_HISTORY[@]} > _MON_HISTORY_MAX )); then
        _MON_IO_READ_HISTORY=("${_MON_IO_READ_HISTORY[@]: -${_MON_HISTORY_MAX}}")
        _MON_IO_WRITE_HISTORY=("${_MON_IO_WRITE_HISTORY[@]: -${_MON_HISTORY_MAX}}")
    fi

    # -- Disk usage per real mount, deduped by device (btrfs subvolumes
    #    otherwise all report the same device + Use% under different paths).
    local -a entries=() colors=()
    local -A seen_device=()
    local line device pct target label

    while read -r line; do
        device="${line%%$'\x01'*}"
        line="${line#*$'\x01'}"
        pct="${line%%$'\x01'*}"
        target="${line#*$'\x01'}"
        pct="${pct%\%}"

        [[ -n "${seen_device[$device]:-}" ]] && continue
        seen_device[$device]=1

        label="$target"
        [[ "$label" == "/" ]] && label="root"
        label="${label##*/}"
        [[ -z "$label" ]] && label="root"

        entries+=("${label}:${pct}")
        _mon_color_v "$pct"; colors+=("$_MC")
    done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
                | tail -n +2 \
                | awk '{print $1"\x01"$5"\x01"$6}')

    # Reserve 4 rows for the I/O section (blank separator + read/write
    # sparkline lines + nothing else); the rest goes to disk usage bars.
    local io_rows=3
    local hbar_rows=$(( cah - io_rows ))
    (( hbar_rows < 1 )) && hbar_rows=1
    if (( ${#entries[@]} > hbar_rows )); then
        entries=("${entries[@]:0:hbar_rows}")
        colors=("${colors[@]:0:hbar_rows}")
    fi

    local out=""
    if (( ${#entries[@]} > 0 )); then
        # Line length is label_width + bar_w + 2 (spaces) + value_reserve.
        # Same degrade-the-label-first approach as the memory gauge, so a
        # narrow quadrant still fits rather than overflowing caw.
        local label_width=10
        local value_reserve=4
        local bar_w=$(( caw - label_width - 2 - value_reserve ))
        if (( bar_w < 4 )); then
            label_width=$(( caw - 2 - value_reserve - 4 ))
            (( label_width < 3 )) && label_width=3
            bar_w=$(( caw - label_width - 2 - value_reserve ))
            (( bar_w < 1 )) && bar_w=1
        fi
        local color_arg; color_arg="$(IFS=,; printf '%s' "${colors[*]}")"
        out+="$(hbar_string -m 100 -n 0 -w "$bar_w" -lw "$label_width" -c "$color_arg" "${entries[@]}")\n"
    fi

    local spark_w=$(( caw - 14 ))
    (( spark_w < 5 )) && spark_w=5
    local read_series="${_MON_IO_READ_HISTORY[*]:-0}"
    local write_series="${_MON_IO_WRITE_HISTORY[*]:-0}"
    out+="$(printf 'R %-6s %s' "${read_kbps}K/s" "$(sparkline_string -w "$spark_w" -c GREEN "$read_series")")\n"
    out+="$(printf 'W %-6s %s' "${write_kbps}K/s" "$(sparkline_string -w "$spark_w" -c YELLOW "$write_series")")"

    local _out_b; printf -v _out_b '%b' "$out"; _mon_output_fit "disk_pane" "$_out_b"
}

_mon_refresh_all() {
    _mon_refresh_cpu
    _mon_refresh_mem
    _mon_refresh_load
    _mon_refresh_disk

    local interval_s
    interval_s="$(awk -v t="$_MON_REFRESH_EVERY_TICKS" -v p="${TUI_INPUT_POLL_TIMEOUT:-0.05}" 'BEGIN{printf "%.2g", t*p}')"
    _TUI_W_LABEL[lbl_mon_stamp]="Last refreshed: $(date +%H:%M:%S)  (every ${interval_s}s)"
    (( _TUI_RUNNING )) && _tui._queue_render "header"
}

# ── Controls: toggles + interval, wired from monitor.xml ────────────────
# Toggling off rebuilds the 2x2 grid without that pane (its cell
# disappears and the remaining panes stretch to fill the space); toggling
# back on rebuilds it back in, then refreshes its content now that
# tui.content_area for it reflects the new, correct geometry.
on_monitor_toggle_cpu() {
    _MON_ENABLED_CPU="$1"
    _mon_rebuild_grid
    (( _MON_ENABLED_CPU )) && _mon_refresh_cpu
    (( _TUI_RUNNING )) && tui.render
}
on_monitor_toggle_mem() {
    _MON_ENABLED_MEM="$1"
    _mon_rebuild_grid
    (( _MON_ENABLED_MEM )) && _mon_refresh_mem
    (( _TUI_RUNNING )) && tui.render
}
on_monitor_toggle_load() {
    _MON_ENABLED_LOAD="$1"
    _mon_rebuild_grid
    (( _MON_ENABLED_LOAD )) && _mon_refresh_load
    (( _TUI_RUNNING )) && tui.render
}
on_monitor_toggle_disk() {
    _MON_ENABLED_DISK="$1"
    _mon_rebuild_grid
    (( _MON_ENABLED_DISK )) && _mon_refresh_disk
    (( _TUI_RUNNING )) && tui.render
}

on_monitor_set_interval() {
    local value="$1"
    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        value=1
    fi
    local ticks
    ticks="$(awk -v s="$value" -v p="${TUI_INPUT_POLL_TIMEOUT:-0.05}" \
        'BEGIN{t=int(s/p+0.5); if (t<1) t=1; print t}')"
    _MON_REFRESH_EVERY_TICKS=$ticks
    _MON_TICK_COUNT=0
    tui.set "inp_mon_interval" "$value"
    _TUI_W_LABEL[lbl_mon_stamp]="Interval set to ${value}s - refreshed $(date +%H:%M:%S)"
    (( _TUI_RUNNING )) && _tui._queue_render "header"
}

on_monitor_refresh() {
    _mon_refresh_all
}

_mon_tick() {
    (( _MON_TICK_COUNT++ ))
    (( _MON_TICK_COUNT % _MON_REFRESH_EVERY_TICKS == 0 )) && _mon_refresh_all
}
_TUI_TICK_FN="_mon_tick"

# Prime all four panes once the page is laid out (on_visit runs after final layout).
on_monitor_visit() { _mon_refresh_all; }

