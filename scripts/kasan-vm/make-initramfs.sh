#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build a busybox initramfs containing g7pro.ko and the test binaries.
#
# Usage:
#   KERNEL_SRC=~/Projects/kasan-kernel/linux-7.3.4 \
#   REPO=~/Projects/g7pro-kernel ./make-initramfs.sh
set -eu

KERNEL_SRC=${KERNEL_SRC:?set KERNEL_SRC to the kernel tree}
REPO=${REPO:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
OUT=${OUT:-/tmp/g7pro-kasan}
# Default to the upstream submission (xpad); MODULE=g7pro tests the
# standalone prototype instead.
MODULE=${MODULE:-xpad}
WORK=$OUT/root
INITRD=$OUT/initramfs.cpio.gz

rm -rf "$WORK" "$INITRD"
mkdir -p "$WORK"/{bin,lib/modules,tests,proc,sys,dev,tmp}

# Static busybox gives us a shell and the few applets init needs.
cp "$(command -v busybox)" "$WORK/bin/busybox"
for applet in sh mount insmod ls cat sleep echo dmesg poweroff grep cut; do
	ln -sf busybox "$WORK/bin/$applet"
done

# Build the module against the target tree.
case "$MODULE" in
xpad)
	make -C "$KERNEL_SRC" LLVM=1 M="$REPO/xpad" modules >/dev/null
	KO="$REPO/xpad/xpad.ko"
	;;
stock)
	# The unmodified in-tree xpad, for a control run against the same kernel.
	KO="$KERNEL_SRC/drivers/input/joystick/xpad.ko"
	;;
none)
	# No module: control run to attribute reports that happen before load.
	KO=
	;;
g7pro)
	make -C "$KERNEL_SRC" LLVM=1 M="$REPO" modules >/dev/null
	KO="$REPO/g7pro.ko"
	;;
*)
	echo "unknown MODULE=$MODULE"; exit 1
	;;
esac
[ -n "$KO" ] && cp "$KO" "$WORK/lib/modules/$MODULE.ko"

# Static test binaries.
cc -static -O2 -Wall -Wextra -o "$WORK/tests/evdev_caps" "$REPO/tests/evdev_caps.c"
cc -static -O2 -Wall -Wextra -o "$WORK/tests/rumble_test" "$REPO/tests/rumble_test.c"
cc -static -O2 -Wall -Wextra -I"$REPO" -o "$WORK/tests/parser_test" "$REPO/tests/parser_test.c"
cc -static -O2 -Wall -Wextra -o "$WORK/tests/accel_watch" "$REPO/tests/accel_watch.c" -lm

cat > "$WORK/init" <<'EOF'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
echo "=== init: loading module ==="
insmod /lib/modules/__MODULE__.ko || echo "insmod failed"
sleep 2


echo "=== input devices ==="
cat /proc/bus/input/devices
echo "=== power supply ==="
for p in /sys/class/power_supply/*; do
	[ -e "$p" ] || continue
	echo "--- $p"
	cat "$p/name" "$p/capacity" "$p/status" 2>/dev/null
done

echo "=== parser test ==="
/tests/parser_test || echo "parser_test failed"

echo "=== evdev + ff ==="
FOUND=
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	base="/sys/class/input/$(basename "$ev")/device"
	[ "$(cat "$base/id/vendor" 2>/dev/null)" = 3537 ] || continue
	# Only the gamepad advertises force feedback; the motion node does not.
	case "$(cat "$base/name" 2>/dev/null)" in *"Motion Sensors"*) continue ;; esac
	/tests/evdev_caps "$ev"
	/tests/accel_watch "$ev" 300
	[ -n "${GAME_EV:-}" ] || GAME_EV=$ev
	/tests/rumble_test "$ev" 5000 || echo "rumble_test failed"
	FOUND=1
done
[ -n "$FOUND" ] && echo "GAMEPAD-FOUND" || echo "NO-GAMEPAD"

# Prove the IMU stream is alive.  xpad only submits its input URB while the
# gamepad is open, so hold it open with a background effect.
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	case "$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)" in
	*"Motion Sensors"*)
		MOTION_EV=$ev
		;;
	esac
done
if [ -n "${MOTION_EV:-}" ] && [ -n "${GAME_EV:-}" ]; then
	/tests/rumble_test "$GAME_EV" 2000 &
	HOLD_PID=$!
	sleep 1
	echo "IMU check (gamepad held open)"
	/tests/accel_watch "$MOTION_EV" 1200
	wait "$HOLD_PID" 2>/dev/null || true
fi

echo "=== runtime PM ==="
for d in /sys/bus/usb/devices/*/idVendor; do
	[ -e "$d" ] || continue
	[ "$(cat "$d")" = 3537 ] || continue
	P=$(dirname "$d")/power
	echo "control=$(cat "$P/control") status=$(cat "$P/runtime_status")"
	echo auto > "$P/control"
	sleep 2
	echo "after-auto control=$(cat "$P/control") status=$(cat "$P/runtime_status")"
	echo on > "$P/control"
done

echo "=== concurrent FF clients ==="
if [ -n "${GAME_EV:-}" ]; then
	/tests/rumble_test "$GAME_EV" 1500 & P1=$!
	/tests/rumble_test "$GAME_EV" 1500 & P2=$!
	sleep 1
	/tests/rumble_test "$GAME_EV" 800 & P3=$!
	wait $P1 2>/dev/null || echo "client1 failed"
	wait $P2 2>/dev/null || echo "client2 failed"
	wait $P3 2>/dev/null || echo "client3 failed"
	echo "CONCURRENT-FF-DONE"
fi

echo "=== teardown under load ==="
if [ -n "$FOUND" ]; then
	/tests/rumble_test "$GAME_EV" 3000 &
	TEST_PID=$!
	sleep 1
	UDEV=
	for d in /sys/bus/usb/devices/*/idVendor; do
		[ -e "$d" ] || continue
		[ "$(cat "$d")" = 3537 ] && UDEV=$(dirname "$d")
	done
	if [ -n "$UDEV" ]; then
		NAME=${UDEV##*/}
		echo "unbinding $NAME during FF"
		echo "$NAME" > /sys/bus/usb/drivers/usb/unbind
		sleep 1
		echo "$NAME" > /sys/bus/usb/drivers/usb/bind
		sleep 2
	fi
	wait "$TEST_PID" 2>/dev/null || true
	echo "GAMEPAD-FOUND after rebind" >/dev/null
	for ev in /dev/input/event*; do
		[ -e "$ev" ] || continue
		base="/sys/class/input/$(basename "$ev")/device"
		[ "$(cat "$base/id/vendor" 2>/dev/null)" = 3537 ] || continue
		case "$(cat "$base/name" 2>/dev/null)" in *"Motion Sensors"*) continue ;; esac
		echo "REBIND-GAMEPAD-OK"
	done
fi

echo "=== dmesg tail ==="
dmesg | tail -40
echo "=== init: done ==="
sync
poweroff -f
EOF

if [ "${LEAK:-0}" = 1 ]; then
	cat > "$WORK/init" <<'EOF'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mkdir -p /sys/kernel/debug
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
insmod /lib/modules/__MODULE__.ko || echo "insmod failed"
sleep 2
for round in 1 2 3; do
	echo "leak round $round"
	for ev in /dev/input/event*; do
		[ -e "$ev" ] || continue
		case "$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)" in
		"GameSir G7 Pro") GAME_EV=$ev ;;
		*"Motion Sensors"*) MOTION_EV=$ev ;;
		esac
	done
	[ -n "$GAME_EV" ] && /tests/rumble_test "$GAME_EV" 1200 &
	[ -n "$MOTION_EV" ] && /tests/accel_watch "$MOTION_EV" 800
	wait 2>/dev/null || true
done
rmmod xpad
sleep 2
echo scan > /sys/kernel/debug/kmemleak
sleep 3
echo scan > /sys/kernel/debug/kmemleak
sleep 2
if [ -s /sys/kernel/debug/kmemleak ]; then
	echo "KMEMLEAK-REPORT"
	cat /sys/kernel/debug/kmemleak
else
	echo "KMEMLEAK-CLEAR"
fi
sync
poweroff -f
EOF
fi

if [ "${FAULT:-0}" = 1 ]; then
	cat > "$WORK/init" <<'EOF'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mkdir -p /sys/kernel/debug
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
F=/sys/kernel/debug/failslab
if [ -d "$F" ]; then
	echo 0 > "$F/ignore-gfp-wait"
	echo 2 > "$F/probability"
	echo -1 > "$F/times"
	echo 1 > "$F/interval"
	echo 0 > "$F/verbose"
	echo 1 > "$F/task-filter"
	echo "failslab settings: p=$(cat "$F/probability") t=$(cat "$F/times") i=$(cat "$F/interval") gfpwait=$(cat "$F/ignore-gfp-wait")"
else
	echo "failslab unavailable"
fi
ok=0
fail=0
i=0
while [ $i -lt 30 ]; do
	i=$((i + 1))
	# Mark only the insmod child, so the shell's own allocations are safe.
	if sh -c 'echo 1 > /proc/self/make-it-fail; exec insmod /lib/modules/__MODULE__.ko' 2>/dev/null; then
		ok=$((ok + 1))
		sleep 0.3
		rmmod xpad 2>/dev/null
	else
		fail=$((fail + 1))
	fi
done
echo "FAULT-DONE ok=$ok fail=$fail"
[ -d "$F" ] && echo 0 > "$F/probability"
insmod /lib/modules/__MODULE__.ko || echo "final insmod failed"
sleep 2
for ev in /dev/input/event*; do
	[ -e "$ev" ] || continue
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
	[ "$name" = "GameSir G7 Pro" ] && echo "FINAL-GAMEPAD-OK"
done
sync
poweroff -f
EOF
fi

if [ "${REBIND_ONLY:-0}" = 1 ]; then
	cat > "$WORK/init" <<'EOF'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
sleep 2
echo "rebind-only: no driver loaded"
for d in /sys/bus/usb/devices/*/idVendor; do
	[ -e "$d" ] || continue
	[ "$(cat "$d")" = 3537 ] || continue
	NAME=$(basename "$(dirname "$d")")
	echo "rebind-only: unbind $NAME"
	echo "$NAME" > /sys/bus/usb/drivers/usb/unbind
	sleep 2
	echo "rebind-only: bind $NAME"
	echo "$NAME" > /sys/bus/usb/drivers/usb/bind
	sleep 2
done
echo "rebind-only: done"
dmesg | tail -20
sync
poweroff -f
EOF
fi
if [ "$MODULE" = none ]; then
	sed -i "s|insmod /lib/modules/__MODULE__.ko .*|echo \"control run: no module loaded\"|" "$WORK/init"
else
	sed -i "s/__MODULE__/$MODULE/" "$WORK/init"
fi
chmod +x "$WORK/init"

# cpio without busybox dependency on the host.
( cd "$WORK" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 ) > "$INITRD"
echo "initramfs: $INITRD ($(du -h "$INITRD" | cut -f1))"
