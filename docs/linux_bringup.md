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
- Linux entry convention: `a0=0`, `a1=0x82000000`, `satp=0`.
- SBI v0.2 base probing and TIME extension probing.
- SBI legacy console put/get path used by early console and `hvc0`.
- SBI timer programming and repeated Linux timer events.
- Sv32 page-table setup far enough for kernel init and BusyBox userspace.
- Embedded initramfs execution through `rdinit=/init`.
- Buildroot init scripts, syslog/klog, sysctl, networking setup, crond, getty, login, and an interactive shell.

## Boot Flow

```text
PS standalone launcher
  -> copies Linux Image to PS DDR 0x0040_0000
  -> copies DTB to PS DDR 0x0200_0000
  -> loads linux_boot_firmware.zx32.s into PL CPU IMEM
  -> writes entry/DTB arguments into scratch mailbox
  -> releases the PL CPU

PL CPU M-mode firmware
  -> installs mtvec and SBI state
  -> delegates Linux-facing traps/interrupts
  -> sets mcounteren for S-mode counter reads
  -> enters Linux S-mode at 0x8040_0000

Linux kernel
  -> consumes DTB at 0x8200_0000
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

## RV64 (ZX64) Boot Chain — In Development

The `riscv64gc` branch extends this document's contract to an RV64 platform. Everything in the sections above stays true for ZX32; the differences for ZX64 are:

| Aspect | ZX32 (board-proven) | ZX64 (sim-validated) |
| --- | --- | --- |
| Kernel | mainline RV32, text offset `0x0040_0000`, Image at `0x8040_0000` | Linux v7.1.3 RV64, text offset `0x0020_0000`, Image at `0x8020_0000` |
| MMU | Sv32 | Sv39 |
| ISA string | `rv32ima...` | `rv64gc_zicsr_zifencei` (misa-gated) |
| Rootfs | embedded Buildroot cpio initramfs only | embedded cpio as fallback + 64 MiB ext4 image served by PS-backed virtio-blk, `root=/dev/vda rw` |
| DTB | `linux/zynq_cpu.dts` | `linux/zx64.dts` → `build/linux-rv64/zx64.effective.dts` (PLIC/virtio/simplefb enabled) |
| Firmware | `linux_boot_firmware.zx32.s` (zx32asm) | `linux_boot_firmware.rv64.S` (clang/ld.lld, `-march=rv64ima_zicsr_zifencei -mabi=lp64`) |
| Launcher | `ps_linux_boot` default build | same source built with `-DZYNQ_CPU_RV64_BOOT` via `scripts/build_ps_linux_boot_rv64.sh` |
| XSBL | `download_zynq_cpu_linux_boot.xsbl` | `download_zynq_cpu_rv64_linux_boot.xsbl` |
| Interrupts | SBI/timer only | PLIC at `0x0c00_0000`; virtio-blk = source 1, virtio-input = source 2 |

The SBI shim contract is intentionally identical: same 256-byte console output ring, 128-byte input ring, mailbox offsets, and `mtime - rdtime` timer bridge (the RV64 firmware additionally defines warm-reboot slots at `0x258..0x260` and time-sample slots at `0x340/0x344`), so the PS-side console mirror and diagnostics work unchanged.

```text
PS launcher (RV64 build)
  -> loads rv64 firmware into IMEM, verifies word-by-word
  -> Linux Image -> PS 0x0020_0000, DTB -> PS 0x0200_0000
  -> ext4 rootfs -> PS 0x0800_0000 (capacity meta @ 0x07ff_f000, magic 0x5A363442)
  -> services virtio-blk/input virtqueues over the bring-up-registers window
  -> releases the PL CPU; S-mode entry a0=0, a1=0x8200_0000, satp=0
```

Validation status at the time of writing:

- Icarus: `soc64-5stage-linux`, `soc64-5stage-real-sbi`, `zx64-fw`, `zx64-boot-chain` pass.
- Vivado RV64 implementation: timing met with `ZYNQ_CPU_RV64_ENABLE_FPU=0`; the FPU-enabled RV64GC build over-utilizes the XC7Z020 (see `docs/synthesis_status.md`).
- Contract checks: `scripts/check_zx64_linux_boot_chain.sh` verifies hashes/addresses/MISA/rootfs mode and writes `build/linux-rv64/boot_artifacts.env`.
- **Board boot: not yet run.** No RV64 expected-log signature exists in `docs/hardware_uart_test.md` yet. Until one is recorded, do not debug RV64 userspace/kernel issues against hardware assumptions.

Board sequence once RV64 hardware bring-up starts:

```sh
ZYNQ_CPU_SOC=rv64 ./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
./scripts/prepare_mainline_rv64_linux.sh
./scripts/build_zx64_busybox_rootfs.sh
./scripts/build_zx64_virtio_rootfs_ext4.sh
./scripts/prepare_zx64_linux_boot_artifacts.sh
./scripts/check_zx64_linux_boot_chain.sh
./scripts/build_ps_linux_boot_rv64.sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_rv64_linux_boot.xsbl
```
