#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ZX64_VIVADO_VALIDATE_BUILD_DIR:-}"
keep_build_dir="${ZX64_VIVADO_VALIDATE_KEEP:-0}"

if [[ -z "$build_dir" ]]; then
    build_dir="$(mktemp -d /tmp/zx64_vivado_validate.XXXXXX)"
    if [[ "$keep_build_dir" != "1" ]]; then
        trap 'rm -rf "$build_dir"' EXIT
    fi
else
    mkdir -p "$build_dir"
fi

echo "ZX64 Vivado validate-only"
echo "  build: $build_dir"

(
    cd "$repo_dir"
    ZYNQ_CPU_SOC=rv64 \
    ZYNQ_CPU_VALIDATE_ONLY=1 \
    ZYNQ_CPU_VIVADO_BUILD_DIR="$build_dir" \
        ./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
)

bd="$build_dir/zynq_cpu_hw.srcs/sources_1/bd/zynq_cpu_system/zynq_cpu_system.bd"
[[ -f "$bd" ]] || {
    echo "ZX64 Vivado validate failed: missing generated BD: $bd" >&2
    exit 1
}

echo "ZX64 Vivado validate: PASS"
