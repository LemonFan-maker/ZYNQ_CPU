# ZX32 ISA Notes

ZX32 is the current in-house CPU ISA layer. It stays close to RV32I so the
software and toolchain path remains practical, but it already exposes a small
custom extension set for bring-up and DataMover control.

## Base Direction

- RV32I core instructions are implemented first.
- Custom instructions use `OPCODE_CUSTOM0` (`0x0b`).
- The current custom op family is intentionally small and hardware-backed.

## Custom Instructions

| Mnemonic | Encoding | Purpose |
| --- | --- | --- |
| `xcpyw rd, rs1, rs2` | `funct3=000` | word copy / register move primitive |
| `xdm2s rd, rs1, rs2` | `funct3=001` | launch DataMover MM2S and wait |
| `xds2m rd, rs1, rs2` | `funct3=010` | launch DataMover S2MM and wait |

## Machine-Mode Foundation

The core now has the first privileged-architecture substrate needed before a
Linux-capable path:

- `Zicsr`-style CSR instructions: `csrrw/csrrs/csrrc` and immediate variants.
- `ecall`, `ebreak`, `mret`, `sret`, `fence`, and `fence.i`.
- RV32A word atomics: `lr.w`, `sc.w`, `amoadd.w`, `amoswap.w`, `amoxor.w`,
  `amoand.w`, `amoor.w`, `amomin.w`, `amomax.w`, `amominu.w`, `amomaxu.w`.
- RV32M multiply/divide: `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`,
  `rem`, and `remu`.
- Initial machine and supervisor CSRs: `mstatus`, `misa`, `medeleg`, `mideleg`,
  `mie`, `mtvec`, `mcounteren`, `sstatus`, `sie`, `stvec`, `scounteren`,
  `sscratch`, `sepc`, `scause`, `stval`, `sip`, `satp`, `mscratch`, `mepc`,
  `mcause`, `mtval`, `mip`, counter CSRs, and read-only ID CSRs.

## Counter CSRs

The core implements the RV32 counter CSR split:

| CSR | Purpose |
| --- | --- |
| `mcycle/mcycleh` | 64-bit machine cycle counter |
| `minstret/minstreth` | 64-bit retired-instruction counter |
| `cycle/cycleh` | user-visible alias of `mcycle` gated by `mcounteren/scounteren` |
| `time/timeh` | current internal timebase alias of `mcycle`, gated as `time` |
| `instret/instreth` | user-visible alias of `minstret`, gated by `mcounteren/scounteren` |
| `mcounteren` | M-mode counter exposure control for S/U |
| `scounteren` | S-mode counter exposure control for U |

`time` is intentionally backed by the internal cycle counter for this bring-up
stage. A Linux platform will eventually want this tied to a CLINT/SBI-compatible
mtime source or documented as a fixed-frequency CPU-local timebase.

This is still far from a Linux-capable core. Supervisor mode exists as a
scaffold, and the current core now includes Sv32 page walking, a small TLB,
`sfence.vma`, timer/external interrupt paths, atomics, and counter CSRs. A real
cache hierarchy and platform-grade interrupt/timer devices remain later Linux
milestones.

## Software Entry Points

- C-side encoding helpers: `hw_bringup/zx32_isa.h`
- Assembler: `tools/zx32asm.py`
- Encoding tests: `scripts/run_zx32asm_tests.sh`
- Bring-up assembly programs: `hw_bringup/programs/*.zx32.s`
- Generated PS-side program header: `hw_bringup/build/generated/zx32_programs.h`

## Bring-Up Program Build

The PS UART probe no longer embeds raw instruction constants for PL CPU test
programs. Rebuild the generated program header with:

```sh
scripts/build_zx32_programs.sh
```

`scripts/build_ps_uart_probe.sh` runs that step automatically before compiling
the ARM-side UART probe.

## Near-Term Direction

The next step after this assembler is a real object/ELF pipeline for bare-metal
programs, then compiler integration for inline custom ops. The Linux kernel
direction can stay RISC-V-compatible while the custom extension remains a local
project ABI.

## Entry Convention

- ELF `e_entry` is treated as the PL CPU reset vector by the PS loader.
- If a source file defines `_start`, that symbol becomes the default ELF entry.
- The CPU reset vector is exposed through the PL control block so software can
  set the next boot PC before releasing reset.
