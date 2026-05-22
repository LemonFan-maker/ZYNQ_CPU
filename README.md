# ZYNQ_CPU

ZYNQ_CPU is a custom RV32-class CPU and SoC bring-up project for the Zynq-7020
PL on the ALINX AX7020B board.

The long-term target is to boot a riscv32 Linux kernel with a BusyBox initramfs.
The current project is not a Linux system yet. It is a hardware bring-up and
execution substrate with simulation tests, a Vivado block design, PS-controlled
board tests, direct PS DDR access from the PL CPU, and early SBI-style smoke
tests.

## Current Status

Implemented and tested in the current tree:

- Multi-cycle in-order RV32 core skeleton in `rtl/core/zx32_core.sv`.
- RV32I-style integer execution, loads/stores, branches, jumps, fences, and
  system instructions.
- RV32M multiply/divide and RV32A word atomics.
- Machine and supervisor CSR substrate, exception return, delegated traps, timer
  interrupt path, external interrupt path, counters, `satp`, Sv32 page walking,
  small TLB, and `sfence.vma`.
- Local boot/scratch memories and simple MMIO peripherals.
- AXI DataMover control path for bulk DDR transfers through Zynq PS HP.
- Direct single-word AXI4 master bridge for PL CPU load/store and instruction
  fetches from PS DDR.
- PS-side bring-up probe that loads ZX32 assembly/ELF tests, starts the PL CPU,
  and reports PASS/FAIL over PS UART.

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
- SBI firmware smoke
- SBI timer smoke

New Linux bring-up scaffolding has been added but still needs board UART
confirmation:

- Linux boot contract smoke: S-mode observes `a0=hartid`, `a1=dtb`, reads a
  DTB-like magic word from DDR, calls SBI base/timer, and receives a delegated
  S-mode timer interrupt.
- `docs/linux_boot_layout.md` and `linux/zynq_cpu.dts` define the first boot layout
  and DTB draft.

Important gap: this is not ready to boot Linux until the Linux contract smoke is
board-confirmed and the real firmware/kernel loading path, device tree,
Linux-visible timer/interrupt/console model, and wider MMU/platform validation
are completed.

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
| `hw_bringup/` | PS UART probe and PL CPU assembly smoke programs |
| `linux/` | Linux DTS, config fragment, and initramfs sources |
| `docs/linux_*.md` | Linux boot layout and bring-up contract notes |
| `vivado/` | Vivado batch scripts for synthesis and hardware bring-up |
| `scripts/` | Project automation entry points |
| `docs/` | Development notes, current status, and roadmap |

## Quick Commands

Run software and RTL simulation tests:

```sh
./scripts/run_all_tests.sh
```

Run only one Icarus target:

```sh
./scripts/run_iverilog_tests.sh core
./scripts/run_iverilog_tests.sh irqctrl
./scripts/run_iverilog_tests.sh scratchpad
./scripts/run_iverilog_tests.sh soc
```

Build the PS UART probe ELF. This also regenerates the ZX32 program header from
`hw_bringup/programs/*.zx32.s`:

```sh
./scripts/build_ps_uart_probe.sh
```

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

## Script Rules

Vivado, Vitis, and XSCT commands must use the repository wrappers so the local
Vivado 2025.2 environment is loaded consistently:

- `scripts/run_vivado.sh`
- `scripts/run_xsct.sh`
- `scripts/build_ps_uart_probe.sh`

The wrappers source `/home/orionisli/.zshrc`, call `vi25`, then run the relevant
tool. Do not rely on an already-configured interactive shell when adding project
automation.

## Documentation Index

- `docs/architecture.md`: current core/SoC architecture and memory maps
- `docs/board_ax7020b.md`: board-specific clock, UART, DDR, and Vivado notes
- `docs/datamover_memory.md`: DDR access paths and DataMover details
- `docs/hardware_uart_test.md`: hardware build, download, and expected probe log
- `docs/isa.md`: supported ISA subset, custom instructions, and toolchain notes
- `docs/toolchain.md`: local tools and command entry points
- `docs/synthesis_status.md`: current synthesis/implementation snapshots
- `docs/roadmap.md`: Linux readiness plan and remaining work
- `docs/linux_bringup.md`: Linux bring-up contract and next payload milestones
- `docs/linux_boot_layout.md`: DDR placement for firmware/kernel/DTB/initramfs
- `linux/zynq_cpu.dts`: first DTB source draft for the current custom platform
