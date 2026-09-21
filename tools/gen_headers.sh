#!/usr/bin/env bash
# Regenerates all README section headers via tools/gen_header.sh.
set -eu
d=$(dirname "$0")
for h in "what-is-this|WHAT IS THIS?" "quick-start|QUICK START" "the-dabt-command|THE DABT COMMAND" \
  "features|FEATURES" "security-scan|SECURITY SCAN" "plugins|PLUGINS" "screenshots|SCREENSHOTS" \
  "themes|THEMES" "documentation|DOCUMENTATION" "project-structure|PROJECT STRUCTURE" \
  "requirements|REQUIREMENTS" "going-beyond-the-demo|GOING BEYOND THE DEMO" "contributing|CONTRIBUTING" \
  "release-new|NEW IN 0.0.8" "release-install|INSTALL OR UPDATE" "release-package|PACKAGE YOUR OWN APP" \
  "release-added|ADDED" "release-changed|CHANGED" "release-fixed|FIXED"; do
  "$d/gen_header.sh" "${h#*|}" "$d/../assets/headers/${h%%|*}.svg" >/dev/null
done
