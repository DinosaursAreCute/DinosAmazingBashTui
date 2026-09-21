#!/usr/bin/env bash
# deps.sh - declared system dependencies: check, plan and (only with consent) install.
#
# Declared in dabt.pkg as [[dependency]] tables, stored in the MANIFEST header as dep.N.* (signed). Nothing is installed unless the user
# says so: see dapk.deps.flow for the exact behaviour (the matrix in docs/concepts/dapk-packaging.md, 11.2).
#
# dapk.deps.load_config | load_manifest    read the declarations (from DAPK_CFG / DAPK_MANIFEST_H) into DAPK_DEPS_N + _DD
# dapk.deps.header                         write them into the manifest header
# dapk.deps.check                          run the checks -> DAPK_DEPS_MISSING_REQ[] / DAPK_DEPS_MISSING_OPT[] (indexes); prints a status table
# dapk.deps.detect_pm [NAME]               -> DAPK_DEPS_PM (pacman|apt|dnf|zypper|apk|brew)
# dapk.deps.flow                           the install decision. Settings (globals): DAPK_DEPS_MODE=default|install|none  DAPK_DEPS_REQUIRE=0|1
#                                          DAPK_DEPS_YES=0|1  DAPK_DEPS_ALLOW_CUSTOM=0|1  DAPK_DEPS_PM  DAPK_DEPS_PLAN_ONLY=0|1
#                                          rc 0 = continue with the install, rc 1 = abort. Sets DAPK_DEPS_UNMET (1 = required still missing).
# dapk.deps.mark NAME unmet|ok  /  dapk.deps.marker NAME   the "deps unmet" marker of an installed app
# Environment: DAPK_SUDO overrides the privilege command (default: sudo unless root; empty = none).

declare -gA _DD=()
declare -g DAPK_DEPS_N=0 DAPK_DEPS_PM="" DAPK_DEPS_UNMET=0
declare -g DAPK_DEPS_MODE="default" DAPK_DEPS_REQUIRE=0 DAPK_DEPS_YES=0 DAPK_DEPS_ALLOW_CUSTOM=0 DAPK_DEPS_PLAN_ONLY=0
declare -ga DAPK_DEPS_MISSING_REQ=() DAPK_DEPS_MISSING_OPT=()
_DAPK_DEP_FIELDS=(name optional check version_cmd min_version apt pacman dnf zypper apk brew install)
declare -gA _DAPK_PM_CMD=([pacman]="pacman -S --needed --noconfirm" [apt]="apt-get install -y" [dnf]="dnf install -y" [zypper]="zypper --non-interactive install" [apk]="apk add" [brew]="brew install")

dapk.deps.load_config() {
    local i f; _DD=(); DAPK_DEPS_N=${DAPK_CFG[@count.dependency]:-0}
    for (( i = 1; i <= DAPK_DEPS_N; i++ )); do for f in "${_DAPK_DEP_FIELDS[@]}"; do [[ -n "${DAPK_CFG[dependency.$i.$f]:-}" ]] && _DD[$i.$f]="${DAPK_CFG[dependency.$i.$f]}"; done; done
}

dapk.deps.load_manifest() {
    local k i f; _DD=(); DAPK_DEPS_N=0
    for k in "${!DAPK_MANIFEST_H[@]}"; do
        [[ "$k" =~ ^dep\.([0-9]+)\.([a-z_]+)$ ]] || continue
        i="${BASH_REMATCH[1]}" f="${BASH_REMATCH[2]}"
        [[ " ${_DAPK_DEP_FIELDS[*]} " == *" $f "* ]] || continue
        _DD[$i.$f]="${DAPK_MANIFEST_H[$k]}"; (( i > DAPK_DEPS_N )) && DAPK_DEPS_N=$i
    done 
}

dapk.deps.header() {
    local i f
    for (( i = 1; i <= DAPK_DEPS_N; i++ )); do
        for f in "${_DAPK_DEP_FIELDS[@]}"; do [[ -n "${_DD[$i.$f]:-}" ]] && dapk.manifest.header_set "dep.$i.$f" "${_DD[$i.$f]}"; done
    done
}

_dapk.deps.optional() { case "${_DD[$1.optional]:-false}" in true|yes|1) return 0 ;; esac; return 1; }

# INDEX : present (rc 0) or not; a version gate (min_version + version_cmd) counts as missing when too old
_dapk.deps.present() {
    local i="$1" chk="${_DD[$1.check]:-}" out v
    [[ -n "$chk" ]] || chk="command -v ${_DD[$i.name]}"
    bash -c "$chk" >/dev/null 2>&1 || return 1
    if [[ -n "${_DD[$i.min_version]:-}" && -n "${_DD[$i.version_cmd]:-}" ]]; then
        out="$(bash -c "${_DD[$i.version_cmd]}" 2>&1)"
        [[ "$out" =~ ([0-9]+(\.[0-9]+)+) ]] || return 1
        v="${BASH_REMATCH[1]}"
        [[ "$(printf '%s\n%s\n' "${_DD[$i.min_version]}" "$v" | sort -V | head -n1)" == "${_DD[$i.min_version]}" ]] || return 1
    fi
    return 0
}

dapk.deps.check() {
    local i; DAPK_DEPS_MISSING_REQ=(); DAPK_DEPS_MISSING_OPT=()
    for (( i = 1; i <= DAPK_DEPS_N; i++ )); do
        [[ -n "${_DD[$i.name]:-}" ]] || continue
        if _dapk.deps.present "$i"; then dapk.ui.ok "${_DD[$i.name]}"
        elif _dapk.deps.optional "$i"; then DAPK_DEPS_MISSING_OPT+=("$i"); dapk.ui.info "○ ${_DD[$i.name]} (optional, missing)"
        else DAPK_DEPS_MISSING_REQ+=("$i"); dapk.ui.err "${_DD[$i.name]} (missing)"; fi
    done
    return 0
}

dapk.deps.detect_pm() {
    local p; DAPK_DEPS_PM=""
    if [[ -n "${1:-}" ]]; then case "$1" in apt-get) DAPK_DEPS_PM=apt ;; *) DAPK_DEPS_PM="$1" ;; esac; [[ -n "${_DAPK_PM_CMD[$DAPK_DEPS_PM]:-}" ]]; return; fi
    for p in pacman apt-get dnf zypper apk brew; do command -v "$p" >/dev/null 2>&1 && { DAPK_DEPS_PM="$p"; break; }; done
    [[ "$DAPK_DEPS_PM" == apt-get ]] && DAPK_DEPS_PM=apt
    [[ -n "$DAPK_DEPS_PM" ]]
}

_dapk.deps.sudo() {   # -> _SUDO (array-safe string)
    if [[ -n "${DAPK_SUDO+x}" ]]; then _SUDO="$DAPK_SUDO"; return; fi
    if (( EUID == 0 )) || [[ "$DAPK_DEPS_PM" == brew ]]; then _SUDO=""; else _SUDO="sudo"; fi
}

dapk.deps.mark() {
    local d="$TUI_HOME/apps.deps"
    if [[ "$2" == unmet ]]; then mkdir -p "$d" && printf 'unmet\n' > "$d/$1"; else rm -f "$d/$1"; fi
}
dapk.deps.marker() { [[ -f "$TUI_HOME/apps.deps/$1" ]]; }

dapk.deps.flow() {
    local i pkgs=() customs=() unresolved=() cmd go=0 rc n name a
    DAPK_DEPS_UNMET=0
    dapk.deps.check
    local missing=("${DAPK_DEPS_MISSING_REQ[@]}" "${DAPK_DEPS_MISSING_OPT[@]}")
    (( ${#missing[@]} )) || return 0
    if [[ "$DAPK_DEPS_MODE" == none ]]; then
        (( ${#DAPK_DEPS_MISSING_REQ[@]} )) && { DAPK_DEPS_UNMET=1; dapk.ui.warn "continuing without ${#DAPK_DEPS_MISSING_REQ[@]} missing required dependenc$( (( ${#DAPK_DEPS_MISSING_REQ[@]} == 1 )) && echo y || echo ies ) (--no-deps)"; }
        return 0
    fi

    # plan
    dapk.deps.detect_pm "$DAPK_DEPS_PM" || dapk.ui.debug "no supported package manager found"
    local pm="$DAPK_DEPS_PM"
    for i in "${missing[@]}"; do
        name="${_DD[$i.name]}"
        if [[ -n "$pm" && -n "${_DD[$i.$pm]:-}" ]]; then pkgs+=("${_DD[$i.$pm]}")
        elif [[ -n "${_DD[$i.install]:-}" ]]; then customs+=("$i")
        else unresolved+=("$name"); fi
    done
    _dapk.deps.sudo
    printf '\n%sMissing dependencies:%s\n' "$B" "$R" >&2
    for i in "${missing[@]}"; do printf '  %s%s%s\n' "$D" "${_DD[$i.name]}$(_dapk.deps.optional "$i" && echo ' (optional)')" "$R" >&2; done
    (( ${#pkgs[@]} )) && printf '  will run: %s%s %s\n' "${_SUDO:+$_SUDO }" "${_DAPK_PM_CMD[$pm]}" "${pkgs[*]}" >&2
    for i in "${customs[@]}"; do printf '  custom command (%s): %s\n' "${_DD[$i.name]}" "${_DD[$i.install]}" >&2; done
    (( ${#unresolved[@]} )) && dapk.ui.warn "no install recipe for this system: ${unresolved[*]} (install them by hand)"
    (( DAPK_DEPS_PLAN_ONLY )) && { (( ${#DAPK_DEPS_MISSING_REQ[@]} )) && DAPK_DEPS_UNMET=1; return 0; }

    # decide
    local defans=n; [[ "$DAPK_DEPS_MODE" == install ]] && defans=y
    if (( DAPK_DEPS_YES )); then go=1
    elif [[ -t 0 ]]; then dapk.ui.confirm "Install missing dependencies?" "$defans" && go=1
    else
        if [[ "$DAPK_DEPS_MODE" == install ]] || (( DAPK_DEPS_REQUIRE && ${#DAPK_DEPS_MISSING_REQ[@]} )); then
            dapk.ui.err "cannot ask without a terminal: pass --yes to install the dependencies"; return 1
        fi
        dapk.ui.warn "no terminal to ask on: not installing dependencies"
    fi
    if (( ! go )); then
        if (( DAPK_DEPS_REQUIRE && ${#DAPK_DEPS_MISSING_REQ[@]} )); then dapk.ui.err "required dependencies are missing (--require-deps)"; return 1; fi
        (( ${#DAPK_DEPS_MISSING_REQ[@]} )) && { DAPK_DEPS_UNMET=1; dapk.ui.warn "continuing without the missing dependencies"; }
        return 0
    fi

    # install: one batched command per package manager, custom commands one by one
    if (( ${#pkgs[@]} )); then
        cmd=(${_SUDO:+$_SUDO} ${_DAPK_PM_CMD[$pm]} "${pkgs[@]}")
        _dapk.ui.log INFO "run: ${cmd[*]}"
        "${cmd[@]}"; rc=$?
        (( rc )) && dapk.ui.warn "package manager exited with $rc"
    fi
    for i in "${customs[@]}"; do
        if (( ! DAPK_DEPS_ALLOW_CUSTOM )); then
            printf '\n' >&2
            dapk.ui.confirm "Run this custom install command for ${_DD[$i.name]}? ${_DD[$i.install]}" n
            a=$?
            (( a == 0 )) || { dapk.ui.warn "custom install of ${_DD[$i.name]} skipped$( (( a == 2 )) && echo ' (no terminal; use --allow-custom-install)')"; continue; }
        fi
        _dapk.ui.log INFO "run: ${_DD[$i.install]}"
        bash -c "${_DD[$i.install]}" || dapk.ui.warn "custom install of ${_DD[$i.name]} failed"
    done

    # verify
    local -a still=()
    for i in "${DAPK_DEPS_MISSING_REQ[@]}"; do _dapk.deps.present "$i" || still+=("${_DD[$i.name]}"); done
    for i in "${DAPK_DEPS_MISSING_OPT[@]}"; do _dapk.deps.present "$i" || dapk.ui.warn "optional dependency ${_DD[$i.name]} is still missing"; done
    if (( ${#still[@]} )); then
        dapk.ui.err "still missing: ${still[*]}"
        (( DAPK_DEPS_REQUIRE )) && return 1
        DAPK_DEPS_UNMET=1
    else (( ${#DAPK_DEPS_MISSING_REQ[@]} )) && dapk.ui.ok "dependencies installed"; fi
    return 0
}
