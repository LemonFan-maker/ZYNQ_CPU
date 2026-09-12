#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linux_out="${LINUX_OUT:-$repo_dir/build/linux-mainline-rv64}"
image="${LINUX_IMAGE:-$linux_out/arch/riscv/boot/Image}"
kernel_config="$linux_out/.config"
kernel_release="$linux_out/include/config/kernel.release"
linux_src="${LINUX_SRC:-$repo_dir/linux/kernel-v7.1.3}"
linux_tag="${LINUX_TAG:-v7.1.3}"
core_rtl="${ZX64_CORE_RTL:-$repo_dir/rtl/core64/zx64_core5.sv}"
rootfs="${ZX64_BUILDROOT_CPIO:-$repo_dir/build/buildroot-zx64/images/rootfs.cpio}"
busybox="${ZX64_BUSYBOX:-$repo_dir/build/buildroot-zx64/target/bin/busybox}"
artifact_dir="${LINUX_ARTIFACT_DIR:-$repo_dir/build/linux-rv64}"
manifest="$artifact_dir/boot_artifacts.env"
dtb_src="${LINUX_DTS:-$repo_dir/linux/zx64.dts}"
dtb="${LINUX_DTB:-$artifact_dir/zx64.dtb}"
launcher="$repo_dir/hw_bringup/build/ps_linux_boot.elf"
launcher_build="$repo_dir/scripts/build_ps_linux_boot_rv64.sh"
xsbl="$repo_dir/hw_bringup/download_zynq_cpu_rv64_linux_boot.xsbl"
vivado_hw_tcl="$repo_dir/vivado/build_hw_bringup.tcl"
embedded_initramfs="$linux_out/usr/initramfs_inc_data"
virtio_blk_ps_addr="0x08000000"
virtio_blk_cpu_addr="0x88000000"
virtio_blk_meta_ps_addr="0x07fff000"
virtio_blk_meta_magic="0x5A363442"
virtio_blk_max_bytes=$((0x04000000))
virtio_blk_reserve_bytes=$virtio_blk_max_bytes
virtio_blk_reserve_hex="$(printf '0x%08x' "$virtio_blk_reserve_bytes")"
boot_backup_ps_addr=$((0x04100000))
boot_backup_bytes=$((0x01300000))
vram_ps_addr=$((0x3c000000))
initramfs_bootargs="earlycon=sbi console=hvc0 rdinit=/init lpj=10000 loglevel=7 ignore_loglevel"
virtio_root_bootargs="earlycon=sbi console=hvc0 root=/dev/vda rw rootwait lpj=10000 loglevel=7 ignore_loglevel"

fail() {
    echo "zx64 boot-chain check failed: $*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

ranges_overlap() {
    local start_a="$1"
    local end_a="$2"
    local start_b="$3"
    local end_b="$4"

    (( start_a < end_b && start_b < end_a ))
}

rtl_misa_hex() {
    local file="$1"
    [[ -f "$file" ]] &&
        awk '
            /CSR_MISA_VALUE/ {scan = 6}
            scan > 0 {
                if (match($0, /[0-9]+'\''h[0-9a-fA-F_]+/)) {
                    value = substr($0, RSTART, RLENGTH)
                    sub(/.*'\''h/, "", value)
                    gsub(/_/, "", value)
                    print value
                    exit
                }
                scan--
            }
        ' "$file"
}

require_file "$image"
require_file "$kernel_config"
require_file "$kernel_release"
require_file "$core_rtl"
require_file "$rootfs"
require_file "$busybox"
require_file "$manifest"
require_file "$dtb"
require_file "$launcher"
require_file "$launcher_build"
require_file "$xsbl"
require_file "$vivado_hw_tcl"
require_file "$dtb_src"
require_file "$embedded_initramfs"
require_cmd cpio
require_cmd dtc
require_cmd file
require_cmd git
require_cmd readelf
require_cmd sha256sum

"$repo_dir/scripts/check_zx64_linux_boot_firmware.sh" >/dev/null

release="$(<"$kernel_release")"
[[ "$release" == "7.1.3" ]] || fail "expected Linux 7.1.3, got $release"
[[ -d "$linux_src/.git" ]] || fail "Linux source git tree is missing: $linux_src"
[[ -e "$linux_out/source" ]] || fail "Linux build output source symlink is missing: $linux_out/source"
[[ "$(readlink -f "$linux_out/source")" == "$(readlink -f "$linux_src")" ]] || \
    fail "Linux build output source symlink does not point at $linux_src"
tag_commit="$(git -C "$linux_src" rev-parse --verify "$linux_tag^{commit}")"
head_commit="$(git -C "$linux_src" rev-parse --verify HEAD)"
[[ "$head_commit" == "$tag_commit" ]] || fail "Linux source HEAD is not exactly $linux_tag"
[[ -z "$(git -C "$linux_src" status --porcelain)" ]] || fail "Linux source worktree is dirty"
grep -qx 'CONFIG_ARCH_RV64I=y' "$kernel_config" || fail "kernel is not configured for RV64"
grep -qx 'CONFIG_MMU=y' "$kernel_config" || fail "kernel MMU is disabled"
grep -qx 'CONFIG_RISCV_SBI=y' "$kernel_config" || fail "kernel SBI support is disabled"
grep -qx 'CONFIG_SERIAL_EARLYCON_RISCV_SBI=y' "$kernel_config" || fail "SBI earlycon is disabled"
grep -qx 'CONFIG_HVC_RISCV_SBI=y' "$kernel_config" || fail "SBI HVC console is disabled"
grep -qx 'CONFIG_RISCV_ISA_C=y' "$kernel_config" || fail "RVC is disabled in kernel config"
grep -qx 'CONFIG_FPU=y' "$kernel_config" || fail "kernel FPU context support is disabled for the RV64GC contract"
grep -qx 'CONFIG_CMDLINE_FALLBACK=y' "$kernel_config" || \
    fail "kernel built-in command line must be fallback-only so DTB bootargs select the boot mode"
if grep -qx 'CONFIG_CMDLINE_FORCE=y' "$kernel_config"; then
    fail "CONFIG_CMDLINE_FORCE overrides DTB bootargs and breaks the virtio-root boot contract"
fi
if grep -qx 'CONFIG_CMDLINE_EXTEND=y' "$kernel_config"; then
    fail "CONFIG_CMDLINE_EXTEND appends the fallback rdinit command line to DTB bootargs"
fi
misa_hex="$(rtl_misa_hex "$core_rtl")"
[[ -n "$misa_hex" ]] || fail "cannot verify core CSR_MISA_VALUE in $core_rtl"
misa_low=$((16#${misa_hex: -8}))
(( (misa_low & 0x28) == 0x28 )) || fail "core MISA does not advertise both F and D for the RV64GC DTS contract"
grep -Fq 'set rv64_enable_fpu 1' "$vivado_hw_tcl" || \
    fail "Vivado RV64 hardware build does not default to FPU enabled for the RV64GC contract"
if grep -Fq 'set rv64_enable_fpu 0' "$vivado_hw_tcl"; then
    fail "Vivado RV64 hardware build defaults to FPU disabled while DTS/Linux advertise RV64GC"
fi
initramfs_source="$(sed -n 's/^CONFIG_INITRAMFS_SOURCE="\(.*\)"$/\1/p' "$kernel_config")"
[[ "$initramfs_source" != "" ]] || fail "kernel initramfs source is not configured"
[[ "$(readlink -f "$initramfs_source")" == "$(readlink -f "$rootfs")" ]] || \
    fail "kernel initramfs source does not point at $rootfs: $initramfs_source"

required_distro_configs=(
    CONFIG_MULTIUSER
    CONFIG_SYSVIPC
    CONFIG_POSIX_MQUEUE
    CONFIG_BLK_DEV_INITRD
    CONFIG_DEVTMPFS
    CONFIG_DEVTMPFS_MOUNT
    CONFIG_TTY
    CONFIG_UNIX98_PTYS
    CONFIG_BINFMT_ELF
    CONFIG_BINFMT_SCRIPT
    CONFIG_COREDUMP
    CONFIG_ELF_CORE
    CONFIG_SHMEM
    CONFIG_TMPFS
    CONFIG_TMPFS_POSIX_ACL
    CONFIG_TMPFS_XATTR
    CONFIG_PROC_FS
    CONFIG_PROC_SYSCTL
    CONFIG_SYSFS
    CONFIG_FHANDLE
    CONFIG_INOTIFY_USER
    CONFIG_AUTOFS_FS
    CONFIG_EXT4_FS
    CONFIG_EXT4_FS_POSIX_ACL
    CONFIG_EXT4_FS_SECURITY
    CONFIG_BLK_DEV_LOOP
    CONFIG_OVERLAY_FS
    CONFIG_DRM
    CONFIG_DRM_SIMPLEDRM
    CONFIG_FB
    CONFIG_FRAMEBUFFER_CONSOLE
    CONFIG_VT
    CONFIG_VT_CONSOLE
    CONFIG_INPUT
    CONFIG_INPUT_EVDEV
    CONFIG_FUTEX
    CONFIG_EPOLL
    CONFIG_SIGNALFD
    CONFIG_TIMERFD
    CONFIG_EVENTFD
    CONFIG_CGROUPS
    CONFIG_MEMCG
    CONFIG_BLK_CGROUP
    CONFIG_CGROUP_SCHED
    CONFIG_FAIR_GROUP_SCHED
    CONFIG_CGROUP_PIDS
    CONFIG_CGROUP_DEVICE
    CONFIG_CGROUP_CPUACCT
    CONFIG_BPF_SYSCALL
    CONFIG_CGROUP_BPF
    CONFIG_NAMESPACES
    CONFIG_UTS_NS
    CONFIG_IPC_NS
    CONFIG_PID_NS
    CONFIG_NET_NS
    CONFIG_SECCOMP
    CONFIG_SECCOMP_FILTER
)
for config_symbol in "${required_distro_configs[@]}"; do
    grep -qx "$config_symbol=y" "$kernel_config" || \
        fail "distro prerequisite missing from kernel config: $config_symbol"
done

image_file="$(file -b "$image")"
case "$image_file" in
    *"Linux kernel RISC-V boot executable Image"*) ;;
    *) fail "unexpected kernel Image type: $image_file" ;;
esac

text_offset_hex="$(od -An -t x8 -j 8 -N 8 "$image" | tr -d '[:space:]')"
code0="$(od -An -t x4 -j 0 -N 4 "$image" | tr -d '[:space:]')"
magic="$(od -An -t x1 -j 48 -N 8 "$image" | tr -d '[:space:]')"
magic2="$(od -An -t x1 -j 56 -N 4 "$image" | tr -d '[:space:]')"
[[ "$text_offset_hex" == "0000000000200000" ]] || fail "unexpected Image text offset: 0x$text_offset_hex"
case "$code0" in
    0c40006f|0000a0d1) ;;
    *) fail "unexpected Image first word: 0x$code0" ;;
esac
[[ "$magic" == "5249534356000000" && "$magic2" == "52534305" ]] || \
    fail "unexpected RISC-V Image magic: $magic / $magic2"

busybox_file="$(file -b "$busybox")"
case "$busybox_file" in
    *"ELF 64-bit"*"RISC-V"*"statically linked"*) ;;
    *) fail "unexpected BusyBox binary type: $busybox_file" ;;
esac
LC_ALL=C readelf -h "$busybox" | grep -q 'Flags:.*RVC.*soft-float ABI' || \
    fail "BusyBox is not RV64 RVC soft-float"

cpio_list="$(cpio -t < "$rootfs" 2>/dev/null)"
grep -qx 'init' <<<"$cpio_list" || fail "rootfs.cpio does not contain /init"
grep -qx 'bin/busybox' <<<"$cpio_list" || fail "rootfs.cpio does not contain /bin/busybox"
grep -qx 'sbin/init' <<<"$cpio_list" || fail "rootfs.cpio does not contain /sbin/init"
cmp -s "$embedded_initramfs" "$rootfs" || \
    fail "Linux Image embedded initramfs does not match current rootfs.cpio"

dtb_magic="$(od -An -t x1 -N 4 "$dtb" | tr -d '[:space:]')"
[[ "$dtb_magic" == "d00dfeed" ]] || fail "unexpected DTB magic: $dtb_magic"
dtb_dts="$(mktemp)"
trap 'rm -f "$dtb_dts"' EXIT
dtc -I dtb -O dts -o "$dtb_dts" "$dtb" 2>/dev/null

dtb_node_status() {
    local node="$1"
    awk -v node="$node" '
        index($0, node " {") { in_node = 1 }
        in_node && /status =/ { print; exit }
        in_node && /^[[:space:]]*};/ { exit }
    ' "$dtb_dts"
}

source_dts_node_status() {
    local node="$1"
    awk -v node="$node" '
        index($0, node " {") { in_node = 1 }
        in_node && /status =/ { print; exit }
        in_node && /^[[:space:]]*};/ { exit }
    ' "$dtb_src"
}

require_dtb_node_status() {
    local node="$1"
    local expected="$2"
    local status
    status="$(dtb_node_status "$node")"
    [[ "$status" == *"\"$expected\""* ]] || \
        fail "DTB node $node status is not $expected: ${status:-missing}"
}

require_source_dts_node_status() {
    local node="$1"
    local expected="$2"
    local status
    status="$(source_dts_node_status "$node")"
    [[ "$status" == *"\"$expected\""* ]] || \
        fail "source DTS node $node status is not $expected: ${status:-missing}"
}

dtb_has_property() {
    local node="$1"
    local property="$2"
    local expected="$3"
    awk -v node="$node" -v property="$property" -v expected="$expected" '
        index($0, node " {") { in_node = 1 }
        in_node && index($0, property " = " expected ";") { found = 1; exit }
        in_node && /^[[:space:]]*};/ { exit }
        END { exit !found }
    ' "$dtb_dts"
}

dtb_node_has_property_name() {
    local node="$1"
    local property="$2"
    awk -v node="$node" -v property="$property" '
        index($0, node " {") { in_node = 1 }
        in_node && index($0, property " = ") { found = 1; exit }
        in_node && /^[[:space:]]*};/ { exit }
        END { exit !found }
    ' "$dtb_dts"
}

require_dtb_property() {
    local node="$1"
    local property="$2"
    local expected="$3"
    dtb_has_property "$node" "$property" "$expected" || \
        fail "DTB node $node missing $property = $expected"
}

grep -q 'compatible = "orion,zx64", "orion,zynq-cpu"' "$dtb_dts" || \
    fail "DTB compatible is not orion,zx64/orion,zynq-cpu"
grep -q 'model = "ZYNQ_CPU ZX64 RV64 bring-up platform"' "$dtb_dts" || \
    fail "DTB model does not match ZX64 RV64 bring-up platform"
if ! dtb_has_property 'chosen' 'bootargs' "\"$initramfs_bootargs\"" &&
   ! dtb_has_property 'chosen' 'bootargs' "\"$virtio_root_bootargs\""; then
    fail "DTB bootargs are neither the initramfs nor virtio root contract"
fi
require_dtb_property 'chosen' 'boot-hartid' '<0x00>'
grep -q 'riscv,isa = "rv64gc_zicsr_zifencei"' "$dtb_dts" || fail "DTB ISA string does not match rv64gc_zicsr_zifencei"
grep -q 'riscv,isa-extensions = "i", "m", "a", "f", "d", "c", "zicsr", "zifencei"' "$dtb_dts" || \
    fail "DTB ISA extensions do not advertise the RV64GC F/D contract"
grep -q 'mmu-type = "riscv,sv39"' "$dtb_dts" || fail "DTB does not advertise Sv39"
grep -q 'memory@80000000' "$dtb_dts" || fail "DTB missing memory@80000000"
require_dtb_property 'memory@80000000' 'reg' '<0x00 0x80000000 0x00 0x40000000>'
grep -q 'cpu@0' "$dtb_dts" || fail "DTB missing cpu@0"
require_dtb_property 'cpu@0' 'reg' '<0x00>'
grep -q 'interrupt-controller' "$dtb_dts" || fail "DTB missing CPU interrupt controller"
require_dtb_property 'cpus' 'timebase-frequency' '<0x47868c0>'
require_dtb_property 'cpu@0' 'i-cache-block-size' '<0x20>'
require_dtb_property 'cpu@0' 'i-cache-sets' '<0x10>'
require_dtb_property 'cpu@0' 'i-cache-size' '<0x200>'
require_dtb_property 'cpu@0' 'd-cache-block-size' '<0x20>'
require_dtb_property 'cpu@0' 'd-cache-sets' '<0x20>'
require_dtb_property 'cpu@0' 'd-cache-size' '<0x400>'
grep -q 'sram@20000000' "$dtb_dts" || fail "DTB missing scratch RX SRAM node"
grep -q 'sram@20010000' "$dtb_dts" || fail "DTB missing scratch TX SRAM node"
grep -q 'boot-artifacts@84100000' "$dtb_dts" || fail "DTB missing boot artifact backup reservation"
awk '
    /boot-artifacts@84100000 {/ { in_node = 1 }
    in_node && /reg = <0x00 0x84100000 0x00 0x1300000>/ { have_reg = 1 }
    in_node && /no-map/ { have_no_map = 1 }
    in_node && /^[[:space:]]*};/ { exit }
    END { exit !(have_reg && have_no_map) }
' "$dtb_dts" || fail "DTB boot artifact backup reservation must be 0x84100000..0x853fffff no-map"
grep -q 'vram@bc000000' "$dtb_dts" || fail "DTB missing 64 MiB VRAM reservation"
awk '
    /vram@bc000000 {/ { in_node = 1 }
    in_node && /reg = <0x00 0xbc000000 0x00 0x4000000>/ { have_reg = 1 }
    in_node && /no-map/ { have_no_map = 1 }
    in_node && /^[[:space:]]*};/ { exit }
    END { exit !(have_reg && have_no_map) }
' "$dtb_dts" || fail "DTB VRAM reservation must be 0xbc000000..0xbfffffff no-map"
if grep -Eiq '(^|[[:space:]])(mailbox|mailboxes|mboxes|mbox-names)([[:space:]=@,{;]|$)' "$dtb_dts"; then
    fail "DTB exposes a mailbox/mbox node or binding to Linux"
fi
require_dtb_node_status 'serial@10000000' disabled
require_dtb_node_status 'timer@10010000' disabled
require_dtb_node_status 'dma@10020000' disabled
require_dtb_node_status 'interrupt-controller@10040000' disabled
require_dtb_node_status 'gpu@10070000' disabled
require_dtb_node_status 'display@10080000' disabled
require_dtb_node_status 'sram@20000000' disabled
require_dtb_node_status 'sram@20010000' disabled
require_dtb_node_status 'framebuffer@bc000000' okay
require_dtb_property 'framebuffer@bc000000' 'compatible' '"simple-framebuffer"'
require_dtb_property 'framebuffer@bc000000' 'reg' '<0x00 0xbc000000 0x00 0x7e9000>'
require_dtb_property 'framebuffer@bc000000' 'width' '<0x780>'
require_dtb_property 'framebuffer@bc000000' 'height' '<0x438>'
require_dtb_property 'framebuffer@bc000000' 'stride' '<0x1e00>'
require_dtb_property 'framebuffer@bc000000' 'format' '"x8r8g8b8"'
require_source_dts_node_status 'interrupt-controller@c000000' disabled
require_source_dts_node_status 'virtio@10060000' disabled
require_source_dts_node_status 'virtio@10090000' disabled
require_source_dts_node_status 'framebuffer@bc000000' disabled
grep -Fq "bootargs = \"$initramfs_bootargs\";" "$dtb_src" || \
    fail "source DTS bootargs must remain the initramfs contract; virtio root belongs only in effective DTS"

declare -A boot_manifest=()
while IFS= read -r line; do
    [[ "$line" == "" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *=* ]] || fail "malformed boot manifest line: $line"
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Z0-9_]+$ ]] || fail "malformed boot manifest key: $key"
    boot_manifest["$key"]="$value"
done < "$manifest"

manifest_get() {
    local key="$1"
    local value="${boot_manifest[$key]:-}"
    [[ "$value" != "" ]] || fail "manifest missing key: $key"
    printf '%s\n' "$value"
}

manifest_has() {
    local key="$1"
    [[ -n "${boot_manifest[$key]+set}" ]]
}

[[ "$(manifest_get LINUX_TAG)" == "v7.1.3" ]] || fail "manifest Linux tag is not v7.1.3"
[[ "$(manifest_get LINUX_RELEASE)" == "$release" ]] || fail "manifest Linux release does not match"
[[ "$(readlink -f "$(manifest_get LINUX_SOURCE)")" == "$(readlink -f "$linux_src")" ]] || \
    fail "manifest Linux source path does not match"
[[ "$(readlink -f "$(manifest_get LINUX_BUILD_SOURCE)")" == "$(readlink -f "$linux_out/source")" ]] || \
    fail "manifest Linux build source path does not match"
[[ "$(manifest_get LINUX_SOURCE_COMMIT)" == "$head_commit" ]] || \
    fail "manifest Linux source commit does not match HEAD"
[[ "$(manifest_get LINUX_SOURCE_CLEAN)" == "1" ]] || \
    fail "manifest does not record a clean Linux source"
manifest_get PS_LINUX_BOOT_ELF >/dev/null
manifest_get PS_LINUX_BOOT_ELF_SIZE >/dev/null
manifest_get PS_LINUX_BOOT_ELF_SHA256 >/dev/null
[[ "$(readlink -f "$(manifest_get LINUX_IMAGE)")" == "$(readlink -f "$image")" ]] || \
    fail "manifest Image path does not match"
[[ "$(readlink -f "$(manifest_get LINUX_DTS_SOURCE)")" == "$(readlink -f "$dtb_src")" ]] || \
    fail "manifest source DTS path does not match"
[[ "$(manifest_get LINUX_DTS_SOURCE_SIZE)" == "$(stat -c '%s' "$dtb_src")" ]] || \
    fail "manifest source DTS size does not match"
[[ "$(manifest_get LINUX_DTS_SOURCE_SHA256)" == "$(sha256sum "$dtb_src" | awk '{print $1}')" ]] || \
    fail "manifest source DTS SHA256 does not match"
require_file "$(manifest_get LINUX_DTS_EFFECTIVE)"
[[ "$(manifest_get LINUX_DTS_EFFECTIVE_SIZE)" == "$(stat -c '%s' "$(manifest_get LINUX_DTS_EFFECTIVE)")" ]] || \
    fail "manifest effective DTS size does not match"
[[ "$(manifest_get LINUX_DTS_EFFECTIVE_SHA256)" == "$(sha256sum "$(manifest_get LINUX_DTS_EFFECTIVE)" | awk '{print $1}')" ]] || \
    fail "manifest effective DTS SHA256 does not match"
[[ "$(readlink -f "$(manifest_get LINUX_DTB)")" == "$(readlink -f "$dtb")" ]] || \
    fail "manifest DTB path does not match"
[[ "$(readlink -f "$(manifest_get ROOTFS_CPIO)")" == "$(readlink -f "$rootfs")" ]] || \
    fail "manifest rootfs path does not match"
[[ "$(readlink -f "$(manifest_get PS_LINUX_BOOT_ELF)")" == "$(readlink -f "$launcher")" ]] || \
    fail "manifest PS Linux boot ELF path does not match"
[[ "$(manifest_get LINUX_IMAGE_SIZE)" == "$(stat -c '%s' "$image")" ]] || \
    fail "manifest Image size does not match"
[[ "$(manifest_get LINUX_DTB_SIZE)" == "$(stat -c '%s' "$dtb")" ]] || \
    fail "manifest DTB size does not match"
[[ "$(manifest_get ROOTFS_CPIO_SIZE)" == "$(stat -c '%s' "$rootfs")" ]] || \
    fail "manifest rootfs size does not match"
[[ "$(manifest_get LINUX_EMBEDDED_INITRAMFS_SIZE)" == "$(stat -c '%s' "$embedded_initramfs")" ]] || \
    fail "manifest embedded initramfs size does not match"
[[ "$(manifest_get PS_LINUX_BOOT_ELF_SIZE)" == "$(stat -c '%s' "$launcher")" ]] || \
    fail "manifest PS Linux boot ELF size does not match"
[[ "$(manifest_get LINUX_IMAGE_SHA256)" == "$(sha256sum "$image" | awk '{print $1}')" ]] || \
    fail "manifest Image SHA256 does not match"
[[ "$(manifest_get LINUX_DTB_SHA256)" == "$(sha256sum "$dtb" | awk '{print $1}')" ]] || \
    fail "manifest DTB SHA256 does not match"
[[ "$(manifest_get ROOTFS_CPIO_SHA256)" == "$(sha256sum "$rootfs" | awk '{print $1}')" ]] || \
    fail "manifest rootfs SHA256 does not match"
[[ "$(manifest_get LINUX_EMBEDDED_INITRAMFS_SHA256)" == "$(sha256sum "$embedded_initramfs" | awk '{print $1}')" ]] || \
    fail "manifest embedded initramfs SHA256 does not match"
[[ "$(manifest_get ROOTFS_CPIO_SHA256)" == "$(manifest_get LINUX_EMBEDDED_INITRAMFS_SHA256)" ]] || \
    fail "manifest rootfs and embedded initramfs SHA256 do not match"
[[ "$(manifest_get PS_LINUX_BOOT_ELF_SHA256)" == "$(sha256sum "$launcher" | awk '{print $1}')" ]] || \
    fail "manifest PS Linux boot ELF SHA256 does not match"
dtb_bootargs="$(manifest_get LINUX_DTB_BOOTARGS)"
dtb_storage_mode="$(manifest_get LINUX_DTB_STORAGE_MODE)"
[[ "$dtb_bootargs" == "$initramfs_bootargs" || "$dtb_bootargs" == "$virtio_root_bootargs" ]] || \
    fail "manifest DTB bootargs are not a known ZX64 boot contract"
[[ "$(manifest_get KERNEL_CPU_ADDR)" == "0x80200000" ]] || fail "manifest kernel CPU address mismatch"
[[ "$(manifest_get KERNEL_PS_ADDR)" == "0x00200000" ]] || fail "manifest kernel PS address mismatch"
[[ "$(manifest_get KERNEL_TEXT_OFFSET)" == "0x0000000000200000" ]] || fail "manifest text offset mismatch"
[[ "$(manifest_get DTB_CPU_ADDR)" == "0x82000000" ]] || fail "manifest DTB CPU address mismatch"
[[ "$(manifest_get DTB_PS_ADDR)" == "0x02000000" ]] || fail "manifest DTB PS address mismatch"
[[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_META_PS_ADDR)" == "$virtio_blk_meta_ps_addr" ]] || \
    fail "manifest ZX64 virtio block metadata PS address mismatch"
[[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_META_MAGIC)" == "$virtio_blk_meta_magic" ]] || \
    fail "manifest ZX64 virtio block metadata magic mismatch"
[[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_MAX_BYTES)" == "$virtio_blk_max_bytes" ]] || \
    fail "manifest ZX64 virtio block max bytes mismatch"
[[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_RESERVE_CPU_ADDR)" == "$virtio_blk_cpu_addr" ]] || \
    fail "manifest ZX64 virtio block reserve CPU address mismatch"
[[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_RESERVE_BYTES)" == "$virtio_blk_reserve_bytes" ]] || \
    fail "manifest ZX64 virtio block reserve bytes mismatch"
[[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_RESERVE_HEX)" == "$virtio_blk_reserve_hex" ]] || \
    fail "manifest ZX64 virtio block reserve hex mismatch"
[[ "$(manifest_get LINUX_DTB_DISPLAY_MODE)" == "simple-framebuffer" ]] || \
    fail "manifest DTB display mode is not simple-framebuffer"
dtb_input_mode="$(manifest_get LINUX_DTB_INPUT_MODE)"
[[ "$dtb_input_mode" == "none" || "$dtb_input_mode" == "virtio-input" ]] || \
    fail "manifest DTB input mode is not a known ZX64 input contract"
grep -Fq "virtio_input_backend_poll" "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS Linux boot launcher source lacks the virtio-input backend poll path"
grep -Fq "virtio_input_queue_uart_char" "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS Linux boot launcher source lacks UART-to-virtio-input event injection"
grep -Fq "Xil_DCacheDisable();" "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS Linux boot launcher must keep PS D-cache disabled for the in-DDR virtio backend"
grep -Fq "if (virtio_blk_backend_irq || virtio_input_backend_irq)" "$repo_dir/rtl/soc/zx64_soc.sv" || \
    fail "ZX64 SoC lacks the virtio backend IRQ cache-coherency hook"
grep -Fq "dcache_valid <= '0;" "$repo_dir/rtl/soc/zx64_soc.sv" || \
    fail "ZX64 SoC lacks D-cache invalidation needed by the virtio backend"

if [[ "$dtb_input_mode" == "virtio-input" ]]; then
    require_dtb_node_status 'interrupt-controller@c000000' okay
    require_dtb_node_status 'virtio@10090000' okay
    require_dtb_property 'virtio@10090000' 'compatible' '"virtio,mmio"'
    require_dtb_property 'virtio@10090000' 'reg' '<0x00 0x10090000 0x00 0x1000>'
    dtb_node_has_property_name 'virtio@10090000' 'interrupts-extended' || \
        fail "effective DTB virtio-input node lacks an interrupts-extended property"
else
    require_dtb_node_status 'virtio@10090000' disabled
fi

image_size="$(stat -c '%s' "$image")"
kernel_ps_end=$(($(manifest_get KERNEL_PS_ADDR) + image_size))
dtb_ps=$(($(manifest_get DTB_PS_ADDR)))
(( kernel_ps_end <= dtb_ps )) || fail "kernel Image overlaps DTB PS placement"

virtio_manifest_keys=(
    ZX64_VIRTIO_BLK_IMAGE
    ZX64_VIRTIO_BLK_IMAGE_SIZE
    ZX64_VIRTIO_BLK_IMAGE_SHA256
    ZX64_VIRTIO_BLK_CAPACITY_SECTORS
    ZX64_VIRTIO_BLK_CPU_ADDR
    ZX64_VIRTIO_BLK_PS_ADDR
    ZX64_VIRTIO_BLK_ROOTFS_EXT4
)
virtio_manifest_count=0
for key in "${virtio_manifest_keys[@]}"; do
    if manifest_has "$key"; then
        virtio_manifest_count=$((virtio_manifest_count + 1))
    fi
done
(( virtio_manifest_count == 0 || virtio_manifest_count == ${#virtio_manifest_keys[@]} )) || \
    fail "manifest has a partial ZX64 virtio block image contract"

virtio_blk_present="$(manifest_get ZX64_VIRTIO_BLK_IMAGE_PRESENT)"
if [[ "$virtio_blk_present" == "0" ]]; then
    (( virtio_manifest_count == 0 )) || \
        fail "manifest marks ZX64 virtio block image absent but still has image keys"
    [[ "$dtb_storage_mode" == "initramfs" ]] || \
        fail "manifest DTB storage mode is not initramfs for no-image boot"
    [[ "$dtb_bootargs" == "$initramfs_bootargs" ]] || \
        fail "manifest bootargs are not initramfs bootargs for no-image boot"
    require_dtb_property 'chosen' 'bootargs' "\"$initramfs_bootargs\""
    require_dtb_node_status 'interrupt-controller@c000000' disabled
    require_dtb_node_status 'virtio@10060000' disabled
    if grep -q 'virtio-blk-image@88000000' "$dtb_dts"; then
        fail "DTB reserves a ZX64 virtio block backing image without ZX64_VIRTIO_BLK_IMAGE"
    fi
    if grep -Eq 'root=/dev/(vd|sd|mmcblk)' "$dtb_dts"; then
        fail "DTB bootargs enable block root storage without ZX64_VIRTIO_BLK_IMAGE"
    fi
elif [[ "$virtio_blk_present" == "1" ]]; then
    (( virtio_manifest_count == ${#virtio_manifest_keys[@]} )) || \
        fail "manifest marks ZX64 virtio block image present but image contract is incomplete"
    [[ "$dtb_storage_mode" == "virtio-blk" ]] || \
        fail "manifest DTB storage mode is not virtio-blk for image-backed boot"
    [[ "$dtb_bootargs" == "$virtio_root_bootargs" ]] || \
        fail "manifest bootargs are not virtio root bootargs for image-backed boot"
    require_dtb_property 'chosen' 'bootargs' "\"$virtio_root_bootargs\""
    if grep -Eq 'rdinit=/init|root=/dev/(sd|mmcblk)' "$dtb_dts"; then
        fail "DTB bootargs do not select the ZX64 virtio rootfs exclusively"
    fi
    require_dtb_node_status 'interrupt-controller@c000000' okay
    require_dtb_node_status 'virtio@10060000' okay
    grep -q 'virtio-blk-image@88000000' "$dtb_dts" || \
        fail "DTB missing ZX64 virtio block backing image reservation"
    awk '
        /virtio-blk-image@88000000 {/ { in_node = 1 }
        in_node && /reg = <0x00 0x88000000 0x00 0x4000000>/ { have_reg = 1 }
        in_node && /no-map/ { have_no_map = 1 }
        in_node && /^[[:space:]]*};/ { exit }
        END { exit !(have_reg && have_no_map) }
    ' "$dtb_dts" || fail "DTB ZX64 virtio block backing image reservation must be 0x88000000..0x8bffffff no-map"
    virtio_blk_image="$(manifest_get ZX64_VIRTIO_BLK_IMAGE)"
    require_file "$virtio_blk_image"
    [[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_SIZE)" == "$(stat -c '%s' "$virtio_blk_image")" ]] || \
        fail "manifest ZX64 virtio block image size does not match"
    [[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_SHA256)" == "$(sha256sum "$virtio_blk_image" | awk '{print $1}')" ]] || \
        fail "manifest ZX64 virtio block image SHA256 does not match"
    [[ "$(manifest_get ZX64_VIRTIO_BLK_CAPACITY_SECTORS)" == "$(($(stat -c '%s' "$virtio_blk_image") / 512))" ]] || \
        fail "manifest ZX64 virtio block capacity does not match image size"
    [[ "$(manifest_get ZX64_VIRTIO_BLK_CPU_ADDR)" == "$virtio_blk_cpu_addr" ]] || \
        fail "manifest ZX64 virtio block CPU address mismatch"
    [[ "$(manifest_get ZX64_VIRTIO_BLK_PS_ADDR)" == "$virtio_blk_ps_addr" ]] || \
        fail "manifest ZX64 virtio block PS address mismatch"
    [[ "$(manifest_get ZX64_VIRTIO_BLK_ROOTFS_EXT4)" == "1" ]] || \
        fail "manifest ZX64 virtio block image is not a verified ext4 rootfs"
    require_cmd debugfs

    virtio_blk_size="$(stat -c '%s' "$virtio_blk_image")"
    (( virtio_blk_size > 0 && (virtio_blk_size % 512) == 0 )) || \
        fail "ZX64 virtio block image size is not a non-zero multiple of 512"
    (( virtio_blk_size <= virtio_blk_max_bytes )) || \
        fail "ZX64 virtio block image exceeds max bytes"
    virtio_blk_ps=$((virtio_blk_ps_addr))
    virtio_blk_end=$((virtio_blk_ps + virtio_blk_size))
    (( virtio_blk_end > virtio_blk_ps && virtio_blk_end <= vram_ps_addr )) || \
        fail "ZX64 virtio block image is outside non-VRAM DDR"
    if ranges_overlap "$virtio_blk_ps" "$virtio_blk_end" \
                      "$(($(manifest_get KERNEL_PS_ADDR)))" "$kernel_ps_end"; then
        fail "ZX64 virtio block image overlaps kernel Image placement"
    fi
    if ranges_overlap "$virtio_blk_ps" "$virtio_blk_end" \
                      "$dtb_ps" "$((dtb_ps + $(stat -c '%s' "$dtb")))"; then
        fail "ZX64 virtio block image overlaps DTB placement"
    fi
    if ranges_overlap "$virtio_blk_ps" "$virtio_blk_end" \
                      "$boot_backup_ps_addr" "$((boot_backup_ps_addr + boot_backup_bytes))"; then
        fail "ZX64 virtio block image overlaps boot artifact backup placement"
    fi
    debugfs -R 'stat /sbin/init' "$virtio_blk_image" >/dev/null 2>&1 || \
        fail "ZX64 virtio block rootfs image is missing /sbin/init"
    debugfs -R 'stat /bin/busybox' "$virtio_blk_image" >/dev/null 2>&1 || \
        fail "ZX64 virtio block rootfs image is missing /bin/busybox"
else
    fail "manifest has invalid ZX64_VIRTIO_BLK_IMAGE_PRESENT=$virtio_blk_present"
fi

grep -Fq 'set kernel_image "./build/linux-mainline-rv64/arch/riscv/boot/Image"' "$xsbl" || \
    fail "XSBL kernel Image path is not the RV64 Image"
grep -Fq 'set kernel_dtb "./build/linux-rv64/zx64.dtb"' "$xsbl" || \
    fail "XSBL DTB path is not the RV64 DTB"
grep -Fq 'set boot_manifest "./build/linux-rv64/boot_artifacts.env"' "$xsbl" || \
    fail "XSBL boot manifest path is not the RV64 boot manifest"
if grep -Fq './build/linux/boot_artifacts.env' "$xsbl" || grep -Fq './build/linux/zynq_cpu.dtb' "$xsbl"; then
    fail "XSBL still references RV32 Linux boot artifacts"
fi
grep -Fq 'set ps_launcher "./hw_bringup/build/ps_linux_boot.elf"' "$xsbl" || \
    fail "XSBL launcher path is not ps_linux_boot.elf"
grep -Fq 'read_boot_manifest $boot_manifest' "$xsbl" || \
    fail "XSBL does not read the RV64 boot manifest"
grep -Fq 'require_manifest_value $manifest "LINUX_RELEASE" "7.1.3"' "$xsbl" || \
    fail "XSBL does not verify Linux 7.1.3 in the boot manifest"
grep -Fq 'require_manifest_file $manifest $kernel_image "LINUX_IMAGE" "LINUX_IMAGE_SIZE" "LINUX_IMAGE_SHA256"' "$xsbl" || \
    fail "XSBL does not verify the kernel Image manifest hash"
grep -Fq 'require_manifest_file $manifest $kernel_dtb "LINUX_DTB" "LINUX_DTB_SIZE" "LINUX_DTB_SHA256"' "$xsbl" || \
    fail "XSBL does not verify the DTB manifest hash"
grep -Fq 'require_manifest_file $manifest $ps_launcher "PS_LINUX_BOOT_ELF" "PS_LINUX_BOOT_ELF_SIZE" "PS_LINUX_BOOT_ELF_SHA256"' "$xsbl" || \
    fail "XSBL does not verify the PS Linux boot ELF manifest hash"
grep -Fq 'require_manifest_file $manifest $virtio_blk_image "ZX64_VIRTIO_BLK_IMAGE" "ZX64_VIRTIO_BLK_IMAGE_SIZE" "ZX64_VIRTIO_BLK_IMAGE_SHA256"' "$xsbl" || \
    fail "XSBL does not verify the optional ZX64 virtio block image manifest hash"
grep -Fq 'require_manifest_value $manifest "ZX64_VIRTIO_BLK_PS_ADDR" $virtio_blk_ps_addr' "$xsbl" || \
    fail "XSBL does not verify the optional ZX64 virtio block PS address"
grep -Fq 'require_manifest_value $manifest "ZX64_VIRTIO_BLK_CPU_ADDR" $virtio_blk_cpu_addr' "$xsbl" || \
    fail "XSBL does not verify the optional ZX64 virtio block CPU address"
grep -Fq 'require_manifest_value $manifest "ZX64_VIRTIO_BLK_ROOTFS_EXT4" "1"' "$xsbl" || \
    fail "XSBL does not verify the optional ZX64 virtio block image is a rootfs"
grep -Fq 'require_manifest_value $manifest "LINUX_DTB_STORAGE_MODE" "virtio-blk"' "$xsbl" || \
    fail "XSBL does not verify the virtio DTB storage mode"
grep -Fq 'require_manifest_value $manifest "LINUX_DTB_BOOTARGS" $virtio_root_bootargs' "$xsbl" || \
    fail "XSBL does not verify the virtio root bootargs"
grep -Fq 'require_manifest_value $manifest "LINUX_DTB_STORAGE_MODE" "initramfs"' "$xsbl" || \
    fail "XSBL does not verify the initramfs DTB storage mode"
grep -Fq 'require_manifest_value $manifest "LINUX_DTB_BOOTARGS" $initramfs_bootargs' "$xsbl" || \
    fail "XSBL does not verify the initramfs bootargs"
grep -Fq 'require_manifest_value $manifest "ZX64_VIRTIO_BLK_IMAGE_META_PS_ADDR" $virtio_blk_meta_ps_addr' "$xsbl" || \
    fail "XSBL does not verify the ZX64 virtio block metadata PS address"
grep -Fq 'require_manifest_value $manifest "ZX64_VIRTIO_BLK_IMAGE_META_MAGIC" $virtio_blk_meta_magic' "$xsbl" || \
    fail "XSBL does not verify the ZX64 virtio block metadata magic"
grep -Fq 'dow -data $kernel_image 0x00200000' "$xsbl" || \
    fail "XSBL does not download Image to 0x00200000"
grep -Fq 'dow -data $kernel_dtb 0x02000000' "$xsbl" || \
    fail "XSBL does not download DTB to 0x02000000"
grep -Fq 'dow -data $virtio_blk_image 0x08000000' "$xsbl" || \
    fail "XSBL does not download the optional ZX64 virtio block image to 0x08000000"
grep -Fq 'mwr 0x07fff000 0x5A363442' "$xsbl" || \
    fail "XSBL does not publish the optional ZX64 virtio block metadata magic"
grep -Fq 'mwr 0x07fff004 0x08000000' "$xsbl" || \
    fail "XSBL does not publish the optional ZX64 virtio block image PS address"
grep -Fq 'mwr 0x07fff008 $virtio_blk_size' "$xsbl" || \
    fail "XSBL does not publish the optional ZX64 virtio block image byte size"
grep -Fq 'mwr 0x07fff00c [expr {$virtio_blk_size / 512}]' "$xsbl" || \
    fail "XSBL does not publish the optional ZX64 virtio block image sector count"
grep -Fq 'mwr 0x07fff010 0x00000000' "$xsbl" || \
    fail "XSBL does not clear the optional ZX64 virtio block high sector count"
grep -Fq 'mwr 0x07fff000 0x00000000' "$xsbl" || \
    fail "XSBL does not clear the ZX64 virtio block metadata magic when no image is present"
grep -Fq 'dow $ps_launcher' "$xsbl" || \
    fail "XSBL does not download ps_linux_boot.elf"

grep -Fq 'ZYNQ_CPU_LINUX_IMAGE_CODE0_ALT 0x0000A0D1U' "$repo_dir/hw_bringup/ps_uart_probe.h" || \
    fail "PS launcher ABI does not allow the RV64 RVC Image entry word"
grep -Fq 'ps_code0 != ZYNQ_CPU_LINUX_IMAGE_CODE0_ALT' "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS launcher Image header check does not accept the RV64 RVC entry word"
grep -Fq 'ZYNQ_CPU_VIRTIO_BLK_IMAGE_META_MAGIC' "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS launcher virtio-blk backend does not consume metadata magic"
grep -Fq 'Xil_In32(ZYNQ_CPU_VIRTIO_BLK_IMAGE_META_IMAGE_PS)' "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS launcher virtio-blk backend does not read the metadata image PS address"
grep -Fq 'Xil_In32(ZYNQ_CPU_VIRTIO_BLK_IMAGE_META_BYTES)' "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS launcher virtio-blk backend does not read the metadata image byte size"
grep -Fq 'image_ps_addr != ZYNQ_CPU_VIRTIO_BLK_IMAGE_PS_ADDR' "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS launcher virtio-blk backend does not validate the metadata image PS address"
grep -Fq 'image_bytes > ZYNQ_CPU_VIRTIO_BLK_IMAGE_MAX_BYTES' "$repo_dir/hw_bringup/ps_linux_boot.c" || \
    fail "PS launcher virtio-blk backend does not bound the metadata image byte size"
if grep -Fq 'ZYNQ_CPU_VIRTIO_BLK_IMAGE_BYTES' "$repo_dir/hw_bringup/ps_linux_boot.c"; then
    fail "PS launcher virtio-blk backend still uses a compile-time fake image size"
fi
grep -Fq 'PS_UART_PROBE_CFLAGS="${PS_UART_PROBE_CFLAGS:-} -DZYNQ_CPU_RV64_BOOT=1"' "$launcher_build" || \
    fail "RV64 launcher build wrapper does not force ZYNQ_CPU_RV64_BOOT"

grep -Fq 'read_sv $repo_dir rtl/periph/mmio_virtio_blk_regs.sv' "$vivado_hw_tcl" || \
    fail "Vivado RV64 hardware build does not include the virtio-blk MMIO source"
grep -Fq 'read_sv $repo_dir rtl/periph/mmio_virtio_input_regs.sv' "$vivado_hw_tcl" || \
    fail "Vivado RV64 hardware build does not include the virtio-input MMIO source"
grep -Fq 'read_sv $repo_dir rtl/periph/mmio_plic_min.sv' "$vivado_hw_tcl" || \
    fail "Vivado RV64 hardware build does not include the PLIC MMIO source"

echo "ZX64 boot chain: PASS"
echo "  kernel:  Linux $release Image=$(stat -c '%s' "$image") bytes code0=0x$code0"
echo "  rootfs:  $rootfs ($(stat -c '%s' "$rootfs") bytes)"
echo "  dtb:     $dtb"
if (( virtio_manifest_count == 0 )); then
    echo "  virtio:  disabled (no ZX64_VIRTIO_BLK_IMAGE)"
else
    echo "  virtio:  $(manifest_get ZX64_VIRTIO_BLK_IMAGE) ($(manifest_get ZX64_VIRTIO_BLK_CAPACITY_SECTORS) sectors)"
fi
echo "  launcher: $launcher"
