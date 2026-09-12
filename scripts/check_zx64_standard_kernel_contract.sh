#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

default_icarus_targets=(
    core64-5stage
    soc64-5stage
    soc64-mmio
    soc64-5stage-ddr
    soc64-5stage-sv39
    soc64-5stage-sbi
    soc64-5stage-real-sbi
    soc64-5stage-linux
    plic
    virtio-blk-regs
    virtio-input-regs
)

if [[ -n "${ZX64_STANDARD_KERNEL_ICARUS_TARGETS:-}" ]]; then
    read -r -a icarus_targets <<<"$ZX64_STANDARD_KERNEL_ICARUS_TARGETS"
else
    icarus_targets=("${default_icarus_targets[@]}")
fi

run_step() {
    local name="$1"
    shift

    printf '\n[%s]\n' "$name"
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

cd "$repo_dir"

echo "ZX64/RV64GC standard-kernel contract"
echo "  repo: $repo_dir"

run_step "RV64 SBI firmware" \
    "$repo_dir/scripts/check_zx64_linux_boot_firmware.sh"

run_step "RV64 Linux boot chain" \
    "$repo_dir/scripts/check_zx64_linux_boot_chain.sh"

run_step "Arch/Linux readiness" \
    "$repo_dir/scripts/check_zx64_archlinux_readiness.sh" --strict-distro

run_step "RV64 Vivado hardware validate" \
    "$repo_dir/scripts/check_zx64_vivado_validate.sh"

for target in "${icarus_targets[@]}"; do
    run_step "Icarus $target" \
        "$repo_dir/scripts/run_iverilog_tests.sh" "$target"
done

echo
echo "ZX64/RV64GC standard-kernel contract: PASS"
