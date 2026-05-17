# Roadmap

## Guiding Decision

The CPU is custom, but the instruction set should not be invented from scratch.
Linux already supports RISC-V, so the practical route is to implement a RISC-V
CPU from scratch and grow it until it satisfies the Linux execution environment.

Starting with a private ISA would require a compiler backend, binutils, kernel
port, ABI, libc work, and userspace rebuilds before any CPU hardware issue can
be debugged. That is not a good first path.

## Phase 0: Project Rules

- Keep the core small and testable.
- Use Verilog/SystemVerilog RTL that Vivado can synthesize.
- Every ISA feature gets simulation tests before FPGA bring-up.
- Do not optimize for performance until correctness is visible.
- Treat Linux as a late-stage integration target, not the first test.

## Phase 1: RV32I Core

Goal: run small bare-metal programs in simulation.

Required blocks:

- Program counter
- Instruction fetch
- Decoder
- Register file
- ALU
- Load/store unit
- Branch/jump unit
- Trap placeholder

Recommended first microarchitecture:

- Multi-cycle core, not pipelined.
- One instruction retires after several states.
- Unified memory interface for simulation.
- No cache.
- No interrupts.
- No MMU.

This is slower, but much easier to debug.

## Phase 2: FPGA Bare-Metal

Goal: run a hand-written or compiled bare-metal program from BRAM.

Required blocks:

- BRAM instruction/data memory
- UART output
- Reset vector
- Simple linker script
- RISC-V cross toolchain flow

Success condition:

- The CPU prints text through UART or writes a known memory-mapped register.

## Phase 3: Zynq PS DDR Access Through DataMover

Goal: let the PL CPU request block transfers to and from PS DDR.

Recommended path:

```text
PL CPU -> MMIO DataMover control -> AXI DataMover -> Zynq PS S_AXI_HP port -> PS DDR
```

The PS side must initialize DDR and release the PL CPU reset after the bitstream
and clocks are ready.

This is not a transparent random-access memory port. For Linux, this approach
will need a local-memory/cache/page-refill layer above DataMover, or a later
direct AXI master load/store path if the DataMover-only design becomes too
restrictive.

Current control register draft:

| Offset | Name | Description |
| --- | --- | --- |
| `0x00` | control | bit 0 starts MM2S, bit 1 starts S2MM |
| `0x04` | status | busy/done/error/channel-ready bits |
| `0x08` | ddr_addr | PS DDR address |
| `0x0c` | local_addr | reserved for local stream mover |
| `0x10` | length | transfer length in bytes |
| `0x14` | tag | DataMover command tag |


## Phase 4: Linux-Capable CPU

Linux requires far more than RV32I.

Minimum target:

- RV32IMA or a kernel configuration that avoids atomics where possible
- Machine CSRs
- Supervisor mode
- Exceptions and interrupts
- Timer interrupt
- External interrupt path
- Sv32 MMU
- Page table walker
- TLB
- Correct memory ordering for the selected platform
- Device tree

Strongly recommended:

- I-cache
- D-cache or carefully documented uncached behavior
- UART compatible with a simple Linux driver
- CLINT-like timer block
- PLIC-like interrupt controller

## Phase 5: Linux + BusyBox

Initial boot path:

1. PS FSBL initializes DDR and clocks.
2. PS loads PL bitstream.
3. PS places kernel image, device tree, and initramfs in DDR.
4. PS releases PL CPU reset.
5. PL boot ROM jumps into a small RISC-V bootloader.
6. Bootloader enters Linux with the expected register convention.
7. Linux mounts initramfs and starts BusyBox init.
