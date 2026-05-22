# Linux Bring-Up

This document describes the Linux bring-up contract for ZYNQ_CPU. It is not a
finished Linux port yet.

The immediate goal is to move from board-level smoke tests to a reproducible
boot contract:

```text
M-mode firmware
  -> S-mode payload or Linux kernel in DDR
  -> a0 = hartid
  -> a1 = DTB address
  -> SBI calls for base/timer services
```

## Current Hardware Contract

The new smoke test is compiled into the PS UART probe and is ready for board
confirmation. When it passes on the PL CPU path, it proves:

- S-mode payload entry with `a0=0`, `a1=<dtb cpu address>`
- S-mode payload can read a DTB-like magic word from DDR
- SBI base `get_spec_version` smoke call returns `0x00000002`
- SBI timer extension smoke call programs the MMIO timer
- delegated S-mode timer interrupt reaches the S-mode trap handler
- pass/fail is reported through the PS-visible mailbox

The expected board output is:

```text
> PL CPU Linux boot contract smoke
ZYNQ_CPU Linux boot contract smoke: PASS
```

Source files:

- `hw_bringup/programs/linux_contract_firmware_smoke.zx32.s`
- `hw_bringup/programs/linux_contract_payload_smoke.zx32.s`
- `hw_bringup/ps_uart_probe_sbi.c`

## Files

| File | Purpose |
| --- | --- |
| `docs/linux_boot_layout.md` | DDR placement for firmware, kernel, DTB, and initramfs |
| `linux/zynq_cpu.dts` | DTB source for the current custom platform |

## Next Development Step

Replace the hand-written Linux contract payload with progressively larger
payloads before attempting a real kernel:

1. S-mode payload that parses the DTB header and selected nodes.
2. S-mode payload that calls a few SBI base functions.
3. S-mode payload that exercises repeated timer events.
4. Minimal riscv32 Linux kernel entry.
5. initramfs shell.

Keep the PS UART probe mailbox path until Linux early console is reliable.
