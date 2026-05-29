# ZX32 Simulator

This document describes the Python functional simulator under `tools/zx32sim/`.

The simulator is not a replacement for RTL or board verification. It is a fast software bring-up target for the CPU-visible contract: ISA behavior, traps, Sv32 translation, SBI firmware behavior, Linux boot, the scratch console bridge, and simple block-device experiments.

## What It Can Run

The current simulator can run the same Linux Image, DTB, and local M-mode SBI firmware used by the board boot path. The expected Linux milestone is:

```text
Saving 2048 bits of non-creditable seed for next boot
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Starting network: OK
Starting crond: OK
Welcome to Buildroot
buildroot login:
```

It can also bridge the simulated SBI/HVC console to the host terminal, so a normal login and shell session works:

```text
buildroot login: root
# uname -a
Linux buildroot 5.10.0+ #52 Thu May 28 14:42:18 CST 2026 riscv32 GNU/Linux
# hostname
buildroot
```

The simulator intentionally follows the board path for the core Linux boot:

- M-mode firmware starts in local IMEM at `0x00000000`.
- Linux `Image` is loaded at CPU address `0x80400000`.
- DTB is loaded at CPU address `0x81600000`.
- The firmware enters Linux in S-mode with `a0=0`, `a1=0x81600000`, and `satp=0`.
- Linux uses SBI console put/get and SBI TIME through the local firmware shim.

## Prerequisites

The Linux simulator runner expects the normal Linux artifacts to exist:

```text
hw_bringup/build/elf/linux_boot_firmware.elf
build/linux-mainline-rv32/arch/riscv/boot/Image
build/linux/zynq_cpu.dtb
```

Build them with the same flow used for board bring-up:

```sh
./scripts/build_zx32_busybox_rootfs.sh
./scripts/build_mainline_rv32_linux.sh
./scripts/prepare_linux_boot_artifacts.sh
./scripts/build_zx32_programs.sh
```

`scripts/run_zx32sim_linux_early.sh` will build `linux_boot_firmware.elf` from the assembly source if that ELF is missing, but it does not build the Linux Image or DTB for you.

## Quick Start

Run the Linux path until the Buildroot login prompt appears:

```sh
./scripts/run_zx32sim_linux_early.sh
```

The default non-interactive stop condition is `buildroot login:`. When that text appears in the simulated console stream, the runner exits and dumps the scratch diagnostic words and recent console text.

Run a live interactive console:

```sh
ZX32SIM_INTERACTIVE=1 ./scripts/run_zx32sim_linux_early.sh
```

When the login prompt appears, type:

```text
root
```

The default root password is empty. Exit the simulator with `Ctrl-C` when you are done. In interactive mode the default max-step budget is deliberately large so the simulator does not stop immediately after reaching the prompt.

## Scripted Console Sessions

For repeatable tests, use the expect/send console script mechanism. Each non-empty line is:

```text
TRIGGER<TAB>TEXT_TO_SEND
```

The send side accepts common escapes such as `\n`, `\r`, `\t`, `\\`, and hex bytes written as `\xNN`.

Example:

```sh
printf 'buildroot login:\troot\\n\n# \tuname -a\\nhostname\\necho ZX32SIM_DONE\\n\n' \
  > /tmp/zx32sim-console-script

ZX32SIM_CONSOLE_SCRIPT=/tmp/zx32sim-console-script \
ZX32SIM_STOP_CONSOLE=ZX32SIM_DONE \
ZX32SIM_LINUX_STEPS=600000000 \
./scripts/run_zx32sim_linux_early.sh
```

Expected output includes:

```text
buildroot login: root
# uname -a
Linux buildroot 5.10.0+ #52 Thu May 28 14:42:18 CST 2026 riscv32 GNU/Linux
# hostname
buildroot
# echo ZX32SIM_DONE
ZX32SIM_DONE
```

Do not preload login text too early with `ZX32SIM_CONSOLE_INPUT` when testing a login shell. The HVC layer may consume and echo those bytes before `getty` is ready. Prefer `ZX32SIM_CONSOLE_SCRIPT` for login and shell workflows.

## Runner Environment Variables

`scripts/run_zx32sim_linux_early.sh` is the normal entry point. It maps these environment variables to simulator CLI flags:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ZX32SIM_INTERACTIVE` | `0` | Set to non-zero for live stdin/stdout console bridging. |
| `ZX32SIM_LINUX_STEPS` | `150000000` non-interactive, `1000000000000` interactive | Max simulator steps. |
| `ZX32SIM_STOP_CONSOLE` | `buildroot login:` non-interactive, empty interactive | Stop when console text contains this string. |
| `ZX32SIM_STOP_CHECK_INTERVAL` | `1000000` | Step interval between stop/console checks. Larger values let WFI fast-forward work better. |
| `ZX32SIM_LINUX_CHECKPOINT_INTERVAL` | unset | Print periodic PC/CSR/checkpoint words. |
| `ZX32SIM_CONSOLE_INPUT` | empty | Preload raw console input bytes at start. |
| `ZX32SIM_CONSOLE_INPUT_FILE` | empty | Preload console input bytes from a file. |
| `ZX32SIM_CONSOLE_SCRIPT` | empty | Expect/send console script file. |
| `ZX32SIM_VIRTIO_BLOCK_IMAGE` | empty | Attach a virtio-mmio block image and switch to the simulator DTB. |
| `ZX32SIM_EXTRA_ARGS` | empty | Append raw `tools.zx32sim.main` CLI arguments. |

## Console Model

The board and simulator use the same scratch-backed SBI console contract. 

Firmware sets `mscratch = 0x20010000` and uses these offsets:

| Offset | Size | Direction | Meaning |
| ---: | ---: | --- | --- |
| `0x000..0x0ff` | 256 bytes | guest to host | SBI console output ring data |
| `0x100` | word | host to guest | output ring drain/head counter |
| `0x104` | word | guest to host | output ring total byte counter |
| `0x108` | word | host to guest | legacy single-byte input value |
| `0x10c` | word | host to guest | legacy single-byte input valid flag |
| `0x110..0x18f` | 128 bytes | host to guest | SBI console input ring data |
| `0x190` | word | guest to host | input ring read counter |
| `0x194` | word | host to guest | input ring write counter |

The board PS launcher drains the output ring and prints it on the PS UART. The simulator does the same when any console feature is active. 

This is important: if the host does not advance the output ring head, the firmware will eventually block in `console_wait_space` after 256 pending bytes.

Interactive input and scripted input both write to the 128-byte input ring, so Linux sees the same SBI console getchar path as it sees on the board.

## Block Devices

The simulator has two block-device paths:

- `--block-image FILE`: a simple ZX32-specific MMIO block device at `0x10050000`, useful for firmware/device-model smokes.
- `--virtio-block-image FILE`: a virtio-mmio block device at `0x10060000`, with a simulator PLIC at `0x0c000000` and IRQ source 1.

The Linux runner exposes the virtio path:

```sh
truncate -s 16M /tmp/zx32sim-sd.img

ZX32SIM_VIRTIO_BLOCK_IMAGE=/tmp/zx32sim-sd.img \
./scripts/run_zx32sim_linux_early.sh
```

When `ZX32SIM_VIRTIO_BLOCK_IMAGE` is set, the runner uses `build/linux/zx32sim_virtio.dtb`, which is generated from `linux/zx32sim_virtio.dts` by `scripts/prepare_linux_boot_artifacts.sh`.

The board DTB does not expose these simulator-only virtio devices.

## Performance Notes

The simulator is a Python functional model. It is intended for correctness, bring-up, and software workflow debugging, not cycle accuracy.

Important performance behavior:

- Instruction decode is cached by instruction word.
- Sv32 translations use small software TLBs.
- In `--continue-on-wfi` mode, WFI can fast-forward simulator time to the next local timer deadline when no external interrupt is pending.
- Console stop checks and expect/send scripts run at `ZX32SIM_STOP_CHECK_INTERVAL`. Too small a value can make Linux idle runs much slower because it prevents larger WFI fast-forward chunks.

The default non-interactive Linux run reaches `buildroot login:` in about 109 million simulator steps with the current kernel/rootfs. That number is not a stable ABI; it changes when kernel config, init scripts, timebase, or runner checks change.

## Direct CLI Use

Most users should use `scripts/run_zx32sim_linux_early.sh`. For lower-level bring-up, the raw CLI is:

```sh
python3 -m tools.zx32sim.main IMAGE.elf [options]
```

Useful raw options include:

| Option | Meaning |
| --- | --- |
| `--load-elf FILE` | Load an additional ELF image. |
| `--load-raw ADDR=FILE` | Load a raw blob at a CPU address. |
| `--poke-word ADDR=VALUE` | Initialize a 32-bit memory word. |
| `--expect-word ADDR=VALUE` | Fail if a word does not match at the end. |
| `--stop-pc ADDR` | Stop when PC reaches an address. |
| `--stop-word ADDR=VALUE` | Stop when a word matches. |
| `--stop-console TEXT` | Stop when drained console text contains TEXT. |
| `--interactive-console` | Bridge host stdin/stdout to the scratch console. |
| `--console-input TEXT` | Preload console input bytes. |
| `--console-input-file FILE` | Preload console input from a file. |
| `--console-send-after TRIGGER=TEXT` | Send text after seeing console text. |
| `--console-script FILE` | Load expect/send entries from a script file. |
| `--dump-console-ring` | Dump the decoded scratch console ring at exit. |
| `--continue-on-wfi` | Treat WFI as idle instead of stopping. |
| `--symbols System.map` | Annotate PCs in checkpoints and final stop output. |

## Regression Commands

Run simulator unit tests:

```sh
PYTHONPATH=tools python3 tools/test_zx32sim.py
```

Run assembler/ELF/simulator unit tests through the project wrapper:

```sh
./scripts/run_zx32_toolchain_tests.sh
```

Run simulator smoke tests for firmware handoff, SBI, Linux boot contracts, and block devices:

```sh
./scripts/run_zx32sim_smokes.sh
```

Run the full boardless regression set:

```sh
./scripts/run_all_tests.sh
```

## Limitations

- It is not cycle accurate and does not model RTL state-machine timing.
- It does not model caches because the RTL currently has no cache hierarchy.
- The virtio block/Plic path is simulator-only and not part of the current board platform ABI.
- Real-time terminal behavior depends on host terminal buffering. Scripted console sessions are better for repeatable tests.
- The default Linux DTB still exposes only about 24 MiB starting at `0x80000000`; after kernel and initramfs reservations, BusyBox sees only a few MiB of free memory. That matches the current bring-up layout rather than a full DDR-sized machine model.
