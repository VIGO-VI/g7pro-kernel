#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Test the xpad extension as a temporary module.  Run as root.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG=/tmp/xpad-g7pro-test.log
exec >"$LOG" 2>&1
set -x
dmesg -C 2>/dev/null || true

cleanup() {
	rmmod xpad 2>/dev/null || true
	modprobe xpad 2>/dev/null || true
}
trap cleanup EXIT

rmmod xpad || exit 1
insmod "$ROOT/xpad/xpad.ko" || exit 1
sleep 3

echo "=== input devices ==="
grep -A12 -B2 -i "GameSir G7 Pro" /proc/bus/input/devices || true
echo "=== battery ==="
for p in /sys/class/power_supply/g7pro-*; do
	[ -e "$p" ] || continue
	echo "--- $p"
	cat "$p/capacity" "$p/status" 2>/dev/null || true
done
echo "=== dmesg ==="
dmesg | tail -120
echo "=== rumble ==="
EV_GAME=
set +x
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null || true)
	if [ "$name" = "GameSir G7 Pro" ]; then EV_GAME=$ev; break; fi
done
set -x
if [ -n "$EV_GAME" ] && [ -x "$ROOT/tests/rumble_test" ]; then
	"$ROOT/tests/rumble_test" "$EV_GAME" || true
fi
echo "=== SDL3 probe ==="
echo "Rotate the controller now; the probe runs for 8 seconds." >/dev/tty 2>/dev/null || true
sleep 3
[ -x /home/greenstar/Projects/g7motion/build/sdl3_probe ] && /home/greenstar/Projects/g7motion/build/sdl3_probe || true
