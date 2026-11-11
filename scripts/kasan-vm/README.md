# KASAN test VM

Boots a KASAN-enabled mainline kernel under QEMU with the real controller
passed through, loads the module under test (`xpad.ko` by default), and
exercises probe/read/teardown plus a
force-feedback effect.

This covers the memory-safety gap that the daily host kernel cannot: it has no
`CONFIG_KASAN`.

## Prerequisites

- `qemu-system-x86_64` with `usb-host` (`qemu-hw-usb-host` on Arch)
- `busybox` (static build), `cpio`, `bc`, clang/lld

Build the two kernels with the helper (the `modules` step is required: without
`Module.symvers` the external module cannot resolve built-in symbols):

```sh
./scripts/kasan-vm/build-kernel.sh kasan "$HOME/Projects/kasan-kernel"
./scripts/kasan-vm/build-kernel.sh kcsan "$HOME/Projects/kcsan-kernel"
```

KCSAN cannot be enabled together with KASAN (`lib/Kconfig.kcsan` depends on
`!KASAN`), hence two trees.  The KASAN tree also enables lockdep, so one run
proves memory safety and lock ordering.  The KCSAN tree uses
`CONFIG_KCSAN_STRICT=y` so every race is reported, not only racing writes.

Both configurations enable `JOYSTICK_XPAD=m` and `JOYSTICK_XPAD_FF=y`.
Reviewers should note why: `CONFIG_JOYSTICK_XPAD_FF` is a separate option, and
without it the built module has no `FF_RUMBLE` capability at all, so a run
would silently test nothing on the force-feedback path.

## Run

```sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 ./scripts/kasan-vm/run.sh
```

`run.sh` stops `g7motion`, unbinds `xpad` (needs sudo), boots the VM with
`-device usb-host,vendorid=0x3537,productid=0x109b`, then restores both.

Use `MODULE=g7pro` to test the standalone prototype instead of the `xpad`
submission.  The default is `MODULE=xpad`, because that is what upstream
receives.

The initramfs runs, in order:

1. parser unit test,
2. evdev capability dump of both devices,
3. a 5 s full-strength `FF_RUMBLE`,
4. **teardown under load**: unbind the USB device while a 3 s effect is still
   playing, rebind it, and check that the gamepad comes back.

Step 4 is the one that turns "the ordering is reasoned" into "the ordering was
executed while an effect was in flight".

If the host has no KVM, QEMU uses TCG: slow but functional, and `-cpu max` is
needed so userland (static busybox) does not hit an unavailable instruction.

## Results, 2026-11-11

### KCSAN + lockdep, `xpad.ko`

Kernel 7.3.4, `defconfig` + `CONFIG_KCSAN` (non-strict at the time of this run)
+ `CONFIG_PROVE_LOCKING`, module with `JOYSTICK_XPAD_FF=y`:

```text
rumble_test: playing 5000 ms
rumble_test: OK
GAMEPAD-FOUND
```

- zero `BUG: KCSAN` reports
- zero lockdep reports
- the FF path ran for a full 5 s (the pad buzzed), so the concurrency-sensitive
  code was actually executed

A strict-mode rerun and a teardown-under-load run are recorded separately in
`upstream/evidence/`.

### KASAN, prototype driver (superseded for upstream purposes)

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

This run covered `g7pro.ko` and is kept only as history: the submission builds
`xpad.ko`, and its KASAN run is recorded in `upstream/evidence/`.
