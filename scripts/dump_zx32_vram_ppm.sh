#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 6 ]]; then
    echo "usage: $0 <out.ppm> <width> <height> [out_width] [out_height] [ps_addr]" >&2
    echo "default ps_addr is 0x3c000000, the PS alias for CPU VRAM 0xbc000000" >&2
    exit 2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_ppm="$1"
width="$2"
height="$3"
out_width="${4:-}"
out_height="${5:-}"
ps_addr="${6:-0x3c000000}"

if ! [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]; then
    echo "width and height must be decimal integers" >&2
    exit 2
fi
if [[ -n "$out_width" || -n "$out_height" ]]; then
    if ! [[ "$out_width" =~ ^[0-9]+$ && "$out_height" =~ ^[0-9]+$ ]]; then
        echo "out_width and out_height must be decimal integers" >&2
        exit 2
    fi
fi

bytes=$((width * height * 4))
words=$((width * height))
vram_bytes=$((64 * 1024 * 1024))
if (( bytes > vram_bytes )); then
    echo "framebuffer is $bytes bytes, exceeds 64 MiB VRAM" >&2
    exit 1
fi

mkdir -p "$repo_dir/build/xsct" "$repo_dir/build/vram_dump"
raw_out="$repo_dir/build/vram_dump/vram_${width}x${height}.xrgb"
script="$repo_dir/build/xsct/dump_zx32_vram_file.xsbl"
cat > "$script" <<EOF
connect
targets -set -filter {name =~ "ARM*#0"}
mrd -bin -file [file normalize "$raw_out"] $ps_addr $words
EOF

echo "Reading $bytes bytes ($words words) from PS $ps_addr to $raw_out"
"$repo_dir/scripts/run_xsct.sh" "$script"

if [[ -n "$out_width" ]]; then
    python3 "$repo_dir/tools/xrgb_to_ppm.py" "$raw_out" "$out_ppm" "$width" "$height" --out-size "${out_width}x${out_height}"
else
    python3 "$repo_dir/tools/xrgb_to_ppm.py" "$raw_out" "$out_ppm" "$width" "$height"
fi
