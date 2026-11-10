#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Hardware smoke test for g7pro.ko.  Run as root:
#   sudo ./scripts/hw-test.sh
#
# It unbinds xpad from the controller, loads the module, prints the kernel
# and input-device state, runs the SDL3 probe, then unloads the module and
# rebinds xpad.  Everything goes to /tmp/g7pro-kernel-test.log.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOD="$ROOT/g7pro.ko"
LOG=/tmp/g7pro-kernel-test.log
SDL_PROBE=${SDL_PROBE:-$ROOT/../g7motion/build/sdl3_probe}

exec >"$LOG" 2>&1
set -x
dmesg -C 2>/dev/null || true

cleanup() {
	rmmod g7pro 2>/dev/null || true
	if [ -n "${IF:-}" ] && [ -e /sys/bus/usb/drivers/xpad/bind ]; then
		echo -n "$IF" > /sys/bus/usb/drivers/xpad/bind 2>/dev/null || true
	fi
}
trap cleanup EXIT

DEV=$(grep -l '^3537$' /sys/bus/usb/devices/*/idVendor 2>/dev/null | head -1)
if [ -z "$DEV" ]; then
	echo "GameSir device not found"
	exit 1
fi
BUS=$(basename "$(dirname "$DEV")")
IF="$BUS:1.0"
echo "device=$DEV interface=$IF"

# Structural xpad baseline before we unbind it.
EV_XPAD=
set +x
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null || true)
	case "$name" in
	*X-Box*|*GameSir*)
		EV_XPAD=$ev
		break
		;;
	esac
done
[ -n "$EV_XPAD" ] && "$ROOT/tests/evdev_caps" "$EV_XPAD" > /tmp/xpad-caps.txt 2>&1 || true
set -x

if [ -e "/sys/bus/usb/drivers/xpad/$IF" ]; then
	echo -n "$IF" > /sys/bus/usb/drivers/xpad/unbind
fi

insmod "$MOD" || exit 1
sleep 2

echo "=== dmesg ==="
dmesg | tail -100

echo "=== input devices ==="
grep -A12 -B2 -i "GameSir G7 Pro" /proc/bus/input/devices || true

echo "=== evdev caps ==="
set +x
EV_GAME=$(for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null || true)
	[ "$name" = "GameSir G7 Pro" ] && { echo "$ev"; break; }
done)
[ -n "$EV_GAME" ] && "$ROOT/tests/evdev_caps" "$EV_GAME" > /tmp/g7pro-caps.txt 2>&1 || true
echo "--- xpad baseline"; cat /tmp/xpad-caps.txt 2>/dev/null || true
echo "--- g7pro"; cat /tmp/g7pro-caps.txt 2>/dev/null || true
echo "--- diff (names/IDs will differ)"; diff -u /tmp/xpad-caps.txt /tmp/g7pro-caps.txt 2>/dev/null || true
set -x

echo "=== battery ==="
for p in /sys/class/power_supply/g7pro-*; do
	[ -e "$p" ] || continue
	echo "--- $p"
	cat "$p/capacity" "$p/status" 2>/dev/null || true
done

echo "=== udev properties ==="
set +x
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null || true)
	case "$name" in
	*"GameSir G7 Pro"*)
		echo "--- $ev: $name"
		udevadm info --query=property --name="$ev" |
			grep -E 'ID_INPUT|ID_PATH|ID_SERIAL' || true
		;;
	esac
done

echo "=== rumble ==="
if [ -n "$EV_GAME" ] && [ -x "$ROOT/tests/rumble_test" ]; then
	"$ROOT/tests/rumble_test" "$EV_GAME" || true
else
	echo "rumble_test or gamepad event node missing (EV_GAME=$EV_GAME)"
fi

echo "=== SDL3 probe ==="
echo "Rotate the controller now; the probe runs for 8 seconds." >/dev/tty 2>/dev/null || true
sleep 3
if [ -x "$SDL_PROBE" ]; then
	"$SDL_PROBE" || true
else
	echo "missing $SDL_PROBE"
fi

echo "=== done ==="
