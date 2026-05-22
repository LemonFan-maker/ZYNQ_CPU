# Linux Boot Layout

This is the current board-used layout for the real Linux boot launcher. It matches `hw_bringup/ps_uart_probe.h`, `hw_bringup/ps_linux_boot.c`, and `scripts/prepare_linux_boot_artifacts.sh`.

## Address Translation

Current direct DDR bridge mapping:

```text
PL CPU address = PS physical address - 0x0010_0000 + 0x8000_0000
PS physical    = PL CPU address - 0x8000_0000 + 0x0010_0000
```

Examples:

| PL CPU address | PS physical address |
| ---: | ---: |
| `0x8000_0000` | `0x0010_0000` |
| `0x8020_0000` | `0x0030_0000` |
| `0x8040_0000` | `0x0050_0000` |
| `0x8160_0000` | `0x0170_0000` |

## Current Image Placement

| Image or region | PL CPU address | PS physical address | Notes |
| --- | ---: | ---: | --- |
| M-mode firmware | `0x0000_0000` | PS writes through IMEM aperture | `linux_boot_firmware.zx32.s` |
| Linux kernel Image | `0x8040_0000` | `0x0050_0000` | RISC-V Image with text offset `0x0040_0000` |
| DTB | `0x8160_0000` | `0x0170_0000` | built from `linux/zynq_cpu.dts` |
| initramfs | embedded in Image | embedded in Image | generated from `build/linux-initramfs/initramfs.list` |
| SBI console/counter scratch | `0x2001_0000` | AXI-Lite TX scratch aperture | PS-visible mailbox and ring |
| MMIO timer | `0x1001_0000` | PL CPU MMIO | `mtime` and `mtimecmp` |

The older separate DTB/initramfs placeholders at `0x8200_0000` and `0x8240_0000` are not the current boot path. The initramfs is built into the kernel Image for now.

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
KERNEL_PS_ADDR=0x00500000
DTB_CPU_ADDR=0x81600000
DTB_PS_ADDR=0x01700000
```

## Entry Convention

The Linux entry convention is the standard RISC-V boot convention:

```text
a0 = 0
a1 = 0x81600000
satp = 0
privilege = S-mode
interrupts disabled on initial entry
```

The PS launcher writes:

| Scratch offset | Meaning |
| ---: | --- |
| `0x300` | Linux kernel entry address, currently `0x80400000` |
| `0x304` | DTB address, currently `0x81600000` |

The firmware reads these two words before entering S-mode.

## Scratch Mailbox

The firmware uses `mscratch = 0x2001_0000`. The same region is visible to the PS launcher as the TX scratch aperture. The current Linux boot monitor relies on these offsets:

| Offset | Meaning |
| ---: | --- |
| `0x000..0x0ff` | 256-byte SBI console ring data |
| `0x100` | SBI console ring head |
| `0x104` | SBI console total byte count |
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
