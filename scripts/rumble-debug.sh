#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Debug the rumble test under gdb. Run as root.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG=/tmp/g7pro-rumble-debug.log
exec >"$LOG" 2>&1
set -x

cleanup() {
	rmmod g7pro 2>/dev/null || true
	[ -n "${IF:-}" ] && echo -n "$IF" > /sys/bus/usb/drivers/xpad/bind 2>/dev/null || true
}
trap cleanup EXIT

DEV=$(grep -l '^3537$' /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1)
[ -n "$DEV" ] || exit 1
BUS=$(basename "$(dirname "$DEV")")
IF="$BUS:1.0"
[ -e "/sys/bus/usb/drivers/xpad/$IF" ] && echo -n "$IF" > /sys/bus/usb/drivers/xpad/unbind

insmod "$ROOT/g7pro.ko" || exit 1
sleep 2

EV_GAME=
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null || true)
	if [ "$name" = "GameSir G7 Pro" ]; then
		EV_GAME=$ev
		break
	fi
done
echo "EV_GAME=$EV_GAME"

gdb -batch -ex run -ex "bt full" --args "$ROOT/tests/rumble_test_dbg" "$EV_GAME" || true

echo "=== dmesg ==="
dmesg | tail -80
