#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Simulate a USB disconnect/reconnect while g7pro is streaming.
# Run as root.  Log: /tmp/g7pro-hotplug.log.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG=/tmp/g7pro-hotplug.log
exec >"$LOG" 2>&1
set -x
dmesg -C 2>/dev/null || true

cleanup() {
	rmmod g7pro 2>/dev/null || true
	[ -n "${BUS:-}" ] && echo -n "$BUS" > /sys/bus/usb/drivers/usb/bind 2>/dev/null || true
	[ -n "${IF:-}" ] && echo -n "$IF" > /sys/bus/usb/drivers/xpad/bind 2>/dev/null || true
}
trap cleanup EXIT

DEV=$(grep -l '^3537$' /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1)
[ -n "$DEV" ] || exit 1
BUS=$(basename "$(dirname "$DEV")")
IF="$BUS:1.0"
echo "BUS=$BUS IF=$IF"

[ -e "/sys/bus/usb/drivers/xpad/$IF" ] && echo -n "$IF" > /sys/bus/usb/drivers/xpad/unbind
insmod "$ROOT/g7pro.ko" || exit 1
sleep 2
grep -c "GameSir G7 Pro" /proc/bus/input/devices || true

# Disconnect the whole USB device while the input URB is active.
echo -n "$BUS" > /sys/bus/usb/drivers/usb/unbind
sleep 2
echo -n "$BUS" > /sys/bus/usb/drivers/usb/bind
sleep 3

# xpad may win the re-probe; hand interface 0 back to g7pro.
if [ -e "/sys/bus/usb/drivers/xpad/$IF" ]; then
	echo -n "$IF" > /sys/bus/usb/drivers/xpad/unbind
fi
if [ -e "/sys/bus/usb/drivers/g7pro/$IF" ]; then
	:
elif [ -e /sys/bus/usb/drivers/g7pro/bind ]; then
	echo -n "$IF" > /sys/bus/usb/drivers/g7pro/bind 2>/dev/null || true
fi
sleep 2

echo "=== input devices after reconnect ==="
grep -A12 -B2 -i "GameSir G7 Pro" /proc/bus/input/devices || true
echo "=== dmesg ==="
dmesg | tail -100

echo "=== SDL3 probe ==="
if [ -x /home/greenstar/Projects/g7motion/build/sdl3_probe ]; then
	/home/greenstar/Projects/g7motion/build/sdl3_probe || true
fi
