# ZYNQ_CPU

ZYNQ_CPU is a custom RV32-class CPU and SoC bring-up project for the Zynq-7020 PL on the ALINX AX7020B board.

The long-term target is to boot a usable riscv32 Linux environment on the PL CPU. The current tree now boots a mainline RV32 kernel on the board, uses the local SBI shim for console and timer services, starts an embedded Buildroot/BusyBox initramfs, reaches `buildroot login:`, and accepts interactive `hvc0` input through the PS/SBI console bridge. It is still a bring-up Linux environment, but it is now a usable minimal userspace rather than only an early boot marker.

## Current Status

Implemented and tested in the current tree:

- Multi-cycle in-order RV32 core skeleton in `rtl/core/zx32_core.sv`.
- RV32I-style integer execution, loads/stores, branches, jumps, fences, and system instructions.
- RV32M multiply/divide and RV32A word atomics.
- Machine and supervisor CSR substrate, exception return, delegated traps, timer interrupt path, external interrupt path, counters, `satp`, Sv32 page walking, small TLB, and `sfence.vma`.
- Local boot/scratch memories and simple MMIO peripherals.
- AXI DataMover control path for bulk DDR transfers through Zynq PS HP.
- Direct serialized AXI4 master bridge for PL CPU load/store and instruction fetches from PS DDR, with multi-beat read refills behind the SoC I-cache/D-cache front end.
- MMIO-controlled framebuffer fill renderer v0 for DDR clear and rectangle-fill tests.
- PS-side bring-up probe that loads ZX32 assembly/ELF tests, starts the PL CPU, and reports PASS/FAIL over PS UART.

Latest board-level bring-up has passed:

- AXI-Lite register probe
- DataMover HP0 loopback
- PL CPU initiated DataMover loopback
- BRAM program load/run
- ELF load/run and reset-vector entry
- machine trap smoke
- supervisor trap smoke
- supervisor timer interrupt smoke
- boot payload handoff smoke
- supervisor counter CSR smoke
- custom DataMover instruction smoke
- DDR random load/store smoke
- DDR instruction fetch smoke
- DDR high-address random load/store, instruction fetch, and AMO smoke
- SBI firmware smoke
- SBI timer smoke
- Linux boot contract smoke
- Linux SBI compatibility smoke
- Linux image layout smoke
- Linux boot to Buildroot userspace:
  - `Saving 2048 bits of non-creditable seed for next boot`
  - `Starting syslogd: OK`
  - `Starting klogd: OK`
  - `Running sysctl: OK`
  - `Starting network: OK`
  - `Starting crond: OK`
  - `Welcome to Buildroot`
  - `buildroot login:`

The current Linux path is intentionally simple:

- the Buildroot rootfs is embedded in the kernel Image from `build/buildroot-zx32/images/rootfs.cpio`;
- console output is mirrored through an SBI console scratch ring and drained by the PS launcher;
- console input is forwarded from PS UART through a scratch-backed SBI getchar ring;
- the local M-mode firmware implements only the SBI pieces needed by this board path;
- production device drivers and a stable platform ABI are not present yet.

The same Image/DTB/firmware path can also run in the Python functional simulator under `tools/zx32sim/`. The simulator now reaches the Buildroot login prompt, supports scripted expect/send console tests, supports live interactive stdin/stdout console bridging, and includes simulator-only block-device models for software bring-up without a board.

The next Linux work is to make this Buildroot environment repeatable on both board and simulator, reduce board console input latency, and clean up the SBI/platform contracts.

## Target Board

- Board: ALINX AX7020B
- FPGA: `xc7z020clg400-2`
- PS DDR3 device target: `MT41K256M16RE-125`, 32-bit
- PL clock in current hardware build: PS FCLK0 at about 75 MHz
- Vivado target: 2025.2 through the local `vi25` shell function

## Repository Layout

| Path | Purpose |
| --- | --- |
| `rtl/core/` | ZX32 CPU core RTL |
| `rtl/bus/` | DataMover control and AXI4 master bridge |
| `rtl/periph/` | UART, timer, interrupt controller, scratchpad, simple RAM |
| `rtl/soc/` | PL CPU SoC wrapper |
| `tb/` | Icarus Verilog/SystemVerilog testbenches |
| `tools/` | ZX32 assembler, ELF packer, and unit tests |
| `tools/zx32sim/` | Python functional simulator for ISA, SBI, Linux, and device-model bring-up |
| `hw_bringup/` | PS UART probe, PL CPU assembly smoke programs, and small userspace test tools |
| `linux/` | Linux DTS and config fragment |
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
./scripts/run_iverilog_tests.sh irqctrl
./scripts/run_iverilog_tests.sh scratchpad
./scripts/run_iverilog_tests.sh gpu
./scripts/run_iverilog_tests.sh soc
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

Build the current Zynq hardware bitstream and XSA:

```sh
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

Prepare and run the current Linux boot path:

```sh
./scripts/prepare_mainline_linux.sh
./scripts/build_zx32_busybox_rootfs.sh
./scripts/build_mainline_rv32_linux.sh
./scripts/prepare_linux_boot_artifacts.sh
./scripts/build_ps_uart_probe.sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl
```

## Script Rules

Vivado, Vitis, and XSCT commands must use the repository wrappers so the local Vivado 2025.2 environment is loaded consistently:

- `scripts/run_vivado.sh`
- `scripts/run_xsct.sh`
- `scripts/build_ps_uart_probe.sh`

The wrappers source `/home/orionisli/.zshrc`, call `vi25`, then run the relevant tool. 

Do not rely on an already-configured interactive shell when adding project automation.

## Documentation Index

- `docs/architecture.md`: current core/SoC architecture and memory maps
- `docs/board_ax7020b.md`: board-specific clock, UART, DDR, and Vivado notes
- `docs/datamover_memory.md`: DDR access paths and DataMover details
- `docs/hardware_uart_test.md`: hardware build, download, and expected probe log
- `docs/isa.md`: supported ISA subset, custom instructions, and toolchain notes
- `docs/toolchain.md`: local tools and command entry points
- `docs/synthesis_status.md`: current synthesis/implementation snapshots
- `docs/simulator.md`: ZX32 functional simulator usage, console model, and limitations
- `docs/roadmap.md`: completed Linux milestone and remaining platform work
- `docs/linux_bringup.md`: current Linux boot flow, evidence, and limitations
- `docs/linux_boot_layout.md`: actual firmware/kernel/DTB/initramfs placement
- `linux/zynq_cpu.dts`: first DTB source draft for the current custom platform
