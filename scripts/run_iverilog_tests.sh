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

run_core64() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_core_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_core.sv \
    tb/tb_zx64_core.sv

  vvp /tmp/zx64_core_tb.vvp

  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_core_compressed_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_core.sv \
    tb/tb_zx64_core_compressed.sv

  vvp /tmp/zx64_core_compressed_tb.vvp
}

run_core64_5stage() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_core5_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core5.sv \
    tb/tb_zx64_core5.sv

  vvp /tmp/zx64_core5_tb.vvp
}

run_soc64() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_smoke_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_smoke.sv

  vvp /tmp/zx64_soc_smoke_tb.vvp
}

run_soc64_5stage() {
  iverilog -g2012 \
    -Ptb_zx64_soc_smoke.USE_CORE5=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc5_smoke_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_smoke.sv

  vvp /tmp/zx64_soc5_smoke_tb.vvp
}

run_soc64_mmio() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_mmio_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_mmio.sv

  vvp /tmp/zx64_soc_mmio_tb.vvp
}

run_soc64_host() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_host_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_host.sv

  vvp /tmp/zx64_soc_host_tb.vvp
}

run_soc64_bd_host() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_bd_host_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    rtl/soc/zx64_soc_bd.v \
    tb/tb_zx64_soc_bd_host.sv

  vvp /tmp/zx64_soc_bd_host_tb.vvp
}

run_soc64_ddr() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_ddr_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_ddr.sv

  vvp /tmp/zx64_soc_ddr_tb.vvp
}

run_soc64_5stage_ddr() {
  iverilog -g2012 \
    -Ptb_zx64_soc_ddr.USE_CORE5=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc5_ddr_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_ddr.sv

  vvp /tmp/zx64_soc5_ddr_tb.vvp
}

run_soc64_sv39() {
  iverilog -g2012 \
    -Ptb_zx64_soc_ddr.RUN_SV39=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_sv39_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_ddr.sv

  vvp /tmp/zx64_soc_sv39_tb.vvp
}

run_soc64_5stage_sv39() {
  iverilog -g2012 \
    -Ptb_zx64_soc_ddr.USE_CORE5=1 \
    -Ptb_zx64_soc_ddr.RUN_SV39=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc5_sv39_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_ddr.sv

  vvp /tmp/zx64_soc5_sv39_tb.vvp
}

run_soc64_sbi() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_sbi_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_sbi.sv

  vvp /tmp/zx64_soc_sbi_tb.vvp
}

run_soc64_5stage_sbi() {
  iverilog -g2012 \
    -Ptb_zx64_soc_sbi.USE_CORE5=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc5_sbi_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_sbi.sv

  vvp /tmp/zx64_soc5_sbi_tb.vvp
}

run_soc64_real_sbi() {
  ./scripts/build_zx32_programs.sh >/dev/null
  python3 - hw_bringup/build/elf/linux_boot_firmware.rv64.bin /tmp/zx64_linux_boot_firmware.memh <<'PY'
import pathlib
import struct
import sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
if len(raw) % 4:
    raise SystemExit("RV64 firmware binary is not 32-bit aligned")
words = list(struct.unpack("<" + "I" * (len(raw) // 4), raw))
if len(words) % 2:
    words.append(0)
while len(words) < 2048:
    words.append(0)
with pathlib.Path(sys.argv[2]).open("w") as f:
    for i in range(0, len(words), 2):
        f.write(f"{words[i + 1]:08x}{words[i]:08x}\n")
PY

  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_real_sbi_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_real_sbi.sv

  vvp /tmp/zx64_soc_real_sbi_tb.vvp +FW_MEMH=/tmp/zx64_linux_boot_firmware.memh
}

run_soc64_5stage_real_sbi() {
  ./scripts/build_zx32_programs.sh >/dev/null
  python3 - hw_bringup/build/elf/linux_boot_firmware.rv64.bin /tmp/zx64_linux_boot_firmware.memh <<'PY'
import pathlib
import struct
import sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
if len(raw) % 4:
    raise SystemExit("RV64 firmware binary is not 32-bit aligned")
words = list(struct.unpack("<" + "I" * (len(raw) // 4), raw))
if len(words) % 2:
    words.append(0)
while len(words) < 2048:
    words.append(0)
with pathlib.Path(sys.argv[2]).open("w") as f:
    for i in range(0, len(words), 2):
        f.write(f"{words[i + 1]:08x}{words[i]:08x}\n")
PY

  iverilog -g2012 \
    -Ptb_zx64_soc_real_sbi.USE_CORE5=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc5_real_sbi_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_real_sbi.sv

  vvp /tmp/zx64_soc5_real_sbi_tb.vvp +FW_MEMH=/tmp/zx64_linux_boot_firmware.memh
}

run_soc64_linux() {
  iverilog -g2012 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc_linux_handoff_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_linux_handoff.sv

  vvp /tmp/zx64_soc_linux_handoff_tb.vvp
}

run_soc64_5stage_linux() {
  iverilog -g2012 \
    -Ptb_zx64_soc_linux_handoff.USE_CORE5=1 \
    -I rtl/core \
    -I rtl/core64 \
    -o /tmp/zx64_soc5_linux_handoff_tb.vvp \
    rtl/core64/regfile64.sv \
    rtl/core64/fregfile64.sv \
    rtl/core64/alu64.sv \
    rtl/core64/zx64_muldiv_unit.sv \
    rtl/core64/zx64_core.sv \
    rtl/core64/zx64_core5.sv \
    rtl/periph/simple_ram64.sv \
    rtl/periph/mmio_uart_tx.sv \
    rtl/periph/mmio_timer.sv \
    rtl/periph/mmio_virtio_blk_regs.sv \
    rtl/periph/mmio_virtio_input_regs.sv \
    rtl/periph/mmio_plic_min.sv \
    rtl/bus/axi4_master_bridge.sv \
    rtl/soc/zx64_soc.sv \
    tb/tb_zx64_soc_linux_handoff.sv

  vvp /tmp/zx64_soc5_linux_handoff_tb.vvp
}

run_zx64_fw() {
  ./scripts/check_zx64_linux_boot_firmware.sh
}

run_zx64_boot_chain() {
  ./scripts/check_zx64_linux_boot_chain.sh
}

run_zx64_standard_kernel() {
  local contract_script="scripts/check_zx64_standard_kernel_contract.sh"

  if [[ ! -f "$contract_script" ]]; then
    echo "error: zx64-standard-kernel requires $contract_script, but it is missing" >&2
    return 127
  fi

  bash "$contract_script"
}

run_zx64_vivado_bitstream() {
  ./scripts/check_zx64_vivado_bitstream.sh
}

run_irqctrl() {
  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/zx32_irqctrl_tb.vvp \
    rtl/periph/mmio_irqctrl.sv \
    tb/tb_mmio_irqctrl.sv

  vvp /tmp/zx32_irqctrl_tb.vvp
}

run_plic() {
  iverilog -g2012 \
    -o /tmp/mmio_plic_min_tb.vvp \
    rtl/periph/mmio_plic_min.sv \
    tb/tb_mmio_plic_min.sv

  vvp /tmp/mmio_plic_min_tb.vvp
}

run_virtio_blk_regs() {
  iverilog -g2012 \
    -o /tmp/mmio_virtio_blk_regs_tb.vvp \
    rtl/periph/mmio_virtio_blk_regs.sv \
    tb/tb_mmio_virtio_blk_regs.sv

  vvp /tmp/mmio_virtio_blk_regs_tb.vvp
}

run_virtio_input_regs() {
  iverilog -g2012 \
    -o /tmp/mmio_virtio_input_regs_tb.vvp \
    rtl/periph/mmio_virtio_input_regs.sv \
    tb/tb_mmio_virtio_input_regs.sv

  vvp /tmp/mmio_virtio_input_regs_tb.vvp
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
    rtl/video/hdmi_console_ram.sv \
    rtl/video/hdmi_text_console_core.sv

  iverilog -g2012 \
    -I rtl/core \
    -o /tmp/hdmi_text_console_core_tb.vvp \
    rtl/video/video_timing.sv \
    rtl/video/tmds_encoder.sv \
    rtl/video/hdmi_test_pattern.sv \
    rtl/video/hdmi_console_ram.sv \
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
    rtl/video/hdmi_console_ram.sv \
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
    rtl/video/hdmi_console_ram.sv \
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
  core64)
    run_core64
    ;;
  core64-5stage)
    run_core64_5stage
    ;;
  soc64)
    run_soc64
    ;;
  soc64-5stage)
    run_soc64_5stage
    ;;
  soc64-mmio)
    run_soc64_mmio
    ;;
  soc64-host)
    run_soc64_host
    ;;
  soc64-bd-host)
    run_soc64_bd_host
    ;;
  soc64-ddr)
    run_soc64_ddr
    ;;
  soc64-5stage-ddr)
    run_soc64_5stage_ddr
    ;;
  soc64-sv39)
    run_soc64_sv39
    ;;
  soc64-5stage-sv39)
    run_soc64_5stage_sv39
    ;;
  soc64-sbi)
    run_soc64_sbi
    ;;
  soc64-5stage-sbi)
    run_soc64_5stage_sbi
    ;;
  soc64-real-sbi)
    run_soc64_real_sbi
    ;;
  soc64-5stage-real-sbi)
    run_soc64_5stage_real_sbi
    ;;
  soc64-linux)
    run_soc64_linux
    ;;
  soc64-5stage-linux)
    run_soc64_5stage_linux
    ;;
  zx64-fw)
    run_zx64_fw
    ;;
  zx64-boot-chain)
    run_zx64_boot_chain
    ;;
  zx64-standard-kernel)
    run_zx64_standard_kernel
    ;;
  zx64-vivado-bitstream)
    run_zx64_vivado_bitstream
    ;;
  irqctrl)
    run_irqctrl
    ;;
  plic)
    run_plic
    ;;
  virtio-blk-regs)
    run_virtio_blk_regs
    ;;
  virtio-input-regs)
    run_virtio_input_regs
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
    run_core64
    run_core64_5stage
    run_soc64
    run_soc64_5stage
    run_soc64_mmio
    run_soc64_host
    run_soc64_bd_host
    run_soc64_ddr
    run_soc64_5stage_ddr
    run_soc64_sv39
    run_soc64_5stage_sv39
    run_soc64_sbi
    run_soc64_5stage_sbi
    run_soc64_real_sbi
    run_soc64_5stage_real_sbi
    run_soc64_linux
    run_soc64_5stage_linux
    run_zx64_fw
    run_zx64_boot_chain
    run_irqctrl
    run_plic
    run_virtio_blk_regs
    run_virtio_input_regs
    run_scratchpad
    run_gpu
    run_video
    run_soc
    run_soc_sv32
    ;;
  *)
    echo "usage: $0 [core|core64|core64-5stage|soc64|soc64-5stage|soc64-mmio|soc64-host|soc64-bd-host|soc64-ddr|soc64-5stage-ddr|soc64-sv39|soc64-5stage-sv39|soc64-sbi|soc64-5stage-sbi|soc64-real-sbi|soc64-5stage-real-sbi|soc64-linux|soc64-5stage-linux|zx64-fw|zx64-boot-chain|zx64-standard-kernel|zx64-vivado-bitstream|irqctrl|plic|virtio-blk-regs|virtio-input-regs|scratchpad|gpu|video|soc|soc-sv32|all]" >&2
    exit 2
    ;;
esac
