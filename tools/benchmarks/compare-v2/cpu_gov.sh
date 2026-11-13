#!/bin/sh
# cpu_gov.sh on|off  -  on: governor "performance"; off: restore the previous one (default schedutil).
# Needs root for the sysfs write (uses sudo when not root).
S=/tmp/cpu_gov.prev
G=/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
set_gov() { for f in $G; do echo "$1" | ${SUDO} tee "$f" >/dev/null; done; }
SUDO=
[ "$(id -u)" -eq 0 ] || SUDO=sudo
case "$1" in
	on)
		[ -f "$S" ] || {
			read -r cur </sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
			echo "$cur" >"$S"
		}
		set_gov performance
		;;
	off)
		prev=schedutil
		[ -f "$S" ] && read -r prev <"$S"
		set_gov "$prev"
		rm -f "$S"
		;;
	*)
		echo "usage: $0 on|off" >&2
		exit 1
		;;
esac
read -r now </sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo "governor: $now"
