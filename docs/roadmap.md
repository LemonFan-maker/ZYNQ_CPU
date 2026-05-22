# Roadmap

The project goal is a custom PL CPU that can run a useful riscv32 Linux environment. 

The first real Linux milestone is now complete: the board boots a mainline RV32 kernel into an embedded initramfs `/init`, completes a userspace `getpid` smoke test, and reaches a quiet idle loop.

## Completed Bring-Up Milestones

These are already represented in code, tests, or board logs:

- local RV32-style core execution in simulation
- assembler and minimal ELF generation flow
- PS-loadable PL CPU programs
- AXI-Lite PS-to-PL register probe
- DataMover loopback through PS DDR
- PL CPU initiated DataMover transfers
- ELF loading and reset-vector selection
- M-mode trap smoke
- S-mode trap smoke
- timer interrupt delegation to S-mode
- boot payload handoff with `a0=hartid`, `a1=dtb`
- S-mode counter CSR access
- direct DDR load/store from PL CPU
- instruction fetch and execution from the DDR window
- high-address DDR load/store, instruction fetch, and AMO smokes
- SBI-style firmware and timer smoke tests
- Linux boot contract smoke
- Linux SBI compatibility smoke
- Linux image layout smoke
- PS-side real Linux Image/DTB loader
- local SBI shim with console and TIME services sufficient for kernel boot
- mainline RV32 Linux reaches `Run /init as init process`
- embedded `/init` prints `userspace entered`, completes `getpid`, and reaches `idle`
- Vivado 2025.2 bitstream generation with timing met at the current 75 MHz target

## Current Development Stage

The active stage is:

```text
turn the board-proven Linux smoke boot into a useful minimal userspace
```

The immediate success signature to preserve is:

```text
[zx32-init] userspace entered
[zx32-init] getpid ok
[zx32-init] idle
Boot monitor: userspace idle reached
```

Do not treat later Linux regressions as userspace or kernel bugs until this signature still reproduces with the same Image/DTB/firmware layout.

## Current Linux Artifacts

Source-of-truth files:

- `docs/linux_bringup.md`
- `docs/linux_boot_layout.md`
- `linux/zynq_cpu.dts`
- `linux/zx32_rv32.config`
- `linux/initramfs/init.S`
- `hw_bringup/ps_linux_boot.c`
- `hw_bringup/programs/linux_boot_firmware.zx32.s`
- `hw_bringup/download_zynq_cpu_linux_boot.xsbl`

Generated artifacts:

- `linux/kernel/`
- `build/linux-mainline-rv32/`
- `build/linux-initramfs/`
- `build/linux/`
- `hw_bringup/build/`

These generated paths are ignored and should not become source-of-truth.

## Next Milestone: Stable Linux Smoke Regression

Goal: make the current Linux boot easy to rerun and compare.

Required work:

- keep the final success condition as `Boot monitor: userspace idle reached`
- reduce or gate noisy periodic monitor samples
- keep a compact expected-log section in `docs/hardware_uart_test.md`
- record the exact Image/DTB addresses through `build/linux/boot_artifacts.env`
- make all Linux boot diagnostics explainable from `docs/linux_boot_layout.md`

## Next Milestone: Richer Tiny Userspace

Goal: expand `/init` before bringing in a larger userspace.

Suggested syscall smokes:

- `getpid`
- `write`
- `uname` or another simple read-only syscall
- `clock_gettime` or `nanosleep` once timer behavior is stable enough
- simple fork/exec only after memory behavior is better characterized

Keep this stage assembly-only or otherwise very small. The point is to isolate kernel/platform behavior before libc and BusyBox add noise.

## Next Milestone: BusyBox or Minimal Libc Initramfs

Goal: reach an interactive or scriptable userspace.

Required work:

- choose a riscv32 userspace toolchain and ABI strategy
- build a static BusyBox or smaller libc-based init
- decide whether `/dev/console` through `hvc0` is enough
- verify initramfs size still fits before the DTB placement at `0x81600000`
- keep the old assembly `/init` as a known-good fallback

## Next Milestone: Firmware and Platform ABI Cleanup

Goal: replace bring-up assumptions with a stable platform contract.

Required work:

- decide whether to keep the local SBI shim or move toward OpenSBI
- document the permanent relationship between CSR `time` and MMIO `mtime`
- clean up the current timer offset bridge if the clocks can be made identical
- define which devices Linux should see directly and which should be hidden behind SBI
- keep the DTB synchronized with real hardware and with any Linux-visible drivers
- document reserved memory needs for firmware, DTB, and future initramfs growth

## Next Milestone: CPU/Memory Correctness Around Linux

Goal: expand regressions around behavior Linux actually exercises.

Required work:

- add MMU-focused simulation tests for valid/invalid PTE cases
- add accessed/dirty and permission behavior tests around Linux page-table use
- add interrupt priority/delegation tests
- expand AMO/LR/SC and memory-ordering tests
- test direct DDR load/store with wider address and alignment cases
- decide whether scratchpad memories should become explicit block RAMs

## Later Performance Work

Performance is intentionally not the first priority. 

After Linux reaches a reliable small userspace, consider:

- instruction cache
- data cache or a documented uncached memory model
- burst-capable DDR bridge
- prefetch for instruction fetch from DDR
- larger local memories
- pipelining the core

Do not start with these unless a correctness milestone is blocked by current performance.
