# ZX32 ISA Notes

ZX32 is the local name for this project's RV32-class core and its small custom bring-up extension set. The direction remains RISC-V compatible enough to reuse upstream software where possible.

## Current ISA Substrate

Implemented or intentionally scaffolded in the current core/tooling:

- RV32I-style integer instructions
- byte/halfword/word loads and stores
- branch, jump, `lui`, `auipc`
- `fence` and `fence.i`
- `Zicsr` CSR instruction forms
- `ecall`, `ebreak`, `mret`, `sret`, `wfi`, `sfence.vma`
- RV32M: `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`, `rem`, `remu`
- RV32A word atomics: `lr.w`, `sc.w`, `amoadd.w`, `amoswap.w`, `amoxor.w`, `amoand.w`, `amoor.w`, `amomin.w`, `amomax.w`, `amominu.w`, `amomaxu.w`
- machine and supervisor CSR substrate
- Sv32 page-table walking and TLB invalidation
- custom `OPCODE_CUSTOM0` instructions for bring-up

The core is still a project CPU, not a certified RISC-V implementation. Treat new instructions and privileged behavior as requiring targeted tests before using them for Linux work.

## Custom Instructions

Custom instructions use RISC-V `OPCODE_CUSTOM0` (`0x0b`) with `funct7=0`.

| Mnemonic | `funct3` | Purpose |
| --- | ---: | --- |
| `xcpyw rd, rs1, rs2` | `000` | word copy/register move primitive |
| `xdm2s rd, rs1, rs2` | `001` | launch DataMover MM2S and wait |
| `xds2m rd, rs1, rs2` | `010` | launch DataMover S2MM and wait |

Software helpers:

- C-side encodings: `hw_bringup/zx32_isa.h`
- assembler support: `tools/zx32asm.py`
- assembler tests: `tools/test_zx32asm.py`

## Privileged Architecture

Current CSR and trap work is aimed at the minimum substrate needed for an M-mode firmware layer and S-mode payloads.

Implemented CSR families include:

- machine trap/control CSRs such as `mstatus`, `misa`, `medeleg`, `mideleg`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`
- supervisor CSRs such as `sstatus`, `sie`, `stvec`, `sscratch`, `sepc`, `scause`, `stval`, `sip`, `satp`
- counter control CSRs such as `mcounteren` and `scounteren`
- counter CSRs and read-only ID CSRs

Board smoke tests currently cover:

- M-mode trap handling
- M-mode to S-mode entry
- delegated S-mode `ecall`
- `sret`
- S-mode timer interrupt handling
- `mcounteren` and S-mode counter reads
- SBI-style firmware/payload handoff

## Counter CSRs

The core implements the RV32 split counter CSRs:

| CSR | Purpose |
| --- | --- |
| `mcycle/mcycleh` | 64-bit machine cycle counter |
| `minstret/minstreth` | 64-bit retired-instruction counter |
| `cycle/cycleh` | lower-privilege alias gated by `mcounteren/scounteren` |
| `time/timeh` | current internal timebase alias, gated like `time` |
| `instret/instreth` | lower-privilege retired-instruction alias |
| `mcounteren` | exposes counters from M-mode to S/U |
| `scounteren` | exposes counters from S-mode to U |

For this bring-up stage, `time` is backed by the core's internal time/cycle source. 

A Linux platform must define the final timebase contract clearly through SBI and device tree.

## Program Build Flow

Bring-up programs live in:

```text
hw_bringup/programs/*.zx32.s
```

Generate ELF images and the C header used by the PS UART probe:

```sh
./scripts/build_zx32_programs.sh
```

Build the PS UART probe, including regeneration of the ZX32 program header:

```sh
./scripts/build_ps_uart_probe.sh
```

Run toolchain unit tests:

```sh
./scripts/run_zx32_toolchain_tests.sh
```

The generated header is:

```text
hw_bringup/build/generated/zx32_programs.h
```

It contains both raw instruction arrays and ELF byte arrays.

## ELF Entry Convention

- The local ELF packer treats `_start` as the default entry symbol when present.
- The PS probe loads ELF segments into the PL CPU IMEM window.
- ELF `e_entry` is written to the PL CPU reset-vector register before reset is released.
- DDR execution tests can set the reset vector to a CPU DDR address such as `0x8001_8200`.

## Linux Direction

The ISA direction for Linux remains:

```text
RV32IMA + Zicsr + privileged architecture + Sv32
```

Still needed before trusting a Linux boot:

- broader ISA compliance tests
- exception priority and corner-case validation
- MMU permission/accessed/dirty behavior validation against Linux expectations
- atomics under real memory traffic
- final SBI ABI coverage, not only smoke tests
