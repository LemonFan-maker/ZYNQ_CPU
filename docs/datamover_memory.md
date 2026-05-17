# DataMover Memory Plan

The DDR path is based on AXI DataMover rather than a custom PL DDR controller.

```text
zx32 CPU
  -> native MMIO store/load
  -> datamover_ctrl
  -> AXI DataMover command/status streams
  -> AXI DataMover M_AXI MM2S/S2MM
  -> Zynq PS S_AXI_HP
  -> PS DDR controller
  -> MT41K256M16RE-125 DDR3
```

## Important Boundary

AXI DataMover is a DMA/block-transfer engine. It does not behave like a normal
CPU memory port for arbitrary single-cycle instruction fetches or load/store
operations.

The first usable memory model is therefore:

- CPU executes from local BRAM.
- CPU configures `datamover_ctrl` over MMIO.
- DataMover copies DDR blocks into a local stream/BRAM endpoint.
- DataMover copies local stream/BRAM blocks back to DDR.

For a Linux-capable system, this implies one of two later designs:

- Keep DataMover as the DDR transport and build a local cache/page-refill engine
  around it.
- Add a direct AXI load/store master later and keep DataMover for bulk DMA.

## MMIO Register Map

Base address: `0x1002_0000`

| Offset | Register | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | control | W | bit 0 starts MM2S, bit 1 starts S2MM |
| `0x04` | status | R/W1C | busy/done/error/channel-ready flags |
| `0x08` | ddr_addr | R/W | DDR byte address |
| `0x0c` | local_addr | R/W | reserved for local BRAM/stream endpoint |
| `0x10` | length | R/W | bytes to transfer |
| `0x14` | tag | R/W | 4-bit DataMover command tag |
| `0x18` | mm2s_status_raw | R | last MM2S status byte |
| `0x1c` | s2mm_status_raw | R | last S2MM status byte |

## Local Scratchpad Map

The current local endpoint is split into two memories so the RTL stays easy to
synthesize:

| Region | Base | Direction | Owner |
| --- | ---: | --- | --- |
| RX scratch | `0x2000_0000` | DDR to local | DataMover MM2S writes, CPU reads |
| TX scratch | `0x2001_0000` | local to DDR | CPU writes, DataMover S2MM reads |

Default size is currently 256 32-bit words per direction. This is intentionally
small for early bring-up. The final design should replace these inferred
scratch memories with XPM or Block Memory Generator RAMs before increasing the
buffer size.

## DataMover Command

The controller currently emits the default 72-bit DataMover command form for a
32-bit address configuration:

- bits `[22:0]`: bytes to transfer
- bit `[23]`: burst type, set to INCR
- bits `[29:24]`: DSA, currently zero
- bit `[30]`: EOF, set
- bit `[31]`: DRR, set for S2MM and clear for MM2S
- bits `[63:32]`: DDR address
- bits `[67:64]`: tag
- bits `[71:68]`: zero

This command layout is isolated inside `rtl/bus/datamover_ctrl.sv` so it can be
adjusted if the Vivado IP configuration changes.
