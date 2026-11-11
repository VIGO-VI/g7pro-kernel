# Evidence index

Every artifact is a raw VM console log, sanitized only for controller serial
and MAC/IP strings.  Environment: Linux 7.3.4 (`defconfig` + options from
`scripts/kasan-vm/build-kernel.sh`), clang 23.1.4, QEMU 11.1.3, TCG with
`-cpu max` (KVM unavailable: SVM disabled in firmware), real controller via
`-device usb-host,vendorid=0x3537,productid=0x109b`.

## Artifacts

| File | Run | Result |
|---|---|---|
| `kasan-lockdep-xpad-7.3.4.log` | KASAN + lockdep | no report in any driver path |
| `kcsan-xpad-7.3.4.log` | KCSAN strict + lockdep | no report in any driver path |
| `leak-kasan-xpad-7.3.4.log` | KASAN + kmemleak, 3 FF/IMU rounds, unload, scans | `KMEMLEAK-CLEAR` |
| `fault-injection-xpad-7.3.4.log` | KASAN + failslab, 30 insmod/rmmod cycles at 2 % | `ok=3 fail=27`, final load OK, no KASAN |
| `pm-suspend-resume-xpad-7.3.3.log` | patched `xpad.ko` on the host, S3, 15 s | devices, IMU, rumble, battery after resume |
| `control-none-7.3.4.log` | same kernel, **no module** | boot-time KASAN report reproduces: not ours |
| `control-stock-7.3.4.log` | **stock** `xpad.ko` | rumble lingers after unbind: the stop fix is real |

Hashes: `sha256sum upstream/evidence/*.log`.

## Reproduce

```sh
./scripts/kasan-vm/build-kernel.sh kasan "$HOME/Projects/kasan-kernel"
./scripts/kasan-vm/build-kernel.sh kcsan "$HOME/Projects/kcsan-kernel"

KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  ./scripts/kasan-vm/make-initramfs.sh
KERNEL_SRC=$HOME/Projects/kasan-kernel/linux-7.3.4 \
  ./scripts/kasan-vm/run.sh
```

Controls and specialised runs: `MODULE=none`, `MODULE=stock`,
`MODULE=none REBIND_ONLY=1`, `LEAK=1`, `FAULT=1`.

## Results

### Sanitizers

No report in any driver path under KASAN+lockdep or KCSAN strict.  The single
KASAN line in the logs is at `t≈0.0036 s`, in `do_raw_spin_lock` called from
`identify_cpu`; `control-none` reproduces it with no module, so it belongs to
this kernel/TCG configuration.

KCSAN strict also reports a mainline idle race (`tick_nohz_handler` vs
`tick_nohz_idle_got_tick`) during the longer runs.  It has no driver frames and
is a known idle/timer artifact, not this series.

### IMU

`n=16–34` samples per 100 ms with the gamepad held open (roughly 300/s under
TCG).  `xpad` submits its interrupt-IN URB from `open()`, so `0x10` only flows
while the gamepad is open — a test opening only the motion node sees nothing.
That is API behaviour, not a defect.

### Rumble

- 5 s `FF_RUMBLE` is continuous: bounded packets refreshed every 150 ms.
- Teardown/suspend send a zeroed packet while the interface is reachable.
  Stock `xpad` leaves the motors running in the same test.
- Tail after the host disappears, measured with the controller accelerometer
  (`g7motion`'s `rumble_tail`, single packet, no refresh):

  | on-period | to decay |
  |---|---|
  | 16 | 600 ms |
  | 32 | 850 ms |
  | 64 | 1300 ms |
  | 255 | 3150 ms |

  On-period 32 with a 150 ms refresh leaves under a second.

### Concurrent FF clients

Three processes upload and play effects simultaneously, then the teardown test
runs: `CONCURRENT-FF-DONE`, no failures, no KCSAN report in driver code.

### Memory leaks

Three FF/IMU rounds, module unload, two kmemleak scans: `KMEMLEAK-CLEAR`, no
`unreferenced object` entries.

### Fault injection

`failslab` with `ignore-gfp-wait=0` (otherwise every `GFP_KERNEL` allocation is
skipped) and `task-filter=1` so only the `insmod` child is injected.  30 cycles
at 2 %: `ok=3 fail=27`, then a clean final load and `FINAL-GAMEPAD-OK`, no KASAN
during any failed probe.  Failures inside the module loader itself are expected
and visible as `vmalloc`/`vm_struct` errors.

### Runtime PM

`power/control=auto` leaves `runtime_status=active`: the driver does not
implement USB runtime autosuspend.  Recorded as "not implemented", not as a
failure.

### Build coverage

- x86_64 7.3.4: builds, boots, all tests above.
- arm64 7.3.4 cross-build (`ARCH=arm64 LLVM=1`, `modules_prepare`): produces a
  clean `aarch64` relocatable `xpad.ko` with no compiler warnings.
- 6.12 LTS: the series does not apply (baseline `xpad.c` uses newer symbols
  such as `BTN_GRIPR`, and hunk contexts differ).  A stable backport would be a
  separate, manual series; it is out of scope for the mainline submission.

### Suspend/resume on hardware

Host 7.3.3, patched module, `rtcwake -m mem -s 15` with `mem_sleep=deep`.
Devices, IMU, rumble and battery all work after resume.  The pad
**re-enumerates** on resume (`reset_resume`), so `probe()` repeats the warm-up;
the non-reset callback path is not exercised.

### Residual observation

A ~0.3–0.5 s pulse is felt when a driver binds after re-enumeration.  It is not
caused by any packet the driver sends: instrumented builds log no rumble
packet, a control build with no heartbeats and no serial read still pulses, and
there is no pulse with no driver bound or on host replug.  Recorded as an
unexplained, cosmetic residual rather than claimed as understood.

## Not covered

- a second xpad controller (issue #1); only one unit exists here
- 2.4 GHz dongle (`109c`) and the `100a` identity — not claimed at all
- the non-reset suspend→resume path
- a 6.12 stable backport
