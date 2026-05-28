#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linux_out="${LINUX_OUT:-$repo_dir/build/linux-mainline-rv32}"
image="${LINUX_IMAGE:-$linux_out/arch/riscv/boot/Image}"
dtb_src="${LINUX_DTS:-$repo_dir/linux/zynq_cpu.dts}"
artifact_dir="${LINUX_ARTIFACT_DIR:-$repo_dir/build/linux}"
dtb_out="${LINUX_DTB:-$artifact_dir/zynq_cpu.dtb}"
sim_dtb_src="${LINUX_SIM_DTS:-$repo_dir/linux/zx32sim_virtio.dts}"
sim_dtb_out="${LINUX_SIM_DTB:-$artifact_dir/zx32sim_virtio.dtb}"
manifest="$artifact_dir/boot_artifacts.env"

kernel_cpu_addr="0x80400000"
kernel_ps_addr="0x00500000"
dtb_cpu_addr="0x81600000"
dtb_ps_addr="0x01700000"

if [[ ! -f "$image" ]]; then
    echo "Linux Image not found: $image" >&2
    echo "Run scripts/build_mainline_rv32_linux.sh first." >&2
    exit 2
fi

if ! command -v dtc >/dev/null 2>&1; then
    echo "dtc not found in PATH." >&2
    exit 2
fi

mkdir -p "$artifact_dir"
dtc -I dts -O dtb -o "$dtb_out" "$dtb_src"
if [[ -f "$sim_dtb_src" ]]; then
    dtc -I dts -O dtb -o "$sim_dtb_out" "$sim_dtb_src"
fi

text_offset="$(od -An -t x8 -j 8 -N 8 "$image" | tr -d '[:space:]')"
magic="$(od -An -t x1 -j 48 -N 8 "$image" | tr -d '[:space:]')"
magic2="$(od -An -t x1 -j 56 -N 4 "$image" | tr -d '[:space:]')"
image_size="$(stat -c '%s' "$image")"
dtb_magic="$(od -An -t x1 -N 4 "$dtb_out" | tr -d '[:space:]')"
kernel_ps_end_dec=$((kernel_ps_addr + image_size))
dtb_ps_dec=$((dtb_ps_addr))

if [[ "$text_offset" != "0000000000400000" ]]; then
    echo "Unexpected RISC-V Image text_offset: 0x$text_offset" >&2
    exit 1
fi

if [[ "$magic" != "5249534356000000" || "$magic2" != "52534305" ]]; then
    echo "Unexpected RISC-V Image magic: $magic / $magic2" >&2
    exit 1
fi

if [[ "$dtb_magic" != "d00dfeed" ]]; then
    echo "Unexpected DTB magic: $dtb_magic" >&2
    exit 1
fi

if (( kernel_ps_end_dec > dtb_ps_dec )); then
    printf 'Linux Image overlaps DTB placement: kernel PS end 0x%08x, DTB PS 0x%08x\n' \
        "$kernel_ps_end_dec" "$dtb_ps_dec" >&2
    exit 1
fi

cat > "$manifest" <<EOF
LINUX_IMAGE=$image
LINUX_DTB=$dtb_out
KERNEL_CPU_ADDR=$kernel_cpu_addr
KERNEL_PS_ADDR=$kernel_ps_addr
DTB_CPU_ADDR=$dtb_cpu_addr
DTB_PS_ADDR=$dtb_ps_addr
LINUX_SIM_DTB=$sim_dtb_out
EOF

echo "Linux Image: $image"
echo "Linux DTB: $dtb_out"
if [[ -f "$sim_dtb_out" ]]; then
    echo "Linux simulator DTB: $sim_dtb_out"
fi
echo "Image size: $image_size bytes"
echo "Kernel: CPU $kernel_cpu_addr -> PS $kernel_ps_addr"
echo "DTB: CPU $dtb_cpu_addr -> PS $dtb_ps_addr"
echo "Manifest: $manifest"
