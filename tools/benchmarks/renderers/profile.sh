#!/usr/bin/env bash
# profile.sh - renderer profiler: times every renderer of lib/terminal_renderer.sh on several datasets and argument sets.
#   tools/benchmarks/renderers/profile.sh [--quick] [--only box,table] [--list] [--report DIR]   (profile.sh --help: every option)
((BASH_VERSINFO[0] >= 5)) || {
	echo "profile.sh needs bash >= 5" >&2
	exit 1
}
command -v python3 >/dev/null || {
	echo "profile.sh needs python3 (standard library only)" >&2
	exit 1
}
exec python3 -I "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/profile.py" "$@"
