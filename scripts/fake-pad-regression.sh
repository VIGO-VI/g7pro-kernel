#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Compare stock xpad and the patched xpad against an emulated non-GameSir pad
# (045e:028e) on dummy_hcd.  Supplementary evidence: it proves the shared
# driver paths produce the same input device capabilities for a non-G7 pad.
#
#   sudo ./scripts/fake-pad-regression.sh
#
# Requires CONFIG_USB_DUMMY_HCD and CONFIG_USB_RAW_GADGET.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:-/tmp/fake-pad-regression.log}
MOD="$ROOT/xpad/xpad.ko"
KDIR=/lib/modules/$(uname -r)/build
FAKE=/tmp/fake_xpad
CAPS_STOCK=$OUT.stock
CAPS_PATCHED=$OUT.patched

exec >"$OUT" 2>&1
set -x

if [ "$(id -u)" != 0 ]; then
	echo "run as root" >&2
	exit 1
fi

cleanup() {
	kill "${FAKE_PID:-0}" 2>/dev/null || true
	wait "${FAKE_PID:-0}" 2>/dev/null || true
	pkill -f /tmp/fake_xpad 2>/dev/null || true
	rmmod xpad 2>/dev/null || true
	modprobe xpad 2>/dev/null || true
	rmmod dummy_hcd 2>/dev/null || true
	rmmod raw_gadget 2>/dev/null || true
}
trap cleanup EXIT

# Start from a clean UDC: a half-configured device from a failed run would
# otherwise satisfy the VID/PID check below.
pkill -f /tmp/fake_xpad 2>/dev/null || true
rmmod dummy_hcd 2>/dev/null || true
rmmod raw_gadget 2>/dev/null || true
modprobe dummy_hcd || exit 1
modprobe raw_gadget || exit 1
cc -O2 -Wall -Wextra -o "$FAKE" "$ROOT/tests/fake_xpad.c" || exit 1
cc -O2 -Wall -Wextra -o /tmp/evdev_caps_report "$ROOT/tests/evdev_caps.c" || exit 1

MAKE_ARGS=
grep -qi clang /proc/version && MAKE_ARGS="LLVM=1"
make $MAKE_ARGS -C "$KDIR" M="$ROOT/xpad" modules || exit 1

wait_for_fake() {
	i=0
	while [ $i -lt 50 ]; do
		for f in /sys/bus/usb/devices/*/idVendor; do
			[ -e "$f" ] || continue
			[ "$(cat "$f")" = 045e ] || continue
			d=$(dirname "$f")
			[ "$(cat "$d/idProduct" 2>/dev/null)" = 028e ] || continue
			[ "$(cat "$d/bConfigurationValue" 2>/dev/null)" = 1 ] && return 0
		done
		i=$((i + 1))
		sleep 0.1
	done
	return 1
}

capture() {
	out=$1
	: >"$out"
	for ev in /dev/input/event*; do
		[ -e "$ev" ] || continue
		base="/sys/class/input/$(basename "$ev")/device"
		[ "$(cat "$base/id/vendor" 2>/dev/null)" = 045e ] || continue
		[ "$(cat "$base/id/product" 2>/dev/null)" = 028e ] || continue
		echo "-- $(cat "$base/name" 2>/dev/null)" >>"$out"
		/tmp/evdev_caps_report "$ev" >>"$out" 2>&1 || true
	done
}

run_case() {
	tag=$1
	shift

	"$@" || return 1
	"$FAKE" & FAKE_PID=$!
	if ! wait_for_fake; then
		echo "fake pad did not enumerate ($tag)"
		dmesg | tail -40
		for f in /sys/bus/usb/devices/*/idVendor; do
			[ -e "$f" ] || continue
			echo "candidate $(dirname "$f") vid=$(cat "$f") pid=$(cat "$(dirname "$f")/idProduct" 2>/dev/null) cfg=$(cat "$(dirname "$f")/bConfigurationValue" 2>/dev/null)"
		done
		kill "$FAKE_PID" 2>/dev/null
		return 1
	fi
	sleep 1
	echo "=== $tag fake device state ==="
	for f in /sys/bus/usb/devices/*/idVendor; do
		[ -e "$f" ] || continue
		[ "$(cat "$f")" = 045e ] || continue
		d=$(dirname "$f")
		[ "$(cat "$d/idProduct" 2>/dev/null)" = 028e ] || continue
		echo "path=$d class=$(cat "$d/bDeviceClass" 2>/dev/null) cfg=$(cat "$d/bConfigurationValue" 2>/dev/null)"
		for i in "$d"/*:*/; do
			[ -e "$i" ] || continue
			echo "  interface $(basename "$i") driver=$(basename "$(readlink -f "$i/driver" 2>/dev/null)")"
		done
	done
	echo "xpad driver entries: $(ls /sys/bus/usb/drivers/xpad/ 2>/dev/null | tr '\n' ' ')"
	dmesg | tail -40
	echo "=== $tag input devices ==="
	cat /proc/bus/input/devices
	capture "$tag"
	n=$(grep -c '^-- ' "$tag" || true)
	if [ "$n" -eq 0 ]; then
		echo "ERROR: xpad did not bind to the fake pad ($tag)"
		dmesg | tail -20
		return 1
	fi
	echo "captured $n input node(s) for $tag"
	kill "$FAKE_PID" 2>/dev/null
	wait "$FAKE_PID" 2>/dev/null || true
	FAKE_PID=
	sleep 1
}

rmmod xpad || true
run_case "$CAPS_STOCK" modprobe xpad || { echo "stock case failed"; exit 1; }
rmmod xpad || true
run_case "$CAPS_PATCHED" insmod "$MOD" || { echo "patched case failed"; exit 1; }
rmmod xpad || true
modprobe xpad || true

echo "=== comparison ==="
if diff -u "$CAPS_STOCK" "$CAPS_PATCHED"; then
	echo "RESULT: IDENTICAL — patched xpad presents the same capabilities"
else
	echo "RESULT: DIFFERENT — investigate before submitting"
fi
