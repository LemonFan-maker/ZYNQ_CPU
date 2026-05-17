# Toolchain and Scripts

## AMD/Xilinx Environment

This project targets Vivado/Vitis 2025.2 through the local `vi25` shell
function.

Project automation should not call `vivado` or `xsct` directly. Use the wrapper
scripts so every command runs in the same environment:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/synth_zx32_soc.tcl
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

The wrappers start `zsh`, source `/home/orionisli/.zshrc`, call `vi25`, then
invoke the requested tool.

## Script Inventory

| Script | Purpose |
| --- | --- |
| `scripts/run_all_tests.sh` | run Python tool tests and all Icarus RTL tests |
| `scripts/run_iverilog_tests.sh` | run `core`, `irqctrl`, `scratchpad`, `soc`, or `all` Icarus tests |
| `scripts/run_zx32_toolchain_tests.sh` | run assembler and ELF unit tests |
| `scripts/build_zx32_programs.sh` | assemble bring-up programs, build ELF files, generate `zx32_programs.h` |
| `scripts/build_ps_uart_probe.sh` | build the ARM-side PS UART probe ELF |
| `scripts/run_vivado.sh` | Vivado 2025.2 wrapper |
| `scripts/run_xsct.sh` | XSCT 2025.2 wrapper |
| `scripts/serial_monitor.sh` | open `picocom` on a board serial port |

## Local Software Tools

| Tool | Purpose |
| --- | --- |
| `tools/zx32asm.py` | minimal ZX32/RV32 assembler for bring-up programs |
| `tools/zx32elf.py` | pack ZX32 assembly into minimal ELF images |
| `tools/bin2c.py` | convert ELF binaries into C arrays |
| `tools/test_zx32asm.py` | assembler unit tests |
| `tools/test_zx32elf.py` | ELF packer unit tests |

## Test Commands

Run everything that is practical without a board:

```sh
./scripts/run_all_tests.sh
```

Run one RTL simulation target:

```sh
./scripts/run_iverilog_tests.sh core
./scripts/run_iverilog_tests.sh irqctrl
./scripts/run_iverilog_tests.sh scratchpad
./scripts/run_iverilog_tests.sh soc
```

Run only Python toolchain tests:

```sh
./scripts/run_zx32_toolchain_tests.sh
```

Icarus currently prints warnings like:

```text
sorry: constant selects in always_* processes are not fully supported
```

These are tool limitations/warnings in the current simulations. The pass/fail
gate is still the script exit code and the testbench `PASS` lines.

## Build Commands

Generate bring-up program artifacts:

```sh
./scripts/build_zx32_programs.sh
```

Build the PS UART probe:

```sh
./scripts/build_ps_uart_probe.sh
```

Run RTL-only Vivado synthesis:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/synth_zx32_soc.tcl
```

Build the full hardware bring-up bitstream:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

## Board Run Commands

Terminal 1:

```sh
./scripts/serial_monitor.sh /dev/ttyUSB0 115200
```

Terminal 2:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

## Generated Outputs

Common generated outputs:

- `hw_bringup/build/generated/zx32_programs.h`
- `hw_bringup/build/elf/*.elf`
- `hw_bringup/build/ps_uart_probe.elf`
- `build/vivado_hw/`
- `build/vivado_synth/`

These are build artifacts, not source-of-truth files.
