#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linux_out="${LINUX_OUT:-$repo_dir/build/linux-mainline-rv64}"
image="${LINUX_IMAGE:-$linux_out/arch/riscv/boot/Image}"
kernel_release_file="$linux_out/include/config/kernel.release"
linux_src="${LINUX_SRC:-$repo_dir/linux/kernel-v7.1.3}"
linux_tag="${LINUX_TAG:-v7.1.3}"
dtb_src="${LINUX_DTS:-$repo_dir/linux/zx64.dts}"
artifact_dir="${LINUX_ARTIFACT_DIR:-$repo_dir/build/linux-rv64}"
dtb_effective_dts="$artifact_dir/zx64.effective.dts"
dtb_out="${LINUX_DTB:-$artifact_dir/zx64.dtb}"
manifest="$artifact_dir/boot_artifacts.env"
ps_launcher="${PS_LINUX_BOOT_ELF:-$repo_dir/hw_bringup/build/ps_linux_boot.elf}"
rootfs="${ZX64_BUILDROOT_CPIO:-$repo_dir/build/buildroot-zx64/images/rootfs.cpio}"
embedded_initramfs="$linux_out/usr/initramfs_inc_data"
default_virtio_rootfs_image="$artifact_dir/zx64-rootfs.ext4"
virtio_blk_image="${ZX64_VIRTIO_BLK_IMAGE-}"
virtio_blk_image_auto=0
simplefb_enable="${ZX64_SIMPLEFB:-1}"
virtio_input_enable="${ZX64_VIRTIO_INPUT:-1}"
initramfs_bootargs="earlycon=sbi console=hvc0 rdinit=/init lpj=10000 loglevel=7 ignore_loglevel"
virtio_root_bootargs="earlycon=sbi console=hvc0 root=/dev/vda rw rootwait lpj=10000 loglevel=7 ignore_loglevel"
dtb_bootargs="$initramfs_bootargs"

case "${virtio_blk_image,,}" in
    off|none|disabled|0)
        virtio_blk_image=""
        ;;
    "")
        if [[ -z "${ZX64_VIRTIO_BLK_IMAGE+x}" && -f "$default_virtio_rootfs_image" ]]; then
            virtio_blk_image="$default_virtio_rootfs_image"
            virtio_blk_image_auto=1
        fi
        ;;
esac

case "${simplefb_enable,,}" in
    off|none|disabled|0)
        simplefb_enable=0
        ;;
    *)
        simplefb_enable=1
        ;;
esac

case "${virtio_input_enable,,}" in
    off|none|disabled|0)
        virtio_input_enable=0
        ;;
    *)
        virtio_input_enable=1
        ;;
esac

dram_cpu_base=$((0x80000000))
kernel_ps_addr="${KERNEL_PS_ADDR:-0x00200000}"
dtb_cpu_addr="${DTB_CPU_ADDR:-0x82000000}"
dtb_ps_addr="${DTB_PS_ADDR:-0x02000000}"
boot_backup_ps_addr=$((0x04100000))
boot_backup_bytes=$((0x01300000))
vram_ps_addr=$((0x3c000000))
virtio_blk_ps_addr="0x08000000"
virtio_blk_cpu_addr="0x88000000"
virtio_blk_meta_ps_addr="0x07fff000"
virtio_blk_meta_magic="0x5A363442"
virtio_blk_max_bytes=$((0x04000000))
virtio_blk_reserve_bytes=$virtio_blk_max_bytes
virtio_blk_reserve_hex="$(printf '0x%08x' "$virtio_blk_reserve_bytes")"

if [[ ! -f "$image" ]]; then
    echo "Linux Image not found: $image" >&2
    echo "Run scripts/prepare_mainline_rv64_linux.sh first." >&2
    exit 2
fi

if [[ ! -f "$kernel_release_file" ]]; then
    echo "Linux kernel release file not found: $kernel_release_file" >&2
    echo "Run scripts/prepare_mainline_rv64_linux.sh first." >&2
    exit 2
fi

if ! command -v dtc >/dev/null 2>&1; then
    echo "dtc not found in PATH." >&2
    exit 2
fi

if ! command -v perl >/dev/null 2>&1; then
    echo "perl not found in PATH." >&2
    exit 2
fi

if [[ ! -f "$ps_launcher" ]]; then
    echo "PS Linux boot launcher not found: $ps_launcher" >&2
    echo "Run scripts/build_ps_linux_boot_rv64.sh first." >&2
    exit 2
fi

if [[ ! -f "$rootfs" ]]; then
    echo "Buildroot rootfs not found: $rootfs" >&2
    echo "Run scripts/build_zx64_busybox_rootfs.sh first." >&2
    exit 2
fi

if [[ ! -f "$embedded_initramfs" ]]; then
    echo "Embedded Linux initramfs copy not found: $embedded_initramfs" >&2
    echo "Rebuild the RV64 Linux Image after updating the rootfs." >&2
    exit 2
fi

mkdir -p "$artifact_dir"
cp "$dtb_src" "$dtb_effective_dts"
dtb_storage_mode="initramfs"
dtb_display_mode="none"
dtb_input_mode="none"
if [[ "$simplefb_enable" == "1" ]]; then
    dtb_display_mode="simple-framebuffer"
    perl -0pi -e 's/(zx64_simplefb:\s*framebuffer\@bc000000\s*\{.*?status\s*=\s*")disabled(";.*?\n\s*\};)/${1}okay$2/s or die "failed to enable zx64_simplefb in effective DTS\n"' "$dtb_effective_dts"
fi
if [[ -n "$virtio_blk_image" || "$virtio_input_enable" == "1" ]]; then
    perl -0pi -e 's/(plic0:\s*interrupt-controller\@c000000\s*\{.*?status\s*=\s*")disabled(";.*?\n\s*\};)/${1}okay$2/s or die "failed to enable plic0 in effective DTS\n"' "$dtb_effective_dts"
fi
if [[ -n "$virtio_blk_image" ]]; then
    dtb_storage_mode="virtio-blk"
    dtb_bootargs="$virtio_root_bootargs"
    perl -0pi -e 's/(virtio_blk0:\s*virtio\@10060000\s*\{.*?status\s*=\s*")disabled(";.*?\n\s*\};)/${1}okay$2/s or die "failed to enable virtio_blk0 in effective DTS\n"' "$dtb_effective_dts"
    perl -0pi -e 's/(chosen\s*\{.*?bootargs\s*=\s*")[^"]*(";)/${1}earlycon=sbi console=hvc0 root=\/dev\/vda rw rootwait lpj=10000 loglevel=7 ignore_loglevel$2/s or die "failed to switch effective DTS bootargs to virtio root\n"' "$dtb_effective_dts"
    perl -0pi -e 's/(boot_artifacts_backup:\s*boot-artifacts\@84100000\s*\{.*?\n\s*\};\n)/$1\n        zx64_virtio_blk_image: virtio-blk-image\@88000000 {\n            reg = <0x0 0x88000000 0x0 0x04000000>;\n            no-map;\n        };\n/s or die "failed to reserve ZX64 virtio block backing image in effective DTS\n"' "$dtb_effective_dts"
fi
if [[ "$virtio_input_enable" == "1" ]]; then
    dtb_input_mode="virtio-input"
    perl -0pi -e 's/(virtio_input0:\s*virtio\@10090000\s*\{.*?status\s*=\s*")disabled(";.*?\n\s*\};)/${1}okay$2/s or die "failed to enable virtio_input0 in effective DTS\n"' "$dtb_effective_dts"
fi
dtc -I dts -O dtb -o "$dtb_out" "$dtb_effective_dts"

text_offset_hex="$(od -An -t x8 -j 8 -N 8 "$image" | tr -d '[:space:]')"
code0="$(od -An -t x4 -j 0 -N 4 "$image" | tr -d '[:space:]')"
magic="$(od -An -t x1 -j 48 -N 8 "$image" | tr -d '[:space:]')"
magic2="$(od -An -t x1 -j 56 -N 4 "$image" | tr -d '[:space:]')"
image_size="$(stat -c '%s' "$image")"
dtb_magic="$(od -An -t x1 -N 4 "$dtb_out" | tr -d '[:space:]')"
text_offset_dec=$((16#$text_offset_hex))
kernel_cpu_dec=$((dram_cpu_base + text_offset_dec))
kernel_cpu_addr="$(printf '0x%08x' "$kernel_cpu_dec")"
kernel_ps_dec=$((kernel_ps_addr))
dtb_ps_dec=$((dtb_ps_addr))
kernel_ps_end_dec=$((kernel_ps_dec + image_size))
kernel_release="$(<"$kernel_release_file")"
linux_commit="unknown"
linux_src_real="$(readlink -f "$linux_src")"
linux_build_source_real=""
linux_source_clean=unknown
image_real="$(readlink -f "$image")"
dtb_src_real="$(readlink -f "$dtb_src")"
dtb_effective_real="$(readlink -f "$dtb_effective_dts")"
dtb_real="$(readlink -f "$dtb_out")"
ps_launcher_real="$(readlink -f "$ps_launcher")"
image_sha256="$(sha256sum "$image" | awk '{print $1}')"
dtb_src_size="$(stat -c '%s' "$dtb_src")"
dtb_src_sha256="$(sha256sum "$dtb_src" | awk '{print $1}')"
dtb_effective_size="$(stat -c '%s' "$dtb_effective_dts")"
dtb_effective_sha256="$(sha256sum "$dtb_effective_dts" | awk '{print $1}')"
dtb_size="$(stat -c '%s' "$dtb_out")"
dtb_sha256="$(sha256sum "$dtb_out" | awk '{print $1}')"
ps_launcher_size="$(stat -c '%s' "$ps_launcher")"
ps_launcher_sha256="$(sha256sum "$ps_launcher" | awk '{print $1}')"
rootfs_real="$(readlink -f "$rootfs")"
rootfs_size="$(stat -c '%s' "$rootfs")"
rootfs_sha256="$(sha256sum "$rootfs" | awk '{print $1}')"
embedded_initramfs_size="$(stat -c '%s' "$embedded_initramfs")"
embedded_initramfs_sha256="$(sha256sum "$embedded_initramfs" | awk '{print $1}')"
virtio_blk_image_real=""
virtio_blk_image_size=0
virtio_blk_image_sha256=""
virtio_blk_capacity_sectors=0
virtio_blk_rootfs_ext4=0
virtio_blk_ps_dec=$((virtio_blk_ps_addr))
virtio_blk_cpu_dec=$((virtio_blk_cpu_addr))
virtio_blk_ps_end_dec=$virtio_blk_ps_dec

ranges_overlap() {
    local start_a="$1"
    local end_a="$2"
    local start_b="$3"
    local end_b="$4"

    (( start_a < end_b && start_b < end_a ))
}

if [[ "$kernel_release" != "7.1.3" ]]; then
    echo "Unexpected Linux kernel release: $kernel_release" >&2
    echo "Expected 7.1.3 from $kernel_release_file." >&2
    exit 1
fi

if [[ -d "$linux_src/.git" ]]; then
    tag_commit="$(git -C "$linux_src" rev-parse --verify "$linux_tag^{commit}")"
    head_commit="$(git -C "$linux_src" rev-parse --verify HEAD)"
    if [[ "$head_commit" != "$tag_commit" ]]; then
        echo "Linux source HEAD is not exactly $linux_tag: $linux_src" >&2
        exit 1
    fi
    if [[ -n "$(git -C "$linux_src" status --porcelain)" ]]; then
        echo "Linux source worktree is dirty: $linux_src" >&2
        exit 1
    fi
    linux_commit="$head_commit"
    linux_source_clean=1
fi

if [[ -e "$linux_out/source" ]]; then
    linux_build_source_real="$(readlink -f "$linux_out/source")"
    if [[ "$linux_build_source_real" != "$linux_src_real" ]]; then
        echo "Linux build output source symlink does not point at $linux_src_real: $linux_build_source_real" >&2
        exit 1
    fi
else
    echo "Linux build output source symlink is missing: $linux_out/source" >&2
    exit 1
fi

if [[ "$text_offset_hex" != "0000000000200000" ]]; then
    echo "Unexpected RV64 RISC-V Image text_offset: 0x$text_offset_hex" >&2
    echo "Expected 0x0000000000200000, which maps the kernel to CPU $kernel_cpu_addr." >&2
    exit 1
fi

case "$code0" in
    0c40006f|0000a0d1)
        ;;
    *)
        echo "Unexpected RV64 RISC-V Image first word: 0x$code0" >&2
        exit 1
        ;;
esac

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

if [[ -n "$virtio_blk_image" ]]; then
    if [[ ! -f "$virtio_blk_image" ]]; then
        echo "ZX64 virtio block image not found: $virtio_blk_image" >&2
        exit 2
    fi

    virtio_blk_image_real="$(readlink -f "$virtio_blk_image")"
    virtio_blk_image_size="$(stat -c '%s' "$virtio_blk_image")"
    virtio_blk_image_sha256="$(sha256sum "$virtio_blk_image" | awk '{print $1}')"
    virtio_blk_capacity_sectors=$((virtio_blk_image_size / 512))
    virtio_blk_ps_end_dec=$((virtio_blk_ps_dec + virtio_blk_image_size))

    if (( virtio_blk_image_size == 0 || (virtio_blk_image_size % 512) != 0 )); then
        echo "ZX64 virtio block image size must be a non-zero multiple of 512 bytes: $virtio_blk_image_size" >&2
        exit 1
    fi
    if (( virtio_blk_image_size > virtio_blk_max_bytes )); then
        printf 'ZX64 virtio block image exceeds max size: %u > %u\n' \
            "$virtio_blk_image_size" "$virtio_blk_max_bytes" >&2
        exit 1
    fi
    if (( virtio_blk_cpu_dec != dram_cpu_base + virtio_blk_ps_dec )); then
        printf 'ZX64 virtio block CPU/PS address mismatch: CPU 0x%08x PS 0x%08x\n' \
            "$virtio_blk_cpu_dec" "$virtio_blk_ps_dec" >&2
        exit 1
    fi
    if (( virtio_blk_ps_end_dec <= virtio_blk_ps_dec || virtio_blk_ps_end_dec > vram_ps_addr )); then
        printf 'ZX64 virtio block image outside non-VRAM DDR window: PS 0x%08x..0x%08x\n' \
            "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" >&2
        exit 1
    fi
    if ranges_overlap "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" \
                      "$kernel_ps_dec" "$kernel_ps_end_dec"; then
        printf 'ZX64 virtio block image overlaps kernel Image: disk PS 0x%08x..0x%08x kernel PS 0x%08x..0x%08x\n' \
            "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" "$kernel_ps_dec" "$kernel_ps_end_dec" >&2
        exit 1
    fi
    if ranges_overlap "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" \
                      "$dtb_ps_dec" "$((dtb_ps_dec + dtb_size))"; then
        printf 'ZX64 virtio block image overlaps DTB: disk PS 0x%08x..0x%08x DTB PS 0x%08x..0x%08x\n' \
            "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" "$dtb_ps_dec" "$((dtb_ps_dec + dtb_size))" >&2
        exit 1
    fi
    if ranges_overlap "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" \
                      "$boot_backup_ps_addr" "$((boot_backup_ps_addr + boot_backup_bytes))"; then
        printf 'ZX64 virtio block image overlaps boot artifact backup: disk PS 0x%08x..0x%08x backup PS 0x%08x..0x%08x\n' \
            "$virtio_blk_ps_dec" "$virtio_blk_ps_end_dec" \
            "$boot_backup_ps_addr" "$((boot_backup_ps_addr + boot_backup_bytes))" >&2
        exit 1
    fi

    if ! command -v debugfs >/dev/null 2>&1; then
        echo "debugfs not found in PATH; cannot verify ZX64 virtio ext4 rootfs image." >&2
        exit 2
    fi
    if debugfs -R 'stat /sbin/init' "$virtio_blk_image" >/dev/null 2>&1 &&
       debugfs -R 'stat /bin/busybox' "$virtio_blk_image" >/dev/null 2>&1; then
        virtio_blk_rootfs_ext4=1
    else
        echo "ZX64 virtio block image is not a verified ext4 rootfs with /sbin/init and /bin/busybox: $virtio_blk_image" >&2
        exit 1
    fi
fi

if [[ "$embedded_initramfs_size" != "$rootfs_size" || "$embedded_initramfs_sha256" != "$rootfs_sha256" ]]; then
    echo "Linux Image embedded initramfs does not match current rootfs.cpio." >&2
    echo "Re-run scripts/prepare_mainline_rv64_linux.sh after rebuilding the rootfs." >&2
    exit 1
fi

cat > "$manifest" <<EOF
LINUX_TAG=$linux_tag
LINUX_RELEASE=$kernel_release
LINUX_SOURCE=$linux_src_real
LINUX_BUILD_SOURCE=$linux_build_source_real
LINUX_SOURCE_COMMIT=$linux_commit
LINUX_SOURCE_CLEAN=$linux_source_clean
LINUX_IMAGE=$image_real
LINUX_IMAGE_SIZE=$image_size
LINUX_IMAGE_SHA256=$image_sha256
LINUX_DTS_SOURCE=$dtb_src_real
LINUX_DTS_SOURCE_SIZE=$dtb_src_size
LINUX_DTS_SOURCE_SHA256=$dtb_src_sha256
LINUX_DTS_EFFECTIVE=$dtb_effective_real
LINUX_DTS_EFFECTIVE_SIZE=$dtb_effective_size
LINUX_DTS_EFFECTIVE_SHA256=$dtb_effective_sha256
LINUX_DTB_STORAGE_MODE=$dtb_storage_mode
LINUX_DTB_DISPLAY_MODE=$dtb_display_mode
LINUX_DTB_INPUT_MODE=$dtb_input_mode
LINUX_DTB_BOOTARGS=$dtb_bootargs
LINUX_DTB=$dtb_real
LINUX_DTB_SIZE=$dtb_size
LINUX_DTB_SHA256=$dtb_sha256
ROOTFS_CPIO=$rootfs_real
ROOTFS_CPIO_SIZE=$rootfs_size
ROOTFS_CPIO_SHA256=$rootfs_sha256
LINUX_EMBEDDED_INITRAMFS_SIZE=$embedded_initramfs_size
LINUX_EMBEDDED_INITRAMFS_SHA256=$embedded_initramfs_sha256
PS_LINUX_BOOT_ELF=$ps_launcher_real
PS_LINUX_BOOT_ELF_SIZE=$ps_launcher_size
PS_LINUX_BOOT_ELF_SHA256=$ps_launcher_sha256
KERNEL_CPU_ADDR=$kernel_cpu_addr
KERNEL_PS_ADDR=$kernel_ps_addr
KERNEL_IMAGE_CODE0=0x$code0
KERNEL_TEXT_OFFSET=0x$text_offset_hex
DTB_CPU_ADDR=$dtb_cpu_addr
DTB_PS_ADDR=$dtb_ps_addr
ZX64_VIRTIO_BLK_IMAGE_PRESENT=$([[ -n "$virtio_blk_image" ]] && echo 1 || echo 0)
ZX64_VIRTIO_BLK_IMAGE_AUTO=$virtio_blk_image_auto
ZX64_VIRTIO_BLK_IMAGE_META_PS_ADDR=$virtio_blk_meta_ps_addr
ZX64_VIRTIO_BLK_IMAGE_META_MAGIC=$virtio_blk_meta_magic
ZX64_VIRTIO_BLK_IMAGE_MAX_BYTES=$virtio_blk_max_bytes
ZX64_VIRTIO_BLK_IMAGE_RESERVE_CPU_ADDR=$virtio_blk_cpu_addr
ZX64_VIRTIO_BLK_IMAGE_RESERVE_BYTES=$virtio_blk_reserve_bytes
ZX64_VIRTIO_BLK_IMAGE_RESERVE_HEX=$virtio_blk_reserve_hex
EOF

if [[ -n "$virtio_blk_image" ]]; then
    cat >> "$manifest" <<EOF
ZX64_VIRTIO_BLK_IMAGE=$virtio_blk_image_real
ZX64_VIRTIO_BLK_IMAGE_SIZE=$virtio_blk_image_size
ZX64_VIRTIO_BLK_IMAGE_SHA256=$virtio_blk_image_sha256
ZX64_VIRTIO_BLK_CAPACITY_SECTORS=$virtio_blk_capacity_sectors
ZX64_VIRTIO_BLK_CPU_ADDR=$virtio_blk_cpu_addr
ZX64_VIRTIO_BLK_PS_ADDR=$virtio_blk_ps_addr
ZX64_VIRTIO_BLK_ROOTFS_EXT4=$virtio_blk_rootfs_ext4
EOF
fi

echo "Linux Image: $image"
echo "Linux DTB: $dtb_out"
echo "Linux release: $kernel_release"
echo "Linux commit: $linux_commit"
echo "Image size: $image_size bytes"
echo "Rootfs: $rootfs"
echo "Rootfs size: $rootfs_size bytes"
echo "Launcher: $ps_launcher"
echo "Launcher size: $ps_launcher_size bytes"
echo "Image code0: 0x$code0"
echo "Image text offset: 0x$text_offset_hex"
echo "Kernel: CPU $kernel_cpu_addr -> PS $kernel_ps_addr"
echo "DTB: CPU $dtb_cpu_addr -> PS $dtb_ps_addr"
if [[ -n "$virtio_blk_image" ]]; then
    echo "Virtio block image: $virtio_blk_image"
    echo "Virtio block size: $virtio_blk_image_size bytes ($virtio_blk_capacity_sectors sectors)"
    echo "Virtio block: CPU $virtio_blk_cpu_addr -> PS $virtio_blk_ps_addr"
else
    echo "Virtio block image: disabled"
fi
echo "Manifest: $manifest"
