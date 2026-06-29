# Linux Boot Layout

This is the current board-used layout for the real Linux boot launcher. It matches `hw_bringup/ps_uart_probe.h`, `hw_bringup/ps_linux_boot.c`, and `scripts/prepare_linux_boot_artifacts.sh`.

## Address Translation

Current direct DDR bridge mapping:

```text
PL CPU address = PS physical address + 0x8000_0000
PS physical    = PL CPU address - 0x8000_0000
```

Examples:

| PL CPU address | PS physical address |
| ---: | ---: |
| `0x8000_0000` | `0x0000_0000` |
| `0x8020_0000` | `0x0020_0000` |
| `0x8040_0000` | `0x0040_0000` |
| `0x8200_0000` | `0x0200_0000` |

## Current Image Placement

| Image or region | PL CPU address | PS physical address | Notes |
| --- | ---: | ---: | --- |
| M-mode firmware | `0x0000_0000` | PS writes through IMEM aperture | `linux_boot_firmware.zx32.s` |
| Linux kernel Image | `0x8040_0000` | `0x0040_0000` | RISC-V Image with text offset `0x0040_0000` |
| DTB | `0x8200_0000` | `0x0200_0000` | built from `linux/zynq_cpu.dts` |
| GPU framebuffer reserve | `0xbc00_0000` | `0x3c00_0000` | 64 MiB `no-map` VRAM |
| boot artifact backup | `0x8410_0000` | `0x0410_0000` | 19 MiB `no-map` PS launcher backup |
| initramfs | embedded in Image | embedded in Image | Buildroot `build/buildroot-zx32/images/rootfs.cpio` |
| SBI console/counter scratch | `0x2001_0000` | AXI-Lite TX scratch aperture | PS-visible mailbox and ring |
| MMIO timer | `0x1001_0000` | PL CPU MMIO | `mtime` and `mtimecmp` |

The older separate initramfs placeholder at `0x8240_0000` is not the current boot path. The initramfs is built into the kernel Image for now.

## Loader Validation

`scripts/prepare_linux_boot_artifacts.sh` validates the boot artifacts before a board run:

- Linux Image exists at `build/linux-mainline-rv32/arch/riscv/boot/Image`.
- Image text offset is `0x0040_0000`.
- RISC-V Image magic matches the expected header bytes.
- DTB magic is `0xd00dfeed`.
- the Image does not overlap the DTB placement.

It writes `build/linux/boot_artifacts.env` with the active addresses:

```text
KERNEL_CPU_ADDR=0x80400000
KERNEL_PS_ADDR=0x00400000
DTB_CPU_ADDR=0x82000000
DTB_PS_ADDR=0x02000000
```

## Entry Convention

The Linux entry convention is the standard RISC-V boot convention:

```text
a0 = 0
a1 = 0x82000000
satp = 0
privilege = S-mode
interrupts disabled on initial entry
```

The PS launcher writes:

| Scratch offset | Meaning |
| ---: | --- |
| `0x300` | Linux kernel entry address, currently `0x80400000` |
| `0x304` | DTB address, currently `0x82000000` |

The firmware reads these two words before entering S-mode.

## Scratch Mailbox

The firmware uses `mscratch = 0x2001_0000`. The same region is visible to the PS launcher as the TX scratch aperture. The current Linux boot monitor relies on these offsets:

| Offset | Meaning |
| ---: | --- |
| `0x000..0x0ff` | 256-byte SBI console ring data |
| `0x100` | SBI console ring head |
| `0x104` | SBI console total byte count |
| `0x108` | legacy SBI console input byte |
| `0x10c` | legacy SBI console input valid flag |
| `0x110..0x18f` | 128-byte SBI console input ring data |
| `0x190` | SBI console input ring read counter |
| `0x194` | SBI console input ring write counter |
| `0x200` | SBI ecall count |
| `0x204` | SBI TIME count |
| `0x208` | SBI base count |
| `0x20c` | SBI console put count |
| `0x210` | SBI console get count |
| `0x214` | debug marker count |
| `0x218` | unsupported SBI count |
| `0x21c` | M-mode trap count |
| `0x220` | last console character |
| `0x224` | last TIME SBI `mepc` |
| `0x228` | last console SBI `mepc` |
| `0x22c` | timer offset valid flag |
| `0x230` | timer offset low word |
| `0x234` | timer offset high word |
| `0x238` | last MMIO `mtime` low word |
| `0x23c` | last MMIO `mtime` high word |
| `0x240` | Linux head debug marker |
| `0x244` | Linux head observed `a0` |
| `0x248` | Linux head observed `a1` |
| `0x24c` | Linux head AMO old value |
| `0x250` | Linux BSS low address |
| `0x254` | Linux BSS high address |
| `0x300` | firmware entry target |
| `0x304` | firmware DTB argument |
| `0x308` | last M-mode trap cause |
| `0x30c` | last M-mode trap PC |
| `0x310` | last SBI extension ID |
| `0x314` | last SBI function ID |
| `0x318` | last SBI argument 0 |
| `0x31c` | last SBI error return |
| `0x320` | last programmed `mtimecmp` low word |
| `0x324` | last programmed `mtimecmp` high word |
| `0x328` | payload-observed hart ID |
| `0x32c` | payload-observed DTB pointer |
| `0x330` | payload-observed DTB magic |
| `0x334` | SBI base spec version |
| `0x338` | payload trap cause |
| `0x33c` | payload trap PC |

Some offsets above are used by older Linux contract/image-layout smokes as well as the real Linux boot path. Keep this table synchronized with `hw_bringup/ps_uart_probe.h` when adding diagnostics.

The console output ring is a producer/consumer ring, not a log buffer that can be ignored forever. Firmware checks `total - head < 256` before writing the next console byte. 

The board PS launcher and the simulator both must advance the head counter after draining bytes; otherwise Linux output eventually stalls in the firmware `console_wait_space` loop.

The input ring mirrors the board PS UART path. The host writes bytes into `0x110..0x18f` and advances the write counter at `0x194`; SBI console getchar consumes bytes and advances `0x190`. The legacy single-byte mailbox at `0x108/0x10c` remains a fallback path, but normal Linux `hvc0` interaction uses the ring.

The simulator uses this exact scratch contract for live and scripted console input. See `docs/simulator.md` for command examples.

## Timer Register Layout

PL CPU MMIO timer base: `0x1001_0000`.

| Offset | Register |
| ---: | --- |
| `0x00` | `mtime[31:0]` |
| `0x04` | `mtime[63:32]` |
| `0x08` | `mtimecmp[31:0]` |
| `0x0c` | `mtimecmp[63:32]` |
| `0x10` | timer IRQ status |

Linux requests timer events in the CSR `time/timeh` domain. The firmware maps those requests to MMIO `mtimecmp` by storing the observed `mtime - rdtime` offset and by enforcing a minimum future compare window.
