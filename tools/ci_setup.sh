#!/usr/bin/env bash
# ci_setup.sh - configures the repository for .github/workflows/build.yml with the GitHub CLI (gh must be logged in: gh auth login).
#
#   tools/ci_setup.sh [--key FILE] [--repo OWNER/NAME] [--generate]
#
# Sets   secret   DABT_SIGN_KEY             the private Ed25519 signing key (read from FILE, never printed)
#        variable DABT_SIGNER_FINGERPRINT   its fingerprint (SHA256:...), checked by the workflow
# --generate creates a dedicated passphrase-less CI key (default ~/.config/DABT/keys/dabt_ci_ed25519) if FILE does not exist, so your
# personal key never has to leave your machine. Publish the fingerprint (README) so users can pin it with --trust-key.
set -u
key="${HOME}/.config/DABT/keys/dabt_ci_ed25519"
repo=""
gen=0
while (($#)); do
	case "$1" in --key)
		key="$2"
		shift
		;;
	--repo)
		repo="$2"
		shift
		;;
	--generate) gen=1 ;;
	-h | --help)
		sed -n '2,10p' "$0" | sed 's/^# \?//'
		exit 0
		;;
	*)
		echo "ci_setup: unknown option $1" >&2
		exit 2
		;;
	esac
	shift
done
command -v gh >/dev/null 2>&1 || {
	echo "ci_setup: the GitHub CLI (gh) is required" >&2
	exit 2
}
gh auth status >/dev/null 2>&1 || {
	echo "ci_setup: run  gh auth login  first" >&2
	exit 2
}
[[ -n "$repo" ]] || repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
[[ -n "$repo" ]] || {
	echo "ci_setup: cannot tell the repository; pass --repo OWNER/NAME" >&2
	exit 2
}
if [[ ! -f "$key" ]]; then
	((gen)) || {
		echo "ci_setup: $key does not exist (use --generate, or --key FILE)" >&2
		exit 2
	}
	mkdir -p "$(dirname "$key")" && ssh-keygen -q -t ed25519 -N "" -C "dabt-ci" -f "$key" </dev/null && chmod 600 "$key" || exit 1
	echo "created $key"
fi
fp="$(ssh-keygen -lf "$key" | awk '{print $2}')"
gh secret set DABT_SIGN_KEY --repo "$repo" <"$key" || exit 1
gh variable set DABT_SIGNER_FINGERPRINT --repo "$repo" --body "$fp" || exit 1
echo "set secret DABT_SIGN_KEY and variable DABT_SIGNER_FINGERPRINT=$fp on $repo"
