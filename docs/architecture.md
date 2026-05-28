# Architecture

This document describes the current RTL architecture, not the original plan.

## System Shape

```text
PS UART / XSCT
  -> ARM-side ps_uart_probe.elf
  -> AXI GP0 register windows in PL
  -> zx32_soc
       -> zx32_core
       -> local IMEM / scratchpad
       -> MMIO UART, timer, interrupt controller, DataMover control
       -> AXI DataMover for bulk DDR transfers
       -> AXI4 master bridge for direct PS DDR load/store/fetch
```

The PS side still owns bootstrapping: PS initializes DDR, configures the PL, loads the ARM-side probe, writes PL CPU test programs, and releases the PL CPU from reset.

## Core

The core is a multi-cycle in-order RV32 design. It is intentionally simple:

- one instruction is processed through explicit fetch/decode/execute/memory/
  writeback-style states
- no instruction or data cache
- no pipeline hazards to manage yet
- memory requests are held until the selected local, MMIO, or DDR target is ready

Implemented execution substrate:

- RV32I-style integer operations, branches, jumps, loads, stores, fences
- RV32M multiply/divide
- RV32A word atomics, including LR/SC reservation tracking
- CSR instructions and a first privileged-architecture substrate
- M-mode and S-mode trap/return paths
- timer and external interrupt injection
- RV32 counter CSRs
- Sv32 page-table walking, small TLB, and `sfence.vma`
- three local custom instructions for bring-up/DataMover control

## PL CPU Memory Map

These addresses are seen by software running on the PL CPU.

| Region | Base | Purpose |
| --- | ---: | --- |
| Boot/local RAM | `0x0000_0000` | reset code and early tests loaded by PS |
| UART | `0x1000_0000` | simple PL MMIO UART transmitter |
| Timer | `0x1001_0000` | `mtime`, `mtimecmp`, timer IRQ |
| DataMover control | `0x1002_0000` | bulk DDR DMA command/status registers |
| CPU control | `0x1003_0000` | reset/status/sizing control block |
| Interrupt controller | `0x1004_0000` | pending/enable/threshold/claim registers |
| Scratchpad | `0x2000_0000` | CPU and DataMover local stream endpoint |
| PS DDR window | `0x8000_0000` | direct DDR load/store/fetch window |

The DDR window is translated by `rtl/bus/axi4_master_bridge.sv`:

```text
PL CPU 0x8000_0000 -> PS physical 0x0010_0000
```

The bridge currently issues single-beat 32-bit AXI4 reads and writes. It is good enough for smoke tests and early firmware, but not a cache or high-performance memory system.

## PS-Side AXI Register Windows

The ARM-side bring-up probe uses these PS-visible addresses:

| PS address | Region |
| ---: | --- |
| `0x43c0_0000` | build-id/status/scratch AXI-Lite probe registers |
| `0x43c1_0000` | DataMover and PL CPU control aperture |
| `0x43c1_1000` | RX scratch region |
| `0x43c1_2000` | TX scratch/mailbox region |
| `0x43c1_3000` | PL CPU IMEM load window |
| `0x43c1_7000` | PL CPU reset/status/reset-vector control |

The detailed PS-side constants live in `hw_bringup/ps_uart_probe.h`.

## Timer and Interrupt Model

`rtl/periph/mmio_timer.sv` exposes:

| Offset | Register |
| ---: | --- |
| `0x00` | `mtime[31:0]` |
| `0x04` | `mtime[63:32]` |
| `0x08` | `mtimecmp[31:0]` |
| `0x0c` | `mtimecmp[63:32]` |
| `0x10` | timer IRQ status |

`rtl/periph/mmio_irqctrl.sv` exposes:

| Offset | Register |
| ---: | --- |
| `0x00` | pending bits |
| `0x04` | enable bits |
| `0x08` | threshold |
| `0x0c` | claim/complete |
| `0x10` | raw source bits |

This is enough for the current S-mode timer smokes and the real Linux boot path. Linux timer events are currently handled through the local SBI shim: the kernel requests SBI TIME events in the CSR `time/timeh` domain, and firmware programs the MMIO `mtimecmp` register after applying the measured `mtime - rdtime` offset.

## Linux Status

The architecture now boots a mainline RV32 Linux kernel to an embedded Buildroot/BusyBox userspace on the board. The board-proven path is:

```text
PS launcher
  -> Linux Image at CPU 0x8040_0000 / PS 0x0050_0000
  -> DTB at CPU 0x8160_0000 / PS 0x0170_0000
  -> M-mode SBI firmware in IMEM
  -> Linux S-mode entry with a0=0, a1=0x8160_0000, satp=0
  -> /init -> /sbin/init from built-in Buildroot initramfs
```

Current Linux-visible behavior:

- early console and `hvc0` use SBI console calls mirrored through the PS-visible scratch ring
- `hvc0` input is forwarded from PS UART through a scratch-backed SBI getchar ring
- timer events use SBI TIME and the local MMIO timer
- Sv32 page walking and the TLB are sufficient for kernel init and Buildroot userspace
- the direct DDR bridge provides uncached single-beat instruction/data access
- no Linux drivers exist yet for the custom PL UART, timer, IRQ controller, or DataMover blocks

Remaining architecture work is mostly about turning the bring-up contract into a stable platform ABI:

- decide whether to keep the local SBI shim or move toward OpenSBI
- clean up or formalize the current `rdtime` to `mtime` offset bridge
- expand MMU, interrupt, AMO, and memory-ordering tests around Linux behavior
- decide which custom devices should be visible to Linux
- document cache/uncached memory ordering before performance work
