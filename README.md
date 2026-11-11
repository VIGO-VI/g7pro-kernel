# g7pro — Linux kernel support for the GameSir G7 Pro

> **Status: work in progress, not submitted upstream.**  The `upstream/` series
> is a draft for review; it has no `Signed-off-by`, and no mail has been sent
> to any maintainer or list.  See `upstream/README.md` for the remaining work.

Wired `3537:109b`.  Exposes the controller's real 6-axis IMU as
a sibling **Motion Sensors** input device so SDL3, Eden and ScarletNX get
`SDL_SENSOR_GYRO` / `SDL_SENSOR_ACCEL` out of the box — no userspace daemon.

Two implementations live here:

- `g7pro.c` — a standalone USB driver (reference and fallback).
- `xpad/` — the same protocol support added to the existing `xpad` driver.
  This is the upstream direction, because `xpad` already owns interface 0.

## Quick start

```sh
git clone https://github.com/VIGO-VI/g7pro-kernel.git
cd g7pro-kernel
```

### 1. Requirements

You need the headers and build tools for the **running** kernel.  The module
is out-of-tree and must be rebuilt after every kernel update.

| Distribution | Command |
| --- | --- |
| Arch | `sudo pacman -S --needed base-devel clang llvm linux-headers` |
| Debian/Ubuntu | `sudo apt install build-essential clang llvm linux-headers-$(uname -r)` |
| Fedora | `sudo dnf install gcc make clang llvm kernel-devel` |

An SDL3 build is optional and only needed for the verification probe; it
lives in the companion repository
[`g7motion`](https://github.com/VIGO-VI/g7motion) (`tools/sdl3_probe.cpp`).

Check that the headers exist:

```sh
ls /lib/modules/$(uname -r)/build
```

### 2. Build

The reference host kernel is built with clang, so build the module the same
way:

```sh
make LLVM=1 -C /lib/modules/$(uname -r)/build M=$PWD modules          # g7pro.ko
make LLVM=1 -C /lib/modules/$(uname -r)/build M=$PWD/xpad modules     # xpad/xpad.ko
```

The modules are unsigned.  Secure Boot is not enforced on the reference
host; with enforced module signatures, sign them with your own key.

### 3. Run the hardware smoke test

`xpad` also matches this USB ID, so it must be unbound from interface 0
before the standalone driver can bind.  The script does that, loads the
module, prints the devices, runs the rumble test, then restores `xpad`:

```sh
sudo ./scripts/hw-test.sh
less /tmp/g7pro-kernel-test.log
```

Expected in the log:

- `GameSir G7 Pro` gamepad and `GameSir G7 Pro Motion Sensors`
- `ABS_X/Y/Z` accel, `ABS_RX/RY/RZ` gyro, `INPUT_PROP_ACCELEROMETER`
- battery under `/sys/class/power_supply/g7pro-*`
- `rumble_test: OK` and physical grip vibration
- SDL3 probe printing `gyro=1 accel=1` and changing values when rotated

To try the upstream shape instead:

```sh
sudo ./scripts/xpad-test.sh
less /tmp/xpad-g7pro-test.log
```

It replaces the running `xpad` module with `xpad/xpad.ko` and restores the
stock module on exit.  Neither script makes anything persistent.

### 4. Manual load (optional)

```sh
DEV=$(grep -l '^3537$' /sys/bus/usb/devices/*/idVendor | head -1)
BUS=$(basename "$(dirname "$DEV")")
sudo sh -c "echo -n $BUS:1.0 > /sys/bus/usb/drivers/xpad/unbind"
sudo insmod ./g7pro.ko

grep -A12 'GameSir G7 Pro' /proc/bus/input/devices
sudo ./tests/evdev_caps /dev/input/eventN     # build it first, see Tests
```

Restore the stock driver:

```sh
sudo rmmod g7pro
sudo sh -c "echo -n $BUS:1.0 > /sys/bus/usb/drivers/xpad/bind"
```

### 5. Hotplug test

```sh
sudo ./scripts/hotplug-test.sh          # simulated USB unbind/rebind
sudo ./scripts/physical-replug-test.sh  # asks you to unplug/replug
sudo ./scripts/xpad-hotplug-test.sh     # same for the xpad extension
```

Logs are written to `/tmp/g7pro-*` and `/tmp/xpad-g7pro-*`.

## Devices

- `GameSir G7 Pro` — sticks, triggers, D-pad, buttons, paddles.
- `GameSir G7 Pro Motion Sensors` — `ABS_X/Y/Z` accelerometer and
  `ABS_RX/RY/RZ` gyroscope, `INPUT_PROP_ACCELEROMETER`, `MSC_TIMESTAMP`,
  axis resolution 8192/g and 16/(deg/s), same `uniq` as the gamepad.

SDL3's Linux backend pairs the two by `uniq`, exactly as it does for
`hid-playstation` and `hid-nintendo`.

## Tests

```sh
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
   -I. -o tests/parser_test tests/parser_test.c
./tests/parser_test

cc -O2 -Wall -Wextra -o tests/evdev_caps tests/evdev_caps.c
cc -O2 -Wall -Wextra -o tests/rumble_test tests/rumble_test.c
```

`tests/parser_test.c` covers synthetic frames, a live captured frame,
invalid frames, and 200k fuzz iterations.  `tests/capture_report.c` captures
a fresh frame from the controller for a new golden fixture.

## Help wanted: regression testing

The series changes `xpad`, which drives every Xbox-compatible pad on Linux.  I
only have the GameSir G7 Pro, so the missing evidence is a run on **any other
xpad controller**.

If you own one, there is a one-command report:

```sh
git clone https://github.com/VIGO-VI/g7pro-kernel
cd g7pro-kernel
sudo ./scripts/other-pad-report.sh
```

It builds the patched module, records the pad before and after, restores the
stock driver, and writes a report with serials/MACs/IPs redacted.  Attach that
file to [issue #1](https://github.com/VIGO-VI/g7pro-kernel/issues/1).  Full
instructions, requirements and troubleshooting: `TESTING-OTHER-PADS.md`.

## Status

Working proof on wired `3537:109b`:

- standalone `g7pro` driver: gamepad, Motion Sensors, battery, `FF_RUMBLE`;
- `xpad` extension: the same devices from the existing Xbox driver, including
  the existing rumble path, with no separate driver and no bind-order race.

The upstream direction is the `xpad` extension in `upstream/`; the standalone
driver is kept in `prototype/` as the reference and fallback.  Both were
tested on hardware.  evdev capabilities match xpad (same axes, key codes and
FF bits; only the paddles and device name differ).

Still missing before an upstream submission: KCSAN/lockdep, suspend/resume
field testing, and regression testing on another xpad controller.  KASAN is
covered by booting a mainline kernel in QEMU with the real pad passed through;
see `scripts/kasan-vm/`.

See `HARDWARE.md` for the official capability check, `REFERENCE.md` for the
drivers used as references, `TESTING.md` for current evidence, and
`upstream/` for the series, cover letter and bind-order analysis.

Protocol details: `g7ctl`/`g7motion` report 0x10 layout.  The sensor-device
shape follows `drivers/hid/hid-playstation.c`; gamepad conventions follow
`drivers/input/joystick/xpad.c`.

## Bluetooth

The retail pad's Bluetooth mode (`3537:1022`) exposes a generic HID gamepad:
no vendor interface, no IMU, no battery, and no force feedback in its
descriptor.  This repository targets wired and 2.4 GHz USB modes.

Rumble can still be driven over Bluetooth: the firmware accepts the standard
Xbox One output report (`03 0F LT RT LM RM`) on the hidraw node even though it
never advertises it.  The userspace bridge in `g7motion` (`g7bt`) uses that
today.  A native HID driver proposal is in `upstream/BT-RUMBLE.md`.

## License

GPL-2.0-only.
