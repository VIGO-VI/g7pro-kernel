# Bluetooth rumble — findings and a native-driver proposal

Status: **not submitted**.  This is the design note for a second, separate
upstream series; it is unrelated to the xpad IMU patch in this directory.

## What the hardware does

The retail pad's Bluetooth identity is `3537:1022` (class `0x2508`, HID over
BR/EDR, `bcdDevice 0x011b`).  Its report descriptor declares:

| Report | Direction | Contents |
|---|---|---|
| `0x01` | in/out | keyboard, 8 modifiers + 6 keys, 5-bit LED output |
| `0x02` | in | consumer control (media keys) |
| `0x06` | in | mouse |
| `0x07` | in | gamepad: 4 axes, hat, 16 buttons, 2 vendor bytes |

There is **no output report for the gamepad, no vendor usage page, and no
battery page**.  Linux therefore exposes it through `hid-generic` without
force feedback, and no host has a standards-based way to rumble it over
Bluetooth.

## What it actually accepts

Despite the descriptor, the firmware accepts the standard Xbox One rumble
output report on the same hidraw node:

```text
03 0F LT RT LM RM
```

- `0x03` — report id (not declared by the descriptor)
- `0x0F` — motor enable mask
- `LT`, `RT` — trigger motors (accepted, no perceptible vibration on the
  tested unit)
- `LM`, `RM` — left and right grip motors, `0x00..0xFF`

A single 6-byte write produces a buzz for as long as the motors are driven; a
report with zeroes stops it.  This works while the kernel keeps reading input
reports concurrently.  Verified on one unit (wired firmware `bcdDevice
0x0240`, Bluetooth `0x011b`) with a userspace bridge that grabs the evdev node
and replays the report on hidraw.

This is undocumented: GameSir's materials describe Bluetooth as the Android
HID mode and do not mention vibration there, and the macOS community write-up
only reports vibration after switching the pad into its hidden Xbox
Bluetooth mode.

## Why not just a userspace daemon?

The userspace bridge works and is what ships today (`g7bt` in
[g7motion](https://github.com/VIGO-VI/g7motion)): it grabs the kernel gamepad,
re-exports it as a virtual Xbox 360 pad with `FF_RUMBLE`, and forwards
play/stop to the report above.

It has real costs:

- a second input device for the same hardware,
- a userspace process that must run for rumble to exist,
- FF effects proxied through uinput rather than the real device,
- battery/IMU still absent (they are wired-only).

## Proposed kernel change

A small HID driver, e.g. `drivers/hid/hid-gamesir.c`, matching
`HID_DEVICE(BUS_BLUETOOTH, 0x3537, 0x1022)`:

1. let `hid-generic` do the input mapping unchanged (or reuse its mapping),
2. register a synthetic output report id `0x03` (6 bytes) so
   `hid_hw_output_report()` is well-defined,
3. call `input_ff_create_memless(hdev->input, NULL, play_effect)`,
4. in `play_effect()`, translate `FF_RUMBLE` strong/weak magnitudes into
   `LM`/`RM` and send the 6-byte report; send zeroes for `FF_PERIODIC` rest
   or on stop.

`input_ff_create_memless` gives `FF_RUMBLE`, gain handling, replay length and
effect bookkeeping for free, so the driver body is small.

### Open questions for review

- Is a dedicated HID driver justified for one vendor quirk, or should this be a
  `hid-generic` fixup plus an FF callback registered from a quirk table?
- The descriptor does not describe the output report; adding it in the driver
  must not confuse `hidraw` clients or the report parser.
- Trigger channels (`LT`/`RT`) were accepted but produced no perceptible
  vibration; should they be exposed at all, or left at zero like `xpad` does
  with its two-channel `FF_RUMBLE`?
- Does the report survive suspend/resume and reconnects, or must it be resent
  after every link setup?
- Battery over Bluetooth: the descriptor has no battery page, BlueZ exposes
  no `Battery1`, and probing HID feature report IDs `0x01`–`0x20` produced no
  response at all.  Treated as absent, not merely undocumented.

## Test evidence

- `hidraw` write of `03 0F 00 00 FF FF` on `hid-generic`'s node: grips buzz.
- `03 0F 00 00 FF 00` / `03 0F 00 00 00 FF`: left / right grip independently.
- `03 0F FF FF 00 00`: no perceptible trigger vibration.
- Repeatable after reconnects, with the kernel's gamepad node open and
  grabbed.
- Userspace FF path: `rumble_test` against the virtual pad returns OK and the
  physical grips vibrate.
