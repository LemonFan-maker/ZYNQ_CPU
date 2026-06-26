#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_srcs=(
    "$repo_dir/hw_bringup/ps_uart_probe.c"
    "$repo_dir/hw_bringup/ps_uart_probe_common.c"
    "$repo_dir/hw_bringup/ps_uart_probe_dma.c"
    "$repo_dir/hw_bringup/ps_uart_probe_cpu.c"
    "$repo_dir/hw_bringup/ps_uart_probe_sbi.c"
)
linux_boot_srcs=(
    "$repo_dir/hw_bringup/ps_linux_boot.c"
    "$repo_dir/hw_bringup/ps_uart_probe_common.c"
)
build_dir="$repo_dir/hw_bringup/build"
gen_dir="$build_dir/generated"

bsp="/home/orionisli/Working/Zynq_GPGPU/GPU_PS/export/GPU_PS/sw/standalone_ps7_cortexa9_0"
linker="/home/orionisli/Working/Zynq_GPGPU/gpu_app/src/lscript.ld"
tool_base="/mnt/c9484bc0-c4b3-443c-8378-d72c9f78d3d8/Programs/FPGA/AMD_2025.2/2025.2/Vitis/gnu/aarch32/lin/gcc-arm-none-eabi/bin"

mkdir -p "$build_dir"
"$repo_dir/scripts/build_zx32_programs.sh"

build_elf() {
    local elf="$1"
    shift
    local cmd
    local src

    cmd="source /home/orionisli/.zshrc >/dev/null 2>&1 && vi25 && $(printf '%q' "$tool_base/arm-none-eabi-gcc")"
    cmd+=" -DSDT -O2 -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard"
    if [[ -n "${PS_UART_PROBE_CFLAGS:-}" ]]; then
        cmd+=" $PS_UART_PROBE_CFLAGS"
    fi
    cmd+=" -specs=$(printf '%q' "$bsp/Xilinx.spec")"
    cmd+=" -I$(printf '%q' "$gen_dir")"
    cmd+=" -I$(printf '%q' "$repo_dir/hw_bringup")"
    cmd+=" -I$(printf '%q' "$bsp/include")"
    cmd+=" -Wl,-T -Wl,$(printf '%q' "$linker")"
    for src in "$@"; do
        cmd+=" $(printf '%q' "$src")"
    done
    cmd+=" -L$(printf '%q' "$bsp/lib")"
    cmd+=" -Wl,--start-group -lxilstandalone -lxiltimer -lxil -lgcc -lc -Wl,--end-group"
    cmd+=" -o $(printf '%q' "$elf")"

    zsh -lc "$cmd"
    zsh -lc "source /home/orionisli/.zshrc >/dev/null 2>&1 && vi25 && $(printf '%q' "$tool_base/arm-none-eabi-size") $(printf '%q' "$elf")"
}

build_elf "$build_dir/ps_uart_probe.elf" "${probe_srcs[@]}"
build_elf "$build_dir/ps_linux_boot.elf" "${linux_boot_srcs[@]}"
