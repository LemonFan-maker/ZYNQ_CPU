# DDR and DataMover

The current design has two separate DDR paths. Keep them conceptually separate when debugging.

## Direct DDR Path

```text
PL CPU instruction/data request
  -> zx32_soc DDR decode
  -> axi4_master_bridge
  -> Zynq PS S_AXI_HP
  -> PS DDR controller
```

The direct bridge maps:

```text
PL CPU 0x8000_0000 -> PS physical 0x0000_0000
```

Current behavior:

- serialized AXI4 requests through the current bridge/front end
- used for PL CPU DDR random access smoke tests
- used for PL CPU instruction fetch from DDR
- small direct-mapped instruction and data caches for DDR reads
- D-cache next-line prefetch for detected sequential read streams
- raw DDR writes invalidate matching I-cache and D-cache entries
- no outstanding request queue

This is enough for the current Buildroot Linux boot, including kernel instruction fetches, kernel data accesses, page-table walks, and BusyBox userspace.

It is still a simple bring-up memory system rather than a performance-oriented Linux memory subsystem. The prefetch path is intentionally conservative: it only arms after a sequential DDR read miss and blocks demand completion while the prefetch line is in flight, so future changes should keep random-read behavior and Linux boot stability in the regression set.

## DataMover Path

```text
PL CPU or PS probe
  -> datamover_ctrl registers
  -> AXI DataMover command/status streams
  -> AXI DataMover M_AXI MM2S/S2MM
  -> Zynq PS S_AXI_HP
  -> PS DDR controller
```

The DataMover path remains useful for:

- high-confidence PS DDR block-transfer smoke tests
- custom PL CPU DataMover instructions
- future DMA-style movement between DDR and local buffers

It is not a transparent CPU memory port by itself.

## PL CPU DataMover Register Map

PL CPU base address: `0x1002_0000`

| Offset | Register | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | control | W | bit 0 starts MM2S, bit 1 starts S2MM |
| `0x04` | status | R/W1C | busy/done/error/channel-ready flags |
| `0x08` | ddr_addr | R/W | PS physical DDR byte address |
| `0x0c` | local_addr | R/W | local scratchpad byte address |
| `0x10` | length | R/W | bytes to transfer |
| `0x14` | tag | R/W | 4-bit DataMover command tag |
| `0x18` | mm2s_status_raw | R | last MM2S status byte |
| `0x1c` | s2mm_status_raw | R | last S2MM status byte |

Status bits from `rtl/bus/datamover_ctrl.sv`:

| Bit | Mask | Meaning |
| ---: | ---: | --- |
| 0 | `0x0000_0001` | MM2S busy |
| 1 | `0x0000_0002` | S2MM busy |
| 2 | `0x0000_0004` | MM2S done |
| 3 | `0x0000_0008` | S2MM done |
| 4 | `0x0000_0010` | MM2S error |
| 5 | `0x0000_0020` | S2MM error |
| 6 | `0x0000_0040` | MM2S command ready |
| 7 | `0x0000_0080` | S2MM command ready |

## PS Probe DataMover Aperture

The ARM-side bring-up probe sees the DataMover/control aperture at
`0x43c1_0000`.

| PS address | Purpose |
| ---: | --- |
| `0x43c1_0000` | DataMover control |
| `0x43c1_1000` | RX scratch |
| `0x43c1_2000` | TX scratch and mailbox |
| `0x43c1_3000` | PL CPU IMEM load window |
| `0x43c1_7000` | PL CPU reset/status/reset-vector |

## Scratchpad

`rtl/periph/axis_scratchpad.sv` is currently configured with 256 32-bit words by default. It serves both CPU MMIO accesses and DataMover local stream endpoints.

The scratchpad is deliberately small for bring-up. Replace or parameterize it with a block-RAM-oriented implementation before increasing it substantially.

## Command Format

`datamover_ctrl` emits the 72-bit DataMover command format currently expected by the Vivado IP configuration:

- bits `[22:0]`: byte count
- bit `[23]`: INCR burst
- bits `[29:24]`: DSA, currently zero
- bit `[30]`: EOF
- bit `[31]`: DRR, set for S2MM and clear for MM2S
- bits `[63:32]`: DDR byte address
- bits `[67:64]`: command tag
- bits `[71:68]`: zero

If the Vivado DataMover IP settings change, update this encoding and rerun the DataMover loopback and custom instruction smoke tests before trusting DDR data.
