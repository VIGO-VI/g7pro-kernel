# Evidence index

Every artifact is a raw VM console log, sanitized only for the controller
serial (`U: Uniq=`) and MAC-like strings.  Nothing else was edited.

Environment: Linux 7.3.4 (`defconfig` + options from
`scripts/kasan-vm/build-kernel.sh`), clang 23.1.4, QEMU 11.1.3, TCG with
`-cpu max` (KVM unavailable: `svm` disabled in firmware), real controller via
`-device usb-host,vendorid=0x3537,productid=0x109b`.

## Artifacts

| File | Run | What it proves |
|---|---|---|
| `kasan-lockdep-xpad-7.3.4.log` | patched `xpad.ko`, KASAN + lockdep | probe, `0x10` decode, IMU reporting, 5 s FF, teardown under load, rebind: no KASAN or lockdep report in driver paths |
| `kcsan-xpad-7.3.4.log` | patched `xpad.ko`, **KCSAN strict** + lockdep | zero data-race and zero lockdep reports, with IMU and FF active |
| `control-none-7.3.4.log` | same kernel, **no module** | the boot-time KASAN report reproduces without any driver: not ours |
| `control-stock-7.3.4.log` | **stock** in-tree `xpad.ko` | rumble lingers after unbind without the G7 stop path: the fix is real, and the `usb_submit_urb -ENOENT` is pre-existing |
| `pm-suspend-resume-xpad-7.3.3.log` | patched `xpad.ko` on the host, real S3 (`mem_sleep=deep`), 15 s | both devices and the IMU survive a suspend/resume; rumble and battery work afterwards |

Hashes:

```sh
sha256sum upstream/evidence/*.log
```

## Reproduce

```sh
./scripts/kasan-vm/build-kernel.sh kasan "$HOME/Projects/kasan-kernel"
./scripts/kasan-vm/build-kernel.sh kcsan "$HOME/Projects/kcsan-kernel"

KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  ./scripts/kasan-vm/run.sh
```

The KCSAN run uses the same commands with the `kcsan-kernel` tree.  Controls:
`MODULE=none`, `MODULE=stock`, or `MODULE=none REBIND_ONLY=1`.

## Results

### Memory safety and locking

`kasan-lockdep` and `kcsan` runs: no report in any driver path.  The single
KASAN report in the log is at `t≈0.0035 s`, in `do_raw_spin_lock` called from
`identify_cpu` via `handle_edge_irq`; `control-none` reproduces it with no
module loaded, so it is a property of this kernel/TCG configuration.

### IMU

`watch t=… n=29…34` per 100 ms with the gamepad held open, i.e. roughly
300 samples/s under TCG.  This also documents an API detail reviewers should
know: `xpad` submits its interrupt-IN URB from `open()`, so report `0x10` only
flows while the gamepad input device is open.  A test that opens only the
motion node sees nothing; that is not a driver defect.

### Rumble

- 5 s `FF_RUMBLE` stays continuous (bounded packets refreshed every 150 ms).
- The stop path sends a zeroed packet on teardown/suspend.  In the stock
  control the buzz continues after unbind, so this is a real behavioural fix,
  not a measurement artefact.
- Tail after the host disappears was measured with the controller's own
  accelerometer (`g7motion`'s `rumble_tail`), single packet, no refresh:

  | on-period | measured to decay |
  |---|---|
  | 16 | 600 ms |
  | 32 | 850 ms |
  | 64 | 1300 ms |
  | 255 | 3150 ms |

  On-period 32 (≈320 ms) with a 150 ms refresh therefore leaves under a second
  after host loss, instead of the previous unbounded wait.

### Residual observation: short pulse at re-enumeration

A brief (~0.3–0.5 s) pulse is felt when the device re-enumerates **with a
driver bound**.  It is not caused by any rumble command we send:

- no `g7pro rumble` packet is logged at that point (instrumented builds);
- a control build that sends **no heartbeats** and performs **no serial-string
  read** still pulses;
- `REBIND_ONLY` with no driver loaded does not pulse;
- replugging on the host does not pulse.

So it correlates with binding a driver to the freshly enumerated interface,
not with a transfer from that driver.  Cause not identified; cosmetic; recorded
here rather than claimed as understood.

### Suspend/resume on hardware

Host kernel 7.3.3, patched `xpad.ko` loaded in place of the stock module,
`rtcwake -m mem -s 15` with `mem_sleep=deep` (real S3).  After resume:

- both input devices were recreated (`input139`, `input138`);
- the IMU streamed (`n=6–7` per 100 ms, nonzero variance while rumbling);
- `FF_RUMBLE` and the battery (`100 Full`) worked;
- no driver errors; the only kernel message is the expected unsigned-module
  taint.

Caveat recorded deliberately: the controller **re-enumerated** on resume
(`reset_resume`), so `probe()` ran again and repeated the warm-up.  The
non-reset suspend→resume callback path is therefore not what was exercised;
the behaviour users actually get is verified, the shortcut path is not.

## Not covered

- the non-reset suspend→resume path (see above)
- a second xpad controller
- `109c` (dongle) and `100a`, which are not claimed
