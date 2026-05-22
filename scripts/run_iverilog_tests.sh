#!/usr/bin/env bash
set -euo pipefail

target="${1:-all}"

run_core() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/zx32_core_tb.vvp \
    rtl/core/alu.sv \
    rtl/core/regfile.sv \
    rtl/core/zx32_core.sv \
    rtl/periph/simple_ram.sv \
    tb/tb_zx32_core.sv

  vvp /tmp/zx32_core_tb.vvp
}

run_irqctrl() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/zx32_irqctrl_tb.vvp \
    rtl/periph/mmio_irqctrl.sv \
    tb/tb_mmio_irqctrl.sv

  vvp /tmp/zx32_irqctrl_tb.vvp
}

run_scratchpad() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/axis_scratchpad_tb.vvp \
    rtl/periph/axis_scratchpad.sv \
    tb/tb_axis_scratchpad.sv

  vvp /tmp/axis_scratchpad_tb.vvp
}

run_soc() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/zx32_soc_datamover_tb.vvp \
    rtl/core/alu.sv \
    rtl/core/regfile.sv \
    rtl/core/zx32_core.sv \
    rtl/periph/simple_ram.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_irqctrl.sv \
    rtl/periph/axis_scratchpad.sv \
    rtl/bus/datamover_ctrl.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx32_soc.sv \
    tb/tb_zx32_soc_datamover.sv

  vvp /tmp/zx32_soc_datamover_tb.vvp
}

run_soc_sv32() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/zx32_soc_sv32_ddr_tb.vvp \
    rtl/core/alu.sv \
    rtl/core/regfile.sv \
    rtl/core/zx32_core.sv \
    rtl/periph/simple_ram.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_irqctrl.sv \
    rtl/periph/axis_scratchpad.sv \
    rtl/bus/datamover_ctrl.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx32_soc.sv \
    tb/tb_zx32_soc_sv32_ddr.sv

  vvp /tmp/zx32_soc_sv32_ddr_tb.vvp
}

case "$target" in
  core)
    run_core
    ;;
  irqctrl)
    run_irqctrl
    ;;
  scratchpad)
    run_scratchpad
    ;;
  soc)
    run_soc
    ;;
  soc-sv32)
    run_soc_sv32
    ;;
  all)
    run_core
    run_irqctrl
    run_scratchpad
    run_soc
    run_soc_sv32
    ;;
  *)
    echo "usage: $0 [core|irqctrl|scratchpad|soc|soc-sv32|all]" >&2
    exit 2
    ;;
esac
