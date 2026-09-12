# Synthesis and Implementation Status

This file records the last known-good synthesis/implementation state. Re-run the commands after RTL or Vivado block-design changes.

## RTL-Only Synthesis

Command:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/synth_zx32_soc.tcl
```

Last recorded result:

- Vivado version: 2025.2 through `vi25`
- Top: `zx32_soc`
- Part: `xc7z020clg400-2`
- Errors: 0
- Critical warnings: 0

Resource snapshot:

| Resource | Used | Device | Percent |
| --- | ---: | ---: | ---: |
| Slice LUTs | 30133 | 53200 | 56.64% |
| Slice Registers | 18211 | 106400 | 17.12% |
| Block RAM Tile | 4 | 140 | 2.86% |
| DSPs | 10 | 220 | 4.55% |

The standalone RTL synthesis script does not provide full board timing context, so use it as a synthesizability/resource check rather than final timing signoff.

## Hardware Bring-Up Build

Command:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Last recorded result:

- Vivado version: 2025.2 through `vi25`
- Top: `zynq_cpu_system_wrapper`
- Part: `xc7z020clg400-2`
- FCLK0: 75.002 MHz
- Errors: 0
- Critical warnings: 0
- Bitstream: `build/vivado_hw/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit`
- XSA: `build/vivado_hw/zynq_cpu_system_wrapper.xsa`
- Recorded after the D-cache stream prefetch and core reset timing update.

Timing snapshot:

| Metric | Value |
| --- | ---: |
| Setup WNS | 0.017 ns |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| Hold WHS | 0.043 ns |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 |

Worst setup path in this build:

- source: `req_is_fetch_reg`
- destination: `ptw_l1_pte_reg[30]`
- data path delay: 12.994 ns
- logic levels: 17
- routing share: about 74%

The margin is small. Treat the build as timing-clean but close to the 75 MHz limit.

Resource snapshot:

| Resource | Used | Device | Percent |
| --- | ---: | ---: | ---: |
| Slice LUTs | 29085 | 53200 | 54.67% |
| Slice Registers | 21259 | 106400 | 19.98% |
| Block RAM Tile | 5.5 | 140 | 3.93% |
| DSPs | 10 | 220 | 4.55% |

## Timing Notes

The current timing closure depends on keeping memory request address/data paths registered inside the core and SoC. In particular:

- AMO load data is registered before AMO result calculation.
- data-memory addresses are registered before memory states drive the SoC bus.
- the direct DDR bridge/front end is serialized, which keeps the early timing surface small.
- the core asynchronous reset path does not load the variable `reset_vector` directly into `pc`; reset enters `ST_RESET`, and the reset vector is loaded synchronously from that state. This avoids a variable asynchronous reset load on the PC flops.
- D-cache prefetch must not steal demand-response completion. Demand `imem_ready`/`bus_ready` are gated while a prefetch line is in flight, and refill data is only written to the prefetch target when no demand I-cache/D-cache refill is active.

## Memory Implementation Notes

- Boot/local RAM infers block RAM.
- Current scratchpad storage is intentionally small.
- Before increasing scratchpad size, prefer a block-RAM-oriented implementation or explicit XPM/Block Memory Generator RAMs.

## When to Rebuild

Run the hardware bring-up build after changes to:

- `rtl/`
- `vivado/build_hw_bringup.tcl`
- block-design wrapper files
- AXI interface widths or memory maps

For PS probe C-only changes, `./scripts/build_ps_uart_probe.sh` is enough.

## RV64 (ZX64) Hardware Bring-Up Build

Command:

```sh
ZYNQ_CPU_SOC=rv64 ZYNQ_CPU_VIVADO_BUILD_DIR=build/vivado_hw_rv64 \
  ./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Last fully-implemented result (2026-07-07, `ZYNQ_CPU_RV64_ENABLE_FPU=0`, recorded in `build/vivado_hw_rv64/reports/`):

- Top: `zynq_cpu_system_wrapper`, part `xc7z020clg400-2`, FCLK0 75.002 MHz
- Errors: 0; XSA: `build/vivado_hw_rv64/zynq_cpu_system_wrapper.xsa`
- No `.bit` was retained in that build directory; re-run the command above to regenerate it

Timing snapshot (post-implementation):

| Metric | Value |
| --- | ---: |
| Setup WNS | 0.019 ns |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| Hold WHS | 0.038 ns |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 |

Resource snapshot (`ENABLE_FPU=0`, i.e. RV64IMAC_Zicsr_Zifencei):

| Resource | Used | Device | Percent |
| --- | ---: | ---: | ---: |
| Slice LUTs | 16135 | 53200 | 30.33% |
| Slice Registers | 7786 | 106400 | 7.32% |
| Block RAM Tile | 14.5 | 140 | 10.36% |
| DSPs | 0 | 220 | 0.00% |

### FPU Resource Blocker

`vivado/build_hw_bringup.tcl` defaults `rv64_enable_fpu` to 1, and `scripts/check_zx64_linux_boot_chain.sh` requires MISA to advertise F+D (the `zx64.dts`/kernel `CONFIG_FPU=y` contract is RV64GC). However, a full-FPU `zx64_core5` implementation needs ~77.5k LUT-as-logic and fails DRC UTLZ-1 on `xc7z020clg400-2` (53.2k sites): the 2026-07-07 04:40 attempt with `ENABLE_FPU=1` never placed.

This is an open contradiction between the software contract (RV64GC) and the FPGA part (FPU-less fits, FPU-full does not). Options, not yet decided:

- move the FPU datapath to DSP48/multi-cycle microcode to shrink LUT usage,
- build an `rv64imac` kernel fragment (`CONFIG_FPU=n`, DTB `riscv,isa` without fd) for this board, accepting the boot-chain check must then be relaxed,
- target a larger part.

Until this is resolved, treat the `ENABLE_FPU=0` build above as the only board-sizable RV64 bitstream, and note that its MISA (`...1105`) does not match the current `rv64gc` DTB string that `check_zx64_linux_boot_chain.sh` enforces.
