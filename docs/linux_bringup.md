# Linux Bring-Up

This document records the current board-proven Linux path for ZYNQ_CPU. The milestone is not a full distribution or BusyBox system yet, but it is a real mainline RV32 Linux boot into an embedded initramfs userspace.

## Current Board-Proven Milestone

The current Linux boot run reaches:

```text
SBI specification v0.2 detected
SBI implementation ID=0x5a32 Version=0x1
SBI v0.2 TIME extension detected
Run /init as init process

[zx32-init] userspace entered
[zx32-init] getpid ok
[zx32-init] alive
[zx32-init] idle
Boot monitor: userspace idle reached
```

This proves the following pieces work together on hardware:

- PS-side loading of the kernel Image and DTB into the PL CPU DDR window.
- M-mode firmware handoff into the Linux kernel in S-mode.
- Linux entry convention: `a0=0`, `a1=0x81600000`, `satp=0`.
- SBI v0.2 base probing and TIME extension probing.
- SBI legacy console put/get path used by early console and `hvc0`.
- SBI timer programming and repeated Linux timer events.
- Sv32 page-table setup far enough for kernel init and a tiny userspace ELF.
- Embedded initramfs execution through `rdinit=/init`.
- A userspace `getpid` syscall smoke test followed by a quiet idle loop.

## Boot Flow

```text
PS standalone launcher
  -> copies Linux Image to PS DDR 0x0050_0000
  -> copies DTB to PS DDR 0x0170_0000
  -> loads linux_boot_firmware.zx32.s into PL CPU IMEM
  -> writes entry/DTB arguments into scratch mailbox
  -> releases the PL CPU

PL CPU M-mode firmware
  -> installs mtvec and SBI state
  -> delegates Linux-facing traps/interrupts
  -> sets mcounteren for S-mode counter reads
  -> enters Linux S-mode at 0x8040_0000

Linux kernel
  -> consumes DTB at 0x8160_0000
  -> uses SBI console and timer
  -> mounts the built-in initramfs
  -> execs /init
```

The initramfs payload is assembled from `linux/initramfs/init.S` by `scripts/build_zx32_initramfs.sh`, then embedded into the kernel build through a generated `CONFIG_INITRAMFS_SOURCE` entry.

## SBI Shim

The local firmware is deliberately small. It currently handles:

| Extension | Functionality |
| --- | --- |
| SBI base `0x10` | spec version, implementation ID/version, extension probe, machine IDs |
| SBI TIME `0x54494d45` | `set_timer` |
| legacy `0` | legacy timer compatibility |
| legacy `1` | console putchar into a PS-drained scratch ring |
| legacy `2` | console getchar, currently returns `-1` |
| debug `0x5a444247` | local debug marker used by bring-up code |

Linux reads time through the CPU `time/timeh` CSRs, while the current MMIO timer interrupt is programmed through `mtimecmp` at `0x10010008`. The firmware bridges that difference on the first timer call:

```text
offset = mmio_mtime - csr_rdtime
mtimecmp = max(requested_rdtime + offset, current_mtime + 0x10000)
```

The offset is stored in the scratch mailbox and later boot samples should show `off_valid=1`, an increasing `mtime`, and `cmp` ahead of `mtime`.

## Console Mirror

Linux console output is written through SBI console putchar into a 256-byte ring inside the TX scratch region. The PS launcher drains that ring and prints a `Linux SBI console mirror` section on PS UART.

The launcher watches for the exact string:

```text
[zx32-init] idle
```

When it sees that marker, it prints:

```text
Boot monitor: userspace idle reached
```

After that point the run is considered successful and the launcher suppresses most periodic SBI/TIME noise.

## Source Files

| File | Purpose |
| --- | --- |
| `hw_bringup/ps_linux_boot.c` | PS-side Linux boot launcher and monitor |
| `hw_bringup/programs/linux_boot_firmware.zx32.s` | local M-mode SBI firmware |
| `hw_bringup/download_zynq_cpu_linux_boot.xsbl` | XSCT entry for the real Linux boot run |
| `linux/zynq_cpu.dts` | DTB source for the current custom platform |
| `linux/zx32_rv32.config` | minimal RV32 Linux config fragment |
| `linux/initramfs/init.S` | tiny userspace init payload |
| `scripts/prepare_mainline_linux.sh` | fetch/prepare Linux source tree |
| `scripts/build_mainline_rv32_linux.sh` | build the RV32 kernel Image |
| `scripts/build_zx32_initramfs.sh` | build `/init` and initramfs file list |
| `scripts/prepare_linux_boot_artifacts.sh` | build DTB and validate Image/DTB placement |
| `scripts/build_ps_uart_probe.sh` | build both PS probe launchers and generated payloads |

## Commands

The normal build sequence is:

```sh
./scripts/prepare_mainline_linux.sh
./scripts/build_mainline_rv32_linux.sh
./scripts/prepare_linux_boot_artifacts.sh
./scripts/build_ps_uart_probe.sh
```

Run the board Linux boot launcher with:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl
```

Use the ordinary board probe for broader CPU/SoC smoke tests:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

## Known Limits

- The userspace is a hand-written static RV32 assembly `_start`, not BusyBox.
- There is no interactive shell yet.
- The SBI shim is local bring-up firmware, not a full OpenSBI port.
- Timer bridging currently depends on a measured `rdtime` to MMIO `mtime` offset.
- Linux-visible custom UART, timer, interrupt controller, and DataMover drivers are not implemented.
- The direct DDR bridge is uncached, single-beat, and slow; correctness is the current priority.
- The DTB is still a bring-up description and should be updated whenever the platform ABI changes.

## Next Steps

1. Keep the `userspace idle reached` signature stable as a regression target.
2. Add a few more tiny `/init` syscall smokes before introducing libc or BusyBox.
3. Replace the hand-written initramfs with a minimal BusyBox or libc-based initramfs.
4. Clean up the SBI timer model and document whether `time` and `mtime` share a permanent clock domain.
5. Decide whether the long-term console is SBI/HVC-only or a Linux driver for the PL UART.
6. Expand MMU, trap, interrupt, and AMO regression tests around the real Linux behavior now observed on hardware.