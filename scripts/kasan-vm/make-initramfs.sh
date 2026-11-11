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
g7pro)
	make -C "$KERNEL_SRC" LLVM=1 M="$REPO" modules >/dev/null
	KO="$REPO/g7pro.ko"
	;;
*)
	echo "unknown MODULE=$MODULE"; exit 1
	;;
esac
cp "$KO" "$WORK/lib/modules/$MODULE.ko"

# Static test binaries.
cc -static -O2 -Wall -Wextra -o "$WORK/tests/evdev_caps" "$REPO/tests/evdev_caps.c"
cc -static -O2 -Wall -Wextra -o "$WORK/tests/rumble_test" "$REPO/tests/rumble_test.c"
cc -static -O2 -Wall -Wextra -I"$REPO" -o "$WORK/tests/parser_test" "$REPO/tests/parser_test.c"

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
	name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
	case "$name" in
	*"GameSir G7 Pro"*)
		/tests/evdev_caps "$ev"
		if [ "$name" = "GameSir G7 Pro" ]; then
			GAME_EV=$ev
			/tests/rumble_test "$ev" 5000 || echo "rumble_test failed"
			FOUND=1
		fi
		;;
	esac
done
[ -n "$FOUND" ] && echo "GAMEPAD-FOUND" || echo "NO-GAMEPAD"

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
		name=$(cat "/sys/class/input/$(basename "$ev")/device/name" 2>/dev/null)
		[ "$name" = "GameSir G7 Pro" ] && echo "REBIND-GAMEPAD-OK"
	done
fi

echo "=== dmesg tail ==="
dmesg | tail -40
echo "=== init: done ==="
sync
poweroff -f
EOF
sed -i "s/__MODULE__/$MODULE/" "$WORK/init"
chmod +x "$WORK/init"

# cpio without busybox dependency on the host.
( cd "$WORK" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 ) > "$INITRD"
echo "initramfs: $INITRD ($(du -h "$INITRD" | cut -f1))"
