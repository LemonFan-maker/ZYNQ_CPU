# ALINX AX7020B Board Notes

## Board Target

- Board: ALINX AX7020B
- Part: `xc7z020clg400-2`
- Package: `clg400`
- Speed grade: `-2`
- Current Vivado version: 2025.2

## Clock

The current hardware build uses PS `FCLK0` as the PL clock. The observed build uses about 75 MHz:

```text
FCLK0: 75.002 MHz
```

Keep new RTL synchronous to this clock until there is a measured reason to add another clock domain.

## PS UART

The board bring-up flow currently reports through PS UART1. The known pin/MIO mapping from the existing PS7 setup is:

| Signal | MIO | Pin | Direction |
| --- | ---: | --- | --- |
| UART1 RX | 49 | C12 | input |
| UART1 TX | 48 | B12 | output |

Use:

```sh
./scripts/serial_monitor.sh /dev/ttyUSB0 115200
```

If no device path is supplied, the script tries the first `/dev/ttyUSB*`.

## DDR

The project uses the Zynq PS DDR controller. Do not build a separate PL DDR controller for this board path.

Current DDR assumptions:

- target device: `MT41K256M16RE-125`
- data width: 32-bit
- PL CPU virtual/CPU DDR base: `0x8000_0000`
- PS physical DDR base used by the bridge: `0x0000_0000`
- Linux-visible CPU DDR size: 1 GiB, with 64 MiB reserved as GPU framebuffer VRAM

Current hardware has two DDR access paths from PL:

- AXI DataMover through PS HP for bulk block transfers
- direct serialized AXI4 master bridge for PL CPU load/store/fetch, with multi-beat read refills used by the SoC I-cache/D-cache front end

The GPU fill renderer v0 also writes framebuffers through the direct DDR bridge, but it is currently validated by RTL/SoC simulation rather than a board-rendering demo.

Both original DDR paths have passed board smoke tests.

## Hardware Outputs

The hardware bring-up build command is:

```sh
./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
```

Expected generated outputs:

- `build/vivado_hw/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit`
- `build/vivado_hw/zynq_cpu_system_wrapper.xsa`
- generated PS7 initialization files under `build/vivado_hw/zynq_cpu_hw.gen/`

The download script expects those generated paths:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_bringup.xsbl
```

The real Linux boot launcher uses the same bitstream and PS7 initialization, but downloads `hw_bringup/build/ps_linux_boot.elf` instead:

```sh
./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl
```

Before running that launcher, prepare the Linux Image and DTB:

```sh
./scripts/build_mainline_rv32_linux.sh
./scripts/prepare_linux_boot_artifacts.sh
./scripts/build_ps_uart_probe.sh
```

The current Linux placement is:

| Artifact | PL CPU address | PS physical address |
| --- | ---: | ---: |
| Linux Image | `0x8040_0000` | `0x0040_0000` |

| DTB | `0x8200_0000` | `0x0200_0000` |

## J20 LCD Console (Display2)

The J20 expansion header (PL BANK35, LVCMOS33) drives an AN340-class 4.3"
480x272 RGB888 DE-mode LCD as a second console that mirrors the HDMI boot
text. Pin map lives in `constraints/ax7020_lcd_j20.xdc` (same table as the
classes project panel; RGB/DCLK FAST slew, DRIVE 8). Panel timing: 480x272
active, HFP=20, HS=10 (low-active), HBP=10, HT=530; VFP=8, VS=4 (low-active),
VBP=8, VT=304; 9.375 MHz pixel clock with a 180-degree ODDR DCLK.

Console geometry is 60x17 characters of 8x16 (the 8x16 Cascadia font shared
with the HDMI console). PS access is via the zx32_soc aperture at
`0x43c2_0000` + `0x10000` (`ZYNQ_CPU_DISPLAY2_*` in `hw_bringup/ps_uart_probe.h`);
on the PL bus this maps to `0x1009_0000` (see `docs/architecture.md`). The
`rv64` build has no display2 window: its LCD cell is held disabled with the
DCLK still running.

Board check: after `./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl`
the LCD should show the same boot text as the HDMI console (the PS fans every
console byte into both parsers).

## Environment Rule

Use the wrapper scripts instead of direct `vivado` or `xsct` invocations. They source `/home/orionisli/.zshrc`, call `vi25`, and then run the AMD/Xilinx tool.
