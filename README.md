# g7pro — Linux kernel driver for the GameSir G7 Pro

Wired `3537:109b` / `3537:109c`.  Exposes the controller's real 6-axis IMU as
a sibling **Motion Sensors** input device so SDL3, Eden and ScarletNX get
`SDL_SENSOR_GYRO` / `SDL_SENSOR_ACCEL` out of the box — no userspace daemon.

## Devices

- `GameSir G7 Pro` — sticks, triggers, D-pad, buttons, paddles.
- `GameSir G7 Pro Motion Sensors` — `ABS_X/Y/Z` accelerometer and
  `ABS_RX/RY/RZ` gyroscope, `INPUT_PROP_ACCELEROMETER`, `MSC_TIMESTAMP`,
  axis resolution 8192/g and 16/(deg/s), same `uniq` as the gamepad.

SDL3's Linux backend pairs the two by `uniq`, exactly as it does for
`hid-playstation` and `hid-nintendo`.

## Build

The host kernel is built with clang, so build the module the same way:

```sh
make LLVM=1 -C /lib/modules/$(uname -r)/build M=$PWD modules
```

The module is unsigned.  Secure Boot is not enforced on the reference host;
on a machine with enforced module signatures you must sign it with your own
key.

## Load and test

`xpad` also matches this USB ID, so unbind it from interface 0 first:

```sh
DEV=$(grep -l '^3537$' /sys/bus/usb/devices/*/idVendor | head -1)
BUS=$(basename "$(dirname "$DEV")")
sudo sh -c "echo -n $BUS:1.0 > /sys/bus/usb/drivers/xpad/unbind"
sudo insmod ./g7pro.ko
```

Then:

```sh
grep -A12 'GameSir G7 Pro' /proc/bus/input/devices
sudo ./g7pro-tests/sdl3_probe   # or ~/Projects/g7motion/build/sdl3_probe
```

To unload and restore `xpad`:

```sh
sudo rmmod g7pro
sudo sh -c "echo -n $BUS:1.0 > /sys/bus/usb/drivers/xpad/bind"
```

Or run the whole cycle with `sudo ./scripts/hw-test.sh`, which writes
`/tmp/g7pro-kernel-test.log`.

## Tests

```sh
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
   -I. -o tests/parser_test tests/parser_test.c
./tests/parser_test
```

`tests/parser_test.c` covers synthetic frames, a live captured frame,
invalid frames, and 200k fuzz iterations.  `tests/capture_report.c` captures
a fresh frame from the controller for a new golden fixture.

## Status

Working proof on wired `3537:109b`:

- standalone `g7pro` driver: gamepad, Motion Sensors, battery, `FF_RUMBLE`;
- `xpad` extension: the same devices from the existing Xbox driver, including
  the existing rumble path, with no separate driver and no bind-order race.

The upstream direction is the `xpad` extension in `upstream/`; the standalone
driver is kept in `prototype/` as the reference and fallback.  Both were
tested on hardware.  evdev capabilities match xpad (same axes, key codes and
FF bits; only the paddles and device name differ).

Still missing before an upstream submission: KASAN/KCSAN/lockdep (host kernel
lacks those configs; KFENCE is enabled), suspend/resume field testing, and
regression testing on another xpad controller.

See `HARDWARE.md` for the official capability check, `REFERENCE.md` for the
drivers used as references, `TESTING.md` for current evidence, and
`REVIEW.local.md` for the local line-by-line audit.

Protocol details: `g7ctl`/`g7motion` report 0x10 layout.  The sensor-device
shape follows `drivers/hid/hid-playstation.c`; gamepad conventions follow
`drivers/input/joystick/xpad.c`.

## License

GPL-2.0-only.
