# Upstream series

Not submitted.  The human submitter reviews, adds `Signed-off-by`, and sends.

- `0000-cover-letter.txt` — cover letter with AI disclosure and test evidence.
- `0001-Input-g7pro-add-driver.patch` — driver + Kconfig + Makefile +
  MAINTAINERS.

## Apply / build

```sh
git checkout -b g7pro
git am upstream/0001-Input-g7pro-add-driver.patch
make LLVM=1 olddefconfig
make LLVM=1 -j"$(nproc)"
```

The patch was generated against mainline `master` as of 2026-11-10.

## Before sending

- Add `Signed-off-by: Vigo <...>` as the human submitter.
- Run `scripts/checkpatch.pl` on the patch and `get_maintainer.pl`.
- Re-run the hardware tests on the target kernel, preferably with KASAN.
- Decide the xpad bind-order approach with linux-input.
- Keep the AI disclosure in the cover letter.
