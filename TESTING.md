# Testing and audit status

Pinned to commit `33da321bbc521b4b085712a38e54d06121bb1b00`.

## Automated

| Check | Command | Status |
|---|---|---|
| Build | `make LLVM=1 -C /lib/modules/$(uname -r)/build M=$PWD modules` | pass |
| W=1 | `make LLVM=1 W=1 ...` | pass, no warnings |
| sparse | `make LLVM=1 C=1 CHECK=sparse ...` | pass, no output |
| checkpatch | `scripts/checkpatch.pl --no-tree --file g7pro.c` | 0 errors, 0 warnings |
| Parser unit tests | `cc -fsanitize=address,undefined -I. tests/parser_test.c` | pass |
| Parser fuzz loop | 200k random buffers in `parser_test.c` | pass under ASan/UBSan |
| smatch | not packaged on CachyOS; scan-build could not be driven with the kernel LLVM flags | not run; sparse/checkpatch/KFENCE used |
| Long FF (5 s, VM) | GIP `on-period 0xFF` / `repeat 0xFF` | pass — full 5 s grip rumble |
| KASAN + lockdep (VM, xpad) | `scripts/kasan-vm/` — mainline 7.3.4 + `CONFIG_KASAN` + `CONFIG_PROVE_LOCKING`, real pad via QEMU `usb-host` | pass — clean probe/read/5 s FF/teardown; one pre-module boot report, see evidence log |
| Teardown under load | unbind the USB device while a 3 s effect is playing, then rebind | pass — `rumble_test: OK`, `REBIND-GAMEPAD-OK` |
| KCSAN/lockdep | host lacks `CONFIG_KCSAN`, `CONFIG_PROVE_LOCKING` | not run yet |

## xpad extension (upstream direction)

| Test | Status |
|---|---|
| Custom `xpad.ko` binds 109b without `g7pro` | pass |
| Gamepad + Motion Sensors, same uniq | pass |
| SDL3 `gyro=1 accel=1`, live rotation | pass |
| Battery `g7pro-1-16-battery`: 100 / Full | pass |
| FF_RUMBLE via existing xpad path | pass — `rumble_test: OK`, proper grip rumble |
| Restore stock xpad after test | pass |
| xpad hotplug (USB unbind/rebind) | pass — both devices and battery recreated; SDL3 gyro=1 accel=1 |

Log: `/tmp/xpad-g7pro-test.log`.

## Hardware

| Test | Status |
|---|---|
| Module loads, creates gamepad + Motion Sensors | pass — `input47` gamepad, `input48` Motion Sensors, same `Uniq=<controller-serial>` |
| SDL3 `gyro=1 accel=1`, stationary accel ≈ 9.8 m/s² | pass — 1 gamepad, gyro/accel enabled; stationary accel 9.8–10.0 m/s² |
| Observable rotation → gyro integration | pass — rotated controller produced ±3–5 rad/s gyro and changing accel |
| Battery capacity/status in `/sys/class/power_supply` | pass — `g7pro-1-4-battery`: 100, Full |
| Parity with `xpad` evdev sticks/buttons/triggers | structural pass — identical axes/key codes/FF bits; only paddle buttons differ. Dynamic event comparison pending. |
| Hotplug / disconnect mid-URB | pass — USB unbind/rebind and physical replug; both devices recreated; SDL3 gyro=1 accel=1. `xpad` wins the re-probe; handover to `g7pro` needed. |
| Suspend/resume | pending (manual) |
| Module unload, `xpad` rebind | pass — `hw-test.sh` removes the module and rebinds xpad |
| Rumble/FF | pass — `rumble_test: OK`, grip vibration observed, no new `scheduling while atomic` |

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
