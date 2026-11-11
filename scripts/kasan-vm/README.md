# KASAN test VM

Boots a KASAN-enabled mainline kernel under QEMU with the real controller
passed through, loads `g7pro.ko`, and exercises probe/read/teardown plus a
force-feedback effect.

This covers the memory-safety gap that the daily host kernel cannot: it has no
`CONFIG_KASAN`.

## Prerequisites

- `qemu-system-x86_64` with `usb-host` (`qemu-hw-usb-host` on Arch)
- `busybox` (static build), `cpio`, `bc`, clang/lld
- a mainline tree built with KASAN:

```sh
curl -LO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.4.tar.xz
tar -xf linux-7.3.4.tar.xz
cd linux-7.3.4
make LLVM=1 defconfig
./scripts/config -e KASAN -e KASAN_GENERIC -e KASAN_INLINE -e MODULES \
                 -e USB -e INPUT_EVDEV -e POWER_SUPPLY -e DEVTMPFS -e KFENCE
make LLVM=1 olddefconfig
make LLVM=1 -j"$(nproc)" bzImage
make LLVM=1 -j"$(nproc)" modules     # generates Module.symvers for the module
```

The modules build is required: without `Module.symvers`, the external module
fails to resolve built-in symbols.

## Run

```sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 ./scripts/kasan-vm/run.sh
```

`run.sh` stops `g7motion`, unbinds `xpad` (needs sudo), boots the VM with
`-device usb-host,vendorid=0x3537,productid=0x109b`, then restores both.

If the host has no KVM, QEMU uses TCG: slow but functional, and `-cpu max` is
needed so userland (static busybox) does not hit an unavailable instruction.

## Result, 2026-11-11

Kernel 7.3.4, `defconfig` + KASAN, QEMU 11.1.3 (TCG, `-cpu max`):

```text
input: GameSir G7 Pro Motion Sensors as /devices/.../input5
g7pro 1-1:1.0: GameSir G7 Pro ready (3537:109b)
rumble_test: playing 1 s
rumble_test: OK
GAMEPAD-FOUND
```

- no KASAN report in any driver path (probe, report parsing, FF upload/play,
  teardown)
- one report at `t=0.0038 s` in `identify_cpu` via `handle_edge_irq`, before
  any module is loaded; treated as a mainline/TCG boot artifact, not this
  driver.

KCSAN and lockdep remain untested; they need a kernel configuration with
`CONFIG_KCSAN` and `CONFIG_PROVE_LOCKING`.
