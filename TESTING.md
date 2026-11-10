# Testing and audit status

Pinned to the working tree at the time of writing; see the commit hash in
`REVIEW.local.md` once the first verified commit exists.

## Automated

| Check | Command | Status |
|---|---|---|
| Build | `make LLVM=1 -C /lib/modules/$(uname -r)/build M=$PWD modules` | pass |
| W=1 | `make LLVM=1 W=1 ...` | pass, no warnings |
| sparse | `make LLVM=1 C=1 CHECK=sparse ...` | pass, no output |
| checkpatch | `scripts/checkpatch.pl --no-tree --file g7pro.c` | 0 errors, 0 warnings |
| Parser unit tests | `cc -fsanitize=address,undefined -I. tests/parser_test.c` | pass |
| Parser fuzz loop | 200k random buffers in `parser_test.c` | pass under ASan/UBSan |
| smatch | tool not packaged on CachyOS | pending / substitute review |
| KASAN/KCSAN/lockdep | host kernel lacks `CONFIG_KASAN`, `CONFIG_KCSAN`, `CONFIG_PROVE_LOCKING` | blocked by kernel config |

## Hardware

| Test | Status |
|---|---|
| Module loads, creates gamepad + Motion Sensors | pass — `input47` gamepad, `input48` Motion Sensors, same `Uniq=0000377903ED91EB` |
| SDL3 `gyro=1 accel=1`, stationary accel ≈ 9.8 m/s² | pass — 1 gamepad, gyro/accel enabled; stationary accel 9.8–10.0 m/s² |
| Observable rotation → gyro integration | pass — rotated controller produced ±3–5 rad/s gyro and changing accel |
| Battery capacity/status in `/sys/class/power_supply` | pass — `g7pro-1-4-battery`: 100, Full |
| Parity with `xpad` evdev sticks/buttons/triggers | pending |
| Hotplug / disconnect mid-URB | pending |
| Suspend/resume | pending |
| Module unload, `xpad` rebind | pending |
| Rumble/FF | protocol sends and the grips vibrated once; `tests/rumble_test` segfaults after play, under gdb |

## Evidence

- Live golden frame: `captures/report-0x10.hex`
  `1000b43ce080807d800f00000000000000ffffffff000098ff5220a9000000000064000000000000000000000000000000000084817f800f0000000000000000`
- `tests/parser_test.c` decodes it as:
  sticks `0x80 0x80 0x7d 0x80`, gyro `(-1,-1,0)`, accel `(-104, 8274, 169)`,
  battery 100 %, not charging, D-pad neutral, no buttons.
- `scripts/hw-test.sh` writes `/tmp/g7pro-kernel-test.log`.

## Audit notes

- Sensor-device shape copied from `hid-playstation.c`: `INPUT_PROP_ACCELEROMETER`,
  `EV_MSC/MSC_TIMESTAMP`, `ABS_X/Y/Z` + `ABS_RX/RY/RZ`, resolutions.
- SDL3 pairing checked against `src/joystick/linux/SDL_sysjoystick.c`:
  it matches gamepad and sensor by `EVIOCGUNIQ`.
- Gamepad conventions compared with `xpad.c`: signed 16-bit sticks, ABS_HAT,
  `BTN_*` names, trigger axes.
