#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Disconnect/reconnect the USB device while the custom xpad is streaming.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG=/tmp/xpad-g7pro-hotplug.log
exec >"$LOG" 2>&1
set -x
dmesg -C 2>/dev/null || true

cleanup() {
	rmmod xpad 2>/dev/null || true
	modprobe xpad 2>/dev/null || true
}
trap cleanup EXIT

DEV=$(grep -l '^3537$' /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1)
[ -n "$DEV" ] || exit 1
BUS=$(basename "$(dirname "$DEV")")
echo "BUS=$BUS"

rmmod xpad || exit 1
insmod "$ROOT/xpad/xpad.ko" || exit 1
sleep 3

echo -n "$BUS" > /sys/bus/usb/drivers/usb/unbind
sleep 2
echo -n "$BUS" > /sys/bus/usb/drivers/usb/bind
sleep 4

echo "=== input devices after reconnect ==="
grep -A12 -B2 -i "GameSir G7 Pro" /proc/bus/input/devices || true
echo "=== battery ==="
for p in /sys/class/power_supply/g7pro-*; do
	[ -e "$p" ] || continue
	echo "--- $p"
	cat "$p/capacity" "$p/status" 2>/dev/null || true
done
echo "=== dmesg ==="
dmesg | tail -120
echo "=== SDL3 probe ==="
[ -x /home/greenstar/Projects/g7motion/build/sdl3_probe ] && /home/greenstar/Projects/g7motion/build/sdl3_probe || true
