#!/usr/bin/env bash
# pack.sh - deterministic .dapk creation, inspection and safe extraction (gzip-compressed tar).
#
# A .dapk is valid only if its first member is <root>/MANIFEST and every member is a regular file or directory inside <root>/.
# Reproducible: explicit member order (MANIFEST, MANIFEST.sig, then LC_ALL=C order), owner 0, fixed mtime, gzip -n. Needs GNU tar.
#
# dapk.pack.create PARENT ROOT OUT EPOCH   pack PARENT/ROOT into OUT (progress via dapk.ui.progress_*)
# dapk.pack.check PKG                      validate structure and member safety -> DAPK_PACK_ROOT, DAPK_PACK_COUNT; rc 1 + DAPK_PACK_ERROR
# dapk.pack.manifest PKG                   print MANIFEST to stdout (reads only until it is found)
# dapk.pack.extract PKG DEST               extract (after check) into DEST, which then holds ROOT/
# dapk.pack.file_in PKG NAME               print a member of the package (relative to ROOT), e.g. NEWS

declare -g DAPK_PACK_ROOT="" DAPK_PACK_COUNT=0 DAPK_PACK_ERROR="" _DAPK_TAR=""

_dapk.pack.tar() {
	[[ -n "$_DAPK_TAR" ]] && return 0
	local t
	for t in tar gtar; do command -v "$t" >/dev/null 2>&1 && "$t" --version 2>/dev/null | grep -q 'GNU tar' && {
		_DAPK_TAR="$t"
		return 0
	}; done
	DAPK_PACK_ERROR="GNU tar is required (reproducible archives); on macOS: brew install gnu-tar"
	return 1
}

dapk.pack.create() {
	local parent="$1" root="$2" out="$3" epoch="$4" list tmp n line
	DAPK_PACK_ERROR=""
	_dapk.pack.tar || return 1
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/dapk_pack.XXXXXX")" || return 1
	list="$tmp/list"
	(cd "$parent" && {
		printf '%s\0' "$root/MANIFEST"
		[[ -f "$root/MANIFEST.sig" ]] && printf '%s\0' "$root/MANIFEST.sig"
		find "$root" ! -path "$root/MANIFEST" ! -path "$root/MANIFEST.sig" -print0 | LC_ALL=C sort -z
	}) >"$list"
	n="$(tr -cd '\0' <"$list" | wc -c)"
	n="${n//[[:space:]]/}"
	((DAPK_UI_PROGRESS)) && dapk.ui.progress_start "Packing files" "$n"
	while IFS= read -r line; do dapk.ui.progress_tick; done < <(
		"$_DAPK_TAR" -C "$parent" --no-recursion --null -T "$list" --owner=0 --group=0 --numeric-owner --mtime="@$epoch" -cvf "$tmp/pkg.tar" 2>"$tmp/err"
	)
	[[ -s "$tmp/pkg.tar" ]] || {
		DAPK_PACK_ERROR="tar failed: $(<"$tmp/err")"
		rm -rf "$tmp"
		return 1
	}
	gzip -n -9 <"$tmp/pkg.tar" >"$out" || {
		DAPK_PACK_ERROR="gzip failed"
		rm -rf "$tmp"
		return 1
	}
	rm -rf "$tmp"
	((DAPK_UI_PROGRESS)) && dapk.ui.progress_done "Packed $n entries"
	return 0
}

dapk.pack.check() {
	local pkg="$1" i first root n type name
	local -a names types
	DAPK_PACK_ERROR=""
	DAPK_PACK_ROOT=""
	DAPK_PACK_COUNT=0
	[[ -f "$pkg" ]] || {
		DAPK_PACK_ERROR="not a file: $pkg"
		return 1
	}
	_dapk.pack.tar || return 1
	mapfile -t names < <("$_DAPK_TAR" -tzf "$pkg" 2>/dev/null)
	mapfile -t types < <("$_DAPK_TAR" -tvzf "$pkg" 2>/dev/null | cut -c1)
	n=${#names[@]}
	((n > 0 && n == ${#types[@]})) || {
		DAPK_PACK_ERROR="not a readable .$DABT_PKG_EXT (gzip tar) archive"
		return 1
	}
	first="${names[0]}"
	[[ "$first" == */MANIFEST && "${first%/MANIFEST}" != */* ]] || {
		DAPK_PACK_ERROR="first member must be <root>/MANIFEST (got '$first')"
		return 1
	}
	root="${first%/MANIFEST}"
	[[ "$root" =~ ^[a-z0-9][a-z0-9._+-]*$ ]] || {
		DAPK_PACK_ERROR="invalid package root '$root'"
		return 1
	}
	for i in "${!names[@]}"; do
		name="${names[i]}"
		type="${types[i]}"
		[[ "$name" == "$root" || "$name" == "$root/"* ]] || {
			DAPK_PACK_ERROR="member outside the package root: $name"
			return 1
		}
		[[ "$name" != /* && "/$name/" != *"/../"* ]] || {
			DAPK_PACK_ERROR="unsafe member path: $name"
			return 1
		}
		[[ "$type" == - || "$type" == d ]] || {
			DAPK_PACK_ERROR="member '$name' is not a regular file or directory (links and devices are not allowed)"
			return 1
		}
	done
	DAPK_PACK_ROOT="$root" DAPK_PACK_COUNT=$n
}

dapk.pack.manifest() {
	_dapk.pack.tar || return 1
	local first
	first="$("$_DAPK_TAR" -tzf "$1" 2>/dev/null | head -n1)"
	[[ "$first" == */MANIFEST ]] || return 1
	"$_DAPK_TAR" -xzOf "$1" --occurrence=1 "$first" 2>/dev/null
}

dapk.pack.file_in() {
	_dapk.pack.tar || return 1
	local first root
	first="$("$_DAPK_TAR" -tzf "$1" 2>/dev/null | head -n1)"
	root="${first%/MANIFEST}"
	"$_DAPK_TAR" -xzOf "$1" --occurrence=1 "$root/$2" 2>/dev/null
}

dapk.pack.extract() {
	local pkg="$1" dest="$2" line
	_dapk.pack.tar || return 1
	mkdir -p "$dest" || return 1
	((DAPK_UI_PROGRESS)) && dapk.ui.progress_start "Extracting" "$DAPK_PACK_COUNT"
	while IFS= read -r line; do dapk.ui.progress_tick; done < <("$_DAPK_TAR" -xzvf "$pkg" -C "$dest" --no-same-owner --no-same-permissions 2>/dev/null)
	[[ -f "$dest/$DAPK_PACK_ROOT/MANIFEST" ]] || {
		DAPK_PACK_ERROR="extraction failed"
		return 1
	}
	((DAPK_UI_PROGRESS)) && dapk.ui.progress_done "Extracted $DAPK_PACK_COUNT entries"
	return 0
}
