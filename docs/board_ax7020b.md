# ALINX AX7020B Board Notes

## FPGA

- Board: ALINX AX7020B
- Part: `xc7z020clg400-2`
- Package: `clg400`
- Speed grade: `-2`

These values were taken from the generated PS7 constraints file:

```text
/home/orionisli/Working/Zynq_GPGPU/Zynq_GPGPU_Core.gen/sources_1/bd/gpu_system/ip/gpu_system_processing_system7_0_0/gpu_system_processing_system7_0_0.xdc
```

## PS Clock

The existing PS7 constraints define `FCLKCLK[0]` as:

```tcl
create_clock -name clk_fpga_0 -period "13.333" [get_pins "PS7_i/FCLKCLK[0]"]
```

That corresponds to about 75 MHz. The first PL CPU top should use this clock
until there is a measured reason to change it.

## UART

The existing design uses PS UART1:

| Signal | MIO | Pin | Direction |
| --- | ---: | --- | --- |
| UART1 RX | 49 | C12 | input |
| UART1 TX | 48 | B12 | output |

Early bring-up can use PS UART for boot/debug messages from the PS side. The PL
CPU still needs its own memory-mapped UART or an AXI path to an existing UART if
we want Linux console output from the custom CPU.

## DDR

User-provided memory target:

- DDR3 device: `MT41K256M16RE-125`
- Data width: 32-bit

For this Zynq design, DDR is owned by the PS DDR controller. The PL CPU should
access DDR through a PS AXI HP port rather than implementing a PL DDR controller.

