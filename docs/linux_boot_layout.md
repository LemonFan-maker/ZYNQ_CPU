# Linux Boot Layout

This layout is the starting point for loading Linux-related images from the PS
side into the PL CPU DDR window.

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
| `0x8200_0000` | `0x0210_0000` |
| `0x8240_0000` | `0x0250_0000` |

## Proposed Image Placement

| Image | PL CPU address | PS physical address | Notes |
| --- | ---: | ---: | --- |
| M-mode firmware | `0x0000_0000` | PS writes through IMEM aperture | current smoke-test path |
| S-mode payload | `0x8001_0000` | `0x0011_0000` | next non-Linux payload target |
| Linux kernel | `0x8040_0000` | `0x0050_0000` | RV32 Linux Image placement on a 4 MiB boundary |
| DTB | `0x8200_0000` | `0x0210_0000` | keep separate from the current 17 MiB kernel Image |
| initramfs | `0x8240_0000` | `0x0250_0000` | later BusyBox target |

The current `linux_contract` smoke test uses a smaller self-contained DDR
buffer allocated by the ARM-side probe. It validates the same register
convention but does not use the full layout above yet.

## Entry Convention

The intended S-mode entry convention is the standard RISC-V Linux convention:

```text
a0 = hartid
a1 = physical address of DTB as seen by the PL CPU
satp = 0
privilege = S-mode
interrupts disabled on initial entry
```

For the current smoke test:

```text
a0 = 0
a1 = fake DTB address inside the DDR test buffer
```

## Mailbox Diagnostics

Until Linux early console works, keep a PS-visible mailbox for firmware/payload
diagnostics. The current Linux contract smoke test writes to the TX scratch
mailbox region starting at offset `0x300`.

Key values:

| Offset | Meaning |
| ---: | --- |
| `0x300` | payload entry address |
| `0x304` | DTB address |
| `0x308` | last M-mode trap cause |
| `0x310` | last SBI extension ID |
| `0x314` | last SBI function ID |
| `0x31c` | last SBI return value |
| `0x328` | S-mode observed hartid |
| `0x32c` | S-mode observed DTB pointer |
| `0x330` | S-mode observed DTB magic |
| `0x334` | SBI base spec version |
| `0x338` | S-mode timer trap cause |
| `0x3f0` | final PASS/FAIL status |
