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
- PS physical DDR base used by the bridge: `0x0010_0000`

Current hardware has two DDR access paths from PL:

- AXI DataMover through PS HP for bulk block transfers
- direct serialized AXI4 master bridge for PL CPU load/store/fetch, with multi-beat read refills used by the SoC I-cache/D-cache front end

Both paths have passed board smoke tests.

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
| Linux Image | `0x8040_0000` | `0x0050_0000` |
| DTB | `0x8160_0000` | `0x0170_0000` |

## Environment Rule

Use the wrapper scripts instead of direct `vivado` or `xsct` invocations. They source `/home/orionisli/.zshrc`, call `vi25`, and then run the AMD/Xilinx tool.
