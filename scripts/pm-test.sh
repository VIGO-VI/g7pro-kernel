#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Suspended/resume test for the patched xpad on real hardware.
#
# Run as root after stopping the userspace bridge:
#
#   systemctl --user stop g7motion
#   sudo ./scripts/pm-test.sh
#   systemctl --user start g7motion
#
# It loads the patched xpad, checks IMU + rumble, suspends for 15 s, checks
# both again after resume, then restores the stock module.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG=/tmp/g7pro-pm-test.log
MOD="$ROOT/xpad/xpad.ko"
SLEEP=${PM_SLEEP:-15}

exec >"$LOG" 2>&1
set -x

cleanup() {
	rmmod xpad 2>/dev/null || true
	modprobe xpad 2>/dev/null || true
}
trap cleanup EXIT

[ -f "$MOD" ] || { echo "missing $MOD"; exit 1; }

rmmod xpad || exit 1
insmod "$MOD" || exit 1
sleep 2

find_nodes() {
	GAME_EV=
	MOTION_EV=
	for ev in /dev/input/event*; do
		[ -e "$ev" ] || continue
		name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
		case "$name" in
		"GameSir G7 Pro") GAME_EV=$ev ;;
		*"Motion Sensors"*) MOTION_EV=$ev ;;
		esac
	done
}

check() {
	stage=$1
	find_nodes
	echo "=== $stage: gamepad=$GAME_EV motion=$MOTION_EV"
	if [ -z "$GAME_EV" ] || [ -z "$MOTION_EV" ]; then
		echo "FAIL: missing input devices"
		return 1
	fi

	# The URB runs only while the gamepad is open, so hold it open.
	"$ROOT/tests/rumble_test" "$GAME_EV" 2000 &
	hold=$!
	sleep 1
	echo "--- IMU samples (expect n>0)"
	"$ROOT/tests/accel_watch" "$MOTION_EV" 1200
	wait "$hold" 2>/dev/null || true

	echo "--- power supply"
	for p in /sys/class/power_supply/*; do
		[ -e "$p" ] || continue
		echo "$p: $(cat "$p/capacity" 2>/dev/null) $(cat "$p/status" 2>/dev/null)"
	done

	echo "--- dmesg"
	dmesg | tail -30
}

check before-suspend || exit 1

echo "=== suspending for $SLEEP s"
rtcwake -m mem -s "$SLEEP" || { echo "rtcwake failed"; exit 1; }
sleep 3

check after-resume || exit 1
echo "=== done"
