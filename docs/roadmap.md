# Roadmap

The project goal is a custom PL CPU that can run a useful riscv32 Linux environment. 

The first useful Linux milestone is now complete: the board boots a mainline RV32 kernel into an embedded Buildroot/BusyBox initramfs, starts the standard init scripts, reaches `buildroot login:`, and accepts interactive `hvc0` input.

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
- embedded Buildroot rootfs starts syslogd, klogd, sysctl, network setup, crond, and getty
- interactive login over `hvc0` works through the PS/SBI console bridge
- Vivado 2025.2 bitstream generation with timing met at the current 75 MHz target

## Current Development Stage

The active stage is:

```text
stabilize the board-proven Buildroot userspace and platform ABI
```

The immediate success signature to preserve is:

```text
Saving 2048 bits of non-creditable seed for next boot
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Starting network: OK
Starting crond: OK
Welcome to Buildroot
buildroot login:
```

Do not treat later Linux regressions as userspace or kernel bugs until this signature still reproduces with the same Image/DTB/firmware layout.

## Current Linux Artifacts

Source-of-truth files:

- `docs/linux_bringup.md`
- `docs/linux_boot_layout.md`
- `linux/zynq_cpu.dts`
- `linux/zx32_rv32.config`
- `hw_bringup/ps_linux_boot.c`
- `hw_bringup/programs/linux_boot_firmware.zx32.s`
- `hw_bringup/download_zynq_cpu_linux_boot.xsbl`

Generated artifacts:

- `linux/kernel/`
- `build/linux-mainline-rv32/`
- `build/buildroot-zx32/`
- `build/linux/`
- `hw_bringup/build/`

These generated paths are ignored and should not become source-of-truth.

## Next Milestone: Stable Buildroot Regression

Goal: make the current Linux boot and login path easy to rerun and compare.

Required work:

- keep the final success condition as `Welcome to Buildroot` followed by `buildroot login:`
- keep the PS launcher quiet by default and gate noisy periodic monitor samples
- keep a compact expected-log section in `docs/hardware_uart_test.md`
- record the exact Image/DTB addresses through `build/linux/boot_artifacts.env`
- make all Linux boot diagnostics explainable from `docs/linux_boot_layout.md`

## Next Milestone: Better Interactive Console

Goal: make the interactive terminal path feel usable instead of merely functional.

Required work:

- reduce input latency in the PS UART to SBI getchar path
- keep the scratch-ring overflow behavior explicit and observable
- decide whether `hvc0` remains the primary console or becomes only an early-console path
- validate repeated login shell commands, line editing, and long input bursts

## Next Milestone: Buildroot Platform Cleanup

Goal: remove remaining bring-up assumptions from the Buildroot/Linux configuration.

Required work:

- keep rootfs size within the current Image/DTB placement constraints
- remove or explain init scripts for Linux features the platform does not implement yet
- verify POSIX timer, sysctl, network setup, crond, getty, and shell behavior after kernel config changes
- decide which Buildroot packages are useful enough to keep in the default rootfs

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
