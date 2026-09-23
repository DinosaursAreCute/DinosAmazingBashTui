#!/usr/bin/env bash
# tui_sync.sh - the file-sync engine behind the installer and the updater. Pure bash + sha256sum/shasum/openssl + cp/find/mkdir;
# no TUI, no network - it only compares two folders and applies the difference, so it is easy to test and to reuse.
#
# TWO KINDS OF FILES
#   PROGRAM files (the code): lib/ bin/ share/ docs/ examples/ VERSION README.md CHANGELOG.md LICENSE  ->  $PREFIX/
#       Nobody edits these, they are replaced by whatever the new release holds (a copy of the old one is kept in backups/).
#   CONFIG files (what you may edit): share/defaults/** -> $CONFIG/defaults/**   and   share/plugins/* -> $CONFIG/plugins/*
#       Compared three ways: BASE (the checksum recorded when DABT last wrote the file, in $CONFIG/manifest), MINE (the file
#       now) and NEW (the release). Per file:
#           not there                       ADD       write it
#           MINE == NEW                     SAME      nothing to do
#           MINE == BASE (untouched)        UPDATE    overwrite with NEW
#           NEW == BASE (only you changed)  KEEP      leave yours alone
#           all three differ (or no BASE)   CONFLICT  you choose: override (take NEW) | skip (keep mine) | new (write NEW as FILE.new)
#       Files the release dropped: REMOVE when untouched, ORPHAN (left in place, reported) when you changed them.
#
#   tui.sync.plan SRC CONFIG            -> TUI_SYNC_ADD/UPDATE/SAME/KEEP/CONFLICT/REMOVE/ORPHAN (arrays of CONFIG-relative paths)
#   tui.sync.apply SRC CONFIG [RESOLVER]  apply the plan. RESOLVER REL prints override|skip|new for a conflict; without one the
#                                       TUI_SYNC_POLICY (override|skip|new, default new) decides. Backs up what it replaces to
#                                       $CONFIG/backups/STAMP/, rewrites $CONFIG/manifest. -> TUI_SYNC_BACKUP, counts in TUI_SYNC_COUNT[]
#   tui.sync.program_plan SRC PREFIX    -> TUI_SYNC_P_ADD/UPDATE/SAME/REMOVE (PREFIX-relative)
#   tui.sync.program_apply SRC PREFIX [BACKUP_DIR]
#   tui.sync.valid_source SRC           rc 0 when SRC looks like a DABT release (VERSION, lib/tui.sh, share/defaults)
#   tui.sync.report                     text listing the last plan(s) for humans
# STAMP is a timestamp; set TUI_SYNC_STAMP to fix it (tests).

declare -ga TUI_SYNC_ADD=() TUI_SYNC_UPDATE=() TUI_SYNC_SAME=() TUI_SYNC_KEEP=() TUI_SYNC_CONFLICT=() TUI_SYNC_REMOVE=() TUI_SYNC_ORPHAN=()
declare -ga TUI_SYNC_P_ADD=() TUI_SYNC_P_UPDATE=() TUI_SYNC_P_SAME=() TUI_SYNC_P_REMOVE=()
declare -gA TUI_SYNC_COUNT=()
declare -g TUI_SYNC_BACKUP="" TUI_SYNC_POLICY="${TUI_SYNC_POLICY:-new}"
declare -ga _TUI_SYNC_PROGRAM_TOP=(lib bin share docs examples VERSION README.md CHANGELOG.md LICENSE)

# ── checksums ────────────────────────────────────────────────────────────
_tui_sync.sha() { # FILE -> _SHA ("" when unreadable)
	_SHA=""
	[[ -r "$1" ]] || return 1
	local out
	if command -v sha256sum >/dev/null 2>&1; then
		out="$(sha256sum "$1")"
	elif command -v shasum >/dev/null 2>&1; then
		out="$(shasum -a 256 "$1")"
	elif command -v openssl >/dev/null 2>&1; then
		out="$(openssl dgst -sha256 "$1")"
		out="${out##* }"
	else
		out="$(cksum "$1")"
		out="${out%% *}"
	fi
	_SHA="${out%% *}"
}

tui.sync.valid_source() { [[ -r "$1/VERSION" && -f "$1/lib/tui.sh" && -d "$1/share/defaults" ]]; }

# every regular file below DIR, as paths relative to DIR, sorted, one per line
_tui_sync.files() {
	[[ -d "$1" ]] || return 0
	(cd "$1" && find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)
}

# the config namespace of a release: "defaults/..." from share/defaults, "plugins/..." from share/plugins
_tui_sync.config_list() { # SRC -> lines "REL"
	local f
	while IFS= read -r f; do printf 'defaults/%s\n' "$f"; done < <(_tui_sync.files "$1/share/defaults")
	while IFS= read -r f; do printf 'plugins/%s\n' "$f"; done < <(_tui_sync.files "$1/share/plugins")
}
_tui_sync.config_src() { # SRC REL -> path of that file in the release
	case "$2" in defaults/*) printf '%s/share/defaults/%s' "$1" "${2#defaults/}" ;; plugins/*) printf '%s/share/plugins/%s' "$1" "${2#plugins/}" ;; esac
}

_tui_sync.manifest_load() { # CONFIG -> associative _TUI_SYNC_BASE
	declare -gA _TUI_SYNC_BASE=()
	local line
	[[ -r "$1/manifest" ]] || return 0
	while IFS= read -r line; do
		[[ "$line" == \#* || -z "$line" ]] && continue
		_TUI_SYNC_BASE["${line#*  }"]="${line%%  *}"
	done <"$1/manifest"
}

# ── the config plan ──────────────────────────────────────────────────────
tui.sync.plan() {
	local src="$1" conf="$2" rel new cur base
	TUI_SYNC_ADD=()
	TUI_SYNC_UPDATE=()
	TUI_SYNC_SAME=()
	TUI_SYNC_KEEP=()
	TUI_SYNC_CONFLICT=()
	TUI_SYNC_REMOVE=()
	TUI_SYNC_ORPHAN=()
	_tui_sync.manifest_load "$conf"
	local -A inrelease=()
	while IFS= read -r rel; do
		[[ -n "$rel" ]] || continue
		inrelease[$rel]=1
		_tui_sync.sha "$(_tui_sync.config_src "$src" "$rel")"
		new="$_SHA"
		if [[ ! -f "$conf/$rel" ]]; then
			TUI_SYNC_ADD+=("$rel")
			continue
		fi
		_tui_sync.sha "$conf/$rel"
		cur="$_SHA"
		base="${_TUI_SYNC_BASE[$rel]:-}"
		if [[ "$cur" == "$new" ]]; then
			TUI_SYNC_SAME+=("$rel")
		elif [[ -n "$base" && "$cur" == "$base" ]]; then
			TUI_SYNC_UPDATE+=("$rel")
		elif [[ -n "$base" && "$new" == "$base" ]]; then
			TUI_SYNC_KEEP+=("$rel")
		else TUI_SYNC_CONFLICT+=("$rel"); fi
	done < <(_tui_sync.config_list "$src")
	for rel in "${!_TUI_SYNC_BASE[@]}"; do # files a release used to ship and no longer does
		[[ -n "${inrelease[$rel]:-}" ]] && continue
		[[ -f "$conf/$rel" ]] || continue
		_tui_sync.sha "$conf/$rel"
		if [[ "$_SHA" == "${_TUI_SYNC_BASE[$rel]}" ]]; then TUI_SYNC_REMOVE+=("$rel"); else TUI_SYNC_ORPHAN+=("$rel"); fi
	done
	if ((${#TUI_SYNC_REMOVE[@]})); then mapfile -t TUI_SYNC_REMOVE < <(printf '%s\n' "${TUI_SYNC_REMOVE[@]}" | LC_ALL=C sort); fi
	if ((${#TUI_SYNC_ORPHAN[@]})); then mapfile -t TUI_SYNC_ORPHAN < <(printf '%s\n' "${TUI_SYNC_ORPHAN[@]}" | LC_ALL=C sort); fi
	return 0
}

_tui_sync.dirof() { if [[ "$1" == */* ]]; then _D="${1%/*}"; else _D="."; fi; } # REL -> its folder ("." for a top-level file)

_tui_sync.stamp() { if [[ -n "${TUI_SYNC_STAMP:-}" ]]; then _STAMP="$TUI_SYNC_STAMP"; else printf -v _STAMP '%(%Y%m%d-%H%M%S)T' -1; fi; }

_tui_sync.backup() { # CONFIG REL  (copies CONFIG/REL into the backup folder, creating it on first use)
	[[ -f "$1/$2" ]] || return 0
	if [[ -z "$TUI_SYNC_BACKUP" ]]; then
		_tui_sync.stamp
		TUI_SYNC_BACKUP="$1/backups/$_STAMP"
	fi
	_tui_sync.dirof "$2"
	mkdir -p "$TUI_SYNC_BACKUP/$_D" && cp -p "$1/$2" "$TUI_SYNC_BACKUP/$2"
}

_tui_sync.policy_choice() { # REL -> prints the choice for a conflict under TUI_SYNC_POLICY
	case "${TUI_SYNC_POLICY:-new}" in override | skip | new) printf '%s' "$TUI_SYNC_POLICY" ;; *) printf 'new' ;; esac
}

# apply: SRC CONFIG [RESOLVER]
tui.sync.apply() {
	local src="$1" conf="$2" resolver="${3:-}" rel choice from
	TUI_SYNC_BACKUP=""
	TUI_SYNC_COUNT=([add]=0 [update]=0 [same]=0 [keep]=0 [override]=0 [skip]=0 [new]=0 [remove]=0 [orphan]=0)
	mkdir -p "$conf" || return 1
	tui.sync.plan "$src" "$conf"
	_tui_sync.manifest_load "$conf"
	local -A newbase=()
	for rel in "${!_TUI_SYNC_BASE[@]}"; do newbase[$rel]="${_TUI_SYNC_BASE[$rel]}"; done
	_tui_sync.write() {
		from="$(_tui_sync.config_src "$src" "$1")"
		_tui_sync.dirof "$1"
		mkdir -p "$conf/$_D" && cp -p "$from" "$conf/$1"
	}
	for rel in "${TUI_SYNC_ADD[@]}"; do
		_tui_sync.write "$rel"
		_tui_sync.sha "$conf/$rel"
		newbase[$rel]="$_SHA"
		TUI_SYNC_COUNT[add]=$((TUI_SYNC_COUNT[add] + 1))
	done
	for rel in "${TUI_SYNC_UPDATE[@]}"; do
		_tui_sync.backup "$conf" "$rel"
		_tui_sync.write "$rel"
		_tui_sync.sha "$conf/$rel"
		newbase[$rel]="$_SHA"
		TUI_SYNC_COUNT[update]=$((TUI_SYNC_COUNT[update] + 1))
	done
	for rel in "${TUI_SYNC_SAME[@]}"; do
		_tui_sync.sha "$conf/$rel"
		newbase[$rel]="$_SHA"
		TUI_SYNC_COUNT[same]=$((TUI_SYNC_COUNT[same] + 1))
	done
	TUI_SYNC_COUNT[keep]=${#TUI_SYNC_KEEP[@]}
	for rel in "${TUI_SYNC_CONFLICT[@]}"; do
		if [[ -n "$resolver" ]]; then choice="$("$resolver" "$rel")"; else choice="$(_tui_sync.policy_choice "$rel")"; fi
		case "$choice" in
			override)
				_tui_sync.backup "$conf" "$rel"
				_tui_sync.write "$rel"
				_tui_sync.sha "$conf/$rel"
				newbase[$rel]="$_SHA"
				TUI_SYNC_COUNT[override]=$((TUI_SYNC_COUNT[override] + 1))
				;;
			skip) TUI_SYNC_COUNT[skip]=$((TUI_SYNC_COUNT[skip] + 1)) ;;
			*)
				from="$(_tui_sync.config_src "$src" "$rel")"
				cp -p "$from" "$conf/$rel.new"
				TUI_SYNC_COUNT[new]=$((TUI_SYNC_COUNT[new] + 1))
				;;
		esac
	done
	for rel in "${TUI_SYNC_REMOVE[@]}"; do
		_tui_sync.backup "$conf" "$rel"
		rm -f "$conf/$rel"
		unset 'newbase[$rel]'
		TUI_SYNC_COUNT[remove]=$((TUI_SYNC_COUNT[remove] + 1))
	done
	TUI_SYNC_COUNT[orphan]=${#TUI_SYNC_ORPHAN[@]}
	{
		printf '# DABT manifest: checksums of the config files DABT last wrote (the updater compares against these)\n'
		for rel in $(printf '%s\n' "${!newbase[@]}" | LC_ALL=C sort); do printf '%s  %s\n' "${newbase[$rel]}" "$rel"; done
	} >"$conf/manifest.tmp" && mv -f "$conf/manifest.tmp" "$conf/manifest"
	unset -f _tui_sync.write
	return 0
}

# ── the program plan / apply ─────────────────────────────────────────────
_tui_sync.program_list() { # DIR -> relative paths of the program files below DIR
	local t
	for t in "${_TUI_SYNC_PROGRAM_TOP[@]}"; do
		if [[ -d "$1/$t" ]]; then
			while IFS= read -r f; do printf '%s/%s\n' "$t" "$f"; done < <(_tui_sync.files "$1/$t")
		elif [[ -f "$1/$t" ]]; then printf '%s\n' "$t"; fi
	done
}

tui.sync.program_plan() {
	local src="$1" prefix="$2" rel a b
	TUI_SYNC_P_ADD=()
	TUI_SYNC_P_UPDATE=()
	TUI_SYNC_P_SAME=()
	TUI_SYNC_P_REMOVE=()
	local -A inrelease=()
	while IFS= read -r rel; do
		inrelease[$rel]=1
		if [[ ! -f "$prefix/$rel" ]]; then
			TUI_SYNC_P_ADD+=("$rel")
			continue
		fi
		_tui_sync.sha "$src/$rel"
		a="$_SHA"
		_tui_sync.sha "$prefix/$rel"
		b="$_SHA"
		if [[ "$a" == "$b" ]]; then TUI_SYNC_P_SAME+=("$rel"); else TUI_SYNC_P_UPDATE+=("$rel"); fi
	done < <(_tui_sync.program_list "$src")
	while IFS= read -r rel; do [[ -n "${inrelease[$rel]:-}" ]] || TUI_SYNC_P_REMOVE+=("$rel"); done < <(_tui_sync.program_list "$prefix")
	return 0
}

tui.sync.program_apply() { # SRC PREFIX [BACKUP_DIR]
	local src="$1" prefix="$2" bk="${3:-}" rel
	tui.sync.program_plan "$src" "$prefix"
	mkdir -p "$prefix" || return 1
	for rel in "${TUI_SYNC_P_UPDATE[@]}" "${TUI_SYNC_P_REMOVE[@]}"; do
		[[ -n "$bk" && -f "$prefix/$rel" ]] && {
			_tui_sync.dirof "$rel"
			mkdir -p "$bk/program/$_D" && cp -p "$prefix/$rel" "$bk/program/$rel"
		}
	done
	for rel in "${TUI_SYNC_P_ADD[@]}" "${TUI_SYNC_P_UPDATE[@]}"; do
		_tui_sync.dirof "$rel"
		mkdir -p "$prefix/$_D" && cp -p "$src/$rel" "$prefix/$rel"
	done
	for rel in "${TUI_SYNC_P_REMOVE[@]}"; do rm -f "$prefix/$rel"; done
	return 0
}

# ── a human readable report of the plans above ───────────────────────────
tui.sync.report() {
	local rel out=""
	_r() {
		local title="$1"
		shift
		(($#)) || return 0
		out+="$title ($#)"$'\n'
		for rel in "$@"; do out+="    $rel"$'\n'; done
	}
	_r "Program files added" "${TUI_SYNC_P_ADD[@]}"
	_r "Program files changed" "${TUI_SYNC_P_UPDATE[@]}"
	_r "Program files removed" "${TUI_SYNC_P_REMOVE[@]}"
	_r "Config files added (new defaults)" "${TUI_SYNC_ADD[@]}"
	_r "Config files updated (you had not changed them)" "${TUI_SYNC_UPDATE[@]}"
	_r "CONFLICTS (you and the release both changed them)" "${TUI_SYNC_CONFLICT[@]}"
	_r "Config files you changed, release unchanged (kept)" "${TUI_SYNC_KEEP[@]}"
	_r "Config files the release dropped (removed, untouched)" "${TUI_SYNC_REMOVE[@]}"
	_r "Config files the release dropped (yours, left in place)" "${TUI_SYNC_ORPHAN[@]}"
	unset -f _r
	[[ -n "$out" ]] || out="No changes."$'\n'
	printf '%s' "$out"
}
