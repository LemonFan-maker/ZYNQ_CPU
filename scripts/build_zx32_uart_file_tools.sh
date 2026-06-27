#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
br_out="${BUILDROOT_OUT:-$repo_dir/build/buildroot-zx32}"
tc_dir="$br_out/host/bin"
target_cc="$tc_dir/riscv32-buildroot-linux-musl-gcc"
host_cc="${HOST_CC:-cc}"

if [[ ! -x "$target_cc" ]]; then
    echo "Buildroot riscv32 musl toolchain not found at $target_cc" >&2
    echo "Run scripts/build_zx32_busybox_rootfs.sh first." >&2
    exit 2
fi

overlay_dir="$repo_dir/build/zx32-buildroot/overlay"
host_out_dir="$repo_dir/build/host-tools"
mkdir -p "$overlay_dir/usr/bin" "$host_out_dir"

board_src="$repo_dir/hw_bringup/userspace/uart_file/zx32_uart_send.c"
board_out="$overlay_dir/usr/bin/zx32_uart_send"
host_src="$repo_dir/tools/zx32_uart_recv.c"
host_out="$host_out_dir/zx32_uart_recv"
decode_src="$repo_dir/tools/zx32_uart_decode.c"
decode_out="$host_out_dir/zx32_uart_decode"

echo "Compiling board sender $board_src -> $board_out"
"$target_cc" -O2 -static -Wall -Wextra -o "$board_out" "$board_src"
"$tc_dir"/riscv32-buildroot-linux-musl-strip "$board_out" || true

echo "Compiling host receiver $host_src -> $host_out"
"$host_cc" -O2 -Wall -Wextra -o "$host_out" "$host_src"

echo "Compiling host log decoder $decode_src -> $decode_out"
"$host_cc" -O2 -Wall -Wextra -o "$decode_out" "$decode_src"

echo "Done."
echo "Host receiver:"
echo "  $host_out"
echo "Host log decoder:"
echo "  $decode_out"
