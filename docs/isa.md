# ISA Notes

The project carries two core families. **ZX32** is the local name for the RV32-class core and its small custom bring-up extension set (the rest of this document's RV32 sections). **ZX64** is the RV64GC family under `rtl/core64/` described in [ZX64 ISA](#zx64-rv64-isa). Both remain RISC-V compatible enough to reuse upstream software.

## ZX32 ISA Substrate

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

## ZX64 RV64 ISA

`rtl/core64/zx64_core5.sv` (5-stage, primary) and `rtl/core64/zx64_core.sv` (single-cycle, reference) implement:

```text
rv64gc_zicsr_zifencei   (misa 0x8000_0000_0004_112d with ENABLE_FPU)
rv64imac_zicsr_zifencei (misa 0x8000_0000_0004_1105 with ENABLE_FPU=0)
```

- full 64-bit integer path: LD/SD doubleword loads/stores, `addiw`, shifted immw ops, 64-bit branches/jumps
- RV64M through the shared `zx64_muldiv_unit` (`mulh/mulhsu/mulhu/div/divu/rem/remu` doubleword forms)
- RV64A atomics including doubleword `lr.d/sc.d` and `amo*.d` with reservation tracking
- RV64F/RV64D when `ENABLE_FPU=1`: `fregfile64`, `fflags/frm/fcsr`, FP load/store, arithmetic, convert/compare/move — gated by `mstatus.FS`
- M/S/U privilege, medeleg/mideleg routing, native 64-bit `time`/`cycle`/`instret` counters (RV64 has no split `*h` CSRs)
- **Sv39** page translation (`satp.MODE = 8`), honoring `mstatus.SUM/MXR`; `MPRV` is not implemented

There are no ZX32 custom opcodes in the core64 family; the bring-up DataMover instructions remain RV32-only.

Validation: `tb/tb_zx64_core.sv`, `tb/tb_zx64_core_compressed.sv`, `tb/tb_zx64_core5.sv` (ISA, C-extension, pipeline hazard/forwarding smokes), plus the SoC-level SBI/Sv39/Linux-handoff testbenches listed in `docs/toolchain.md`. No formal RISC-V compliance run exists yet for either family.
