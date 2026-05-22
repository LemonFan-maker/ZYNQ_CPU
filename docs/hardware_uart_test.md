# Hardware UART Bring-Up

This is the current board-level bring-up path for the ZYNQ_CPU hardware design.

## Build Hardware

```sh
./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Main outputs:

- `build/vivado_hw/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit`
- `build/vivado_hw/zynq_cpu_system_wrapper.xsa`

## Build Probe Software

```sh
./scripts/build_ps_uart_probe.sh
```

This compiles the ARM-side standalone probe at:

```text
hw_bringup/build/ps_uart_probe.elf
```

It also runs:

```sh
./scripts/build_zx32_programs.sh
```

That generator builds ELF images from `hw_bringup/programs/*.zx32.s` and emits:

```text
hw_bringup/build/generated/zx32_programs.h
```

The probe source is split by responsibility:

| File | Responsibility |
| --- | --- |
| `ps_uart_probe.c` | main test sequence |
| `ps_uart_probe.h` | shared registers, constants, and declarations |
| `ps_uart_probe_common.c` | ELF loader, wait helpers, shared buffers |
| `ps_uart_probe_dma.c` | DataMover tests |
| `ps_uart_probe_cpu.c` | CPU, DDR, S-mode, boot, and counter tests |
| `ps_uart_probe_sbi.c` | SBI firmware and timer tests |

## Open Serial

```sh
./scripts/serial_monitor.sh /dev/ttyUSB0 115200
```

The device argument is optional. If omitted, the script tries the first
`/dev/ttyUSB*` or `/dev/ttyACM*`.

## Download and Run

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

The XSCT script programs the bitstream, runs PS7 initialization, downloads the
ARM-side probe ELF, and starts it.

## Expected PASS Sections

The probe prints one PASS/FAIL line per section. A currently healthy run should
include:

```text
> ZYNQ_CPU PL bring-up probe
ZYNQ_CPU AXI-Lite probe: PASS

> DataMover HP0 loopback
ZYNQ_CPU DataMover loopback: PASS

> PL CPU initiated DataMover loopback
ZYNQ_CPU PL CPU DataMover: PASS

> PS-loaded PL CPU program
ZYNQ_CPU BRAM load/run: PASS

> PL CPU ELF load/run
ZYNQ_CPU ELF load/run: PASS

> PL CPU entry smoke
ZYNQ_CPU entry smoke: PASS

> PL CPU trap smoke
ZYNQ_CPU trap smoke: PASS

> PL CPU supervisor smoke
ZYNQ_CPU supervisor smoke: PASS

> PL CPU supervisor timer smoke
ZYNQ_CPU supervisor timer smoke: PASS

> PL CPU boot payload smoke
ZYNQ_CPU boot payload smoke: PASS

> PL CPU supervisor counter smoke
ZYNQ_CPU supervisor counter smoke: PASS

> PL custom DataMover instructions
ZYNQ_CPU custom DataMover: PASS

> PL CPU DDR random access smoke
ZYNQ_CPU DDR access smoke: PASS

> PL CPU DDR instruction fetch smoke
ZYNQ_CPU DDR instruction fetch smoke: PASS

> PL CPU SBI firmware smoke
ZYNQ_CPU SBI firmware smoke: PASS

> PL CPU SBI timer smoke
ZYNQ_CPU SBI timer smoke: PASS
```

The probe now also includes the first Linux-facing contract test. This section
is compile-verified, but still needs a board UART run before it should be
treated as board-proven:

```text
> PL CPU Linux boot contract smoke
ZYNQ_CPU Linux boot contract smoke: PASS
```

## What the Late-Stage Tests Prove

- DDR random access smoke: PL CPU can load/store through the direct AXI DDR
  bridge.
- DDR instruction fetch smoke: reset vector can point at the DDR window and the
  PL CPU can execute instructions fetched from DDR.
- SBI firmware smoke: M-mode firmware can enter an S-mode payload and handle an
  S-mode SBI call.
- SBI timer smoke: M-mode firmware can handle the SBI timer extension smoke path
  and return to S-mode after a timer interrupt.
- Linux boot contract smoke, once board-confirmed: M-mode firmware enters an
  S-mode payload with Linux-style `a0=hartid` and `a1=dtb`, the payload reads a
  DTB-like magic word from DDR, calls SBI base/timer services, and observes a
  delegated S-mode timer interrupt.

These are necessary Linux stepping stones, but they do not yet prove that a real
Linux kernel will boot.
