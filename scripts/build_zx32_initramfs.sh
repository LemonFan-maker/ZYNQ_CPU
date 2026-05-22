#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${ZX32_INIT_SRC:-$repo_dir/linux/initramfs/init.S}"
out_dir="${ZX32_INITRAMFS_OUT:-$repo_dir/build/linux-initramfs}"
prefix="${CROSS_COMPILE:-}"

if [[ -z "$prefix" ]]; then
    for candidate in riscv32-linux-gnu- riscv64-linux-gnu- riscv32-unknown-linux-gnu- riscv64-unknown-linux-gnu-; do
        if command -v "${candidate}as" >/dev/null 2>&1 && command -v "${candidate}ld" >/dev/null 2>&1; then
            prefix="$candidate"
            break
        fi
    done
fi

if [[ -z "$prefix" ]]; then
    echo "No RISC-V assembler/linker found in PATH." >&2
    exit 2
fi

mkdir -p "$out_dir"

"${prefix}as" -march=rv32ima_zicsr_zifencei -mabi=ilp32 "$src" -o "$out_dir/init.o"
"${prefix}ld" -melf32lriscv -nostdlib -static -e _start "$out_dir/init.o" -o "$out_dir/init"

if command -v "${prefix}strip" >/dev/null 2>&1; then
    "${prefix}strip" "$out_dir/init"
fi

cat > "$out_dir/initramfs.list" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
file /init $out_dir/init 0755 0 0
EOF

echo "Initramfs list: $out_dir/initramfs.list"
echo "Init binary: $out_dir/init"
