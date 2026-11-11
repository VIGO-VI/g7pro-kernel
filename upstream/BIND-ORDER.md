# Bind-order policy and the xpad question

## What the kernel guarantees

`Documentation/driver-api/driver-model/binding.rst` is explicit:

- drivers are kept in a list, in registration order;
- a new device walks that list and binds to the **first** driver whose ID
  table matches;
- a new driver only probes devices that are **not already bound**.

There is no "most specific match wins" rule.  A device already bound to
`xpad` is skipped by `g7pro` when `g7pro` is registered later.  This is exactly
what the hardware test showed:

```
[ 5310.029843] input: GameSir G7 Pro ... input84
[ 5311.057531] g7pro 1-4:1.0: GameSir G7 Pro ready (3537:109b)
```

That is after the test explicitly handed interface 0 from `xpad` to `g7pro`.

`driver_override` exists, but it must be set **before** binding and does not
load or bind a driver by itself.  A udev rule can race `xpad`; xpadneo does
this out of tree, which is evidence that a separate driver is not OOTB in
mainline.

## Why option 2 (`MODULE_SOFTDEP`) is not a fix

`MODULE_SOFTDEP("pre: g7pro")` is a module-loading hint, not a binding
guarantee:

- it only works when both drivers are modules;
- it does not control the order of built-in drivers;
- initramfs, manual `insmod`, and udev can change the order;
- it makes every `xpad` load pull in `g7pro`, even on machines without this
  controller;
- input maintainers are likely to reject it as an abuse of softdeps.

It is a distro workaround, not an upstream solution.

## Why removing the GameSir IDs from xpad is not a fix

`xpad` does not list only individual GameSir PIDs.  It has:

```c
XPAD_XBOX360_VENDOR(0x3537),
XPAD_XBOXONE_VENDOR(0x3537),
```

Those match **every GameSir controller** with the Xbox vendor interface.
Removing them to free `109b` would regress other GameSir models.  Adding a
per-PID exclusion is not expressible in a USB ID table, and returning
`-ENODEV` from `xpad`'s probe does not make the USB core try another driver.

## Option 1: extend xpad

This is the policy-consistent route:

- the G7 Pro is an Xbox-licensed controller; `xpad` is the Xbox gamepad
  driver, so vendor handling belongs there;
- `xpad` already contains per-vendor/per-device data (`xpad_device`,
  `xboxone_init_packets`, model names) and vendor-specific init sequences;
- no duplicate driver, no bind-order race, no udev rebind;
- users get the gamepad from the existing driver and the new IMU/battery
  from the same probe.

Risks and required care:

- `xpad` is used by many controllers; every change must be gated on
  `VID/PID == 3537:109b` and must not alter the
  existing report paths for other models;
- the vendor report `0x10` is 64 bytes and arrives on the same interrupt IN
  endpoint; `xpad` already allocates a 64-byte buffer, so the parser can be
  added without changing the URB size;
- heartbeat output must use a workqueue/URB path that cannot sleep in the
  input completion callback;
- battery and sensor devices must be unregistered in the right order;
- force feedback already exists in `xpad` for `XTYPE_XBOXONE`; the G7 Pro's
  13-byte GIP rumble packet needs a hardware check against `xpad`'s current
  path;
- regression testing needs at least one other `xpad` device, or explicit
  maintainer review plus a strong "only this VID/PID" argument.

## Recommendation

Do option 1 for the upstream-quality version.  Keep this standalone driver as
the prototype, reference and fallback for kernels without the xpad change.
Before sending anything, do the full audit: xpad build with W=1/sparse/
checkpatch, KASAN if a kernel is available, G7 Pro hardware tests, and at
least a smoke test on another xpad device.

No email or maintainer contact has been made.
