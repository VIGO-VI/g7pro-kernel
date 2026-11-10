#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Load g7pro, then ask the user to physically unplug/replug the controller.
# Log: /tmp/g7pro-replug.log.  Run as root, same USB port both times.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG=/tmp/g7pro-replug.log
exec >"$LOG" 2>&1
set -x
dmesg -C 2>/dev/null || true

cleanup() {
	rmmod g7pro 2>/dev/null || true
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

echo "UNPLUG the controller now (same port); waiting up to 60s..." >/dev/tty 2>/dev/null || true
n=0
while [ -e "/sys/bus/usb/devices/$BUS" ] && [ $n -lt 600 ]; do
	n=$((n + 1))
	sleep 0.1
done
echo "Detected unplug. REPLUG it now; waiting up to 60s..." >/dev/tty 2>/dev/null || true
n=0
while [ ! -e "/sys/bus/usb/devices/$BUS" ] && [ $n -lt 600 ]; do
	n=$((n + 1))
	sleep 0.1
done
sleep 4

PID=$(cat "/sys/bus/usb/devices/$BUS/idProduct" 2>/dev/null || echo unknown)
echo "PID after replug: $PID"
if [ "$PID" = "1022" ]; then
	echo "Controller returned as native/GIP 1022." >/dev/tty 2>/dev/null || true
	echo "Hold Share+Menu for ~4s until the LED blinks, then wait..." >/dev/tty 2>/dev/null || true
	n=0
	while [ "$(cat "/sys/bus/usb/devices/$BUS/idProduct" 2>/dev/null)" = "1022" ] && [ $n -lt 600 ]; do
		n=$((n + 1))
		sleep 0.1
	done
	PID=$(cat "/sys/bus/usb/devices/$BUS/idProduct" 2>/dev/null || echo unknown)
	echo "PID after mode switch: $PID"
fi

echo "=== driver after replug ==="
for d in /sys/bus/usb/drivers/*/"$IF"; do
	[ -e "$d" ] && echo "bound: $(basename "$(dirname "$d")")"
done

echo "=== input devices after replug ==="
grep -A12 -B2 -i "GameSir G7 Pro" /proc/bus/input/devices || true
echo "=== dmesg ==="
dmesg | tail -120

# If xpad won, hand it back explicitly for the rest of the test.
if [ -e "/sys/bus/usb/drivers/xpad/$IF" ]; then
	echo -n "$IF" > /sys/bus/usb/drivers/xpad/unbind
	[ -e /sys/bus/usb/drivers/g7pro/bind ] && echo -n "$IF" > /sys/bus/usb/drivers/g7pro/bind || true
	sleep 2
fi
echo "=== input devices after handover ==="
grep -A12 -B2 -i "GameSir G7 Pro" /proc/bus/input/devices || true

echo "=== SDL3 probe ==="
if [ -x /home/greenstar/Projects/g7motion/build/sdl3_probe ]; then
	/home/greenstar/Projects/g7motion/build/sdl3_probe || true
fi
