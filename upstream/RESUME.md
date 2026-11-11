# Resume notes — rumble refresh rework

Branch `wip/rumble-refresh`.  `master` is the last state backed by committed
evidence; this branch is the in-progress fix and is **not verified yet**.

## Where the work stands

The previous packet shape (`on-period 0xFF`, `repeat 0xFF`, "run until a zero
packet arrives") works while the host is alive, but if the host disappears
(unbind, suspend, crash) nothing sends the zero and the motors keep running.
Observed in the teardown test: the 3 s effect outlived the unbind.

The fix on this branch:

- rumble packets are **bounded** (`on-period 0xFF`, `repeat 0`) and refreshed
  every 200 ms by `g7pro_ff_work()` while the effect is active;
- therefore the pad stops by itself ~0.5 s after the host goes away;
- all sends happen in the workqueue, because `xpad_play_effect()` runs under
  `dev->event_lock` and `usb_interrupt_msg()` sleeps.  Sending directly there
  produced a real lockdep inversion (`event_lock -> usb` vs `usb ->
  event_lock` from URB completion);
- the transfer buffer is `kmalloc`ed.  A stack buffer fails DMA mapping with
  `-EAGAIN` (`usb_hcd_map_urb_for_dma` warning), which is why the first attempt
  at this rework produced no rumble at all.

`g7pro_send_rumble()` currently logs one line per packet:

```text
g7pro rumble s=100 w=100 on=1 ret=0 len=64
```

`ret=0` means the packet left the host.  Remove that logging before collecting
evidence.

## Next step after reboot

`/tmp` is wiped on reboot, so the initramfs must be rebuilt.  The kernel trees
under `$HOME/Projects` persist.

```sh
cd ~/Projects/g7pro-kernel

KERNEL_SRC=$HOME/Projects/kcsan-kernel/linux-7.3.4 \
  OUT=/tmp/g7pro-kcsan-strict ./scripts/kasan-vm/make-initramfs.sh

KERNEL_SRC=$HOME/Projects/kcsan-kernel/linux-7.3.4 \
  OUT=/tmp/g7pro-kcsan-strict ./scripts/kasan-vm/run.sh
```

Expect:

- `rumble_test: playing 5000 ms` and a 5 s buzz;
- `g7pro rumble … ret=0` repeated roughly every 200 ms during it;
- during teardown, the 3 s buzz stops shortly after `unbinding 1-1 during FF`;
- `REBIND-GAMEPAD-OK`;
- no KCSAN or lockdep report.

If the kernel trees are missing, rebuild them (long):

```sh
./scripts/kasan-vm/build-kernel.sh kasan "$HOME/Projects/kasan-kernel"
./scripts/kasan-vm/build-kernel.sh kcsan "$HOME/Projects/kcsan-kernel"
```

## After it is verified

1. Remove the `g7pro rumble` logging.
2. Re-run both harnesses (KASAN + lockdep, KCSAN strict) and replace
   `upstream/evidence/` logs and hashes.
3. Update `upstream/JUSTIFICATION.md` and `upstream/EVIDENCE.md` for the new
   rumble model, and drop the "motors can outlive the host" caveat.
4. Remaining gaps unchanged: suspend/resume on real hardware, a second xpad
   controller, and `109c`/`100a` untested.

## Host state at the pause

- controller on wired `3537:109b`
- `g7motion.service` and `g7bt.service` active, unaffected by the VM work
- nothing has been mailed to any maintainer
