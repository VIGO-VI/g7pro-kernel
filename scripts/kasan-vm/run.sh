#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Boot the KASAN kernel with the G7 Pro passed through, run the tests, and
# collect the log.  Stops g7motion for the duration and restores it after.
set -eu

KERNEL_SRC=${KERNEL_SRC:?set KERNEL_SRC to the KASAN kernel tree}
OUT=${OUT:-/tmp/g7pro-kasan}
LOG=$OUT/vm.log
BZIMAGE=$KERNEL_SRC/arch/x86/boot/bzImage
INITRD=$OUT/initramfs.cpio.gz

[ -f "$BZIMAGE" ] || { echo "missing $BZIMAGE"; exit 1; }
[ -f "$INITRD" ] || { echo "missing $INITRD"; exit 1; }

restore() {
	[ -n "${IFACE:-}" ] && sudo sh -c "echo -n $IFACE > /sys/bus/usb/drivers/xpad/bind" 2>/dev/null || true
	systemctl --user start g7motion 2>/dev/null || true
}
trap restore EXIT

# The VM needs exclusive ownership of the USB device.
systemctl --user stop g7motion 2>/dev/null || true
sleep 1
for intf in /sys/bus/usb/drivers/xpad/*:*; do
	[ -e "$intf" ] || continue
	IFACE=$(basename "$intf")
	echo "unbinding xpad from $IFACE"
	sudo sh -c "echo -n $IFACE > /sys/bus/usb/drivers/xpad/unbind" || true
done

echo "booting KASAN kernel; log: $LOG"
qemu-system-x86_64 \
	-m 4096 -smp 4 -cpu max \
	-kernel "$BZIMAGE" \
	-initrd "$INITRD" \
	-append "console=ttyS0 panic=-1" \
	-nographic -no-reboot \
	-device qemu-xhci \
	-device usb-host,vendorid=0x3537,productid=0x109b \
	2>&1 | tee "$LOG"

echo "=== result ==="
if grep -q 'BUG: KASAN' "$LOG"; then
	echo "KASAN REPORT PRESENT"
	grep -n -A20 'BUG: KASAN' "$LOG" | head -60
else
	echo "no KASAN report"
fi
grep -E 'GAMEPAD-FOUND|NO-GAMEPAD|rumble_test|parser_test' "$LOG" || true
