# Architecture

This document describes the current RTL architecture, not the original plan.

## System Shape

```text
PS UART / XSCT
  -> ARM-side ps_uart_probe.elf
  -> AXI GP0 register windows in PL
  -> zx32_soc
       -> zx32_core
       -> local IMEM / scratchpad
       -> MMIO UART, timer, interrupt controller, DataMover control
       -> AXI DataMover for bulk DDR transfers
       -> AXI4 master bridge for direct PS DDR load/store/fetch
       -> GPU fill/line renderer and display-control MMIO
```

The PS side still owns bootstrapping: PS initializes DDR, configures the PL, loads the ARM-side probe, writes PL CPU test programs, and releases the PL CPU from reset.

For boardless software bring-up, `tools/zx32sim/` provides a Python functional model of the same CPU-visible contract:

```text
host Python process
  -> tools.zx32sim.main
  -> linux_boot_firmware.elf in local IMEM
  -> Linux Image and DTB loaded into the CPU DDR window
  -> sparse memory, MMIO timer/UART, scratch console, optional block devices
```

The simulator is not cycle accurate. It is a reference model for software-visible behavior: instruction execution, traps, Sv32, SBI calls, timer interrupts, console rings, and the current Linux boot path.

## Core

The core is a multi-cycle in-order RV32 design. It is intentionally simple:

- one instruction is processed through explicit fetch/decode/execute/memory/writeback-style states
- no core pipeline; the SoC wraps DDR instruction/data accesses with small direct-mapped caches
- no pipeline hazards to manage yet
- memory requests are held until the selected local, MMIO, or DDR target is ready

Implemented execution substrate:

- RV32I-style integer operations, branches, jumps, loads, stores, fences
- RV32M multiply/divide
- RV32A word atomics, including LR/SC reservation tracking
- CSR instructions and a first privileged-architecture substrate
- M-mode and S-mode trap/return paths
- timer and external interrupt injection
- RV32 counter CSRs
- Sv32 page-table walking, small TLB, and `sfence.vma`
- three local custom instructions for bring-up/DataMover control

## PL CPU Memory Map

These addresses are seen by software running on the PL CPU.

| Region | Base | Purpose |
| --- | ---: | --- |
| Boot/local RAM | `0x0000_0000` | reset code and early tests loaded by PS |
| UART | `0x1000_0000` | simple PL MMIO UART transmitter |
| Timer | `0x1001_0000` | `mtime`, `mtimecmp`, timer IRQ |
| DataMover control | `0x1002_0000` | bulk DDR DMA command/status registers |
| CPU control | `0x1003_0000` | reset/status/sizing control block |
| Interrupt controller | `0x1004_0000` | pending/enable/threshold/claim registers |
| GPU fill renderer | `0x1007_0000` | framebuffer clear/fill-rectangle test accelerator |
| Display control | `0x1008_0000` | framebuffer/display mode control and HDMI bring-up status |
| Scratchpad | `0x2000_0000` | CPU and DataMover local stream endpoint |
| PS DDR window | `0x8000_0000` | direct DDR load/store/fetch window |

The simulator also models optional simulator-only block devices:

| Region | Base | Purpose |
| --- | ---: | --- |
| Simple simulator block device | `0x1005_0000` | raw 512-byte-sector MMIO device for smokes |
| Virtio-mmio block device | `0x1006_0000` | Linux-visible simulator disk when using `zx32sim_virtio.dtb` |
| Simulator PLIC | `0x0c00_0000` | virtio IRQ source 1, simulator-only |

These devices are not part of the current board platform ABI. The board DTB does not expose them.

The DDR window is translated by `rtl/bus/axi4_master_bridge.sv`:

```text
PL CPU 0x8000_0000 -> PS physical 0x0000_0000
```

The bridge currently issues serialized AXI4 requests behind the SoC memory front end. DDR instruction and data reads are cached in small direct-mapped line caches, while raw writes still go to DDR and invalidate the matching cache line. The D-cache also has a conservative next-line prefetch path for sequential DDR read misses. Prefetch is stream-gated so random reads do not continuously pull useless cache lines from DDR.

This is enough for the current Linux and Buildroot path, but it is still a simple bring-up memory system rather than a high-performance coherent cache hierarchy.

## GPU Renderer v0

`rtl/periph/mmio_gpu_fill.sv` implements the first rendering coprocessor milestone. It is a fixed-function MMIO device, not a programmable GPU.

The v0 renderer can:

- clear a 32-bit-per-pixel framebuffer
- fill an axis-aligned rectangle
- draw a Bresenham-style line
- queue up to four commands in a small FIFO
- write pixels to the PS DDR window through the existing SoC DDR bridge
- expose busy/done/error/FIFO/debug counters through MMIO polling

PL CPU base address: `0x1007_0000`

The board and simulator DTS files expose a 1 GiB CPU DDR window and reserve `0xbc00_0000..0xbfff_ffff` as a 64 MiB GPU framebuffer/VRAM region. `hw_bringup/userspace/gpu_smoke/zx32_gpu_smoke.c`, `hw_bringup/userspace/gpu_demo/zx32_gpu_demo.c`, and `hw_bringup/userspace/image_viewer/zx32_image_viewer.c` map that region with `/dev/mem` by default. Host-side helpers convert PNG/JPEG input to little-endian XRGB8888 raw data, download it into VRAM over XSCT/JTAG, and dump VRAM back to PPM for offline preview.

| Offset | Register | Description |
| ---: | --- | --- |
| `0x00` | control | write bit 0 to start; bits `[7:4]` opcode: `1=clear`, `2=fill_rect`, `3=draw_line`; bit 31 soft-resets renderer state |
| `0x04` | status | bit 0 busy, bit 1 done, bit 2 error; write one to bits 1/2 to clear sticky status |
| `0x08` | framebuffer address | CPU-visible DDR framebuffer base, expected in the `0x8000_0000..0xbfff_ffff` DDR window |
| `0x0c` | framebuffer stride | bytes per framebuffer row |
| `0x10` | framebuffer size | `{height[15:0], width[15:0]}` in 32-bit pixels |
| `0x14` | color | 32-bit pixel value written by clear/fill |
| `0x18` | rect origin | `{y[15:0], x[15:0]}` |
| `0x1c` | rect size or line end | fill uses `{height[15:0], width[15:0]}`; line uses `{end_y[15:0], end_x[15:0]}` |
| `0x20` | current pixel | debug readback `{y[15:0], x[15:0]}` |
| `0x34` | FIFO submit/status | write bit 0 to submit opcode bits `[7:4]`; read empty/full/count |
| `0x38` | command done count | number of completed FIFO/direct commands |

The renderer only issues DDR writes when the CPU demand path and D-cache prefetch path are idle. GPU writes invalidate matching I-cache and D-cache lines so CPU readback does not reuse stale cached data.

While the renderer is busy, configuration writes are ignored. Status W1C writes and the control soft-reset bit remain accepted.

The current RTL tests cover direct module operation and SoC-level DDR writeback through the AXI bridge. Linux userspace smoke/demo/image-viewer binaries can configure the renderer or write XRGB8888 pixels through `/dev/mem`. Triangle rasterization, texture reads, interrupts, and Linux drivers are not implemented yet.

## Display and HDMI Bring-Up

The first display-output milestone is split from framebuffer DMA. The repository now has pure RTL blocks for video timing, TMDS encoding, and a test-pattern generator under `rtl/video/`, plus a Xilinx-specific HDMI test-pattern top for AX7020 board bring-up.

The initial board path targets AX7020 HDMI OUT on ZYNQ PL BANK34. The checked-in constraints cover the differential TMDS pins from the board table:

| Signal | Pin |
| --- | --- |
| `HDMI_CLK_P/N` | `U13` / `V13` |
| `HDMI_D0_P/N` | `W14` / `Y14` |
| `HDMI_D1_P/N` | `Y18` / `Y19` |
| `HDMI_D2_P/N` | `Y16` / `Y17` |

The current Vivado HDMI cell generates a 640x480@60-style test pattern from the PS FCLK-derived 25 MHz pixel clock. It does not yet scan VRAM. The next hardware step is to add an independent burst display-DMA read master and line buffers before attempting 720p/1080p framebuffer display.

PL CPU display-control base address: `0x1008_0000`

| Offset | Register | Description |
| ---: | --- | --- |
| `0x00` | control | bit 0 enable, bit 1 soft reset, bit 2 test-pattern enable |
| `0x04` | status | enabled/locked/HPD/underflow/frame-done status, sticky bits W1C |
| `0x08` | framebuffer address | default `0xbc00_0000` |
| `0x0c` | framebuffer stride | bytes per row, default `1920 * 4` |
| `0x10` | framebuffer size | `{height[15:0], width[15:0]}` |
| `0x14` | mode | `0=640x480@60`, `1=1280x720@60`, `2=1920x1080@60` |
| `0x18` | background color | XRGB8888-style color used by test/fallback paths |
| `0x1c` | underflow count | future DMA underflow counter |
| `0x20` | scan position | `{v_count[15:0], h_count[15:0]}` |

## PS-Side AXI Register Windows

The ARM-side bring-up probe uses these PS-visible addresses:

| PS address | Region |
| ---: | --- |
| `0x43c0_0000` | build-id/status/scratch AXI-Lite probe registers |
| `0x43c1_0000` | DataMover and PL CPU control aperture |
| `0x43c1_1000` | RX scratch region |
| `0x43c1_2000` | TX scratch/mailbox region |
| `0x43c1_3000` | PL CPU IMEM load window |
| `0x43c1_7000` | PL CPU reset/status/reset-vector control |
| `0x43c1_9000` | PL CPU display-control MMIO alias |

The detailed PS-side constants live in `hw_bringup/ps_uart_probe.h`.

## Timer and Interrupt Model

`rtl/periph/mmio_timer.sv` exposes:

| Offset | Register |
| ---: | --- |
| `0x00` | `mtime[31:0]` |
| `0x04` | `mtime[63:32]` |
| `0x08` | `mtimecmp[31:0]` |
| `0x0c` | `mtimecmp[63:32]` |
| `0x10` | timer IRQ status |

`rtl/periph/mmio_irqctrl.sv` exposes:

| Offset | Register |
| ---: | --- |
| `0x00` | pending bits |
| `0x04` | enable bits |
| `0x08` | threshold |
| `0x0c` | claim/complete |
| `0x10` | raw source bits |

This is enough for the current S-mode timer smokes and the real Linux boot path. Linux timer events are currently handled through the local SBI shim: the kernel requests SBI TIME events in the CSR `time/timeh` domain, and firmware programs the MMIO `mtimecmp` register after applying the measured `mtime - rdtime` offset.

## Linux Status

The architecture now boots a mainline RV32 Linux kernel to an embedded Buildroot/BusyBox userspace on the board. The board-proven path is:

```text
PS launcher
  -> Linux Image at CPU 0x8040_0000 / PS 0x0050_0000
  -> DTB at CPU 0x8160_0000 / PS 0x0170_0000
  -> M-mode SBI firmware in IMEM
  -> Linux S-mode entry with a0=0, a1=0x8160_0000, satp=0
  -> /init -> /sbin/init from built-in Buildroot initramfs
```

Current Linux-visible behavior:

- early console and `hvc0` use SBI console calls mirrored through the PS-visible scratch ring
- `hvc0` input is forwarded from PS UART through a scratch-backed SBI getchar ring
- timer events use SBI TIME and the local MMIO timer
- Sv32 page walking and the TLB are sufficient for kernel init and Buildroot userspace
- the direct DDR path provides cached read refills through the SoC I-cache/D-cache front end; raw writes remain serialized and invalidate matching cache lines
- no Linux drivers exist yet for the custom PL UART, timer, IRQ controller, or DataMover blocks

The simulator mirrors this path closely enough to reach an interactive Buildroot shell without a board. 

In simulator interactive mode, host stdin is written into the same scratch-backed SBI getchar ring that the PS launcher uses on hardware, and SBI console output is drained from the same 256-byte output ring. 

This keeps shell behavior aligned with the board path while avoiding the need for COM/JTAG access during software debugging.

The simulator adds WFI/timer fast-forwarding for practicality. 

When Linux is in idle and the next local timer deadline is known, simulator time can jump to that deadline instead of interpreting every idle-loop instruction. 

This is a functional optimization, not RTL timing behavior.

Remaining architecture work is mostly about turning the bring-up contract into a stable platform ABI:

- decide whether to keep the local SBI shim or move toward OpenSBI
- clean up or formalize the current `rdtime` to `mtime` offset bridge
- expand MMU, interrupt, AMO, and memory-ordering tests around Linux behavior
- decide which custom devices should be visible to Linux
- document cache/uncached memory ordering before performance work
