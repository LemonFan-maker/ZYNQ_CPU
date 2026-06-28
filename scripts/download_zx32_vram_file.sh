#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <xrgb8888.raw> [ps_addr]" >&2
    echo "default ps_addr is 0x3c000000, the PS alias for CPU VRAM 0xbc000000" >&2
    exit 2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input="$1"
ps_addr="${2:-0x3c000000}"
vram_bytes=$((64 * 1024 * 1024))

if [[ ! -f "$input" ]]; then
    echo "input file not found: $input" >&2
    exit 2
fi

size="$(stat -c '%s' "$input")"
if (( size > vram_bytes )); then
    echo "input is $size bytes, exceeds 64 MiB VRAM" >&2
    exit 1
fi

case "$input" in
    /*) abs_input="$input" ;;
    *) abs_input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")" ;;
esac

mkdir -p "$repo_dir/build/xsct"
script="$repo_dir/build/xsct/download_zx32_vram_file.xsbl"
cat > "$script" <<EOF
connect
targets -set -filter {name =~ "ARM*#0"}
dow -data [file normalize "$abs_input"] $ps_addr
EOF

echo "Downloading $abs_input ($size bytes) to PS $ps_addr"
"$repo_dir/scripts/run_xsct.sh" "$script"
