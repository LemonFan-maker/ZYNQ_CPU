#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PERL5LIB
unset RUBYLIB
unset CMAKE_PREFIX_PATH

br_version="${BUILDROOT_VERSION:-2026.05-rc2}"
br_url="${BUILDROOT_URL:-https://buildroot.org/downloads/buildroot-${br_version}.tar.gz}"
dl_dir="${BUILDROOT_DL_DIR:-$repo_dir/build/downloads}"
src_dir="${BUILDROOT_SRC_DIR:-$repo_dir/build/buildroot-${br_version}}"
out_dir="${BUILDROOT_OUT:-$repo_dir/build/buildroot-zx64}"
work_dir="${ZX64_BUILDROOT_WORK:-$repo_dir/build/zx64-buildroot}"
tarball="$dl_dir/buildroot-${br_version}.tar.gz"
jobs="${JOBS:-$(nproc)}"

# Set ZX64_BUILDROOT_BUILD=0 to stop after download, extraction and .config generation.
do_build="${ZX64_BUILDROOT_BUILD:-1}"
# Set ZX64_BUILDROOT_RECONFIG=0 to preserve an existing Buildroot .config.
do_reconfig="${ZX64_BUILDROOT_RECONFIG:-1}"

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
busybox_fragment="$work_dir/busybox-zx64.fragment"
post_build_script="$work_dir/post-build-zx64.sh"
mkdir -p "$overlay_dir" "$out_dir"

if [[ "$do_reconfig" != "0" || ! -f "$out_dir/.config" ]]; then
    rm -f "$overlay_dir/init"
    cat > "$overlay_dir/init" <<'EOF'
#!/bin/sh
mkdir -p /dev /proc /sys
[ -c /dev/null ] || mknod -m 666 /dev/null c 1 3
[ -c /dev/zero ] || mknod -m 666 /dev/zero c 1 5
[ -c /dev/console ] || mknod -m 600 /dev/console c 5 1
[ -c /dev/hvc0 ] || mknod -m 600 /dev/hvc0 c 229 0
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
[ -c /dev/null ] || mknod -m 666 /dev/null c 1 3
[ -c /dev/zero ] || mknod -m 666 /dev/zero c 1 5
[ -c /dev/console ] || mknod -m 600 /dev/console c 5 1
[ -c /dev/hvc0 ] || mknod -m 600 /dev/hvc0 c 229 0

rootdev=/dev/vda
rootfstype=ext4
rootwait=5

for arg in $(cat /proc/cmdline 2>/dev/null); do
    case "$arg" in
        zx64.root=off)
            rootdev=
            ;;
        zx64.root=*)
            rootdev="${arg#zx64.root=}"
            ;;
        zx64.rootfstype=*)
            rootfstype="${arg#zx64.rootfstype=}"
            ;;
        zx64.rootwait=*)
            rootwait="${arg#zx64.rootwait=}"
            ;;
    esac
done

case "$rootwait" in
    ''|*[!0-9]*)
        rootwait=5
        ;;
esac

if [ -n "$rootdev" ]; then
    echo "[zx64-init] probing $rootdev as $rootfstype root"
    i=0
    while [ "$i" -lt "$rootwait" ]; do
        [ -b "$rootdev" ] && break
        sleep 1
        i=$((i + 1))
    done

    mkdir -p /newroot
    if [ -b "$rootdev" ] && mount -t "$rootfstype" -o rw "$rootdev" /newroot 2>/dev/null; then
        if [ -x /newroot/sbin/init ]; then
            echo "[zx64-init] switching root to $rootdev"
            mkdir -p /newroot/dev /newroot/proc /newroot/sys /newroot/run
            mount -o move /dev /newroot/dev 2>/dev/null || mount -t devtmpfs devtmpfs /newroot/dev 2>/dev/null || true
            mount -o move /proc /newroot/proc 2>/dev/null || mount -t proc proc /newroot/proc 2>/dev/null || true
            mount -o move /sys /newroot/sys 2>/dev/null || mount -t sysfs sysfs /newroot/sys 2>/dev/null || true
            exec switch_root /newroot /sbin/init "$@"
        fi
        echo "[zx64-init] $rootdev mounted but /sbin/init is missing; using initramfs"
        umount /newroot 2>/dev/null || true
    else
        echo "[zx64-init] $rootdev not available; using initramfs"
    fi
fi

exec /sbin/init "$@"
EOF
    chmod +x "$overlay_dir/init"

    cat > "$post_build_script" <<'EOF'
#!/bin/sh
set -eu

target_dir="$1"

rm -f "$target_dir/etc/init.d/S02sysctl"
rm -f "$target_dir/etc/init.d/S99zx64boot"
EOF
    chmod +x "$post_build_script"

    cat > "$busybox_fragment" <<'EOF'
CONFIG_STATIC=y
CONFIG_ASH=y
CONFIG_SH_IS_ASH=y
CONFIG_FEATURE_SH_STANDALONE=y
CONFIG_FEATURE_EDITING=y
CONFIG_FEATURE_EDITING_HISTORY=64
CONFIG_FEATURE_VI=y
CONFIG_MOUNT=y
CONFIG_MKNOD=y
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
BR2_RISCV_64=y
BR2_RISCV_USE_MMU=y
BR2_RISCV_ISA_RVI=y
BR2_RISCV_ISA_RVM=y
BR2_RISCV_ISA_RVA=y
BR2_RISCV_ISA_RVC=y
# BR2_RISCV_ISA_RVF is not set
# BR2_RISCV_ISA_RVD is not set
BR2_RISCV_ISA_EXTRA="zicsr_zifencei"
BR2_RISCV_ABI_LP64=y

BR2_KERNEL_HEADERS_VERSION=y
BR2_DEFAULT_KERNEL_VERSION="7.1.3"
BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_7_0=y
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
BR2_ROOTFS_POST_BUILD_SCRIPT="$post_build_script"

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
