#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build a kernel for the VM harness.
#
#   ./build-kernel.sh kasan ~/Projects/kasan-kernel
#   ./build-kernel.sh kcsan ~/Projects/kcsan-kernel
#
# KASAN and KCSAN cannot be enabled in the same kernel (KCSAN depends on
# !KASAN), hence the two destinations.
set -eu

MODE=${1:?usage: build-kernel.sh kasan|kcsan DEST}
DEST=${2:?usage: build-kernel.sh kasan|kcsan DEST}
VER=${KERNEL_VER:-7.3.4}
SRC=$DEST/linux-$VER

mkdir -p "$DEST"
if [ ! -d "$SRC" ]; then
	[ -f "$DEST/linux-$VER.tar.xz" ] || \
		curl -L -o "$DEST/linux-$VER.tar.xz" \
			"https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$VER.tar.xz"
	tar -xf "$DEST/linux-$VER.tar.xz" -C "$DEST"
fi

cd "$SRC"
make LLVM=1 defconfig

# Common: USB, input, battery, modules, and xpad with force feedback so the
# patched module can be built out of tree exactly as the series expects.
COMMON="-e MODULES -e USB -e INPUT_EVDEV -e POWER_SUPPLY -e DEVTMPFS \
	-e DEVTMPFS_MOUNT -m JOYSTICK_XPAD -e JOYSTICK_XPAD_FF"

case "$MODE" in
kasan)
	# KASAN checks memory safety; no lockdep, matching the image we build.
	./scripts/config $COMMON -e KASAN -e KASAN_GENERIC -e KASAN_INLINE \
		-d PROVE_LOCKING -d DEBUG_LOCK_ALLOC
	;;
kcsan)
	# KCSAN checks data races; lockdep checks ordering.  Strict mode reports
	# every race, not just writes.
	./scripts/config $COMMON -e DEBUG_KERNEL -e KCSAN -e KCSAN_STRICT \
		-e PROVE_LOCKING -d KASAN
	;;
*)
	echo "unknown mode: $MODE" >&2
	exit 1
	;;
esac

make LLVM=1 olddefconfig
make LLVM=1 -j"$(nproc)" bzImage modules
echo "kernel ready: $SRC/arch/x86/boot/bzImage"
