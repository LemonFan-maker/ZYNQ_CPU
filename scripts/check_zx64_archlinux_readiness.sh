#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linux_out="${LINUX_OUT:-$repo_dir/build/linux-mainline-rv64}"
kernel_config="${KERNEL_CONFIG:-$linux_out/.config}"
kernel_release="${KERNEL_RELEASE:-$linux_out/include/config/kernel.release}"
dts="${ZX64_DTS:-$repo_dir/linux/zx64.dts}"
firmware="${ZX64_SBI_FIRMWARE:-$repo_dir/hw_bringup/programs/linux_boot_firmware.rv64.S}"
core_rtl="${ZX64_CORE_RTL:-$repo_dir/rtl/core64/zx64_core5.sv}"
soc_rtl="${ZX64_SOC_RTL:-$repo_dir/rtl/soc/zx64_soc.sv}"
ps_launcher_src="${ZX64_PS_LINUX_BOOT_SRC:-$repo_dir/hw_bringup/ps_linux_boot.c}"
manifest="${LINUX_ARTIFACT_MANIFEST:-$repo_dir/build/linux-rv64/boot_artifacts.env}"
vivado_hw_tcl="${ZX64_VIVADO_HW_TCL:-$repo_dir/vivado/build_hw_bringup.tcl}"
bitstream_build_dir="${ZX64_VIVADO_BITSTREAM_BUILD_DIR:-$repo_dir/build/vivado_hw_rv64}"
bitstream_bit="$bitstream_build_dir/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit"
bitstream_xsa="$bitstream_build_dir/zynq_cpu_system_wrapper.xsa"
bitstream_timing="$bitstream_build_dir/reports/zynq_cpu_system_timing_summary.rpt"
bitstream_util="$bitstream_build_dir/reports/zynq_cpu_system_utilization.rpt"
strict=0
virtio_root_bootargs="earlycon=sbi console=hvc0 root=/dev/vda rw rootwait lpj=10000 loglevel=7 ignore_loglevel"

if [[ "${1:-}" == "--strict-distro" ]]; then
    strict=1
fi

warn_count=0
blocker_count=0
hardware_blocker_count=0
fpu_blocked=0
storage_blocked=0
display_blocked=0
input_blocked=0
sbi_legacy_done=0
sbi_basic_done=0
kernel_ui_framework_done=0
kernel_storage_ready=0
kernel_virtio_storage_ready=0
kernel_input_ready=0
kernel_input_device_ready=0
kernel_fpu_ready=0
rtl_fpu_ready=0
dts_fpu_ready=0
dts_plic_ready=0
dts_virtio_ready=0
dts_storage_ready=0
dts_storage_bootargs_ready=0
dts_display_ready=0
dts_input_ready=0
dts_virtio_input_ready=0
storage_image_ready=0
manifest_storage_ready=0
manifest_input_ready=0
rv64gc_hw_fpu_default_ready=0
rv64gc_hw_bitstream_ready=0
rv64gc_hw_timing_ready=0

have_file() {
    [[ -f "$1" ]]
}

cfg_enabled() {
    local key="$1"
    have_file "$kernel_config" && grep -qx "${key}=y" "$kernel_config"
}

cfg_set() {
    local key="$1"
    have_file "$kernel_config" && grep -q "^${key}=" "$kernel_config"
}

cfg_disabled() {
    local key="$1"
    have_file "$kernel_config" && grep -qx "# ${key} is not set" "$kernel_config"
}

contains() {
    local file="$1"
    local pattern="$2"
    have_file "$file" && grep -q "$pattern" "$file"
}

contains_all() {
    local file="$1"
    shift
    local pattern
    have_file "$file" || return 1
    for pattern in "$@"; do
        grep -q "$pattern" "$file" || return 1
    done
}

manifest_get() {
    local key="$1"
    have_file "$manifest" && awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); found = 1; exit } END { exit !found }' "$manifest"
}

is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

rtl_misa_hex() {
    local file="$1"
    have_file "$file" &&
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

if [[ -z "${ZX64_DTS:-}" ]] && have_file "$manifest"; then
    effective_dts="$(manifest_get LINUX_DTS_EFFECTIVE || true)"
    if [[ -n "$effective_dts" && -f "$effective_dts" ]]; then
        dts="$effective_dts"
    fi
fi

node_contains() {
    local file="$1"
    local node="$2"
    local pattern="$3"
    have_file "$file" && awk -v node="$node" -v pattern="$pattern" '
        index($0, node " {") { in_node = 1 }
        in_node && $0 ~ pattern { found = 1; exit }
        in_node && /^[[:space:]]*};/ { exit }
        END { exit !found }
    ' "$file"
}

ok() {
    printf 'OK      %s\n' "$*"
}

info() {
    printf 'INFO    %s\n' "$*"
}

warn() {
    warn_count=$((warn_count + 1))
    printf 'WARN    %s\n' "$*"
}

blocker() {
    blocker_count=$((blocker_count + 1))
    printf 'BLOCK   %s\n' "$*"
}

hardware_blocker() {
    hardware_blocker_count=$((hardware_blocker_count + 1))
    printf 'HW-BLOCK %s\n' "$*"
}

check_cfg() {
    local key="$1"
    local msg="$2"
    if cfg_enabled "$key"; then
        ok "$msg"
    else
        blocker "$msg ($key is not enabled)"
    fi
}

section() {
    printf '\n[%s]\n' "$*"
}

echo "ZX64 Arch/Linux readiness"
echo "  config:   $kernel_config"
echo "  dts:      $dts"
echo "  firmware: $firmware"
echo "  core RTL: $core_rtl"

section "Boot artifacts"

if have_file "$kernel_release"; then
    release="$(<"$kernel_release")"
    if [[ "$release" == "7.1.3" ]]; then
        ok "Linux release is pinned to 7.1.3"
    else
        blocker "Linux release is $release, expected 7.1.3"
    fi
else
    warn "kernel.release is missing; run scripts/prepare_mainline_rv64_linux.sh first"
fi

if have_file "$manifest"; then
    if grep -qx 'LINUX_RELEASE=7.1.3' "$manifest"; then
        ok "boot artifact manifest records Linux 7.1.3"
    else
        blocker "boot artifact manifest does not record Linux 7.1.3"
    fi
    manifest_dts="$(manifest_get LINUX_DTS_EFFECTIVE || true)"
    manifest_dts_size="$(manifest_get LINUX_DTS_EFFECTIVE_SIZE || true)"
    manifest_dts_sha="$(manifest_get LINUX_DTS_EFFECTIVE_SHA256 || true)"
    manifest_mode="$(manifest_get LINUX_DTB_STORAGE_MODE || true)"
    manifest_input_mode="$(manifest_get LINUX_DTB_INPUT_MODE || true)"
    manifest_bootargs="$(manifest_get LINUX_DTB_BOOTARGS || true)"
    if [[ -n "$manifest_dts" && -f "$manifest_dts" &&
          "$(readlink -f "$manifest_dts")" == "$(readlink -f "$dts")" &&
          "$manifest_dts_size" =~ ^[0-9]+$ &&
          "$(stat -c '%s' "$manifest_dts")" == "$manifest_dts_size" &&
          -n "$manifest_dts_sha" &&
          "$(sha256sum "$manifest_dts" | awk '{print $1}')" == "$manifest_dts_sha" ]]; then
        ok "boot artifact manifest is bound to the effective DTS"
    else
        blocker "boot artifact manifest does not prove the effective DTS in use"
    fi
    if [[ "$manifest_mode" == "virtio-blk" &&
          "$manifest_bootargs" == "$virtio_root_bootargs" &&
          "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_PRESENT || true)" == "1" ]]; then
        manifest_storage_ready=1
        ok "boot artifact manifest selects virtio-blk root storage"
    else
        storage_blocked=1
        blocker "boot artifact manifest does not select the virtio-blk root storage contract"
    fi
    if [[ "$manifest_input_mode" == "virtio-input" ]]; then
        manifest_input_ready=1
        ok "boot artifact manifest selects the virtio-input local input contract"
    else
        input_blocked=1
        blocker "boot artifact manifest does not select an enabled local input contract"
    fi
else
    warn "boot artifact manifest is missing; run scripts/prepare_zx64_linux_boot_artifacts.sh"
fi

if have_file "$kernel_config"; then
    section "Kernel base"
    check_cfg CONFIG_ARCH_RV64I "kernel targets RV64"
    check_cfg CONFIG_MMU "kernel has MMU support"
    check_cfg CONFIG_RISCV_SBI "kernel has SBI support"
    check_cfg CONFIG_SERIAL_EARLYCON_RISCV_SBI "kernel has SBI early console"
    check_cfg CONFIG_HVC_RISCV_SBI "kernel has SBI HVC console"
    if cfg_enabled CONFIG_CMDLINE_FALLBACK &&
       cfg_disabled CONFIG_CMDLINE_FORCE &&
       cfg_disabled CONFIG_CMDLINE_EXTEND; then
        ok "kernel lets DTB bootargs select initramfs or virtio-root mode"
    else
        storage_blocked=1
        blocker "kernel command line must be fallback-only; FORCE/EXTEND would override or pollute DTB bootargs"
    fi
    check_cfg CONFIG_BINFMT_ELF "kernel can run ELF userspace"
    check_cfg CONFIG_BINFMT_SCRIPT "kernel can run script interpreters"
    check_cfg CONFIG_DEVTMPFS "kernel has devtmpfs"
    check_cfg CONFIG_DEVTMPFS_MOUNT "kernel auto-mounts devtmpfs"
    check_cfg CONFIG_TMPFS "kernel has tmpfs"
    check_cfg CONFIG_PROC_FS "kernel has procfs"
    check_cfg CONFIG_SYSFS "kernel has sysfs"
    check_cfg CONFIG_UNIX98_PTYS "kernel has PTY support"
    check_cfg CONFIG_NET "kernel has networking core"
    check_cfg CONFIG_UNIX "kernel has Unix sockets"
    check_cfg CONFIG_INET "kernel has IPv4"
    check_cfg CONFIG_BLOCK "kernel has block layer"

    section "Arch rv64gc ABI"
    if cfg_enabled CONFIG_FPU; then
        kernel_fpu_ready=1
        ok "kernel enables FPU context management"
    else
        fpu_blocked=1
        blocker "standard Arch rv64gc userspace expects F/D floating-point support; current kernel is soft-float"
    fi

    misa_hex="$(rtl_misa_hex "$core_rtl" || true)"
    if [[ -n "$misa_hex" ]]; then
        misa_low=$((16#${misa_hex: -8}))
        if (( (misa_low & 0x28) == 0x28 )); then
            rtl_fpu_ready=1
            ok "core MISA advertises F/D floating-point support"
        else
            fpu_blocked=1
            blocker "core MISA does not advertise both F and D; DTS must not claim rv64gc yet"
        fi
    else
        fpu_blocked=1
        blocker "cannot verify core CSR_MISA_VALUE in RTL"
    fi

    if cfg_enabled CONFIG_RISCV_ISA_C; then
        ok "kernel enables compressed ISA support"
    else
        blocker "RVC is disabled"
    fi

    section "Storage"
    if cfg_enabled CONFIG_VIRTIO_MMIO && cfg_enabled CONFIG_VIRTIO_BLK; then
        kernel_virtio_storage_ready=1
        kernel_storage_ready=1
        ok "kernel has virtio-mmio block support for the ZX64 storage path"
    elif cfg_enabled CONFIG_MMC || cfg_enabled CONFIG_USB_STORAGE; then
        kernel_storage_ready=1
        ok "kernel has a non-virtio persistent root block driver"
    else
        storage_blocked=1
        blocker "kernel lacks a persistent root block driver for the current board storage path"
    fi

    if have_file "$manifest"; then
        virtio_image="$(manifest_get ZX64_VIRTIO_BLK_IMAGE || true)"
        virtio_image_size="$(manifest_get ZX64_VIRTIO_BLK_IMAGE_SIZE || true)"
        virtio_image_sectors="$(manifest_get ZX64_VIRTIO_BLK_CAPACITY_SECTORS || true)"
        virtio_rootfs_ext4="$(manifest_get ZX64_VIRTIO_BLK_ROOTFS_EXT4 || true)"
        if [[ -n "$virtio_image" ]] &&
           is_uint "$virtio_image_size" &&
           is_uint "$virtio_image_sectors" &&
           (( virtio_image_size > 0 && virtio_image_sectors > 0 )) &&
           (( virtio_image_size / 512 == virtio_image_sectors )) &&
           [[ "$virtio_rootfs_ext4" == "1" ]] &&
           [[ -f "$virtio_image" ]] &&
           [[ "$(stat -c '%s' "$virtio_image")" == "$virtio_image_size" ]]; then
            storage_image_ready=1
            ok "boot manifest provides a verified ext4 virtio rootfs image"
        else
            storage_blocked=1
            blocker "boot manifest has no valid verified ext4 ZX64 virtio rootfs image; current boot remains initramfs-only"
        fi
    else
        storage_blocked=1
        blocker "boot manifest is missing, so no persistent root block image is proven"
    fi

    section "Kernel UI framework"
    if cfg_enabled CONFIG_DRM || cfg_enabled CONFIG_FB; then
        ok "kernel has a graphics console framework"
    else
        display_blocked=1
        blocker "KDE/local GUI needs DRM or framebuffer support; both are disabled"
    fi

    if cfg_enabled CONFIG_DRM_SIMPLEDRM || cfg_enabled CONFIG_FB_SIMPLE; then
        ok "kernel has a simple firmware framebuffer driver"
    else
        blocker "short GUI path needs CONFIG_DRM_SIMPLEDRM or CONFIG_FB_SIMPLE for a preconfigured framebuffer"
    fi

    if cfg_enabled CONFIG_VT; then
        ok "kernel has virtual terminal support for local graphical sessions"
    else
        blocker "local KDE/display-manager sessions normally need CONFIG_VT"
    fi

    if cfg_enabled CONFIG_FRAMEBUFFER_CONSOLE; then
        ok "kernel has framebuffer console support"
    else
        warn "kernel lacks framebuffer console; GUI can still start later, but local text fallback is weak"
    fi

    if (cfg_enabled CONFIG_DRM || cfg_enabled CONFIG_FB) &&
       (cfg_enabled CONFIG_DRM_SIMPLEDRM || cfg_enabled CONFIG_FB_SIMPLE) &&
       cfg_enabled CONFIG_VT &&
       cfg_enabled CONFIG_FRAMEBUFFER_CONSOLE; then
        kernel_ui_framework_done=1
    fi

    section "Input"
    if cfg_enabled CONFIG_INPUT && cfg_enabled CONFIG_INPUT_EVDEV; then
        kernel_input_ready=1
        ok "kernel has evdev input path"
    else
        input_blocked=1
        blocker "KDE/local GUI needs input/evdev support"
    fi

    if cfg_enabled CONFIG_VIRTIO_INPUT; then
        kernel_input_device_ready=1
        ok "kernel has the upstream virtio input driver"
    elif cfg_enabled CONFIG_KEYBOARD_GPIO || cfg_enabled CONFIG_KEYBOARD_GPIO_POLLED ||
         cfg_enabled CONFIG_SERIO || cfg_enabled CONFIG_USB_HID; then
        kernel_input_device_ready=1
        ok "kernel has a concrete local input device driver"
    else
        input_blocked=1
        blocker "evdev alone is not enough; kernel lacks a concrete local input device driver"
    fi

    section "Filesystems"
    if cfg_enabled CONFIG_EXT4_FS || cfg_enabled CONFIG_BTRFS_FS || cfg_enabled CONFIG_F2FS_FS; then
        ok "kernel has a common disk filesystem"
    else
        warn "no common disk filesystem is enabled yet; initramfs-only boot is still fine"
    fi

    if cfg_set CONFIG_INITRAMFS_SOURCE; then
        ok "kernel has an initramfs source configured"
    else
        warn "kernel has no initramfs source configured"
    fi
else
    warn "kernel config is missing; run scripts/prepare_mainline_rv64_linux.sh first"
fi

if have_file "$dts"; then
    section "Board description"
    if contains "$dts" 'riscv,isa = "rv64imac_zicsr_zifencei"'; then
        fpu_blocked=1
        blocker "DTS advertises RV64IMAC only; Arch rv64gc needs F/D-capable ISA"
    elif contains "$dts" 'riscv,isa = "rv64gc_zicsr_zifencei"' &&
         contains "$dts" 'riscv,isa-extensions = "i", "m", "a", "f", "d", "c", "zicsr", "zifencei"'; then
        dts_fpu_ready=1
        ok "DTS advertises RV64GC"
    else
        fpu_blocked=1
        blocker "DTS ISA string/extensions do not match the RV64GC F/D contract"
    fi

    if contains "$dts" 'mmu-type = "riscv,sv39"'; then
        ok "DTS advertises Sv39"
    else
        blocker "DTS does not advertise Sv39"
    fi

    if contains "$dts" 'i-cache-block-size = <32>' &&
       contains "$dts" 'i-cache-sets = <16>' &&
       contains "$dts" 'i-cache-size = <512>' &&
       contains "$dts" 'd-cache-block-size = <32>' &&
       contains "$dts" 'd-cache-sets = <32>' &&
       contains "$dts" 'd-cache-size = <1024>'; then
        ok "DTS describes the current I/D cache geometry"
    else
        warn "DTS does not fully describe the current I/D cache geometry"
    fi

    if contains "$dts" 'vram@bc000000' && contains "$dts" 'reg = <0x0 0xbc000000 0x0 0x04000000>'; then
        ok "DTS reserves the 64 MiB VRAM window"
    else
        blocker "DTS does not reserve 0xbc000000..0xbfffffff VRAM from normal memory"
    fi

    if [[ "$(manifest_get ZX64_VIRTIO_BLK_IMAGE_PRESENT || true)" == "1" ]]; then
        if contains "$dts" 'virtio-blk-image@88000000' &&
           contains "$dts" 'reg = <0x0 0x88000000 0x0 0x04000000>' &&
           node_contains "$dts" 'virtio-blk-image@88000000' 'no-map'; then
            ok "DTS reserves the ZX64 virtio rootfs backing image from Linux RAM"
        else
            storage_blocked=1
            blocker "DTS does not reserve 0x88000000..0x8bffffff for the ZX64 virtio rootfs backing image"
        fi
        if contains "$ps_launcher_src" 'Xil_DCacheDisable();' &&
           contains "$soc_rtl" 'if (virtio_blk_backend_irq || virtio_input_backend_irq)' &&
           contains "$soc_rtl" "dcache_valid <= '0;"; then
            ok "virtio backend cache-coherency contract is covered by PS D-cache disable and PL D-cache invalidation"
        else
            storage_blocked=1
            blocker "virtio backend cache-coherency contract is not proven by PS D-cache disable plus PL D-cache invalidation"
        fi
    fi

    if node_contains "$dts" 'chosen' "bootargs[[:space:]]*=[[:space:]]*\"$virtio_root_bootargs\"" &&
       ! contains "$dts" 'rdinit=/init'; then
        dts_storage_bootargs_ready=1
        ok "effective DTS bootargs select /dev/vda as the root filesystem"
    else
        storage_blocked=1
        blocker "effective DTS bootargs do not select the ZX64 virtio /dev/vda root filesystem"
    fi

    section "Board storage/display/input devices"
    if node_contains "$dts" 'interrupt-controller@c000000' 'sifive,plic-1.0.0' &&
       node_contains "$dts" 'interrupt-controller@c000000' 'reg[[:space:]]*=[[:space:]]*<0x0 0x0c000000 0x0 0x00400000>' &&
       node_contains "$dts" 'interrupt-controller@c000000' 'interrupts-extended[[:space:]]*=[[:space:]]*<&cpu0_intc 9>'; then
        if node_contains "$dts" 'interrupt-controller@c000000' 'status[[:space:]]*=[[:space:]]*"okay"'; then
            dts_plic_ready=1
            ok "DTS enables the standard PLIC interrupt controller"
        else
            storage_blocked=1
            blocker "DTS describes the standard PLIC skeleton but keeps it disabled"
        fi
    else
        storage_blocked=1
        blocker "DTS lacks the standard PLIC node needed by virtio-mmio interrupts"
    fi

    if node_contains "$dts" 'virtio@10060000' 'compatible[[:space:]]*=[[:space:]]*"virtio,mmio"' &&
       node_contains "$dts" 'virtio@10060000' 'reg[[:space:]]*=[[:space:]]*<0x0 0x10060000 0x0 0x1000>' &&
       node_contains "$dts" 'virtio@10060000' 'interrupts-extended[[:space:]]*=[[:space:]]*<&plic0 1>'; then
        if node_contains "$dts" 'virtio@10060000' 'status[[:space:]]*=[[:space:]]*"okay"'; then
            dts_virtio_ready=1
            ok "DTS enables virtio-mmio block transport at 0x10060000"
        else
            storage_blocked=1
            blocker "DTS describes virtio-mmio at 0x10060000 but keeps it disabled"
        fi
    else
        storage_blocked=1
        blocker "DTS exposes no enabled standard virtio-mmio root-storage device"
    fi

    if (( dts_plic_ready && dts_virtio_ready )); then
        dts_storage_ready=1
        ok "DTS exposes an enabled interrupt-backed virtio storage path"
    else
        info "disabled or private storage devices are intentionally not counted as Arch-ready"
    fi

    if (node_contains "$dts" 'framebuffer@bc000000' 'compatible[[:space:]]*=[[:space:]]*"simple-framebuffer"' ||
        node_contains "$dts" 'framebuffer@bc000000' 'compatible[[:space:]]*=[[:space:]]*"simple-framebuffer",') &&
       node_contains "$dts" 'framebuffer@bc000000' 'reg[[:space:]]*=[[:space:]]*<0x0 0xbc000000 0x0 0x007e9000>' &&
       node_contains "$dts" 'framebuffer@bc000000' 'width[[:space:]]*=[[:space:]]*<1920>' &&
       node_contains "$dts" 'framebuffer@bc000000' 'height[[:space:]]*=[[:space:]]*<1080>' &&
       node_contains "$dts" 'framebuffer@bc000000' 'stride[[:space:]]*=[[:space:]]*<7680>' &&
       node_contains "$dts" 'framebuffer@bc000000' 'format[[:space:]]*=[[:space:]]*"x8r8g8b8"' &&
       node_contains "$dts" 'framebuffer@bc000000' 'status[[:space:]]*=[[:space:]]*"okay"'; then
        dts_display_ready=1
        ok "DTS exposes an enabled 1920x1080 XRGB8888 simple-framebuffer graphics contract"
    elif node_contains "$dts" 'framebuffer@bc000000' 'compatible[[:space:]]*=[[:space:]]*"simple-framebuffer"'; then
        display_blocked=1
        blocker "DTS has a simple-framebuffer template, but it is not enabled with the expected VRAM geometry"
    elif node_contains "$dts" 'display@10080000' 'status[[:space:]]*=[[:space:]]*"okay"'; then
        display_blocked=1
        blocker "DTS enables a custom display node, but there is no upstream Linux driver contract for it"
    elif contains "$dts" 'display@10080000' || contains "$dts" 'framebuffer@'; then
        display_blocked=1
        blocker "DTS has only disabled/private display nodes; Linux has no bindable graphics device"
    else
        display_blocked=1
        blocker "DTS exposes no display path"
    fi

    if node_contains "$dts" 'virtio@10090000' 'compatible[[:space:]]*=[[:space:]]*"virtio,mmio"' &&
       node_contains "$dts" 'virtio@10090000' 'reg[[:space:]]*=[[:space:]]*<0x0 0x10090000 0x0 0x1000>' &&
       node_contains "$dts" 'virtio@10090000' 'interrupts-extended[[:space:]]*=[[:space:]]*<&plic0 2>'; then
        if node_contains "$dts" 'virtio@10090000' 'status[[:space:]]*=[[:space:]]*"okay"'; then
            if (( manifest_input_ready )); then
                dts_input_ready=1
                dts_virtio_input_ready=1
                ok "DTS enables a second virtio-mmio endpoint reserved for local input"
            else
                input_blocked=1
                blocker "DTS enables virtio-input, but the boot manifest does not select that input contract"
            fi
        else
            input_blocked=1
            blocker "DTS describes the virtio-mmio input endpoint at 0x10090000 but keeps it disabled"
        fi
    elif node_contains "$dts" 'gpio-keys' 'status[[:space:]]*=[[:space:]]*"okay"' ||
         contains "$dts" 'usb@' || contains "$dts" 'ps2@' ||
         contains "$dts" 'keyboard@' || contains "$dts" 'mouse@' || contains "$dts" 'touchscreen@'; then
        dts_input_ready=1
        ok "DTS exposes a plausible local input device path"
    elif contains "$dts" 'virtio_input0' || contains "$dts" 'virtio@10090000' ||
         contains "$dts" 'gpio-keys' || contains "$dts" 'keyboard@' ||
         contains "$dts" 'mouse@' || contains "$dts" 'touchscreen@'; then
        input_blocked=1
        blocker "DTS has only disabled/private input nodes; Linux has no enabled bindable input device"
    else
        input_blocked=1
        blocker "DTS exposes no local input device for evdev"
    fi
else
    warn "DTS is missing"
fi

if have_file "$firmware"; then
    section "SBI firmware"
    if contains_all "$firmware" \
       'sbi_legacy_timer' \
       'sbi_legacy_clear_ipi' \
       'sbi_legacy_send_ipi' \
       'sbi_legacy_remote_fence_i' \
       'sbi_legacy_remote_sfence_vma' \
       'sbi_legacy_remote_sfence_vma_asid' \
       'sbi_legacy_shutdown' \
       'sbi_console_putchar' \
       'sbi_console_getchar'; then
        sbi_legacy_done=1
        ok "SBI legacy v0.1 calls are covered for current Linux boot"
    else
        blocker "SBI firmware is missing one of the legacy timer/console/IPI/RFENCE/shutdown calls"
    fi

    if contains_all "$firmware" \
       'SBI_EXT_BASE' \
       'SBI_EXT_TIME' \
       'SBI_EXT_IPI' \
       'SBI_EXT_RFENCE' \
       'SBI_EXT_HSM' \
       'SBI_EXT_PMU' \
       'SBI_EXT_DBCN' \
       'SBI_EXT_SRST' \
       'sbi_base' \
       'sbi_base_probe' \
       'sbi_time' \
       'sbi_ipi' \
       'sbi_rfence' \
       'sbi_hsm' \
       'sbi_pmu' \
       'sbi_dbcn' \
       'sbi_system_reset'; then
        sbi_basic_done=1
        ok "SBI BASE/TIME/IPI/RFENCE/HSM/PMU/DBCN/SRST coverage is present"
    else
        blocker "SBI shim is missing one of BASE/TIME/IPI/RFENCE/HSM/PMU/DBCN/SRST"
    fi

    if contains "$firmware" 'OpenSBI'; then
        ok "firmware appears to be OpenSBI-based"
    else
        info "firmware is still a local shim; current SBI coverage is no longer the active Arch blocker"
    fi
else
    warn "SBI firmware is missing"
fi

section "RV64GC hardware implementation"
if (( fpu_blocked )); then
    hardware_blocker "RV64GC hardware signoff cannot pass until kernel, RTL MISA, and DTS all agree on F/D support"
else
    ok "RV64GC software-visible F/D contract is internally consistent"
fi

if [[ "${ZYNQ_CPU_RV64_ENABLE_FPU:-}" == "0" ]]; then
    hardware_blocker "ZYNQ_CPU_RV64_ENABLE_FPU=0 would build a non-RV64GC bitstream"
elif contains "$vivado_hw_tcl" 'set rv64_enable_fpu 1' &&
     ! contains "$vivado_hw_tcl" 'set rv64_enable_fpu 0'; then
    rv64gc_hw_fpu_default_ready=1
    ok "Vivado RV64 hardware build defaults to FPU enabled"
else
    hardware_blocker "Vivado RV64 hardware build does not prove an FPU-enabled default"
fi

if [[ -s "$bitstream_bit" && -s "$bitstream_xsa" && -s "$bitstream_timing" && -s "$bitstream_util" ]]; then
    setup_line="$(grep -m1 -E '^Setup[[:space:]]*:' "$bitstream_timing" || true)"
    if [[ -n "$setup_line" ]]; then
        setup_failing="$(sed -E 's/^Setup[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]+Failing Endpoints.*/\1/' <<<"$setup_line")"
        wns="$(sed -E 's/.*Worst Slack[[:space:]]+([-0-9.]+)ns.*/\1/' <<<"$setup_line")"
        if [[ "$setup_failing" =~ ^[0-9]+$ &&
              "$wns" =~ ^-?[0-9]+([.][0-9]+)?$ &&
              "$setup_failing" == "0" ]] &&
           awk -v wns="$wns" 'BEGIN { exit !(wns >= 0.0) }'; then
            rv64gc_hw_bitstream_ready=1
            rv64gc_hw_timing_ready=1
            ok "implemented RV64GC bitstream exists, fits the device, and passes setup timing (WNS=${wns}ns)"
        else
            hardware_blocker "implemented RV64GC bitstream artifacts exist, but setup timing does not pass: $setup_line"
        fi
    else
        hardware_blocker "implemented RV64GC bitstream artifacts exist, but the timing report has no setup summary"
    fi
else
    hardware_blocker "implemented RV64GC bitstream artifacts are missing; run scripts/check_zx64_vivado_bitstream.sh to prove the FPU-enabled design fits and passes implementation"
fi

echo
echo "Current capability status:"
if (( sbi_legacy_done )); then
    echo "  SBI legacy coverage:      done"
else
    echo "  SBI legacy coverage:      blocked"
fi
if (( sbi_basic_done )); then
    echo "  SBI basic boot coverage:  done"
else
    echo "  SBI basic boot coverage:  blocked"
fi
if (( kernel_ui_framework_done )); then
    echo "  kernel UI framework:      done"
else
    echo "  kernel UI framework:      blocked"
fi
if (( fpu_blocked )); then
    echo "  FPU/rv64gc software ABI:  blocked (kernel FPU=$kernel_fpu_ready, RTL F/D=$rtl_fpu_ready, DTS rv64gc=$dts_fpu_ready)"
else
    echo "  FPU/rv64gc software ABI:  ready"
fi
if (( storage_blocked )); then
    echo "  persistent storage path:  blocked (kernel driver=$kernel_storage_ready, virtio-mmio=$kernel_virtio_storage_ready, PLIC=$dts_plic_ready, DTS virtio=$dts_virtio_ready, bootargs=$dts_storage_bootargs_ready, manifest=$manifest_storage_ready, image=$storage_image_ready)"
else
    echo "  persistent storage path:  ready"
fi
if (( display_blocked )); then
    echo "  local display path:       blocked (kernel UI=$kernel_ui_framework_done, DTS display=$dts_display_ready)"
else
    echo "  local display path:       ready"
fi
if (( input_blocked )); then
    echo "  local input path:         blocked (kernel evdev=$kernel_input_ready, kernel device=$kernel_input_device_ready, DTS input=$dts_input_ready, virtio-input=$dts_virtio_input_ready)"
else
    echo "  local input path:         ready"
fi
if (( hardware_blocker_count )); then
    echo "  RV64GC hardware signoff:  blocked (FPU default=$rv64gc_hw_fpu_default_ready, bitstream=$rv64gc_hw_bitstream_ready, timing=$rv64gc_hw_timing_ready)"
else
    echo "  RV64GC hardware signoff:  ready"
fi
echo
echo "Summary: blockers=$blocker_count warnings=$warn_count hardware_blockers=$hardware_blocker_count"
if (( blocker_count == 0 )); then
    echo "ZX64 RV64 Linux/standard-kernel readiness: PASS"
else
    echo "ZX64 RV64 Linux/standard-kernel readiness: not ready for Arch/KDE yet"
fi
if (( blocker_count == 0 && hardware_blocker_count == 0 )); then
    echo "ZX64 RV64GC hardware readiness: PASS"
else
    echo "ZX64 RV64GC hardware readiness: not proven; requires an FPU-enabled bitstream that fits and passes implementation"
fi

if (( strict && blocker_count > 0 )); then
    exit 1
fi
