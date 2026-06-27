#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
br_out="${BUILDROOT_OUT:-$repo_dir/build/buildroot-zx32}"
tc_dir="$br_out/host/bin"
cc="$tc_dir/riscv32-buildroot-linux-musl-gcc"

if [[ ! -x "$cc" ]]; then
    echo "Buildroot riscv32 musl toolchain not found at $cc" >&2
    echo "Run scripts/build_zx32_busybox_rootfs.sh first." >&2
    exit 2
fi

src="$repo_dir/hw_bringup/userspace/gpu_demo/zx32_gpu_demo.c"
overlay_dir="$repo_dir/build/zx32-buildroot/overlay"
mkdir -p "$overlay_dir/usr/bin"
out="$overlay_dir/usr/bin/zx32_gpu_demo"

echo "Compiling $src -> $out"
"$cc" -O2 -static -Wall -Wextra -o "$out" "$src"
"$tc_dir"/riscv32-buildroot-linux-musl-strip "$out" || true

echo "Done."
