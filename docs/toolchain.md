# Toolchain

## Vivado Version

This project targets Vivado 2025.2.

Before every Vivado command, including synthesis, run:

```sh
vi25
```

For scripts, use the repository wrapper:

```sh
scripts/run_vivado.sh -mode batch -source vivado/build.tcl
```

The wrapper starts a fresh `zsh` shell, sources `/home/orionisli/.zshrc` so the
`vi25` function is available, runs `vi25`, then invokes Vivado with the remaining
arguments. Do not call `vivado` directly from project automation.

RTL-only synthesis check:

```sh
scripts/run_vivado.sh -mode batch -source vivado/synth_zx32_soc.tcl
```

ZX32 assembly test and encoding check:

```sh
scripts/run_zx32asm_tests.sh
```

Full ZX32 toolchain smoke test, including ELF packing:

```sh
scripts/run_zx32_toolchain_tests.sh
```

Generate the PL CPU bring-up program header from `hw_bringup/programs/*.zx32.s`:

```sh
scripts/build_zx32_programs.sh
```

Generate minimal ELF images for the same ZX32 sources:

```sh
scripts/build_zx32_elfs.sh
```

The generated ELF blobs are also embedded into the PS bring-up header so the
probe can load them directly into PL IMEM.

The PS UART probe build runs this generation step automatically:

```sh
scripts/build_ps_uart_probe.sh
```

Current local definition:

- `vi25` is a shell function from `/home/orionisli/.zshrc`.
- Direct non-interactive `zsh -lc 'vi25'` does not see it unless `.zshrc` is
  sourced first.
