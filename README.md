# ZYNQ_CPU

This repository is for building a CPU in the Zynq-7020 PL from first principles.

The long-term target is to boot a Linux kernel with a BusyBox userspace. The CPU
implementation is custom, but the ISA target is RISC-V so that the upstream
toolchain, kernel, and userland can be reused.

## Target

- Board: ALINX AX7020B
- FPGA: `xc7z020clg400-2`
- PL CPU ISA path: RV32I -> RV32IM -> RV32IMA -> RV32IMA privileged -> RV32IMA + Sv32
- External memory: PS DDR3 exposed to PL through AXI DataMover on AXI HP
- DDR device: `MT41K256M16RE-125`, 32-bit
- First Linux target: riscv32 Linux with initramfs BusyBox

## Directory Layout

- `docs/`: architecture notes and bring-up plan
- `rtl/core/`: CPU core RTL
- `rtl/bus/`: bus adapters and interconnect-facing logic
- `rtl/periph/`: minimal platform peripherals
- `tb/`: simulation testbenches
- `scripts/`: build, simulation, and utility scripts
- `vivado/`: Zynq-7020 block design and synthesis notes
- `linux/`: kernel, device tree, and boot notes
- `buildroot/`: BusyBox/initramfs build notes

## Toolchain Rule

Every Vivado or synthesis command must first run `vi25` to switch the shell to
Vivado 2025.2. Use `scripts/run_vivado.sh` for Vivado automation so this rule is
applied consistently.

## Milestones

1. RV32I single-cycle or simple multi-cycle core in simulation.
2. Bare-metal program running from BRAM.
3. Native MMIO debug/peripheral bus.
4. AXI DataMover command path to PS DDR through Zynq HP port.
5. Timer, interrupt controller, CSR, exceptions.
6. RV32IMA base Linux instruction substrate.
7. Privileged architecture support.
8. Sv32 MMU, page table walking, TLB, `sfence.vma`, cache policy.
9. Linux early console.
10. BusyBox initramfs shell.
