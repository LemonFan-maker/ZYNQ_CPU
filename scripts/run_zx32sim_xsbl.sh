#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firmware="$repo_dir/hw_bringup/build/elf/linux_boot_firmware.elf"

if [[ $# -gt 0 && "$1" != "--" ]]; then
    xsbl="$1"
    shift
else
    xsbl="$repo_dir/hw_bringup/download_zynq_cpu_linux_boot.xsbl"
fi

if [[ ! -f "$firmware" ]]; then
    python3 "$repo_dir/tools/zx32elf.py" \
        "$repo_dir/hw_bringup/programs/linux_boot_firmware.zx32.s" \
        -o "$firmware" \
        --load-addr 0x0
fi

interactive="${ZX32SIM_INTERACTIVE:-0}"
if [[ "$interactive" == "0" ]]; then
    steps="${ZX32SIM_LINUX_STEPS:-150000000}"
    stop_console="${ZX32SIM_STOP_CONSOLE:-buildroot login:}"
else
    steps="${ZX32SIM_LINUX_STEPS:-1000000000000}"
    stop_console="${ZX32SIM_STOP_CONSOLE:-}"
fi
stop_check_interval="${ZX32SIM_STOP_CHECK_INTERVAL:-1000000}"
console_input="${ZX32SIM_CONSOLE_INPUT:-}"
console_input_file="${ZX32SIM_CONSOLE_INPUT_FILE:-}"
console_script="${ZX32SIM_CONSOLE_SCRIPT:-}"
expect_linux_head="${ZX32SIM_EXPECT_LINUX_HEAD:-1}"

cmd=(python3 -m tools.zx32sim.xsbl
    --repo-dir "$repo_dir"
    --firmware "$firmware"
    "$xsbl"
    --
    --max-steps "$steps"
    --dump-word 0x20010240
    --dump-word 0x20010244
    --dump-word 0x20010248
    --dump-word 0x20010250
    --dump-word 0x20010254
    --dump-word 0x20010308
    --dump-word 0x2001030c
    --dump-word 0x2001021c
    --dump-word 0x20010200
    --dump-console-ring
    --continue-on-wfi
    --stop-check-interval "$stop_check_interval")

if [[ "$expect_linux_head" != "0" ]]; then
    cmd+=(--expect-word 0x20010240=0x4c0de00f)
fi

if [[ -n "$stop_console" ]]; then
    cmd+=(--stop-console "$stop_console")
fi

if [[ "$interactive" != "0" ]]; then
    cmd+=(--interactive-console)
fi

if [[ -n "$console_input" ]]; then
    cmd+=(--console-input "$console_input")
fi

if [[ -n "$console_input_file" ]]; then
    cmd+=(--console-input-file "$console_input_file")
fi

if [[ -n "$console_script" ]]; then
    cmd+=(--console-script "$console_script")
fi

if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--" ]]; then
        shift
    fi
    cmd+=("$@")
fi

cd "$repo_dir"
exec "${cmd[@]}"
