# Evidence index

Every artifact here is a raw VM console log, sanitized only for the controller
serial (`U: Uniq=`) and MAC-like strings.  Nothing else was edited.

Environment for all runs:

- Linux 7.3.4, `defconfig` plus the options in `scripts/kasan-vm/build-kernel.sh`
- clang 23.1.4 / lld, QEMU 11.1.3, KVM unavailable (`svm` disabled in firmware),
  so TCG with `-cpu max`
- real controller passed through with `-device usb-host,vendorid=0x3537,productid=0x109b`

## Artifacts

| File | Run | What it proves |
|---|---|---|
| `kasan-lockdep-xpad-7.3.4.log` | patched `xpad.ko`, KASAN + lockdep | probe, report parsing, 5 s FF, teardown-under-load, rebind: no KASAN or lockdep report in driver paths |
| `kcsan-xpad-7.3.4.log` | patched `xpad.ko`, KCSAN + lockdep | zero data-race reports with the FF path executed |
| `control-none-7.3.4.log` | same kernel, **no module** | the boot-time KASAN report reproduces without any driver: not ours |
| `control-stock-7.3.4.log` | **stock** in-tree `xpad.ko` | `usb_submit_urb -ENOENT` during unbind-during-FF reproduces without our changes |

Hashes:

```sh
sha256sum upstream/evidence/*.log
```

## Reproduce

```sh
./scripts/kasan-vm/build-kernel.sh kasan "$HOME/Projects/kasan-kernel"
./scripts/kasan-vm/build-kernel.sh kcsan "$HOME/Projects/kcsan-kernel"

# patched module
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  ./scripts/kasan-vm/run.sh

# control: no module
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  OUT=/tmp/g7pro-ctl-none MODULE=none ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  OUT=/tmp/g7pro-ctl-none ./scripts/kasan-vm/run.sh

# control: stock xpad
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  OUT=/tmp/g7pro-ctl-stock MODULE=stock ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  OUT=/tmp/g7pro-ctl-stock ./scripts/kasan-vm/run.sh
```

## Attribution of the two anomalies

**Boot-time KASAN report** — `wild-memory-access in do_raw_spin_lock` at
`t≈0.0036 s`, stack `identify_cpu ← asm_common_interrupt ← handle_edge_irq`.
It appears in the `control-none` run, where no module is loaded at all.  It is
therefore a property of this mainline/TCG configuration, not of the driver.
It happens before `g7pro_sensor_alloc()` could possibly run.

**`usb_submit_urb` failures during teardown** — the teardown test unbinds the
USB device while a 3 s effect is still playing, deliberately.  In that window:

- `xpad_try_sending_next_out_packet ... -2` (`-ENOENT`) appears with **stock
  `xpad`** as well, so it is pre-existing behaviour, not introduced here.
- `xpad_irq_in ... -1` (`-EPERM`) is the documented outcome of resubmitting a
  URB while `usb_kill_urb()` is running (`drivers/usb/core/urb.c`, "attempts to
  resubmit the URB will fail with error -EPERM").  Both drivers resubmit from
  the completion handler; the error is expected and the URB goes idle.

Neither line indicates a leak or a use-after-free: KASAN stayed silent in the
patched run, and the device re-enumerated (`REBIND-GAMEPAD-OK`).

## Not covered by these artifacts

- KCSAN strict mode (the recorded run is non-strict; strict rerun pending)
- suspend/resume on physical hardware
- a second xpad controller
