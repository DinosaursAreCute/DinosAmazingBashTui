#!/usr/bin/env bash
# tui_scan.sh - security scan for shell scripts (apps and plugins). Standalone: needs only bash + grep + find.
#
#   Built-in scanner (always on): grep rules for the obvious red flags (pipe-to-shell, reverse shells, rm -rf /, setuid,
#     secrets, persistence ...). Findings are HIGH or WARN. It cannot see obfuscated code: a clean report is not a guarantee.
#   ShellCheck (used when on PATH) and Semgrep (only with deep=1 / DABT_SCAN_SEMGREP=1) add their findings as WARN.
#
#   tui.scan.run PATH [deep]     scan a file or folder -> TUI_SCAN_HIGH TUI_SCAN_WARN, TUI_SCAN_REPORT (text); rc 0 always
#   tui.scan.print               print TUI_SCAN_REPORT and a summary line to stdout
#   tui.scan.tools               status of the optional tools
#   tui.scan.install TOOL [--yes]   install shellcheck|semgrep with the system package manager
#   tui.scan.cli ARGS...         the `dabt scan` command line

declare -g TUI_SCAN_HIGH=0 TUI_SCAN_WARN=0 TUI_SCAN_REPORT="" TUI_SCAN_NOTES=""
declare -ga _SCAN_RULES=()

_scan.rule() { _SCAN_RULES+=("$1"$'\t'"$2"$'\t'"$3"); } # SEV LABEL ERE
_scan.rule HIGH "downloads and pipes into a shell" '(curl|wget|fetch)[^#|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)'
_scan.rule HIGH "runs downloaded code through eval" 'eval[^#]*\$\([[:space:]]*(curl|wget)'
_scan.rule HIGH "decodes and executes a payload" 'base64[^|#]*(-d|--decode)[^|#]*\|[[:space:]]*(ba|z)?sh'
_scan.rule HIGH "reverse shell / raw network socket" '/dev/(tcp|udp)/|(nc|ncat|netcat)[[:space:]].*(-e|-c)[[:space:]]|mkfifo[^#]*(nc|ncat)'
_scan.rule HIGH "recursive delete of / or ~" 'rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*(--no-preserve-root|/|/\*|~|~/|\$HOME|"\$HOME")[[:space:]"]*($|[;&|])'
_scan.rule HIGH "writes to a raw disk / formats one" 'dd[[:space:]][^#]*of=/dev/|mkfs(\.[a-z0-9]+)?[[:space:]]'
_scan.rule HIGH "sets the setuid/setgid bit" 'chmod[[:space:]]+([ugoa]*\+[rwx]*[sS]|[2467][0-7]{3})[[:space:]]'
_scan.rule HIGH "edits system auth files" '(>>?|tee[[:space:]]+(-a[[:space:]]+)?)[[:space:]]*/etc/(passwd|shadow|sudoers|ssh)|authorized_keys'
_scan.rule HIGH "embedded private key / cloud key" '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}'
_scan.rule WARN "downloads from the network" '(^|[;&|`(][[:space:]]*|[[:space:]])(curl|wget)[[:space:]]+[^#]*(https?|ftp)://'
_scan.rule WARN "eval of a variable or substitution" '(^|[;&|][[:space:]]*)eval[[:space:]]+[^#]*[$`]'
_scan.rule WARN "uses sudo / su" '(^|[;&|][[:space:]]*)(sudo|su|doas)[[:space:]]'
_scan.rule WARN "world-writable permissions" 'chmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*([0-7]?[0-7][0-7]7|a\+w|o\+w)[[:space:]]'
_scan.rule WARN "persistence (cron, shell rc, systemd)" 'crontab|/etc/cron|\.(bashrc|bash_profile|zshrc|profile)([^a-zA-Z_]|$)|systemctl[[:space:]]+(--user[[:space:]]+)?enable'
_scan.rule WARN "hardcoded credential" '(password|passwd|secret|api_?key|token)[A-Z_]*=["'"'"'][^"'"'"'$]{8,}["'"'"']'
_scan.rule WARN "preloads a library / reads process memory" 'LD_PRELOAD|/proc/[^[:space:]]*/mem'
_scan.rule WARN "writes outside home (/etc /usr /opt /var)" '(>>?|tee|cp|mv|install|ln)[[:space:]][^#]*[[:space:]"]/(etc|usr|opt|var|boot)/'

_scan.files() { # PATH -> script files, one per line
	local p="$1" f first
	if [[ -f "$p" ]]; then
		printf '%s\n' "$p"
		return
	fi
	while IFS= read -r f; do
		case "$f" in *.sh | *.bash)
			printf '%s\n' "$f"
			continue
			;;
		esac
		[[ -s "$f" && $(stat -c %s -- "$f" 2>/dev/null || echo 0) -lt 1048576 ]] || continue
		IFS= read -r first <"$f" 2>/dev/null
		[[ "$first" == '#!'*sh* ]] && printf '%s\n' "$f"
	done < <(find "$p" -type f -not -path '*/.git/*' 2>/dev/null)
}

tui.scan.run() {
	local path="$1" deep="${2:-0}" files=() f r sev label re hit line out="" n
	TUI_SCAN_HIGH=0 TUI_SCAN_WARN=0 TUI_SCAN_REPORT="" TUI_SCAN_NOTES=""
	[[ "${DABT_SCAN_SEMGREP:-0}" == 1 ]] && deep=1
	[[ -e "$path" ]] || {
		TUI_SCAN_NOTES="scan: not found: $path"
		return 1
	}
	mapfile -t files < <(_scan.files "$path")
	((${#files[@]})) || {
		TUI_SCAN_NOTES="no shell scripts found"
		return 0
	}
	for f in "${files[@]}"; do
		for r in "${_SCAN_RULES[@]}"; do
			IFS=$'\t' read -r sev label re <<<"$r"
			while IFS= read -r hit; do
				[[ -n "$hit" ]] || continue
				line="${hit#*:}"
				line="${line#"${line%%[![:space:]]*}"}"
				out+="  $sev ${f#"$path"/}:${hit%%:*}  $label"$'\n'"      ${line:0:100}"$'\n'
				if [[ "$sev" == HIGH ]]; then ((++TUI_SCAN_HIGH)); else ((++TUI_SCAN_WARN)); fi
			done < <(grep -nE -e "$re" -- "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|_scan\.rule )')
		done
	done
	if command -v shellcheck >/dev/null 2>&1; then
		n=0
		while IFS= read -r hit; do
			[[ "$hit" == *:*:*:* ]] || continue
			((++n))
			((++TUI_SCAN_WARN))
			((n <= 20)) && out+="  WARN ${hit#"$path"/}  (shellcheck)"$'\n'
		done < <(shellcheck -S warning -f gcc -x -- "${files[@]}" 2>/dev/null)
		((n > 20)) && out+="  ... $((n - 20)) more shellcheck findings"$'\n'
	else TUI_SCAN_NOTES+="shellcheck not found, skipped (dabt scan --install shellcheck)"$'\n'; fi
	if [[ "$deep" == 1 ]]; then
		if command -v semgrep >/dev/null 2>&1; then
			n=0
			while IFS= read -r hit; do
				[[ -n "$hit" ]] || continue
				((++n))
				((++TUI_SCAN_WARN))
				out+="  WARN $hit  (semgrep)"$'\n'
			done < <(semgrep scan --config r/bash --metrics off --quiet --disable-version-check --emacs "$path" 2>/dev/null)
		else TUI_SCAN_NOTES+="semgrep not found, skipped (dabt scan --install semgrep)"$'\n'; fi
	fi
	TUI_SCAN_REPORT="$out"
	return 0
}

tui.scan.print() {
	[[ -n "$TUI_SCAN_REPORT" ]] && printf '%s' "$TUI_SCAN_REPORT"
	[[ -n "$TUI_SCAN_NOTES" ]] && printf 'note: %s' "$TUI_SCAN_NOTES"
	printf 'scan: %d high, %d warnings (static checks only; a clean scan is not a guarantee)\n' "$TUI_SCAN_HIGH" "$TUI_SCAN_WARN"
}

# ── optional tools ───────────────────────────────────────────────────────
tui.scan.tools() {
	local t
	printf 'built-in    always on\n'
	for t in shellcheck semgrep; do
		if command -v "$t" >/dev/null 2>&1; then
			printf '%-11s installed (%s)\n' "$t" "$(command -v "$t")"
		else printf '%-11s not installed   dabt scan --install %s\n' "$t" "$t"; fi
	done
	printf 'package manager: %s\n' "$(_scan.pm || echo 'none found')"
}

_scan.pm() {
	local p
	for p in apt-get dnf pacman zypper apk brew nix-env pipx pip3 pip; do command -v "$p" >/dev/null 2>&1 && {
		echo "$p"
		return 0
	}; done
	return 1
}

# TOOL -> the install command (words) for the first known package manager, or rc 1
_scan.install_cmd() {
	local tool="$1" pm root=""
	((EUID == 0)) || { command -v sudo >/dev/null 2>&1 && root="sudo "; }
	case "$tool" in
		shellcheck)
			for pm in apt-get dnf pacman zypper apk brew nix-env; do
				command -v "$pm" >/dev/null 2>&1 || continue
				case "$pm" in
					apt-get) echo "${root}apt-get install -y shellcheck" ;;
					dnf) echo "${root}dnf install -y ShellCheck" ;;
					pacman) echo "${root}pacman -S --noconfirm shellcheck" ;;
					zypper) echo "${root}zypper --non-interactive install ShellCheck" ;;
					apk) echo "${root}apk add shellcheck" ;;
					brew) echo "brew install shellcheck" ;;
					nix-env) echo "nix-env -iA nixpkgs.shellcheck" ;;
				esac
				return 0
			done
			;;
		semgrep)
			for pm in pipx brew pip3 pip; do
				command -v "$pm" >/dev/null 2>&1 || continue
				case "$pm" in
					pipx) echo "pipx install semgrep" ;;
					brew) echo "brew install semgrep" ;;
					*) echo "$pm install --user semgrep" ;;
				esac
				return 0
			done
			;;
		*) return 2 ;;
	esac
	return 1
}

tui.scan.install() {
	local tool="${1:-}" yes=0 cmd a
	[[ "${2:-}" == --yes || "${2:-}" == -y ]] && yes=1
	case "$tool" in shellcheck | semgrep) ;; *)
		echo "dabt scan: unknown tool '$tool' (shellcheck | semgrep)" >&2
		return 2
		;;
	esac
	if command -v "$tool" >/dev/null 2>&1; then
		echo "$tool is already installed"
		return 0
	fi
	cmd="$(_scan.install_cmd "$tool")" || {
		echo "dabt scan: no known package manager found for $tool; install it manually" >&2
		return 1
	}
	echo "Will run: $cmd"
	if ((! yes)); then
		read -r -p "Install $tool? [y/N] " a
		[[ "$a" == [yY]* ]] || {
			echo aborted
			return 1
		}
	fi
	bash -c "$cmd" || {
		echo "dabt scan: install failed" >&2
		case "$cmd" in
			*pacman*) echo "hint: the package database is probably out of date (404s). Run 'sudo pacman -Syu', then retry." >&2 ;;
			*apt-get*) echo "hint: try 'sudo apt-get update' first, then retry." >&2 ;;
			*dnf* | *zypper* | *apk*) echo "hint: refresh the package index / update the system first, then retry." >&2 ;;
		esac
		return 1
	}
	command -v "$tool" >/dev/null 2>&1 && echo "$tool installed" || echo "installed, but $tool is not on PATH yet (restart your shell?)"
}

tui.scan.cli() {
	local deep=0 strict=0 paths=() a rc=0 p
	while (($#)); do
		a="$1"
		shift
		case "$a" in
			--tools | tools)
				tui.scan.tools
				return
				;;
			--install)
				tui.scan.install "${1:-}" "${2:-}"
				return
				;;
			--deep) deep=1 ;; --strict) strict=1 ;;
			-h | --help | help | "") ;;
			-*)
				echo "dabt scan: unknown option $a" >&2
				return 2
				;;
			*) paths+=("$a") ;;
		esac
	done
	if ((! ${#paths[@]})); then
		cat <<'HELP'
dabt scan PATH... [--deep] [--strict]   scan scripts (file or folder) for obvious security problems
dabt scan --tools                        status of the optional scanners
dabt scan --install shellcheck|semgrep [--yes]   install one with the system package manager
Built-in rules always run; shellcheck is added when installed; --deep adds semgrep. --strict: exit 1 on HIGH findings.
HELP
		return 0
	fi
	for p in "${paths[@]}"; do
		printf '== %s\n' "$p"
		tui.scan.run "$p" "$deep" || {
			echo "$TUI_SCAN_NOTES" >&2
			rc=1
			continue
		}
		tui.scan.print
		((strict && TUI_SCAN_HIGH)) && rc=1
	done
	return $rc
}

# tui.scan.run_spin PATH [MSG] [DEEP] : tui.scan.run behind a spinner (plain one-line message when stdout is not a terminal).
# Sets the same TUI_SCAN_* vars as tui.scan.run. The scan runs in a background subshell, its result is carried back through a temp file.
tui.scan.run_spin() {
	local path="$1" msg="${2:-Scanning incoming files for vulnerabilities}" deep="${3:-0}" tmp pid i=0 rc
	local -a frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
	if [[ ! -t 1 ]]; then
		printf '%s ...\n' "$msg"
		tui.scan.run "$path" "$deep"
		return
	fi
	tmp="$(mktemp)" || {
		tui.scan.run "$path" "$deep"
		return
	}
	(
		tui.scan.run "$path" "$deep"
		rc=$?
		declare -p TUI_SCAN_HIGH TUI_SCAN_WARN TUI_SCAN_REPORT TUI_SCAN_NOTES | sed -E 's/^declare -[-a-zA-Z]+ /declare -g /' >"$tmp"
		exit $rc
	) &
	pid=$!
	printf '\e[?25l'
	trap 'kill $pid 2>/dev/null; printf "\r\e[K\e[?25h"; rm -f "$tmp"; trap - INT; return 130' INT
	while kill -0 "$pid" 2>/dev/null; do
		printf '\r\e[1;36m%s\e[0m %s' "${frames[i++ % 10]}" "$msg"
		sleep 0.08
	done
	wait "$pid"
	rc=$?
	trap - INT
	printf '\r\e[K\e[?25h'
	# shellcheck disable=SC1090 # a generated tempfile, no fixed path to point at
	source "$tmp"
	rm -f "$tmp"
	return $rc
}
