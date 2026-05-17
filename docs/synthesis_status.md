# Synthesis Status

## Current RTL-Only Check

Command:

```sh
scripts/run_vivado.sh -mode batch -source vivado/synth_zx32_soc.tcl
```

Current result:

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

## Notes

The boot BRAM is inferred as block RAM. The current RX/TX scratchpad memories
are intentionally small and infer as distributed RAM. Replace them with XPM or
Block Memory Generator RAMs before increasing the scratchpad size.

The standalone RTL synthesis script still has no XDC timing constraints, so the
timing summary reports `NA` for WNS/TNS. The block-design/bitstream build needs
board clocks and generated constraints before timing closure is meaningful.

## Current Hardware Bitstream Build

Command:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Current result:

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

The current timing closure depends on keeping memory request address/data paths
registered inside the core. In particular, AMO load data is now registered before
AMO result calculation, and data-memory addresses are registered before memory
states drive the SoC bus.
