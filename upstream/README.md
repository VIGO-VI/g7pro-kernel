# Upstream series

Not submitted.  The human submitter reviews, adds `Signed-off-by`, and sends.

- `0000-cover-letter.txt` — cover letter with AI disclosure and test evidence.
- `0001-Input-xpad-GameSir-G7-Pro-IMU.patch` — xpad change plus the new
  `g7pro.h` parser header.
- `BT-RUMBLE.md` — separate proposal for Bluetooth force feedback (HID
  driver); not submitted, not part of the xpad series.
- `JUSTIFICATION.md` — hunk-by-hunk rationale and a claim/evidence/gap matrix.
  This is the document to read before reviewing the patch.

The standalone `g7pro` driver is kept in `prototype/` as the reference and
fallback; it is not the upstream submission.

## Apply / build

```sh
git checkout -b g7pro
git am upstream/0001-Input-xpad-GameSir-G7-Pro-IMU.patch
make LLVM=1 olddefconfig
make LLVM=1 M=drivers/input/joystick
```

The patch was generated against mainline `master` as of 2026-11-10.

## Before sending

- Add `Signed-off-by: Vigo <...>` as the human submitter.
- Run `scripts/checkpatch.pl` on the patch and `get_maintainer.pl`.
- Re-run the hardware tests on the target kernel, preferably with KASAN.
- Regression-test at least one other xpad controller if possible.
- Keep the AI disclosure in the cover letter.
