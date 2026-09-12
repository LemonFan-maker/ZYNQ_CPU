#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${ZX64_ROOTFS_TARGET:-$repo_dir/build/buildroot-zx64/target}"
artifact_dir="${LINUX_ARTIFACT_DIR:-$repo_dir/build/linux-rv64}"
image="${ZX64_VIRTIO_ROOTFS_IMAGE:-$artifact_dir/zx64-rootfs.ext4}"
size_mib="${ZX64_VIRTIO_ROOTFS_SIZE_MIB:-64}"
label="${ZX64_VIRTIO_ROOTFS_LABEL:-ZX64ROOT}"
uuid="${ZX64_VIRTIO_ROOTFS_UUID:-5a640000-0000-4000-8000-000000000001}"

if [[ ! -d "$target_dir" ]]; then
    echo "Buildroot target directory not found: $target_dir" >&2
    echo "Run scripts/build_zx64_busybox_rootfs.sh first." >&2
    exit 2
fi

if [[ ! -x "$target_dir/sbin/init" ]]; then
    echo "Target rootfs is missing executable /sbin/init: $target_dir" >&2
    exit 1
fi

if [[ ! "$size_mib" =~ ^[0-9]+$ || "$size_mib" -le 0 ]]; then
    echo "ZX64_VIRTIO_ROOTFS_SIZE_MIB must be a positive integer: $size_mib" >&2
    exit 1
fi

if (( size_mib > 64 )); then
    echo "ZX64 virtio rootfs image must fit the current 64 MiB backing window: ${size_mib} MiB" >&2
    exit 1
fi

for cmd in mke2fs e2fsck debugfs truncate; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 2
    fi
done

mkdir -p "$(dirname "$image")"
rm -f "$image"
truncate -s "${size_mib}M" "$image"

mke2fs -q -F -t ext4 \
    -b 4096 \
    -L "$label" \
    -U "$uuid" \
    -m 0 \
    -d "$target_dir" \
    "$image"

e2fsck -fy "$image" >/dev/null

if ! debugfs -R 'stat /sbin/init' "$image" >/dev/null 2>&1; then
    echo "Generated ext4 image is missing /sbin/init: $image" >&2
    exit 1
fi

if ! debugfs -R 'stat /bin/busybox' "$image" >/dev/null 2>&1; then
    echo "Generated ext4 image is missing /bin/busybox: $image" >&2
    exit 1
fi

image_size="$(stat -c '%s' "$image")"
image_sha256="$(sha256sum "$image" | awk '{print $1}')"

echo "ZX64 virtio rootfs ext4: $image"
echo "  source: $target_dir"
echo "  size:   $image_size bytes"
echo "  label:  $label"
echo "  uuid:   $uuid"
echo "  sha256: $image_sha256"
