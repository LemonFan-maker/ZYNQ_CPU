#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
br_out="${BUILDROOT_OUT:-$repo_dir/build/buildroot-zx32}"
tc_dir="$br_out/host/bin"
cc="$tc_dir/riscv32-buildroot-linux-musl-gcc"
strip="$tc_dir/riscv32-buildroot-linux-musl-strip"
overlay_dir="$repo_dir/build/zx32-buildroot/overlay"
include_dir="$repo_dir/hw_bringup/userspace/include"

if [[ ! -x "$cc" ]]; then
    echo "Buildroot riscv32 musl toolchain not found at $cc" >&2
    echo "Run scripts/build_zx32_busybox_rootfs.sh first." >&2
    exit 2
fi

mkdir -p "$overlay_dir/usr/bin"

build_one() {
    local src="$1"
    local out="$2"
    echo "Compiling $src -> $out"
    "$cc" -O2 -static -Wall -Wextra -I "$include_dir" -o "$out" "$src"
    "$strip" "$out" || true
}

build_one "$repo_dir/hw_bringup/userspace/gpu_top/zx32_nvtop.c" \
          "$overlay_dir/usr/bin/zx32_nvtop"
build_one "$repo_dir/hw_bringup/userspace/fastfetch/zx32_fastfetch.c" \
          "$overlay_dir/usr/bin/zx32_fastfetch"
build_one "$repo_dir/hw_bringup/userspace/sysmon/zx32_temp.c" \
          "$overlay_dir/usr/bin/zx32_temp"

echo "Done."
