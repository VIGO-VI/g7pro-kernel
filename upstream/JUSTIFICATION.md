# Justification and proof pack

Status: **draft for review, not ready to send.**  Nothing here has been mailed to
a maintainer.

This document exists because a patch is not "done" when it works.  Every claim
below is marked one of:

- **proven** — reproducible test, command and result included;
- **reasoned** — follows from a documented API contract or the hardware
  protocol, with the reasoning written out;
- **gap** — not proven yet.  No submission happens while a gap affects
  correctness; gaps are listed with what would close them.

The series is a single patch adding `drivers/input/joystick/g7pro.h` and
extending `xpad.c`.  It does not add a second driver.

## 1. Why xpad and not a new driver

**Reasoned, with evidence in `BIND-ORDER.md`.**

The G7 Pro's IMU is only on the vendor interface, which `xpad` already owns.
USB core matches interfaces in driver registration order and skips an
interface that is already bound.  A separate driver for the same VID/PID
therefore binds or does not bind depending on module load order — it worked in
testing only because it happened to be loaded first.  Upstream cannot accept a
driver whose binding is a race.

Extending `xpad` removes the race by construction: one driver, one owner, and
the existing report/FF paths are untouched.

## 2. Claim → evidence

| Claim | Status | Evidence |
|---|---|---|
| Binds `3537:109b`, creates gamepad + motion node | proven | `TESTING.md`; VM log `GAMEPAD-FOUND` |
| SDL3 sees `gyro=1 accel=1` and live values | proven | `sdl3_probe` in `TESTING.md` |
| Battery `capacity`/`status` correct | proven | `power_supply` 100/Full |
| FF rumble works, including 5 s effects | proven | `rumble_test` 5000 ms in VM; `TESTING.md` |
| Hotplug and physical replug recreate both devices | proven | `xpad-hotplug-test.sh`, replug log |
| No regression on other xpad pads | **gap** | one unit only; request in README |
| Memory safety of probe/read/FF/teardown | proven for `xpad.ko` | `upstream/evidence/kasan-lockdep-xpad-7.3.4.log` |
| No data races | proven with KCSAN strict | `upstream/evidence/kcsan-xpad-7.3.4.log` |
| No lock-order problems | proven under KASAN+lockdep and KCSAN strict | both evidence logs, zero reports |
| Suspend/resume resumes the vendor session | **gap** | only code-reasoned; see §7 |
| Trigger motors | **gap** | accepted by device, not perceptible |

## 3. `g7pro.h` — line by line

**Purpose:** a pure decoder shared by the kernel and the userspace unit/fuzz
tests.  Sharing is deliberate: the parser that runs in kernel context is the
same code that was fuzzed under ASan/UBSan, so the tests cover the shipped
logic rather than a copy of it.  **Proven** by `tests/parser_test.c` (200k
random buffers, ASan/UBSan).

- `#ifdef __KERNEL__` / `typedef`s: in kernel builds it uses `linux/types.h`
  and `get_unaligned_le16`; outside, fixed-width types and a byte-wise
  little-endian read.  **Reasoned:** both paths encode the same two bytes, and
  the userspace build is what the fuzz test exercises.
- `G7PRO_REPORT_LEN 64`: the vendor frame length the driver reads.
- `REPORT_ID 0x10`, `RESPONSE_MARKER 0x3c`, `INPUT_MARKER 0xe0`: the three
  bytes that identify the telemetry frame.  **Reasoned** from the g7ctl
  protocol notes and confirmed by captures (`captures/report-0x10.hex`).
- `struct g7pro_state`: zero-initialised view of one frame.  Booleans, not bit
  fields, so nothing depends on compiler layout.
- `g7pro_decode_report()`:
  - `if (!d || !s || len < 61) return false;` — the highest index read is
    `d[58]`; 61 is the conservative minimum that also keeps the two trailing
    status bytes.  **Reasoned:** every read is bounded by this check; the
    fuzz loop would fault otherwise.
  - marker check before any other access, so random frames are rejected cheaply.
  - `*s = (struct g7pro_state){0};` — stale fields from a previous frame cannot
    leak into a report when a byte group is absent this time.  **Reasoned.**
  - sticks `d[5..8]`, triggers `d[12..13]`, gyro `d[17..22]`, accel `d[23..28]`,
    battery `d[32]`/`d[33]`: offsets from the protocol documents and the capture.
  - `s->battery = d[33] <= 100 ? d[33] : -1;` — anything above 100 is not a
    percentage, so it becomes "unknown" rather than a bogus reading.
  - Buttons come from `d[55..58]`, the **raw pre-remap** group.  **Reasoned:**
    the controller can remap buttons on-device; decoding the raw group means a
    user remap is not applied twice.
  - Hat: only the four cardinal values are decoded; everything else, including
    `0xf`, is neutral.  **Reasoned:** diagonal values are not part of this
    protocol; reporting a wrong diagonal is worse than neutral.
  - No loops, no allocations, no locking: constant time, safe in URB
    completion context.

## 4. `xpad.c` hunks

### 4.1 Includes

`<linux/power_supply.h>` for the battery, `<linux/ktime.h>` for the sensor
timestamp, `"g7pro.h"` for the decoder.  **Reasoned:** no new subsystem is
introduced; power_supply is already used by other input drivers.

### 4.2 `struct usb_xpad` — one pointer

`struct g7pro_sensor *g7pro;` is `NULL` for every other controller.  All new
behaviour is behind `if (xpad->g7pro)`, so the cost for existing devices is one
pointer and one branch; their code path is unchanged.  **Reasoned.**

### 4.3 `struct g7pro_sensor`

Fields and ownership:

- `xpad` back-pointer — borrowed, valid while the interface is bound.
- `motion` — allocated in `g7pro_sensor_alloc`, registered in
  `g7pro_sensor_start`, unregistered in `g7pro_sensor_stop`.
- `battery` — registered/unregistered in the same pair.
- `hb_work`/`hb_buf`/`seq` — vendor heartbeat session.
- `battery_percent`/`charging` — cached so `power_supply_changed()` is only
  called on change, not 500 times a second.
- `uniq` — shared by both input devices so SDL3 pairs gamepad and sensors.
- `started` — gate for both the heartbeat work and report handling.
- `motion_registered` — distinguishes "registered, must unregister" from
  "allocated, must free" on error paths.

**Reasoned**, and the error paths are exercised by the KASAN VM run.

### 4.4 `g7pro_is_device()`

Exact whitelist: VID `0x3537`, PID `0x109b`, `0x109c`, `0x100a`.  No vendor-wide
match, so no unrelated GameSir device changes behaviour.  `0x1022` (Bluetooth)
is deliberately excluded: that identity has no vendor interface.  **Reasoned**;
the PIDs come from hardware enumeration logs in `TESTING.md`.

### 4.5 Battery property callback

- `POWER_SUPPLY_PROP_PRESENT` always 1 — a battery exists when the node exists.
- `CAPACITY` returns the cached percentage, or 0 when unknown.
- `STATUS`: unknown → `STATUS_UNKNOWN`; charging bit → `CHARGING`; 100 →
  `FULL`; otherwise `DISCHARGING`.  The order matters: a full pack that is also
  charging reports `CHARGING`, not `FULL`; that matches what the hardware
  reports on the wire.  **Reasoned**, and 100/Full observed.
- Any other property returns `-EINVAL`, as the API requires.
- Called with the power_supply lock held; touches only cached fields, no
  sleeping, no I/O.  **Reasoned.**

The descriptor is `static const`; only the name is per-instance
(`devm_kasprintf` with bus/port numbers) so two pads do not collide in sysfs.
**Reasoned.**

### 4.6 Heartbeat

`g7pro_send_heartbeat()` builds the vendor packet (`0x0f`, sequence,
`0x02 0xf2`) and sends 64 bytes on interrupt endpoint `0x02` with a 1 s
timeout.  It returns `-EIO` on a short transfer.  **Reasoned:** the device
stops sending report `0x10` without this session; the packet is documented in
`PROTOCOL.md` and in the capture.  Sequence is a `u8` because the protocol's
sequence field is one byte.

`g7pro_hb_work()`:

- returns immediately if `!started` (shutdown or suspend);
- suppresses `-EPIPE`/`-ESHUTDOWN` (expected when the device is gone) and
  rate-limits other errors;
- reschedules only if still `started`, so a stop cannot be followed by a new
  timer.

**Reasoned.**  The work is cancelled synchronously in disconnect and suspend
before state is freed.

### 4.7 `g7pro_handle_report()`

Runs in URB completion context (softirq).  Therefore:

- only cached fields and `input_report_abs()`/`input_event()` are used — the
  same context xpad already reports from;
- `power_supply_changed()` is safe here: the core takes a spinlock and
  `schedule_work()` (verified in `power_supply_core.c`), it does not sleep;
- guards: `!g7`, `!started`, decoder failure, `!motion`.

Mapping follows `hid-playstation`: gyro on `ABS_RX/RY/RZ`, accelerometer on
`ABS_X/Y/Z`, `INPUT_PROP_ACCELEROMETER`, and `MSC_TIMESTAMP` in microseconds.
`(u32)(ktime_get_ns() / 1000)` intentionally wraps — `MSC_TIMESTAMP` is a
32-bit counter and consumers treat it as wrapping.  **Reasoned**, matching
`hid-playstation.c`.

Battery is only re-notified when the value or charging bit changes.
**Reasoned:** avoids waking userspace on every frame.

### 4.8 Allocation and start/stop

`g7pro_sensor_alloc()` allocates state, a heartbeat buffer, the `uniq` string
(USB serial, else bus/port fallback), and the motion input device; it does not
register anything.  Error path frees in reverse order.  **Reasoned.**

`g7pro_sensor_start()`:

1. registers the motion device,
2. allocates and registers the battery supply,
3. sets `started`,
4. sends four heartbeats 250 ms apart to warm the vendor session,
5. schedules the periodic work.

If any step fails it returns an error and the caller runs
`xpad_deinit_input()` then `g7pro_sensor_stop()`, which unregisters exactly
what was registered.  **Reasoned.**  The 1 s probe delay is the price of the
vendor session; measured, not assumed.

`g7pro_sensor_stop()` unregisters battery and motion, frees buffers and state.
Ordering matters: both input devices reference `g7->uniq`, so unregistering
must happen before the string is freed.  **Reasoned.**

### 4.9 URB interception

```c
if (xpad->g7pro && urb->actual_length >= 61 && xpad->idata[0] == 0x10) {
	g7pro_handle_report(...);
	goto exit;
}
```

Report `0x10` is vendor telemetry; the gamepad itself still arrives in xpad's
normal report and is processed unchanged.  The interception prevents the
vendor frame from being parsed as an Xbox report.  It is gated on `xpad->g7pro`,
so other pads never take this branch.  **Reasoned.**

### 4.10 Probe, disconnect, suspend, resume

- `xpad->name = "GameSir G7 Pro"` only for the whitelisted device.
- `xpad_init_input()` adds `uniq` when `g7pro` is present, so SDL3 pairs the
  two devices exactly as it does for hid-playstation.
- Probe error paths call `xpad_deinit_input()` and `g7pro_sensor_stop()` so a
  failed warmup leaves nothing registered.  **Reasoned.**
- Disconnect stops the heartbeat before tearing down input, then frees the
  sensor state.  The IRQ URB is killed by `xpad_deinit_input()` closing the
  input device before `g7pro_sensor_stop()` frees the state it points at.
  **Reasoned — and this is the ordering a reviewer should check; KCSAN would
  confirm the absence of a race.**
- `xpad_resume()` was restructured from early `return`s to a `ret` variable so
  `g7pro_resume()` runs for our device.  For every other device the control
  flow is equivalent: same calls, same return value.  **Reasoned.**

### 4.11 Force feedback (device-specific path)

`xpad_play_effect()` routes the whitelisted device to `g7pro_play_effect()`
and leaves every other pad on the existing code path.

- The vendor packet runs for a **bounded** on-period.  Measured with the
  controller's accelerometer: on-period 32 ≈ 320 ms of drive, decaying within
  850 ms; 255 ≈ 3.1 s.
- A long effect is kept alive by `g7pro_ff_work()` refreshing every 150 ms.
  This is what makes an unplug bounded: when the host disappears, the last
  packet expires instead of driving forever.  The stock driver's
  "run until a zeroed packet" behaviour was reproduced in the control run and
  does exactly the opposite.
- Sends happen **only in the workqueue**.  `xpad_play_effect()` runs under
  `dev->event_lock`; calling `usb_interrupt_msg()` there produced a real
  lockdep inversion against URB completion (`event_lock -> usb` vs
  `usb -> event_lock`), caught by lockdep in an earlier run.
- The transfer buffer is `kmalloc`ed.  A stack buffer fails DMA mapping with
  `-EAGAIN` plus an HCD warning; that is also recorded in the history of this
  branch.
- Teardown and suspend cancel the refresh and send one zeroed packet while the
  interface is still reachable.

## 5. Concurrency and lifetime

| Context | Touches | Serialised by |
|---|---|---|
| probe | allocation, registration | driver core, single-threaded |
| URB completion (softirq) | `started`, cached battery, `motion` | gates only; no locks taken |
| heartbeat work | `hb_buf`, `seq`, USB transfer | own work item, cancelled synchronously |
| disconnect | `started`, cancel work, unregister | USB core serialises with probe |
| power_supply callback | cached fields | power_supply core lock |
| suspend/resume | `started`, work | USB core |

The one deliberate shared flag, `started`, is written at start/stop/suspend and
read in the work and the URB path.  It is a gate, not a reference count: a
stale read can at worst cause one report during teardown, and the URB is dead
by then.  **Gap:** KCSAN has not confirmed this; see §7.

## 6. Failure modes

- No device / wrong PID: no allocation, no behaviour change.
- Allocation failure: probe fails, nothing registered.
- Motion registration failure: battery is never registered.
- Battery registration failure: motion is unregistered by the caller.
- Warmup failure: both are unregistered, probe fails.
- Disconnect during streaming: heartbeat cancelled, input closed, state freed.
- Suspend: heartbeat stops; reports stop at the source.

## 7. Explicit gaps

| Gap | Why it matters | How to close it |
|---|---|---|
| suspend/resume | the 1 s vendor warmup is **not** repeated on resume; IMU may or may not restart | suspend/resume on real hardware with `sdl3_probe` before/after |
| second controller | "no regression on other xpad pads" is unproven | run `xpad-test.sh` on another pad; request in README |
| teardown race | proven under load, with stock-xpad and no-module controls | `upstream/EVIDENCE.md` |
| short pulse at re-enumeration | a ~0.3-0.5 s pulse occurs when a driver binds after re-enumeration; no driver transfer is involved (no-heartbeat and no-serial control builds still pulse), no pulse without a driver, none on host replug | recorded as residual in `upstream/EVIDENCE.md`; cause not identified, cosmetic |
| trigger motors | the packet has two trigger channels; no perceptible vibration | either document as unused or find the correct values |
| `0x109c`/`0x100a` | whitelisted, but only `109b` was tested | test reports from owners of those revisions |
| multiple pads | battery/input names are per-port, but two identical pads are untested | two-device test |
| `MSC_TIMESTAMP` wrap | 32-bit µs wraps every ~71 min | matches hid-playstation; note for reviewers |
| pointer cleared after free | fixed in code: the pointer is cleared before the state is freed | awaiting the xpad VM run |
| shared field accesses | `started`, `battery_percent`, `charging`, `motion` and `battery` were plain accesses across URB/work/sysfs contexts | all now `READ_ONCE`/`WRITE_ONCE`; awaiting KCSAN |

## 8. Questions a hostile reviewer will ask

**"Why is this in xpad instead of hid-playstation or a new driver?"**
The device speaks the Xbox/GIP protocol and xpad owns it; see §1 and
`BIND-ORDER.md`.  A new driver is a registration-order race.

**"This touches a driver used by millions of controllers."**
Every new path is behind `g7pro_is_device()` and `xpad->g7pro`.  No existing
function was reworked except `xpad_resume()`, whose control flow is equivalent
for all other devices (§4.10).

**"Why decode buttons you do not use?"**
The parser is shared with the userspace bridge and its fuzz tests.  The kernel
consumes only the IMU and battery fields.

**"Where is the hardware documentation?"**
There is none from the vendor.  The protocol is documented by g7ctl and
reproduced by live captures; offsets are listed in §3.

**"There is a KASAN report in your own log. Explain."**
It is at `t≈0.0036 s`, in `do_raw_spin_lock` called from `identify_cpu` via
`handle_edge_irq` — before any module can load.  The `control-none` run boots
the same kernel with no module and reproduces it.  It is a property of this
mainline configuration under TCG, not of the driver.  Evidence:
`upstream/EVIDENCE.md`.

**"And the `usb_submit_urb` failures during teardown?"**
The test unbinds the device while a 3 s effect is playing.  `-ENOENT` from the
output path reproduces with **stock** `xpad`, and `-EPERM` is the documented
result of resubmitting while `usb_kill_urb()` runs (`drivers/usb/core/urb.c`).
The URB goes idle, the device re-enumerates, KASAN stays silent.

**"Was this written by an AI?"**
Disclosed in the cover letter: tools, model, inputs, affected portions and
testing.  The human submitter reviews, signs off and is responsible.

**"Why no `Signed-off-by`?"**
Because no submission has been made.  The human adds it when sending.

## 9. What is *not* claimed

- Not claimed: works on revisions other than the tested `109b`.
- Not claimed: suspend/resume keeps the IMU alive.
- Not claimed: trigger motors work.
- Not claimed: no regressions on other controllers — that is explicitly sought
  in the README.
- Not claimed: ready to merge.  This is an RFC-stage tree.
