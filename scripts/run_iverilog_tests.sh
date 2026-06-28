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

run_gpu() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/mmio_gpu_fill_tb.vvp \
    rtl/periph/mmio_gpu_fill.sv \
    tb/tb_mmio_gpu_fill.sv

  vvp /tmp/mmio_gpu_fill_tb.vvp
}

run_video() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/video_timing_tb.vvp \
    rtl/video/video_timing.sv \
    tb/tb_video_timing.sv

  vvp /tmp/video_timing_tb.vvp

  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/mmio_display_ctrl_tb.vvp \
    rtl/video/mmio_display_ctrl.sv \
    tb/tb_mmio_display_ctrl.sv

  vvp /tmp/mmio_display_ctrl_tb.vvp

  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/hdmi_text_console_syntax.vvp \
    rtl/video/video_timing.sv \
    rtl/video/tmds_encoder.sv \
    rtl/video/hdmi_test_pattern.sv \
    rtl/video/hdmi_text_console_core.sv

  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/hdmi_text_console_core_tb.vvp \
    rtl/video/video_timing.sv \
    rtl/video/tmds_encoder.sv \
    rtl/video/hdmi_test_pattern.sv \
    rtl/video/hdmi_text_console_core.sv \
    tb/tb_hdmi_text_console_core.sv

  vvp /tmp/hdmi_text_console_core_tb.vvp
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
    rtl/periph/mmio_gpu_fill.sv \
    rtl/video/mmio_display_ctrl.sv \
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
    rtl/periph/mmio_gpu_fill.sv \
    rtl/video/mmio_display_ctrl.sv \
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
  gpu)
    run_gpu
    ;;
  video)
    run_video
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
    run_gpu
    run_video
    run_soc
    run_soc_sv32
    ;;
  *)
    echo "usage: $0 [core|irqctrl|scratchpad|gpu|video|soc|soc-sv32|all]" >&2
    exit 2
    ;;
esac
