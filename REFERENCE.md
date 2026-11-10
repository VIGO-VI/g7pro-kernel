# Reference implementations and what we reused

We deliberately compared against established drivers rather than inventing
conventions. Nothing below is copied into the kernel driver except functional
facts; the kernel code is GPL-2.0-only and original.

## SDL3 `SDL_hidapi_gamesir.c` (zlib)

The G7 Pro 8K driver is the closest published implementation of a GameSir
IMU report. We used it for:

- report header shape (`0x43 0xA1 0xC8` or `0xA1 0xC8`),
- accelerometer range assumption (`±4 g`, 8192 counts/g),
- gyro scale assumption (16 counts per °/s, PS4-style conversion),
- 1000 Hz IMU rate and synthetic timestamp step,
- the rule that sensors are **not** supported over Bluetooth,
- button/paddle naming and layout.

What differs for the regular G7 Pro:

- the 8K exposes a HID report on a HID interface; the regular G7 Pro's IMU is
  in vendor report `0x10` on interface 0,
- the regular G7 Pro requires the `0x0f 00 seq 02 f2` heartbeat,
- the regular G7 Pro's gamepad fields are already in report `0x10`, so we do
  not need a second input path,
- the 8K has 5-point curves and more buttons; the G7 Pro has the 21-button
  layout documented by `g7ctl`.

## Linux `drivers/hid/hid-playstation.c` (GPL-2.0)

The sensor input device is shaped exactly like `ps_sensors_create()`:

- `INPUT_PROP_ACCELEROMETER`,
- `EV_MSC` / `MSC_TIMESTAMP`,
- `ABS_X/Y/Z` for accel and `ABS_RX/RY/RZ` for gyro,
- fuzz 16 and per-axis `resolution`,
- separate input device with a name ending in `Motion Sensors`.

This is also what udev expects for `ID_INPUT_ACCELEROMETER=1`.

## Linux `drivers/input/joystick/xpad.c` (GPL-2.0)

Gamepad-side conventions:

- signed 16-bit stick axes (`-32768..32767`),
- `ABS_Z` / `ABS_RZ` triggers,
- `ABS_HAT0X/Y` D-pad,
- `BTN_A/B/X/Y`, `BTN_TL/TR`, `BTN_TL2/TR2`, `BTN_SELECT/START`,
  `BTN_THUMBL/R`, `BTN_MODE`.

The G7 Pro's vendor report already carries processed sticks and raw buttons,
so the driver parses those instead of the standard XInput packet.

## SDL3 `src/joystick/linux/SDL_sysjoystick.c` (zlib)

The pairing contract:

- SDL finds a gamepad event node and a sensor event node,
- it compares `EVIOCGUNIQ` between them,
- it requires `ABS_X/Y/Z` and `ABS_RX/RY/RZ` and uses each axis
  `resolution` to scale to m/s² and rad/s,
- it reads `MSC_TIMESTAMP` for sensor timing.

Our two input devices share the USB serial as `uniq`; udev marks the motion
node `ID_INPUT_ACCELEROMETER=1`; SDL3 reports `gyro=1 accel=1`.

## Deadband / gamesir-linux-tools (MIT)

Protocol notes for the G7 Pro family, including:

- report `0x10` marker bytes and field offsets,
- raw button group at bytes 55–58,
- battery byte 33 / charging byte 32,
- GIP rumble packet shape:
  `09 00 seq 09 00 0f LT% RT% left% right% duration 00 00`.

The rumble packet is now wired into `input_ff_create_memless`; hardware
vibration was observed once, and the test tool is being debugged.

## 8K comparison notes

Worth testing later, but **not** assumed:

- whether the regular G7 Pro's 100a HID interface exposes a GameSir HID
  report with IMU (if it does, a HID driver could avoid claiming interface 0
  and leaving `xpad` bound),
- whether the 8K's 1000 Hz sensor semantics apply to the regular G7 Pro's
  report `0x10` rate,
- whether the 8K's extra buttons/curves have equivalents on this model.

Until those are measured, the kernel driver keeps the conservative path:
claim interface 0, heartbeat, report `0x10`.
