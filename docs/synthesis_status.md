# Synthesis and Implementation Status

This file records the last known-good synthesis/implementation state. Re-run the
commands after RTL or Vivado block-design changes.

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
| Slice LUTs | 5999 | 53200 | 11.28% |
| Slice Registers | 2498 | 106400 | 2.35% |
| Block RAM Tile | 4 | 140 | 2.86% |
| DSPs | 12 | 220 | 5.45% |

The standalone RTL synthesis script does not provide full board timing context,
so use it as a synthesizability/resource check rather than final timing signoff.

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

Timing snapshot:

| Metric | Value |
| --- | ---: |
| Setup WNS | 0.358 ns |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| Hold WHS | 0.051 ns |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 |

Resource snapshot:

| Resource | Used | Device | Percent |
| --- | ---: | ---: | ---: |
| Slice LUTs | 8013 | 53200 | 15.06% |
| Slice Registers | 5282 | 106400 | 4.96% |
| Block RAM Tile | 5.5 | 140 | 3.93% |
| DSPs | 12 | 220 | 5.45% |

## Timing Notes

The current timing closure depends on keeping memory request address/data paths
registered inside the core and SoC. In particular:

- AMO load data is registered before AMO result calculation.
- data-memory addresses are registered before memory states drive the SoC bus.
- the direct DDR bridge is single-beat and serialized, which keeps the early
  timing surface small.

## Memory Implementation Notes

- Boot/local RAM infers block RAM.
- Current scratchpad storage is intentionally small.
- Before increasing scratchpad size, prefer a block-RAM-oriented implementation
  or explicit XPM/Block Memory Generator RAMs.

## When to Rebuild

Run the hardware bring-up build after changes to:

- `rtl/`
- `vivado/build_hw_bringup.tcl`
- block-design wrapper files
- AXI interface widths or memory maps

For PS probe C-only changes, `./scripts/build_ps_uart_probe.sh` is enough.
