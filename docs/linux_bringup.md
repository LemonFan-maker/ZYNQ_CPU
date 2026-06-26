# Linux Bring-Up

This document records the current board-proven Linux path for ZYNQ_CPU. The board now boots a mainline RV32 Linux kernel into an embedded Buildroot/BusyBox initramfs and reaches an interactive `hvc0` login shell.

## Current Board-Proven Milestone

The current Linux boot run reaches:

```text
Linux SBI console mirror
Saving 2048 bits of non-creditable seed for next boot
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Starting network: OK
Starting crond: OK

Welcome to Buildroot
buildroot login: root
# uname -a
Linux buildroot 5.10.0+ ... riscv32 GNU/Linux
# hostname
buildroot
```

This proves the following pieces work together on hardware:

- PS-side loading of the kernel Image and DTB into the PL CPU DDR window.
- M-mode firmware handoff into the Linux kernel in S-mode.
- Linux entry convention: `a0=0`, `a1=0x81600000`, `satp=0`.
- SBI v0.2 base probing and TIME extension probing.
- SBI legacy console put/get path used by early console and `hvc0`.
- SBI timer programming and repeated Linux timer events.
- Sv32 page-table setup far enough for kernel init and BusyBox userspace.
- Embedded initramfs execution through `rdinit=/init`.
- Buildroot init scripts, syslog/klog, sysctl, networking setup, crond, getty, login, and an interactive shell.

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
  -> execs /init -> /sbin/init
  -> starts Buildroot services and hvc0 getty
```

The initramfs payload is the Buildroot root filesystem produced by `scripts/build_zx32_busybox_rootfs.sh`. `scripts/build_mainline_rv32_linux.sh` embeds `build/buildroot-zx32/images/rootfs.cpio` through a generated `CONFIG_INITRAMFS_SOURCE` entry.

## SBI Shim

The local firmware is deliberately small. It currently handles:

| Extension | Functionality |
| --- | --- |
| SBI base `0x10` | spec version, implementation ID/version, extension probe, machine IDs |
| SBI TIME `0x54494d45` | `set_timer` |
| legacy `0` | legacy timer compatibility |
| legacy `1` | console putchar into a PS-drained scratch ring |
| legacy `2` | console getchar from a PS-fed scratch input ring |
| debug `0x5a444247` | local debug marker used by bring-up code |

Linux reads time through the CPU `time/timeh` CSRs, while the current MMIO timer interrupt is programmed through `mtimecmp` at `0x10010008`. The firmware bridges that difference on the first timer call:

```text
offset = mmio_mtime - csr_rdtime
mtimecmp = max(requested_rdtime + offset, current_mtime + 0x10000)
```

The offset is stored in the scratch mailbox and later boot samples should show `off_valid=1`, an increasing `mtime`, and `cmp` ahead of `mtime`.

## Console Path

Linux console output is written through SBI console putchar into a 256-byte ring inside the TX scratch region. The PS launcher drains that ring and prints a `Linux SBI console mirror` section on PS UART.

Console input flows in the other direction: the PS launcher drains the PS UART RX FIFO into a 128-byte scratch input ring, and SBI console getchar consumes that ring for Linux `hvc0`. A legacy single-byte mailbox remains as a fallback.

The board-proven login signature is:

```text
Welcome to Buildroot
buildroot login:
```

After logging in as `root`, basic interactive commands should work:

```text
# uname -a
# hostname
```

The PS launcher is intentionally quiet in the normal path; detailed boot monitor and core state dumps should be enabled only for diagnosis.

## Simulator Verification

The same Linux Image, DTB, and M-mode firmware can run in the functional simulator without a board:

```sh
./scripts/run_zx32sim_linux_early.sh
```

That command stops when the simulated SBI console reaches `buildroot login:`.

For a live shell:

```sh
ZX32SIM_INTERACTIVE=1 ./scripts/run_zx32sim_linux_early.sh
```

The simulator bridges host stdin/stdout to the same scratch-backed SBI console input/output rings used by the board PS launcher. 

This makes it useful for software debugging and repeatable command-output checks, but it is still a functional model rather than hardware proof. 

Board logs remain the final source of truth for RTL timing, AXI behavior, and PS/PL integration.

For scripted login tests and simulator-specific block devices, see
`docs/simulator.md`.

## Source Files

| File | Purpose |
| --- | --- |
| `hw_bringup/ps_linux_boot.c` | PS-side Linux boot launcher and monitor |
| `hw_bringup/programs/linux_boot_firmware.zx32.s` | local M-mode SBI firmware |
| `hw_bringup/download_zynq_cpu_linux_boot.xsbl` | XSCT entry for the real Linux boot run |
| `linux/zynq_cpu.dts` | DTB source for the current custom platform |
| `linux/zx32sim_virtio.dts` | simulator-only DTB variant with PLIC and virtio block |
| `linux/zx32_rv32.config` | minimal RV32 Linux config fragment |
| `scripts/prepare_mainline_linux.sh` | fetch/prepare Linux source tree |
| `scripts/build_zx32_busybox_rootfs.sh` | build the Buildroot BusyBox rootfs |
| `scripts/build_mainline_rv32_linux.sh` | build the RV32 kernel Image |
| `scripts/prepare_linux_boot_artifacts.sh` | build DTB and validate Image/DTB placement |
| `scripts/build_ps_uart_probe.sh` | build both PS probe launchers and generated payloads |
| `scripts/run_zx32sim_linux_early.sh` | run the Linux path in the simulator |
| `tools/zx32sim/` | Python functional simulator |

## Commands

The normal build sequence is:

```sh
./scripts/prepare_mainline_linux.sh
./scripts/build_zx32_busybox_rootfs.sh
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

- The SBI shim is local bring-up firmware, not a full OpenSBI port.
- Timer bridging currently depends on a measured `rdtime` to MMIO `mtime` offset.
- Linux-visible custom UART, timer, interrupt controller, and DataMover drivers are not implemented.
- The direct DDR path is still a simple bring-up memory system: read-side I-cache/D-cache refills are present, raw writes are serialized and invalidate matching cache lines, and correctness is still the priority.
- The DTB is still a bring-up description and should be updated whenever the platform ABI changes.
- Console input is functional but still routed through the PS launcher polling loop and scratch ring, so it is not a high-performance terminal path.

## Next Steps

1. Keep the Buildroot login signature stable as the Linux boot regression target.
2. Reduce the latency of the PS-polled console input path or replace it with a Linux-visible UART path.
3. Clean up the SBI timer model and document whether `time` and `mtime` share a permanent clock domain.
4. Decide whether the long-term console is SBI/HVC-only or a Linux driver for the PL UART.
5. Expand MMU, trap, interrupt, and AMO regression tests around the real Linux behavior now observed on hardware.
