#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

br_version="${BUILDROOT_VERSION:-2026.05-rc2}"
br_url="${BUILDROOT_URL:-https://buildroot.org/downloads/buildroot-${br_version}.tar.gz}"
dl_dir="${BUILDROOT_DL_DIR:-$repo_dir/build/downloads}"
src_dir="${BUILDROOT_SRC_DIR:-$repo_dir/build/buildroot-${br_version}}"
out_dir="${BUILDROOT_OUT:-$repo_dir/build/buildroot-zx32}"
work_dir="${ZX32_BUILDROOT_WORK:-$repo_dir/build/zx32-buildroot}"
tarball="$dl_dir/buildroot-${br_version}.tar.gz"
jobs="${JOBS:-$(nproc)}"

# Set ZX32_BUILDROOT_BUILD=0 to stop after download, extraction and .config generation.
do_build="${ZX32_BUILDROOT_BUILD:-1}"
# Set ZX32_BUILDROOT_RECONFIG=0 to preserve an existing Buildroot .config.
do_reconfig="${ZX32_BUILDROOT_RECONFIG:-1}"

mkdir -p "$dl_dir" "$work_dir"

if [[ ! -f "$tarball" ]]; then
    echo "Downloading Buildroot $br_version..."
    curl -L --fail --output "$tarball" "$br_url"
fi

if [[ ! -f "$src_dir/Makefile" ]]; then
    mkdir -p "$(dirname "$src_dir")"
    echo "Extracting Buildroot to $src_dir..."
    tar -C "$(dirname "$src_dir")" -xf "$tarball"
fi

if [[ ! -f "$src_dir/Makefile" ]]; then
    echo "Buildroot source not found after extraction: $src_dir" >&2
    exit 2
fi

overlay_dir="$work_dir/overlay"
busybox_fragment="$work_dir/busybox-zx32.fragment"
mkdir -p "$overlay_dir" "$out_dir"

if [[ "$do_reconfig" != "0" || ! -f "$out_dir/.config" ]]; then
    # The kernel command line currently uses rdinit=/init. Buildroot's BusyBox init
    # lives at /sbin/init, so provide the expected entry point in the initramfs.
    ln -sfn /sbin/init "$overlay_dir/init"

    cat > "$busybox_fragment" <<'EOF'
CONFIG_STATIC=y
CONFIG_ASH=y
CONFIG_SH_IS_ASH=y
CONFIG_FEATURE_SH_STANDALONE=y
CONFIG_FEATURE_EDITING=y
CONFIG_FEATURE_EDITING_HISTORY=64
CONFIG_FEATURE_VI=y
CONFIG_MOUNT=y
CONFIG_UMOUNT=y
CONFIG_DMESG=y
CONFIG_PS=y
CONFIG_TOP=y
CONFIG_FREE=y
CONFIG_UPTIME=y
CONFIG_STTY=y
CONFIG_CTTYHACK=y
CONFIG_HEXDUMP=y
CONFIG_LS=y
CONFIG_CAT=y
CONFIG_ECHO=y
CONFIG_PRINTF=y
CONFIG_SLEEP=y
CONFIG_TRUE=y
CONFIG_FALSE=y
EOF

    cat > "$out_dir/.config" <<EOF
BR2_riscv=y
BR2_riscv_custom=y
BR2_RISCV_32=y
BR2_RISCV_USE_MMU=y
BR2_RISCV_ISA_RVI=y
BR2_RISCV_ISA_RVM=y
BR2_RISCV_ISA_RVA=y
BR2_RISCV_ISA_EXTRA="zicsr_zifencei"
BR2_RISCV_ABI_ILP32=y

BR2_KERNEL_HEADERS_5_10=y
BR2_TOOLCHAIN_BUILDROOT=y
BR2_TOOLCHAIN_BUILDROOT_MUSL=y
BR2_STATIC_LIBS=y

BR2_INIT_BUSYBOX=y
BR2_PACKAGE_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES="$busybox_fragment"
BR2_SYSTEM_BIN_SH_BUSYBOX=y
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS=y
BR2_TARGET_ENABLE_ROOT_LOGIN=y
BR2_TARGET_GENERIC_ROOT_PASSWD=""
BR2_TARGET_GENERIC_GETTY=y
BR2_TARGET_GENERIC_GETTY_PORT="hvc0"
BR2_TARGET_GENERIC_GETTY_BAUDRATE_KEEP=y
BR2_TARGET_GENERIC_GETTY_TERM="linux"
BR2_TARGET_GENERIC_GETTY_OPTIONS="-L"
BR2_TARGET_GENERIC_REMOUNT_ROOTFS_RW=y
BR2_ROOTFS_OVERLAY="$overlay_dir"

BR2_TARGET_ROOTFS_CPIO=y
BR2_TARGET_ROOTFS_CPIO_FULL=y
BR2_TARGET_ROOTFS_CPIO_NONE=y

BR2_DL_DIR="$dl_dir"
EOF
else
    echo "Preserving existing Buildroot configuration: $out_dir/.config"
fi

echo "Updating Buildroot configuration..."
make -C "$src_dir" O="$out_dir" olddefconfig

echo "Buildroot source: $src_dir"
echo "Buildroot output: $out_dir"
echo "Buildroot config: $out_dir/.config"

if [[ "$do_build" == "0" ]]; then
    echo "Config-only mode selected. To build:"
    echo "  $0"
    exit 0
fi

echo "Building Buildroot rootfs with $jobs jobs..."
make -C "$src_dir" O="$out_dir" -j "$jobs"

echo "BusyBox binary: $out_dir/target/bin/busybox"
echo "Rootfs cpio: $out_dir/images/rootfs.cpio"
