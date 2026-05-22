#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_dir/hw_bringup/build"
gen_dir="$build_dir/generated"
asm="$repo_dir/tools/zx32asm.py"
elf="$repo_dir/tools/zx32elf.py"
bin2c="$repo_dir/tools/bin2c.py"

mkdir -p "$gen_dir"
mkdir -p "$build_dir/elf"

python3 "$elf" "$repo_dir/hw_bringup/programs/ps_bram_load.zx32.s" -o "$build_dir/elf/ps_bram_load.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/xcpyw_check.zx32.s" -o "$build_dir/elf/xcpyw_check.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/custom_datamover.zx32.s" -o "$build_dir/elf/custom_datamover.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/entry_smoke.zx32.s" -o "$build_dir/elf/entry_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/machine_trap_smoke.zx32.s" -o "$build_dir/elf/machine_trap_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/supervisor_smoke.zx32.s" -o "$build_dir/elf/supervisor_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/supervisor_timer_smoke.zx32.s" -o "$build_dir/elf/supervisor_timer_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/boot_payload_smoke.zx32.s" -o "$build_dir/elf/boot_payload_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/supervisor_counter_smoke.zx32.s" -o "$build_dir/elf/supervisor_counter_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/ddr_access_smoke.zx32.s" -o "$build_dir/elf/ddr_access_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/ddr_exec_smoke.zx32.s" -o "$build_dir/elf/ddr_exec_smoke.elf" --load-addr 0x80000000
python3 "$elf" "$repo_dir/hw_bringup/programs/ddr_high_amo_smoke.zx32.s" -o "$build_dir/elf/ddr_high_amo_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/sbi_firmware_smoke.zx32.s" -o "$build_dir/elf/sbi_firmware_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/sbi_payload_smoke.zx32.s" -o "$build_dir/elf/sbi_payload_smoke.elf" --load-addr 0x80000000
python3 "$elf" "$repo_dir/hw_bringup/programs/sbi_timer_firmware_smoke.zx32.s" -o "$build_dir/elf/sbi_timer_firmware_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/sbi_timer_payload_smoke.zx32.s" -o "$build_dir/elf/sbi_timer_payload_smoke.elf" --load-addr 0x80000000
python3 "$elf" "$repo_dir/hw_bringup/programs/linux_contract_firmware_smoke.zx32.s" -o "$build_dir/elf/linux_contract_firmware_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/linux_contract_payload_smoke.zx32.s" -o "$build_dir/elf/linux_contract_payload_smoke.elf" --load-addr 0x80000000
python3 "$elf" "$repo_dir/hw_bringup/programs/linux_image_layout_smoke.zx32.s" -o "$build_dir/elf/linux_image_layout_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/linux_sbi_firmware_smoke.zx32.s" -o "$build_dir/elf/linux_sbi_firmware_smoke.elf" --load-addr 0x0
python3 "$elf" "$repo_dir/hw_bringup/programs/linux_sbi_payload_smoke.zx32.s" -o "$build_dir/elf/linux_sbi_payload_smoke.elf" --load-addr 0x80000000
python3 "$elf" "$repo_dir/hw_bringup/programs/linux_boot_firmware.zx32.s" -o "$build_dir/elf/linux_boot_firmware.elf" --load-addr 0x0

tmp_header="$(mktemp "$gen_dir/zx32_programs.XXXXXX")"
trap 'rm -f "$tmp_header"' EXIT

{
  printf '#ifndef ZX32_PROGRAMS_H\n'
  printf '#define ZX32_PROGRAMS_H\n\n'
  printf '#include "xil_types.h"\n\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/ps_bram_load.zx32.s" --format c --c-type u32 --array-name zx32_ps_bram_load_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/xcpyw_check.zx32.s" --format c --c-type u32 --array-name zx32_xcpyw_check_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/custom_datamover.zx32.s" --format c --c-type u32 --array-name zx32_custom_datamover_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/entry_smoke.zx32.s" --format c --c-type u32 --array-name zx32_entry_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/machine_trap_smoke.zx32.s" --format c --c-type u32 --array-name zx32_machine_trap_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/supervisor_smoke.zx32.s" --format c --c-type u32 --array-name zx32_supervisor_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/supervisor_timer_smoke.zx32.s" --format c --c-type u32 --array-name zx32_supervisor_timer_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/boot_payload_smoke.zx32.s" --format c --c-type u32 --array-name zx32_boot_payload_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/supervisor_counter_smoke.zx32.s" --format c --c-type u32 --array-name zx32_supervisor_counter_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/ddr_access_smoke.zx32.s" --format c --c-type u32 --array-name zx32_ddr_access_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/ddr_exec_smoke.zx32.s" --format c --c-type u32 --array-name zx32_ddr_exec_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/ddr_high_amo_smoke.zx32.s" --format c --c-type u32 --array-name zx32_ddr_high_amo_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/sbi_firmware_smoke.zx32.s" --format c --c-type u32 --array-name zx32_sbi_firmware_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/sbi_payload_smoke.zx32.s" --format c --c-type u32 --array-name zx32_sbi_payload_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/sbi_timer_firmware_smoke.zx32.s" --format c --c-type u32 --array-name zx32_sbi_timer_firmware_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/sbi_timer_payload_smoke.zx32.s" --format c --c-type u32 --array-name zx32_sbi_timer_payload_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/linux_contract_firmware_smoke.zx32.s" --format c --c-type u32 --array-name zx32_linux_contract_firmware_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/linux_contract_payload_smoke.zx32.s" --format c --c-type u32 --array-name zx32_linux_contract_payload_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/linux_image_layout_smoke.zx32.s" --format c --c-type u32 --array-name zx32_linux_image_layout_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/linux_sbi_firmware_smoke.zx32.s" --format c --c-type u32 --array-name zx32_linux_sbi_firmware_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/linux_sbi_payload_smoke.zx32.s" --format c --c-type u32 --array-name zx32_linux_sbi_payload_smoke_program
  printf '\n'
  python3 "$asm" "$repo_dir/hw_bringup/programs/linux_boot_firmware.zx32.s" --format c --c-type u32 --array-name zx32_linux_boot_firmware_program
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/ps_bram_load.elf" --array-name zx32_ps_bram_load_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/xcpyw_check.elf" --array-name zx32_xcpyw_check_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/custom_datamover.elf" --array-name zx32_custom_datamover_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/entry_smoke.elf" --array-name zx32_entry_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/machine_trap_smoke.elf" --array-name zx32_machine_trap_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/supervisor_smoke.elf" --array-name zx32_supervisor_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/supervisor_timer_smoke.elf" --array-name zx32_supervisor_timer_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/boot_payload_smoke.elf" --array-name zx32_boot_payload_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/supervisor_counter_smoke.elf" --array-name zx32_supervisor_counter_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/ddr_access_smoke.elf" --array-name zx32_ddr_access_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/ddr_exec_smoke.elf" --array-name zx32_ddr_exec_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/ddr_high_amo_smoke.elf" --array-name zx32_ddr_high_amo_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/sbi_firmware_smoke.elf" --array-name zx32_sbi_firmware_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/sbi_payload_smoke.elf" --array-name zx32_sbi_payload_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/sbi_timer_firmware_smoke.elf" --array-name zx32_sbi_timer_firmware_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/sbi_timer_payload_smoke.elf" --array-name zx32_sbi_timer_payload_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/linux_contract_firmware_smoke.elf" --array-name zx32_linux_contract_firmware_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/linux_contract_payload_smoke.elf" --array-name zx32_linux_contract_payload_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/linux_image_layout_smoke.elf" --array-name zx32_linux_image_layout_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/linux_sbi_firmware_smoke.elf" --array-name zx32_linux_sbi_firmware_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/linux_sbi_payload_smoke.elf" --array-name zx32_linux_sbi_payload_smoke_elf
  printf '\n'
  python3 "$bin2c" "$build_dir/elf/linux_boot_firmware.elf" --array-name zx32_linux_boot_firmware_elf
  printf '\n#endif\n'
} > "$tmp_header"

mv "$tmp_header" "$gen_dir/zx32_programs.h"
