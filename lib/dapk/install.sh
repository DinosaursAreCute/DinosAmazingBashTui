#!/usr/bin/env bash
# install.sh (module) - installing a .dapk as a DABT application: fetch, verify, show News, resolve dependencies, then hand the verified
# tree to tui.apps.install (lib/tui_apps.sh), which scans, registers and copies it. Entered through `dabt app install PKG.dapk|URL`.
#
# dapk.install.run SOURCE [OPTIONS]
#   --install-dependencies  --yes|-y  --no-deps  --require-deps  --allow-custom-install  --pm NAME   dependency handling (see deps.sh)
#   --trust-key SHA256:..   trust this exact new signer      --allow-unsigned   accept an unsigned package
#   --install-path DIR      the app folder (default: managed by dabt app)      --plan   verify + show the dependency plan, install nothing
#   -v -q --log FILE --progress --no-progress   and, passed on to dabt app: --force --strict --no-scan --name --entry
# SOURCE may also be a .zip (e.g. a workflow artifact download) holding exactly one .dapk.
# rc 0 ok, 1 failure, 2 usage error.

# a zip (magic PK\x03\x04), e.g. a GitHub Actions artifact download
_dapk.install.is_zip() { [[ "$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d " \n")" == 504b0304 ]]; }

# _dapk.install.unzip ZIP DIR   extracts ZIP, prints the path of the one .dapk inside (rc 1 with a message otherwise)
_dapk.install.unzip() {
	local zip="$1" dir="$2" f
	local -a found=()
	mkdir -p "$dir" || return 1
	if command -v unzip >/dev/null 2>&1; then
		unzip -qq -o "$zip" -d "$dir" >/dev/null 2>&1
	elif command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xf "$zip" -C "$dir" >/dev/null 2>&1
	else
		dapk.ui.err "unzip (or bsdtar) is required to open ${zip##*/}"
		return 1
	fi || {
		dapk.ui.err "cannot extract ${zip##*/}"
		return 1
	}
	while IFS= read -r f; do found+=("$f"); done < <(find "$dir" -type f -name "*.$DABT_PKG_EXT" -print | sort)
	((${#found[@]} == 1)) || {
		dapk.ui.err "${zip##*/} must contain exactly one .$DABT_PKG_EXT (found ${#found[@]})"
		return 1
	}
	dapk.ui.ok "unpacked ${found[0]##*/} from ${zip##*/}" >&2
	printf '%s' "${found[0]}"
}

dapk.install.run() {
	local src="" plan=0 rc=0 work name ver installed since dir sha want got newsf v t last=""
	local -a pass=()
	DAPK_DEPS_MODE=default DAPK_DEPS_REQUIRE=0 DAPK_DEPS_YES=0 DAPK_DEPS_ALLOW_CUSTOM=0 DAPK_DEPS_PLAN_ONLY=0 DAPK_DEPS_PM=""
	DAPK_VERIFY_TRUST_KEY="" DAPK_VERIFY_ALLOW_UNSIGNED=0 DAPK_VERIFY_ASK=1
	local install_dep=0 no_deps=0
	while (($#)); do
		if _dapk.cmd.ui "$1" "${2:-}"; then
			[[ "$1" == --strict ]] && pass+=(--strict)
			shift "$_UI_SHIFT"
			continue
		fi
		case "$1" in
			--install-dependencies)
				DAPK_DEPS_MODE=install
				install_dep=1
				shift
				;;
			--no-deps)
				DAPK_DEPS_MODE=none
				no_deps=1
				shift
				;;
			--require-deps)
				DAPK_DEPS_REQUIRE=1
				shift
				;;
			--yes | -y)
				DAPK_DEPS_YES=1
				shift
				;;
			--allow-custom-install)
				DAPK_DEPS_ALLOW_CUSTOM=1
				shift
				;;
			--pm)
				DAPK_DEPS_PM="${2:-}"
				shift 2
				;;
			--trust-key)
				DAPK_VERIFY_TRUST_KEY="${2:-}"
				shift 2
				;;
			--allow-unsigned)
				DAPK_VERIFY_ALLOW_UNSIGNED=1
				shift
				;;
			--plan)
				plan=1
				DAPK_DEPS_PLAN_ONLY=1
				shift
				;;
			--install-path)
				pass+=(--install-path "${2:-}")
				shift 2
				;;
			--force | -f | --no-scan)
				pass+=("$1")
				shift
				;;
			--name | --entry)
				pass+=("$1" "${2:-}")
				shift 2
				;;
			-h | --help)
				_dapk.cmd.help
				return 0
				;;
			-*)
				_dapk.cmd.usage "install: unknown option $1"
				return 2
				;;
			*)
				[[ -z "$src" ]] || {
					_dapk.cmd.usage "install: one package only"
					return 2
				}
				src="$1"
				shift
				;;
		esac
	done
	[[ -n "$src" ]] || {
		_dapk.cmd.usage "install: give a .$DABT_PKG_EXT file or URL"
		return 2
	}
	if ((no_deps && (install_dep || DAPK_DEPS_REQUIRE))); then
		_dapk.cmd.usage "--no-deps cannot be combined with --install-dependencies or --require-deps"
		return 2
	fi

	dapk.ui.init
	dapk.ui.steps 4
	work="$(mktemp -d "${TMPDIR:-/tmp}/dapk_inst.XXXXXX")" || return 1
	((DAPK_UI_QUIET)) || printf '%sD.A.B.T%s app install  %s%s%s\n' "$BLUE" "$R" "$D" "${src##*/}" "$R" >&2

	dapk.ui.step "Verifying the package"
	local pkg="$src"
	if [[ "$src" == http://* || "$src" == https://* ]]; then
		command -v curl >/dev/null 2>&1 || {
			dapk.ui.err "curl is required to download a package"
			rc=1
		}
		if ((rc == 0)); then
			pkg="$work/${src##*/}"
			pkg="${pkg%%\?*}"
			dapk.ui.run "Downloading ${src##*/}" curl -fsSL --max-time 300 -o "$pkg" "$src" || rc=1
		fi
		if ((rc == 0)) && curl -fsSL --max-time 20 -o "$pkg.sha256" "$src.sha256" 2>/dev/null; then
			want="$(awk '{print $1; exit}' "$pkg.sha256")"
			got="$(dapk.manifest.sha256 "$pkg")"
			[[ "$want" == "$got" ]] && dapk.ui.ok "download checksum" || {
				dapk.ui.err "download checksum mismatch (expected $want, got $got)"
				rc=1
			}
		elif ((rc == 0)); then dapk.ui.debug "no .sha256 published next to the package"; fi
	elif [[ ! -f "$src" ]]; then
		dapk.ui.err "package not found: $src"
		rc=1
	else
		src="$(cd -P "$(dirname "$src")" && pwd -P)/${src##*/}"
		pkg="$src"
	fi # record an absolute path as the update source
	if ((rc == 0)) && _dapk.install.is_zip "$pkg"; then
		pkg="$(_dapk.install.unzip "$pkg" "$work/zip")" || rc=1 # a workflow artifact download: the .dapk is inside
	fi
	((rc == 0)) && { dapk.verify.run "$pkg" || rc=1; }

	if ((rc == 0)); then
		name="${DAPK_MANIFEST_H[name]}"
		ver="${DAPK_MANIFEST_H[version]}"
		dapk.ui.step "Package"
		dapk.ui.kv name "$name"
		dapk.ui.kv version "$ver-${DAPK_MANIFEST_H[build]:-0}"
		dapk.ui.kv signer "${DAPK_VERIFY_FPR:-unsigned}"
		[[ -n "${DAPK_MANIFEST_H[requires_dabt]:-}" ]] && dapk.ui.kv requires "DABT ${DAPK_MANIFEST_H[requires_dabt]}"
		[[ -n "${DAPK_MANIFEST_H[homepage]:-}" ]] && dapk.ui.kv homepage "${DAPK_MANIFEST_H[homepage]}"
		source "$TUI_ROOT/lib/tui_apps.sh"
		since=""
		_tui_apps.lookup "$name" && since="$A_VERSION"
		newsf="$DAPK_VERIFY_DIR/NEWS"
		if [[ -r "$newsf" ]] && dapk.news.load "$newsf"; then
			[[ -n "$since" ]] && dapk.news.since "$since"
			if ((${#DAPK_NEWS_ITEMS[@]})); then
				dapk.ui.info "$([[ -n "$since" ]] && echo "What this update brings (you have $since):" || echo "What's new:")"
				while IFS= read -r v; do dapk.ui.info "$v"; done < <(dapk.news.print "  ")
			fi
		fi
		dapk.ui.step "Dependencies"
		dapk.deps.load_manifest
		if ((DAPK_DEPS_N)); then dapk.deps.flow || rc=1; else dapk.ui.ok "none declared"; fi
	fi
	if ((rc == 0 && plan)); then
		dapk.ui.step "Install"
		dapk.ui.info "plan only: nothing was installed"
	fi
	if ((rc == 0 && ! plan)); then
		dapk.ui.step "Installing"
		[[ "$src" == http://* || "$src" == https://* ]] && :
		tui.apps.install "$DAPK_VERIFY_DIR" --origin "$src" "${pass[@]}"
		rc=$?
		if ((rc == 0)); then ((DAPK_DEPS_UNMET)) && {
			dapk.deps.mark "$name" unmet
			dapk.ui.warn "$name has unmet dependencies: run  dabt pkg deps $name"
		} || dapk.deps.mark "$name" ok; fi
	fi
	rm -rf "$work"
	_dapk.cmd.finish "$rc"
}
