# ZYNQ_CPU

ZYNQ_CPU is a custom RISC-V CPU and SoC bring-up project for the Zynq-7020 PL on the ALINX AX7020B board.

The project now carries two CPU families on the `riscv64gc` development branch (this branch; `master` stays on the RV32-only line):

- **ZX32 (RV32)** — board-proven: boots a mainline RV32 kernel with the local SBI shim, embedded Buildroot/BusyBox initramfs, reaches `buildroot login:`, interactive `hvc0`; plus HDMI console bring-up, 64 MiB VRAM, and an MMIO 2D GPU (clear/fill/line/blit/color-key/scale/alpha).
- **ZX64 (RV64GC)** — in development: 5-stage `rv64gc_zicsr_zifencei` pipeline core, PLIC, PS-backed virtio-blk/virtio-input MMIO devices, mainline RV64 Linux (v7.1.3) boot chain with an ext4 rootfs on `/dev/vda`, synthesized and timing-clean in the RV64 Vivado flow. **Board boot of the RV64 chain has not been run yet** — simulation and boot-chain checks only.

## Current Status

Implemented and tested in the current tree:

- ZX32: multi-cycle in-order RV32 core (`rtl/core/zx32_core.sv`), RV32IMAC, M/S privilege, Sv32, TLB, SBI shim, Buildroot login on board.
- ZX64: `zx64_core5` 5-stage RV64GC pipeline with FPU (`rtl/core64/`), older single-cycle `zx64_core` kept as reference; Sv39, M/S/U, RV64A doubleword atomics, compressed fetch.
- ZX64 SoC (`rtl/soc/zx64_soc.sv`): PLIC (`0x0c00_0000`), virtio-mmio block (`0x1006_0000`) and input (`0x1009_0000`) with PS-side ring servicing, ZX32-compatible UART/timer/scratch, cached AXI4 DDR bridge, `simple_ram64` boot IMEM.
- RV64 Linux artifacts: `linux/zx64.dts` + effective-DTS generator, `zx64_rv64.config` kernel fragment, RV64 S-mode boot firmware, `ZYNQ_CPU_RV64_BOOT` variant of `ps_linux_boot.c` that loads Image/DTB/ext4 and serves the virtio backends.
- GPU renderer: MMIO device with clear/fill/line plus blit, color-key blit, scale-blit, and fixed-point alpha-blit; Linux userspace smoke/demo tools.
- PS-side bring-up probe that loads ZX32 assembly/ELF tests, starts the PL CPU, and reports PASS/FAIL over PS UART.

Board-proven (ZX32) bring-up has passed:

- AXI-Lite register probe; DataMover HP0 loopback; PL CPU initiated DataMover loopback
- BRAM/ELF program load/run, reset-vector entry
- machine/supervisor trap, supervisor timer, boot payload handoff, supervisor counter smokes
- custom DataMover instruction smoke
- DDR random load/store, instruction fetch, high-address load/store/fetch/AMO smokes
- SBI firmware and timer smokes; Linux boot contract / SBI compatibility / image layout smokes
- Linux boot to Buildroot userspace:
  - `Starting syslogd/klogd, sysctl, network, crond: OK`
  - `Welcome to Buildroot` / `buildroot login:`

ZX64 verification status (no board run yet):

- Icarus regressions: `core64`, `core64-5stage`, `soc64*` (mmio/host/ddr/sv39/sbi/real-sbi/linux), `plic`, `virtio-blk-regs`, `virtio-input-regs`, `zx64-fw`, `zx64-boot-chain`
- RV64 Vivado bring-up build completes with all constraints met at 75 MHz (`build/vivado_hw_rv64`, `ZYNQ_CPU_SOC=rv64`)
- Boot-chain contract checks pass (`scripts/check_zx64_linux_boot_chain.sh`): Image/DTB/ext4 hashes, address non-overlap, MISA vs `riscv,isa`
- Outstanding: program the RV64 bitstream and reach the Linux login prompt on hardware

The current Linux paths are intentionally simple:

- ZX32 embeds the Buildroot rootfs in the kernel Image from `build/buildroot-zx32/images/rootfs.cpio`; ZX64 embeds `build/buildroot-zx64/images/rootfs.cpio` as a fallback initramfs but boots `root=/dev/vda` from the PS-loaded ext4 image;
- console output is mirrored through an SBI console scratch ring and drained by the PS launcher;
- console input is forwarded from PS UART through a scratch-backed SBI getchar ring;
- the local M-mode firmware implements only the SBI pieces needed by these board paths;
- production device drivers and a stable platform ABI are not present yet (the RV64 virtio devices are the first Linux-visible driver contract).

The same ZX32 Image/DTB/firmware path can also run in the Python functional simulator under `tools/zx32sim/`. The simulator reaches the Buildroot login prompt, supports scripted expect/send console tests, supports live interactive stdin/stdout console bridging, and includes simulator-only block-device models for software bring-up without a board. There is no RV64 simulator model yet; ZX64 software is validated through Icarus SoC tests and the boot-chain contract checks.

The next Linux work is to run the RV64 boot chain on the board (virtio-blk ext4 rootfs), keep the ZX32 Buildroot login regression stable, reduce board console input latency, and clean up the SBI/platform contracts.

## Target Board

- Board: ALINX AX7020B
- FPGA: `xc7z020clg400-2`
- PS DDR3 device target: `MT41K256M16RE-125`, 32-bit
- PL clock in current hardware build: PS FCLK0 at about 75 MHz
- Vivado target: 2025.2 through the local `vi25` shell function

## Repository Layout

| Path | Purpose |
| --- | --- |
| `rtl/core/` | ZX32 RV32 CPU core RTL |
| `rtl/core64/` | ZX64 RV64GC cores: 5-stage `zx64_core5` (primary) and single-cycle `zx64_core` (reference) |
| `rtl/bus/` | DataMover control and AXI4 master bridge |
| `rtl/periph/` | UART, timer, interrupt controllers, scratchpad, simple RAMs, GPU fill renderer, virtio-mmio register models |
| `rtl/soc/` | PL CPU SoC wrappers (`zx32_soc`, `zx64_soc`) |
| `tb/` | Icarus Verilog/SystemVerilog testbenches (ZX32 and ZX64) |
| `tools/` | ZX32 assembler, ELF packer, bin2c helpers, and unit tests |
| `tools/zx32sim/` | Python functional simulator for ISA, SBI, Linux, and device-model bring-up (RV32 only) |
| `hw_bringup/` | PS-side probes/launchers (RV32 + RV64), PL CPU smoke programs, Linux userspace test tools |
| `linux/` | Linux DTS and config fragments for both RV32 and RV64 |
| `docs/linux_*.md` | Linux boot layout and bring-up contract notes |
| `vivado/` | Vivado batch scripts for synthesis and hardware bring-up |
| `scripts/` | Project automation entry points |
| `docs/` | Development notes, current status, and roadmap |

## Quick Commands

Run software and RTL simulation tests:

```sh
./scripts/run_all_tests.sh
```

Run the ZX32 functional simulator to the Buildroot login prompt:

```sh
./scripts/run_zx32sim_linux_early.sh
```

Run the same Linux path with a live interactive console:

```sh
ZX32SIM_INTERACTIVE=1 ./scripts/run_zx32sim_linux_early.sh
```

At `buildroot login:`, enter `root`; the default root password is empty. Use `Ctrl-C` to stop the simulator.

Run only one Icarus target:

```sh
./scripts/run_iverilog_tests.sh core
./scripts/run_iverilog_tests.sh gpu
./scripts/run_iverilog_tests.sh soc
./scripts/run_iverilog_tests.sh core64-5stage
./scripts/run_iverilog_tests.sh soc64-5stage-linux
./scripts/run_iverilog_tests.sh zx64-boot-chain
```

Build the PS UART probe ELF. This also regenerates the ZX32 program header from `hw_bringup/programs/*.zx32.s`:

```sh
./scripts/build_ps_uart_probe.sh
```

Build the Linux userspace memory benchmark into the Buildroot overlay:

```sh
./scripts/build_zx32_membench.sh
```

Build the Linux userspace GPU smoke test into the Buildroot overlay:

```sh
./scripts/build_zx32_gpu_smoke.sh
```

After rebuilding a userspace test, rebuild the rootfs, kernel Image, and Linux boot artifacts before booting the board.

Run the RTL-only Vivado synthesis check:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/synth_zx32_soc.tcl
```

Build the Zynq hardware bitstream and XSA (RV32 default SoC):

```sh
./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Build the RV64 (ZX64) SoC variant. Use the default build dir for the board
launcher (its XSBL reads `build/vivado_hw/...`); use a separate dir for
soak/CI builds:

```sh
ZYNQ_CPU_SOC=rv64 ./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
ZYNQ_CPU_SOC=rv64 ZYNQ_CPU_VIVADO_BUILD_DIR=build/vivado_hw_rv64 \
  ./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Open the PS UART monitor:

```sh
./scripts/serial_monitor.sh /dev/ttyUSB0 115200
```

Download the bitstream and run the PS bring-up probe:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

Prepare and run the current RV32 Linux boot path:

```sh
./scripts/prepare_mainline_linux.sh
./scripts/build_zx32_busybox_rootfs.sh
./scripts/build_mainline_rv32_linux.sh
./scripts/prepare_linux_boot_artifacts.sh
./scripts/build_ps_uart_probe.sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl
```

Prepare the RV64 (ZX64) Linux boot artifacts (sim-validated; first board run still pending):

```sh
./scripts/prepare_mainline_rv64_linux.sh
./scripts/build_zx64_busybox_rootfs.sh
./scripts/build_zx64_virtio_rootfs_ext4.sh
./scripts/prepare_zx64_linux_boot_artifacts.sh
./scripts/check_zx64_linux_boot_chain.sh
./scripts/build_ps_linux_boot_rv64.sh
```

The matching board launcher entry point is `hw_bringup/download_zynq_cpu_rv64_linux_boot.xsbl`.

## Script Rules

Vivado, Vitis, and XSCT commands must use the repository wrappers so the local Vivado 2025.2 environment is loaded consistently:

- `scripts/run_vivado.sh`
- `scripts/run_xsct.sh`
- `scripts/build_ps_uart_probe.sh`

The wrappers source `/home/orionisli/.zshrc`, call `vi25`, then run the relevant tool. 

Do not rely on an already-configured interactive shell when adding project automation.

## Documentation Index

- `docs/architecture.md`: current core/SoC architecture and memory maps, including the ZX64 RV64 platform section
- `docs/board_ax7020b.md`: board-specific clock, UART, DDR, and Vivado notes
- `docs/datamover_memory.md`: DDR access paths and DataMover details
- `docs/hardware_uart_test.md`: hardware build, download, and expected probe log
- `docs/isa.md`: supported ISA subsets (ZX32 RV32 and ZX64 RV64GC), custom instructions, and toolchain notes
- `docs/toolchain.md`: local tools and command entry points
- `docs/synthesis_status.md`: current synthesis/implementation snapshots (RV32 + RV64)
- `docs/simulator.md`: ZX32 functional simulator usage, console model, and limitations
- `docs/roadmap.md`: completed milestones and remaining platform work (RV32 stabilization + RV64 board bring-up)
- `docs/linux_bringup.md`: RV32 and RV64 Linux boot flows, evidence, and limitations
- `docs/linux_boot_layout.md`: actual firmware/kernel/DTB/initramfs placement for both paths
- `linux/zynq_cpu.dts` / `linux/zx64.dts`: DTB sources for the two platforms
