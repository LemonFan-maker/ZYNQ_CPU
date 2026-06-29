#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firmware="$repo_dir/hw_bringup/build/elf/linux_boot_firmware.elf"
image="$repo_dir/build/linux-mainline-rv32/arch/riscv/boot/Image"
dtb="$repo_dir/build/linux/zynq_cpu.dtb"
sim_dtb="$repo_dir/build/linux/zx32sim_virtio.dtb"
system_map="$repo_dir/build/linux-mainline-rv32/System.map"
interactive="${ZX32SIM_INTERACTIVE:-0}"
if [[ "$interactive" == "0" ]]; then
    steps="${ZX32SIM_LINUX_STEPS:-150000000}"
else
    steps="${ZX32SIM_LINUX_STEPS:-1000000000000}"
fi
stop_check_interval="${ZX32SIM_STOP_CHECK_INTERVAL:-1000000}"
block_image="${ZX32SIM_VIRTIO_BLOCK_IMAGE:-}"
console_input="${ZX32SIM_CONSOLE_INPUT:-}"
console_input_file="${ZX32SIM_CONSOLE_INPUT_FILE:-}"
console_script="${ZX32SIM_CONSOLE_SCRIPT:-}"
if [[ "$interactive" == "0" ]]; then
    stop_console="${ZX32SIM_STOP_CONSOLE:-buildroot login:}"
else
    stop_console="${ZX32SIM_STOP_CONSOLE:-}"
fi

if [[ ! -f "$firmware" ]]; then
    python3 "$repo_dir/tools/zx32elf.py" \
        "$repo_dir/hw_bringup/programs/linux_boot_firmware.zx32.s" \
        -o "$firmware" \
        --load-addr 0x0
fi

if [[ ! -f "$image" || ! -f "$dtb" ]]; then
    echo "Linux Image/DTB artifacts are missing." >&2
    echo "Run scripts/build_mainline_rv32_linux.sh and scripts/prepare_linux_boot_artifacts.sh first." >&2
    exit 2
fi

if [[ -n "$block_image" && ! -f "$sim_dtb" ]]; then
    echo "Simulator virtio DTB not found: $sim_dtb" >&2
    echo "Run scripts/prepare_linux_boot_artifacts.sh first." >&2
    exit 2
fi

if [[ -n "$block_image" ]]; then
    dtb="$sim_dtb"
fi

cmd=(python3 -m tools.zx32sim.main "$firmware"
    --load-raw 0x80400000="$image"
    --load-raw 0x82000000="$dtb"
    --max-steps "$steps"
    --poke-word 0x20010300=0x80400000
    --poke-word 0x20010304=0x82000000
    --expect-word 0x20010240=0x4c0de00f
    --expect-word 0x20010308=9
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

if [[ -n "$block_image" ]]; then
    cmd+=(--virtio-block-image "$block_image")
fi

if [[ -f "$system_map" ]]; then
    cmd+=(--symbols "$system_map")
fi

if [[ -n "${ZX32SIM_LINUX_CHECKPOINT_INTERVAL:-}" ]]; then
    cmd+=(--checkpoint-interval "$ZX32SIM_LINUX_CHECKPOINT_INTERVAL")
    cmd+=(--checkpoint-word 0x20010240)
    cmd+=(--checkpoint-word 0x20010308)
    cmd+=(--checkpoint-word 0x20010200)
    cmd+=(--checkpoint-word 0x20010204)
    cmd+=(--checkpoint-word 0x2001020c)
    cmd+=(--checkpoint-word 0x20010104)
fi

if [[ -n "${ZX32SIM_EXTRA_ARGS:-}" ]]; then
    extra_args=($ZX32SIM_EXTRA_ARGS)
    cmd+=("${extra_args[@]}")
fi

"${cmd[@]}"
