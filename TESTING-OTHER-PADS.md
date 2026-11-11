# Testing the xpad change on another controller

**Time: about five minutes. One command. Nothing is installed permanently.**

The series changes `xpad`, which drives every Xbox-compatible controller on
Linux. It has only been tested on the GameSir G7 Pro. One run on **any other
xpad pad** is the last piece of evidence needed — even if the result is "no
change", which is what we expect.

You do not need the GameSir pad for this.

## What you need

- a Linux machine with the controller plugged in over USB
- kernel headers for the running kernel
- a C compiler (`cc`) and `make`
- `sudo`
- Secure Boot either off, or you sign the module (see troubleshooting)

Headers by distribution:

| Distribution | Command |
|---|---|
| Arch | `sudo pacman -S --needed base-devel linux-headers` |
| Debian/Ubuntu | `sudo apt install build-essential linux-headers-$(uname -r)` |
| Fedora | `sudo dnf install gcc make kernel-devel` |

## The command

```sh
git clone https://github.com/VIGO-VI/g7pro-kernel
cd g7pro-kernel
sudo ./scripts/other-pad-report.sh
```

It prints a path like `/tmp/xpad-report-20261111-153000.txt`. **Attach that
file** to [issue #1](https://github.com/VIGO-VI/g7pro-kernel/issues/1), or paste
its contents.

## What the script does

1. Builds the patched `xpad` module against your running kernel.
2. Records every input device and its axes, buttons and force-feedback bits.
3. Replaces the stock `xpad` with the patched one **for this session only**.
4. Records the same information again.
5. Runs a one-second rumble on the first pad that supports it (optional to
   feel; it is only a smoke test).
6. Restores the stock module and prints the comparison.

It does not touch your boot configuration, does not create files outside
`/tmp`, and `rmmod`/`modprobe` restores the stock driver when it exits.

The module is unsigned, so the kernel will be marked "tainted" until you
reboot. That is expected and harmless.

## What a good report looks like

```text
RESULT: IDENTICAL — no capability change on this pad
rumble: ok on /dev/input/event5 (Xbox 360 Controller)
```

`IDENTICAL` means the patched driver changed nothing for your pad, which is the
expected outcome: the new code is gated behind the GameSir vendor and product
IDs.

A `DIFFERENT` result is important — attach the report and mention it in the
issue. It means the patch affected another controller.

## Privacy

The script replaces controller serials, MAC addresses and IP addresses with
placeholders before writing the report. It contains your kernel version, USB
device list and dmesg, which is what a maintainer needs to judge the result.
Skim it before attaching if you want to be sure.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `kernel headers missing` | install headers for `$(uname -r)` |
| `insmod: key was rejected` | Secure Boot. Sign the module, or test with Secure Boot off |
| `xpad appears to be built into this kernel` | some distro kernels compile it in; the script then only records devices. Mention this in the issue |
| `RESULT: DIFFERENT` | attach the report; this is the case we want to see |
| no rumble | not required; the report is still useful |

## If you own the GameSir G7 Pro

You are not the target of this request — the G7 Pro path is already covered by
the evidence in `upstream/EVIDENCE.md`. This is specifically for other pads.
