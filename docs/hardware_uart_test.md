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

The device argument is optional. If omitted, the script tries the first `/dev/ttyUSB*`.

## Download and Run the Broad Probe

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

The XSCT script programs the bitstream, runs PS7 initialization, downloads the ARM-side probe ELF, and starts it.

This path runs the broad CPU/SoC smoke suite. It does not boot the real Linux kernel.

## Download and Run Linux

Build the Linux artifacts first:

```sh
./scripts/prepare_mainline_linux.sh
./scripts/build_mainline_rv32_linux.sh
./scripts/prepare_linux_boot_artifacts.sh
./scripts/build_ps_uart_probe.sh
```

Then run the Linux boot launcher:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl
```

This path starts `hw_bringup/build/ps_linux_boot.elf`, copies the Linux Image and DTB into DDR, loads the local M-mode SBI firmware into IMEM, and releases the PL CPU at the Linux entry.

## Expected Broad Probe PASS Sections

The probe prints one PASS/FAIL line per section. A currently healthy run should include:

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

> PL CPU DDR high random access smoke
ZYNQ_CPU DDR high access smoke: PASS

> PL CPU DDR high instruction fetch smoke
ZYNQ_CPU DDR high instruction fetch smoke: PASS

> PL CPU DDR high AMO smoke
ZYNQ_CPU DDR high AMO smoke: PASS

> PL CPU SBI firmware smoke
ZYNQ_CPU SBI firmware smoke: PASS

> PL CPU SBI timer smoke
ZYNQ_CPU SBI timer smoke: PASS

> PL CPU Linux boot contract smoke
ZYNQ_CPU Linux boot contract smoke: PASS

> PL CPU Linux SBI compatibility smoke
ZYNQ_CPU Linux SBI compatibility smoke: PASS

> PL CPU Linux image layout smoke
ZYNQ_CPU Linux image layout smoke: PASS
```

`Linux image layout smoke` may print `SKIP` if the Linux Image/DTB artifacts have not been prepared yet. Treat `PASS` as the expected result before a Linux boot run.

## Expected Linux Boot Signature

A currently healthy Linux boot run should include:

```text
> ZYNQ_CPU Linux boot launcher
Kernel CPU: 0x80400000
DTB CPU: 0x81600000
IMEM verify: 0 errors
Releasing PL CPU at Linux entry

Linux SBI console mirror
Saving 2048 bits of non-creditable seed for next boot
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Starting network: OK
Starting crond: OK

Welcome to Buildroot
buildroot login:
```

Useful timer sanity values in the final counter line:

```text
off_valid=1
cmp > mtime
time=<non-zero>
get=<non-zero>
```

## What the Late-Stage Tests Prove

- DDR random access smoke: PL CPU can load/store through the direct AXI DDR bridge.
- DDR instruction fetch smoke: reset vector can point at the DDR window and the PL CPU can execute instructions fetched from DDR.
- DDR high-address smokes: the direct bridge can reach the Linux-placement region used for the kernel and DTB, including AMO operations.
- SBI firmware smoke: M-mode firmware can enter an S-mode payload and handle an S-mode SBI call.
- SBI timer smoke: M-mode firmware can handle the SBI timer extension smoke path and return to S-mode after a timer interrupt.
- Linux boot contract smoke: M-mode firmware enters an S-mode payload with Linux-style `a0=hartid` and `a1=dtb`, the payload reads a DTB-like magic word from DDR, calls SBI base/timer services, and observes a delegated S-mode timer interrupt.
- Linux SBI compatibility smoke: the bring-up SBI behavior matches the pieces the real Linux boot path expects.
- Linux image layout smoke: the kernel Image header, DTB magic, and configured DDR placement match the launcher assumptions.
- Linux boot launcher: the real kernel reaches Buildroot userspace, starts the default services, and exposes a login prompt on `hvc0`.

These prove a minimal interactive real Linux boot path.

They do not yet prove production drivers, terminal performance, or a complete platform ABI.
