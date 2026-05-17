# Architecture Notes

## ISA

The planned ISA is RISC-V, starting at RV32I.

Final Linux-oriented target:

```text
RV32IMA + Zicsr + privileged architecture + Sv32
```

Optional later extensions:

- `C`: compressed instructions, improves code density.
- `F/D`: floating point, not required for a first BusyBox system.

## First Core Shape

The first implementation should be a multi-cycle in-order core:

```text
RESET -> FETCH -> DECODE -> EXECUTE -> MEMORY -> WRITEBACK -> FETCH
```

This avoids pipeline hazards during the first bring-up. A pipeline can be added
after the ISA tests and FPGA BRAM boot work.

## Memory Map Draft

This is a draft and will change once the Vivado design is fixed.

| Region | Address | Size | Purpose |
| --- | ---: | ---: | --- |
| Boot ROM / BRAM | `0x0000_0000` | 64 KiB | reset code |
| UART | `0x1000_0000` | 4 KiB | console |
| Timer | `0x1001_0000` | 4 KiB | machine timer |
| DataMover control | `0x1002_0000` | 4 KiB | DDR block move |
| CPU reset/control | `0x1003_0000` | 4 KiB | bring-up and reset |
| Interrupt controller | `0x1004_0000` | 64 KiB | external interrupts |
| RX scratchpad | `0x2000_0000` | small | DataMover MM2S destination |
| TX scratchpad | `0x2001_0000` | small | DataMover S2MM source |
| PS DDR window | `0x8000_0000` | board-defined | Linux RAM |

## Counter And Timer Model

The core has RV32-style counter CSRs for `mcycle/minstret` and their
`cycle/time/instret` user-visible aliases. `mcounteren` controls S/U access,
and `scounteren` controls U access once S-mode has been entered.

For now, `time/timeh` aliases the same internal 64-bit cycle counter used by
`mcycle/mcycleh`. The MMIO timer remains the interrupt source in the platform
map. Before a real Linux boot, the time source needs to be made compatible with
the chosen RISC-V platform contract, either through an SBI/CLINT-like mtime path
or a clearly fixed-frequency local counter.

## Zynq DDR Boundary

The DDR3 attached to Zynq-7020 is normally controlled by the PS DDR controller.
The PL CPU will control an AXI DataMover instance connected to a PS
high-performance slave port. DataMover is a block-transfer engine, so the CPU
will initially execute from local BRAM and request explicit DDR transfers rather
than issuing every load/store directly to DDR.

Do not build a PL DDR controller first unless the board physically routes DDR
to PL pins, which normal Zynq-7020 boards do not.
