#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build a busybox initramfs containing g7pro.ko and the test binaries.
#
# Usage:
#   KERNEL_SRC=~/Projects/kasan-kernel/linux-7.3.4 \
#   REPO=~/Projects/g7pro-kernel ./make-initramfs.sh
set -eu

KERNEL_SRC=${KERNEL_SRC:?set KERNEL_SRC to the KASAN kernel tree}
REPO=${REPO:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
OUT=${OUT:-/tmp/g7pro-kasan}
WORK=$OUT/root
INITRD=$OUT/initramfs.cpio.gz

rm -rf "$WORK" "$INITRD"
mkdir -p "$WORK"/{bin,lib/modules,tests,proc,sys,dev,tmp}

# Static busybox gives us a shell and the few applets init needs.
cp "$(command -v busybox)" "$WORK/bin/busybox"
for applet in sh mount insmod ls cat sleep echo dmesg poweroff grep cut; do
	ln -sf busybox "$WORK/bin/$applet"
done

# Build the module against the KASAN tree.
make -C "$KERNEL_SRC" LLVM=1 M="$REPO" modules >/dev/null
cp "$REPO/g7pro.ko" "$WORK/lib/modules/g7pro.ko"

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
echo "=== init: loading g7pro ==="
insmod /lib/modules/g7pro.ko || echo "insmod failed"
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
			/tests/rumble_test "$ev" || echo "rumble_test failed"
			FOUND=1
		fi
		;;
	esac
done
[ -n "$FOUND" ] && echo "GAMEPAD-FOUND" || echo "NO-GAMEPAD"

echo "=== dmesg tail ==="
dmesg | tail -40
echo "=== init: done ==="
sync
poweroff -f
EOF
chmod +x "$WORK/init"

# cpio without busybox dependency on the host.
( cd "$WORK" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 ) > "$INITRD"
echo "initramfs: $INITRD ($(du -h "$INITRD" | cut -f1))"
