# Roadmap

The project goal is still a custom PL CPU that can boot riscv32 Linux with a
BusyBox initramfs. The current state is well past first RTL bring-up, but still
before real Linux integration.

## Completed Bring-Up Milestones

These are already represented in code and tests:

- local RV32-style core execution in simulation
- assembler and minimal ELF generation flow
- PS-loadable PL CPU programs
- AXI-Lite PS-to-PL register probe
- DataMover loopback through PS DDR
- PL CPU initiated DataMover transfers
- ELF loading and reset-vector selection
- M-mode trap smoke
- S-mode trap smoke
- timer interrupt delegation to S-mode
- boot payload handoff with `a0=hartid`, `a1=dtb`
- S-mode counter CSR access
- direct DDR load/store from PL CPU
- instruction fetch and execution from the DDR window
- SBI-style firmware and timer smoke tests
- Vivado 2025.2 bitstream generation with timing met at the current 75 MHz
  target

## Current Development Stage

The active stage is:

```text
turn board-proven smoke tests into a Linux boot substrate
```

That means moving from tiny hand-written payloads to a real firmware/kernel
loading path and a documented platform ABI.

## Next Milestone: Real Firmware Contract

Goal: run an M-mode firmware layer that can enter a larger S-mode payload using
the same convention Linux expects.

Required work:

- decide whether to adapt OpenSBI or keep a small local SBI shim first
- implement the required SBI base and timer behavior beyond smoke-test calls
- define hart ID and DTB address ownership
- place firmware, payload, and DTB in DDR through the PS loader
- make failures visible through UART/mailbox diagnostics

Suggested first target:

```text
M-mode firmware in local RAM or DDR
  -> S-mode payload in DDR
  -> SBI console/timer probes
```

## Next Milestone: Device Tree and Platform ABI

Goal: write a DTB that accurately describes the current platform.

Required decisions:

- memory node for the DDR window starting at `0x8000_0000`
- CPU node and ISA string
- timer source and timebase frequency
- interrupt controller representation
- UART/console path
- reserved memory for firmware, DTB, and initramfs

If the existing custom timer/IRQ blocks are kept, Linux needs compatible drivers
or firmware must hide them behind SBI where possible.

## Next Milestone: Linux Kernel Smoke

Goal: reach early Linux boot text, then a small initramfs shell.

Required work:

- build a riscv32 kernel configured for the implemented ISA/platform
- choose early console strategy
- load kernel image, DTB, and initramfs into DDR from PS
- enter kernel with the RISC-V boot convention
- debug early traps through the firmware/probe mailbox

Expected blockers:

- privileged architecture corner cases
- Sv32 permission/accessed/dirty/page-fault behavior
- atomics and memory ordering under kernel code
- timer interrupt rate and SBI behavior
- no cache and low single-beat DDR performance

## Technical Debt Before Linux

Address these before treating Linux failures as kernel-level issues:

- add broader instruction/CSR compliance tests
- add MMU-focused simulation tests with valid/invalid PTE cases
- add interrupt priority/delegation tests
- test direct DDR load/store with wider address and alignment cases
- decide whether scratchpad memories should become explicit block RAMs
- document and enforce generated artifact cleanup through `.gitignore`

## Later Performance Work

Performance is intentionally not the first priority. After Linux reaches a
reliable early boot, consider:

- instruction cache
- data cache or a documented uncached memory model
- burst-capable DDR bridge
- prefetch for instruction fetch from DDR
- larger local memories
- pipelining the core

Do not start with these unless a correctness milestone is blocked by current
performance.
