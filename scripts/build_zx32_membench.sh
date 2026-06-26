#!/usr/bin/env bash
# Build the zx32 userspace memory benchmark using the Buildroot riscv32 musl toolchain
# and place the static binary into the rootfs overlay so the next Buildroot rebuild
# picks it up.
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

src="$repo_dir/hw_bringup/userspace/membench/zx32_membench.c"
overlay_dir="$repo_dir/build/zx32-buildroot/overlay"
mkdir -p "$overlay_dir/usr/bin"
out="$overlay_dir/usr/bin/zx32_membench"

echo "Compiling $src -> $out"
"$cc" -O2 -static -Wall -Wextra -o "$out" "$src"
"$tc_dir"/riscv32-buildroot-linux-musl-strip "$out" || true

echo "Done. Now rebuild rootfs and kernel:"
echo "  ./scripts/build_zx32_busybox_rootfs.sh"
echo "  ./scripts/build_mainline_rv32_linux.sh"
echo "  ./scripts/prepare_linux_boot_artifacts.sh"
echo "  ./scripts/build_ps_uart_probe.sh"
