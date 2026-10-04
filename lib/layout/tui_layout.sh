#!/usr/bin/env bash
# tui_layout.sh - the constraint/sizing engine behind pane splits (task 2A of
# docs/concepts/markup-v2-implementation-plan.md). Two things live here:
#
#   _tui.layout_resolve   turns one size token into a cell count.
#   _tui.layout_arrange   the measure/arrange pass for one split's children:
#                        largest-remainder fr distribution, min/max clamp
#                        with redistribution of space freed by a max.
#
# Units: N (cells), N% (of the available space), Nfr (share of the space left
# after fixed/%/auto children), auto (sizes to its min, content measurement
# isn't wired up until the 2B paint pipeline lands), fill (alias for 1fr),
# clamp(MIN,PREF,MAX) (each of MIN/PREF/MAX is itself one of the above,
# resolved recursively). fr weights may be decimal ("1.5fr"); internally
# they're scaled by 1000 into plain bash integers (only the first 3 decimal
# digits survive), the same scale a plain legacy integer weight gets when
# it shares a split with an "Nfr"/decimal sibling.
#
# Back-compat: a split whose children are ALL plain integers (today's
# `weight="N"`) and whose parent has no gap keeps the exact old arithmetic
# (_tui._layout_r's inline loop) - last child absorbs the rounding
# remainder, no min enforcement, max clamps in place with no redistribution.
# That old behaviour is pinned down in golden frames (G4) for every
# share/demo/*.xml page; nothing here is allowed to change it. Only a
# child using new unit syntax, or a gap, switches a split over to the new
# engine below.
#
# Memoization: every mutation that can change a pane's computed rect (splits,
# gap, pad, min/max) bumps one global generation counter. A pane's cached
# rect is reused when its own (row,col,h,w) and the generation are both
# unchanged - i.e. "nothing was touched since the last layout pass", which is
# exactly the resize-relayout bench's scenario (repeated relayout of an
# unchanged tree). It is coarser than per-subtree dirty tracking (any
# mutation anywhere invalidates the whole cache) but never stale, and needs
# no parent-pointer bookkeeping.
# requires:

declare -g _TUI_LY_GEN=0
declare -gA _TUI_LY_KEY=() _TUI_LY_GEN_AT=()

# _tui.layout_cache_hit P - true and skips nothing itself; caller
# (_tui._layout_r) does the skipping. Sets nothing on a miss beyond
# recording the new key/generation, so a miss always falls through to a
# real recompute.
_tui.layout_cache_hit() {
	local p="$1" key="$2"
	if [[ "${_TUI_LY_GEN_AT[$p]:-}" == "$_TUI_LY_GEN" && "${_TUI_LY_KEY[$p]:-}" == "$key" ]]; then
		_tui_perf.count layout_memo_hit
		return 0
	fi
	_tui_perf.count layout_memo_miss
	_TUI_LY_KEY[$p]="$key"
	_TUI_LY_GEN_AT[$p]=$_TUI_LY_GEN
	return 1
}

# _tui.layout_resolve SPEC AVAIL -> $_LY_R (cells, >= 0). Fork-free.
_tui.layout_resolve() {
	local spec="$1" avail="${2:-0}"
	if [[ "$spec" == clamp\(*\) ]]; then
		local body="${spec#clamp(}"
		body="${body%)}"
		local a="${body%%,*}" rest="${body#*,}"
		local b="${rest%%,*}" c="${rest#*,}"
		a="${a// /}"
		b="${b// /}"
		c="${c// /}"
		local mn pref mx
		_tui.layout_resolve "$a" "$avail"
		mn=$_LY_R
		_tui.layout_resolve "$b" "$avail"
		pref=$_LY_R
		_tui.layout_resolve "$c" "$avail"
		mx=$_LY_R
		((pref < mn)) && pref=$mn
		((pref > mx)) && pref=$mx
		_LY_R=$pref
	elif [[ "$spec" =~ ^[0-9]+%$ ]]; then
		_LY_R=$((avail * ${spec%\%} / 100))
	elif [[ "$spec" == auto || "$spec" == fill || "$spec" =~ ^[0-9]+(\.[0-9]+)?fr$ ]]; then
		_LY_R=$avail
	elif [[ "$spec" =~ ^-?[0-9]+$ ]]; then
		_LY_R=$spec
	else
		_LY_R=0
	fi
	((_LY_R < 0)) && _LY_R=0
}

# _tui.layout_fr_weight SPEC -> $_LY_R, an integer weight scaled by 1000 so
# a decimal fr value (e.g. "1.5fr") keeps its ratio in bash's integer
# arithmetic without floating point (only the first 3 decimal digits
# survive the scale). Every fr-kind spec in a split - plain integer
# (legacy), "Nfr", "N.Mfr", auto/fill - goes through this same scale, so
# mixing them in one split stays correct.
_tui.layout_fr_weight() {
	local spec="$1"
	if [[ "$spec" =~ ^([0-9]+)\.([0-9]+)fr$ ]]; then
		local ip="${BASH_REMATCH[1]}" fp="${BASH_REMATCH[2]}000"
		_LY_R=$((ip * 1000 + 10#${fp:0:3}))
	elif [[ "$spec" =~ ^([0-9]+)fr$ ]]; then
		_LY_R=$((${BASH_REMATCH[1]} * 1000))
	elif [[ "$spec" =~ ^[0-9]+$ ]]; then
		_LY_R=$((spec * 1000))
	else
		_LY_R=1000 # auto / fill
	fi
}

# _tui.layout_child_kind SPEC MIN MAX AVAIL -> sets _LY_KIND (fixed|fr),
# _LY_CELLS (fixed only), _LY_WEIGHT (fr only), _LY_MIN, _LY_MAX (fr only;
# -1 = no bound). A plain integer is legacy-compatible: it means fr weight,
# same as "Nfr", matching "weight maps to fr" in the roadmap.
_tui.layout_child_kind() {
	local spec="$1" minspec="$2" maxspec="$3" avail="$4"
	if [[ "$spec" == clamp\(*\) ]]; then
		local body="${spec#clamp(}"
		body="${body%)}"
		local pref="${body#*,}"
		pref="${pref%%,*}"
		pref="${pref// /}"
		if [[ "$pref" == auto || "$pref" == fill || "$pref" =~ ^[0-9]+(\.[0-9]+)?fr$ ]]; then
			_LY_KIND=fr
			_tui.layout_fr_weight "$pref"
			_LY_WEIGHT=$_LY_R
			local body2="${spec#clamp(}"
			body2="${body2%)}"
			local mn="${body2%%,*}" rest="${body2#*,}"
			local mx="${rest#*,}"
			mn="${mn// /}"
			mx="${mx// /}"
			_tui.layout_resolve "$mn" "$avail"
			_LY_MIN=$_LY_R
			_tui.layout_resolve "$mx" "$avail"
			_LY_MAX=$_LY_R
			return
		fi
		_tui.layout_resolve "$spec" "$avail"
		_LY_KIND=fixed
		_LY_CELLS=$_LY_R
		return
	fi
	if [[ "$spec" == auto || "$spec" == fill || "$spec" =~ ^[0-9]+(\.[0-9]+)?fr$ || "$spec" =~ ^[0-9]+$ ]]; then
		_LY_KIND=fr
		_tui.layout_fr_weight "$spec"
		_LY_WEIGHT=$_LY_R
		_LY_MIN=-1
		_LY_MAX=-1
		if [[ -n "$minspec" ]]; then
			_tui.layout_resolve "$minspec" "$avail"
			_LY_MIN=$_LY_R
		fi
		if [[ -n "$maxspec" ]]; then
			_tui.layout_resolve "$maxspec" "$avail"
			_LY_MAX=$_LY_R
		fi
		return
	fi
	_tui.layout_resolve "$spec" "$avail"
	_LY_KIND=fixed
	_LY_CELLS=$_LY_R
}

# _tui.layout_arrange AVAIL GAP - the new-engine measure/arrange pass for one
# split's children. Caller sets three parallel global arrays first: _LY_SPECS
# (size token per child), _LY_MINS, _LY_MAXS (min/max token per child, or
# empty). Writes the result into _LY_SIZES (parallel array, cells per
# child) - the same in/out-via-globals convention _tui._widget_pos uses,
# so this stays fork-free.
declare -ga _LY_SPECS=() _LY_MINS=() _LY_MAXS=() _LY_SIZES=()
_tui.layout_arrange() {
	local avail="$1" gap="${2:-0}"
	local n=${#_LY_SPECS[@]}
	_LY_SIZES=()
	((n == 0)) && return
	local usable=$((avail - gap * (n - 1)))
	((usable < 0)) && usable=0

	# Fast path: every child is a plain integer weight (today's common case -
	# a legacy weight="N" split, or new syntax that never used a unit token),
	# no per-child min/max, no gap. Skips the fr-scaling + largest-remainder +
	# clamp-redistribution machinery below and does the old direct division
	# instead - measured ~2.6x faster on the resize_relayout bench
	# (tools/bench/run.sh), which is what caught this: G3 failed without it.
	if ((gap == 0)); then
		local _fp=1 _fi _fs
		for ((_fi = 0; _fi < n; _fi++)); do
			_fs="${_LY_SPECS[$_fi]}"
			# glob, not regex: a bash =~ match measurably costs more per call
			# than a glob test, and this runs on every split every layout pass.
			[[ -n "$_fs" && "$_fs" != *[!0-9]* && -z "${_LY_MINS[$_fi]:-}" && -z "${_LY_MAXS[$_fi]:-}" ]] || {
				_fp=0
				break
			}
		done
		if ((_fp)); then
			local total=0
			for ((_fi = 0; _fi < n; _fi++)); do ((total += _LY_SPECS[_fi])); done
			((total == 0)) && total=n
			local _fp_offset=0
			for ((_fi = 0; _fi < n; _fi++)); do
				if ((_fi == n - 1)); then
					_LY_SIZES[_fi]=$((usable - _fp_offset))
				else
					_LY_SIZES[_fi]=$((usable * _LY_SPECS[_fi] / total))
					((_fp_offset += _LY_SIZES[_fi]))
				fi
			done
			return
		fi
	fi

	local -a kind=() cells=() weight=() cmin=() cmax=()
	local i fixed_total=0
	for ((i = 0; i < n; i++)); do
		_tui.layout_child_kind "${_LY_SPECS[$i]}" "${_LY_MINS[$i]:-}" "${_LY_MAXS[$i]:-}" "$usable"
		kind[i]=$_LY_KIND
		if [[ "$_LY_KIND" == fixed ]]; then
			cells[i]=$_LY_CELLS
			((fixed_total += _LY_CELLS))
		else
			weight[i]=$_LY_WEIGHT
			cmin[i]=$_LY_MIN
			cmax[i]=$_LY_MAX
			cells[i]=0
		fi
	done

	local remaining=$((usable - fixed_total))
	((remaining < 0)) && remaining=0

	# Active fr children (not yet max-clamped); loop redistributes space
	# freed by a max clamp until no more children get clamped, bounded by n
	# iterations (at most one child leaves the active set per pass).
	local -a active=()
	for ((i = 0; i < n; i++)); do [[ "${kind[$i]}" == fr ]] && active+=("$i"); done

	local pass
	for ((pass = 0; pass < n + 1 && ${#active[@]} > 0; pass++)); do
		local total_w=0 j
		for j in "${active[@]}"; do ((total_w += weight[j])); done
		((total_w == 0)) && break

		local -a base=() rem=()
		local sum=0
		for j in "${active[@]}"; do
			local exact=$((remaining * weight[j]))
			base[j]=$((exact / total_w))
			rem[j]=$((exact % total_w))
			((sum += base[j]))
		done
		local leftover=$((remaining - sum))
		# Largest-remainder: hand leftover cells one at a time to the
		# active child with the largest fractional remainder (ties -> the
		# lowest index, since `active` is built in index order).
		while ((leftover > 0)); do
			local best=-1 best_rem=-1
			for j in "${active[@]}"; do
				if ((rem[j] > best_rem)); then
					best_rem=${rem[j]}
					best=$j
				fi
			done
			((best < 0)) && break
			((base[best]++))
			rem[best]=-1
			((leftover--))
		done
		for j in "${active[@]}"; do cells[j]=${base[j]}; done

		# Any active child now over its max? Clamp it, free the excess back
		# into `remaining`, drop it from `active`, and redistribute on the
		# next pass. Only one clamp is applied per pass so freed space is
		# never double-counted.
		local clamped=-1
		for j in "${active[@]}"; do
			if ((cmax[j] >= 0 && cells[j] > cmax[j])); then
				clamped=$j
				break
			fi
		done
		((clamped < 0)) && break
		# clamped's computed share (part of `remaining`) drops to cmax; the
		# difference re-enters `remaining` for the still-active children on
		# the next pass, which is exactly "space freed by max is
		# redistributed".
		cells[clamped]=${cmax[clamped]}
		((remaining -= cmax[clamped]))
		local -a next_active=()
		for j in "${active[@]}"; do [[ "$j" != "$clamped" ]] && next_active+=("$j"); done
		active=("${next_active[@]}")
	done

	# min is honoured for fr children only (new syntax opts in to real
	# enforcement; legacy min_width/min_height stay advisory-only, feeding
	# the "too small" warning as before - see the module comment).
	for ((i = 0; i < n; i++)); do
		if [[ "${kind[$i]}" == fr && ${cmin[$i]:--1} -ge 0 ]] && ((cells[i] < cmin[i])); then
			cells[i]=${cmin[i]}
		fi
	done

	_LY_SIZES=("${cells[@]}")
}
