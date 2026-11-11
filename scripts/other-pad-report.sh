#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# One-command regression report for the GameSir G7 Pro xpad series.
#
# Loads the patched xpad temporarily, records what changed, restores the stock
# module and writes a report you can attach to the issue.  Nothing is made
# persistent and no data leaves the machine.
#
#   sudo ./scripts/other-pad-report.sh
#
# Tested expectation: for a non-GameSir pad nothing should change at all.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${OUT:-/tmp/xpad-report-$(date +%Y%m%d-%H%M%S).txt}
MOD="$ROOT/xpad/xpad.ko"
KDIR=/lib/modules/$(uname -r)/build
CAPS_BEFORE=$OUT.before
CAPS_AFTER=$OUT.after

say() { echo "$*" | tee -a "$OUT"; }
sec() { echo "" | tee -a "$OUT"; echo "=== $* ===" | tee -a "$OUT"; }

if [ "$(id -u)" != 0 ]; then
	echo "run as root: sudo $0" >&2
	exit 1
fi

: >"$OUT"
say "xpad regression report"
say "date: $(date -Is)"
say "kernel: $(uname -a)"
say "arch: $(uname -m)"

FAILED=0
RESTORE_STOCK=1
cleanup() {
	if [ "$RESTORE_STOCK" = 1 ]; then
		rmmod xpad 2>/dev/null || true
		modprobe xpad 2>/dev/null || true
	fi
}
trap cleanup EXIT

# Build the patched module against the running kernel.
sec "build"
if [ ! -d "$KDIR" ]; then
	say "FAIL: kernel headers missing ($KDIR). Install the headers for $(uname -r)."
	exit 1
fi
# Use the compiler the running kernel was built with: clang-built kernels
# reject the GCC-only flags recorded in their build config and vice versa.
MAKE_ARGS=
if grep -qi 'clang' /proc/version; then
	MAKE_ARGS="LLVM=1"
	say "kernel built with clang; using LLVM=1"
fi
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
	BUILD_CMD="make $MAKE_ARGS -C '$KDIR' M='$ROOT/xpad' modules"
	su -s /bin/sh "$SUDO_USER" -c "$BUILD_CMD" >>"$OUT" 2>&1 || BUILD_RC=$?
else
	make $MAKE_ARGS -C "$KDIR" M="$ROOT/xpad" modules >>"$OUT" 2>&1 || BUILD_RC=$?
fi
if [ "${BUILD_RC:-0}" != 0 ]; then
	say "FAIL: module build failed; see the compiler output above."
	say "Common causes: headers for $(uname -r) are missing, the kernel was built"
	say "with a different compiler than the one installed, or the module needs"
	say "signing for Secure Boot."
	exit 1
fi
say "build: ok ($MOD)"

# Is xpad a module we can replace?
if ! modinfo -n xpad >/dev/null 2>&1; then
	say "NOTE: xpad appears to be built into this kernel; it cannot be replaced at runtime."
	say "      The report below still records the current devices; mention this in the issue."
	RESTORE_STOCK=0
fi

build_tools() {
	mkdir -p "$ROOT/tests" 2>/dev/null || true
	cc -O2 -Wall -Wextra -o /tmp/evdev_caps_report "$ROOT/tests/evdev_caps.c" >/dev/null 2>&1 || return 1
	cc -O2 -Wall -Wextra -o /tmp/rumble_test_report "$ROOT/tests/rumble_test.c" >/dev/null 2>&1 || return 1
	return 0
}

# Capture evdev capabilities for every node that has axes (pads and sensors).
capture_caps() {
	out=$1
	: >"$out"
	for ev in /dev/input/event*; do
		[ -e "$ev" ] || continue
		base="/sys/class/input/$(basename "$ev")/device"
		[ -n "$(cat "$base/capabilities/abs" 2>/dev/null)" ] || continue
		name=$(cat "$base/name" 2>/dev/null)
		# Event numbers change across module reload; key on the name only.
		echo "-- $name" >>"$out"
		/tmp/evdev_caps_report "$ev" >>"$out" 2>&1 || true
	done
}

build_tools || { say "FAIL: could not build the test helpers"; exit 1; }

sec "devices before"
lsusb >>"$OUT" 2>&1 || true
cat /proc/bus/input/devices >>"$OUT"
capture_caps "$CAPS_BEFORE"
say "captured $(grep -c '^-- ' "$CAPS_BEFORE") input node(s)"

if [ "$RESTORE_STOCK" != 1 ]; then
	sec "result"
	say "SKIPPED: built-in xpad cannot be replaced. Report the devices above."
	exit 0
fi

sec "load patched module"
if ! rmmod xpad >>"$OUT" 2>&1; then
	say "FAIL: xpad is in use. Close games and controller tools, then run again."
	exit 1
fi
if ! insmod "$MOD" >>"$OUT" 2>&1; then
	say "FAIL: insmod failed (see log above). Secure Boot signing is the usual cause."
	exit 1
fi
sleep 2

sec "devices after"
lsusb >>"$OUT" 2>&1 || true
cat /proc/bus/input/devices >>"$OUT"
capture_caps "$CAPS_AFTER"

# A short rumble on the first pad that advertises FF, as an end-to-end check.
sec "rumble"
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	base="/sys/class/input/$(basename "$ev")/device"
	name=$(cat "$base/name" 2>/dev/null)
	case "$name" in *"Motion Sensors"*) continue ;; esac
	if /tmp/rumble_test_report "$ev" 1000 >>"$OUT" 2>&1; then
		say "rumble: ok on $ev ($name)"
		break
	fi
done

sec "comparison"
if diff -u "$CAPS_BEFORE" "$CAPS_AFTER" >>"$OUT"; then
	say "RESULT: IDENTICAL — no capability change on this pad"
else
	say "RESULT: DIFFERENT — see the diff above"
	FAILED=1
fi

sec "dmesg"
dmesg | tail -120 >>"$OUT" 2>&1 || true

# Redact anything device- or host-identifying before the user shares it.
sec "privacy"
sed -i -E 's/^(U: Uniq=).*/\1<redacted>/; s/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/<mac>/g; s/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' "$OUT"
say "controller serials, MACs and IPs were replaced with placeholders"

sec "done"
say "report: $OUT"
say "attach that file to the issue; it contains no serials, MACs or IPs."
if [ "$FAILED" = 1 ]; then
	if lsusb | grep -q '3537:109b'; then
		say "NOTE: this is the GameSir G7 Pro, whose differences (name and the"
		say "      new motion node) are expected. This report is not needed for"
		say "      issue #1, which asks for other controllers."
	else
		say "POSSIBLE REGRESSION: a non-GameSir pad changed. Please attach this"
		say "report and mention it in issue #1."
	fi
fi
exit 0
