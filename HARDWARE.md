# Hardware capabilities (official sources) and driver coverage

Checked against GameSir's own G7 Pro product/FAQ/manual material:

- https://gamesir.com/products/gamesir-g7-pro
- https://gamesir.com/support/manuals/gamesir-g7-pro
- https://gamesir.com/pages/faq-questions-about-g7-pro
- https://gamesir.com/pages/faq-questions-about-g7-pro-wireless

## What GameSir says

| Capability | Official statement | Driver status |
|---|---|---|
| Connection | Tri-mode: USB-C wired (Xbox), 2.4 GHz dongle (PC), Bluetooth (Android/HID). | USB wired only. Bluetooth and native GIP `1022` out of scope. |
| Gyro | 6-axis gyroscope with mapping support, **PC only**. | Raw gyro/accel exposed via Motion Sensors. No on-device mapping done by the driver. |
| Rumble | 4 motors: one in each grip and each trigger. | 13-byte GIP rumble packet supports all four channels. Generic `FF_RUMBLE` drives the grips (same as `xpad`); trigger channels are available for a future dedicated test/attribute. |
| Polling | 1000 Hz on PC over wired and 2.4 GHz. | Driver uses the endpoint's `bInterval`; actual rate follows the controller profile. |
| Sticks | TMR/Hall-effect, 8–12 bit resolution. | Processed 0..255 values mapped to 16-bit evdev axes. |
| Triggers | Hall-effect with hair-trigger mode. | Analog 0..255 mapped to 10-bit `ABS_Z`/`ABS_RZ` (matches `xpad`). |
| Buttons | 4 mappable: L4, R4, L5, R5. | Exposed as `BTN_TRIGGER_HAPPY1..4`. Share as `BTN_TRIGGER_HAPPY5`. |
| Battery | 1200 mAh, charging dock. | `power_supply` capacity/status; 100/Full observed on the reference unit. |
| Audio | 3.5 mm headset on wired and 2.4 GHz. | Not handled; Linux USB audio is a separate class/interface. |
| Profiles/macros | Four profiles, on-device combos, Nexus app. | Kernel driver does not write configuration; use the existing userspace tools for profiles. |

## Bluetooth

The official FAQ says the Bluetooth mode "adopts the HID protocol and is designed
for Android devices", and gyro mapping is "PC only". The vendor configuration
interface used by this driver is USB-only. Therefore:

- Bluetooth is **not** a configuration/vendor-IMU transport for this driver.
- BT input may still work as a generic HID gamepad through the kernel/BlueZ,
  but no `SDL_SENSOR_GYRO` from this path.
- The 8K SDL driver explicitly disables sensors over Bluetooth as well.

If a future unit exposes the GameSir HID report with IMU over BT, that needs a
separate HID driver and hardware capture; it is not assumed here.

## Four-motor note

The GIP packet is `09 00 seq 09 00 0f LT% RT% left% right% duration 00 00`.
The current `FF_RUMBLE` mapping uses the two grip channels and leaves LT/RT at
zero, matching `xpad`'s GIP rumble path. The protocol supports the trigger
motors; exposing them separately needs either a vendor-specific attribute or a
non-standard FF effect, which should be discussed with linux-input before
adding.
