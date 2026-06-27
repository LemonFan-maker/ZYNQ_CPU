#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PERL5LIB
unset RUBYLIB
unset CMAKE_PREFIX_PATH
linux_src="${LINUX_SRC:-$repo_dir/linux/kernel}"
linux_out="${LINUX_OUT:-$repo_dir/build/linux-mainline-rv32}"
fragment="${LINUX_CONFIG_FRAGMENT:-$repo_dir/linux/zx32_rv32.config}"
base_config="${LINUX_BASE_CONFIG:-allnoconfig}"
riscv_march="${ZX32_RISCV_MARCH:-rv32ima_zicsr_zifencei}"
jobs="${JOBS:-$(nproc)}"
initramfs_list="${LINUX_INITRAMFS_SOURCE:-}"
buildroot_cpio="${ZX32_BUILDROOT_CPIO:-$repo_dir/build/buildroot-zx32/images/rootfs.cpio}"

if [[ ! -d "$linux_src" ]]; then
    echo "Linux source not found: $linux_src" >&2
    echo "Run scripts/prepare_mainline_linux.sh first, or set LINUX_SRC." >&2
    exit 2
fi

if [[ -z "${CROSS_COMPILE:-}" ]]; then
    for prefix in \
        "$repo_dir/build/buildroot-zx32/host/bin/riscv32-buildroot-linux-musl-" \
        "$repo_dir/build/buildroot-zx32/host/bin/riscv32-linux-" \
        "$repo_dir/build/buildroot-zx32/host/bin/riscv32-buildroot-linux-gnu-" \
        "$repo_dir/build/buildroot-zx32/host/bin/riscv32-linux-gnu-"; do
        if [[ -x "${prefix}gcc" ]]; then
            CROSS_COMPILE="$prefix"
            break
        fi
    done
fi

if [[ -z "${CROSS_COMPILE:-}" ]]; then
    for prefix in riscv32-linux-gnu- riscv64-linux-gnu- riscv32-unknown-linux-gnu- riscv64-unknown-linux-gnu-; do
        if command -v "${prefix}gcc" >/dev/null 2>&1; then
            CROSS_COMPILE="$prefix"
            break
        fi
    done
fi

if [[ -z "${CROSS_COMPILE:-}" ]]; then
    echo "No RISC-V Linux cross compiler found in PATH." >&2
    echo "Set CROSS_COMPILE, for example CROSS_COMPILE=/path/to/riscv32-linux-gnu-." >&2
    exit 2
fi

mkdir -p "$linux_out"

config_fragment="$fragment"
if [[ "${ZX32_INITRAMFS:-1}" != "0" && -z "$initramfs_list" ]]; then
    if [[ ! -f "$buildroot_cpio" ]]; then
        echo "No initramfs selected and Buildroot rootfs not found: $buildroot_cpio" >&2
        echo "Run scripts/build_zx32_busybox_rootfs.sh, set LINUX_INITRAMFS_SOURCE, or set ZX32_INITRAMFS=0." >&2
        exit 2
    fi
    initramfs_list="$buildroot_cpio"
fi

if [[ -n "$initramfs_list" ]]; then
    generated_fragment="$linux_out/zx32_rv32.generated.config"
    awk '!/^CONFIG_INITRAMFS_SOURCE=/' "$fragment" > "$generated_fragment"
    printf 'CONFIG_INITRAMFS_SOURCE="%s"\n' "$initramfs_list" >> "$generated_fragment"
    config_fragment="$generated_fragment"
fi

if [[ "$base_config" == "allnoconfig" ]]; then
    if [[ ! -f "$config_fragment" ]]; then
        echo "Config fragment not found: $config_fragment" >&2
        exit 2
    fi
    KCONFIG_ALLCONFIG="$config_fragment" \
        make -C "$linux_src" O="$linux_out" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" allnoconfig
else
    make -C "$linux_src" O="$linux_out" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" "$base_config"
fi

if [[ -f "$config_fragment" && "$base_config" != "allnoconfig" ]]; then
    "$linux_src/scripts/kconfig/merge_config.sh" -m -O "$linux_out" "$linux_out/.config" "$config_fragment"
fi

make -C "$linux_src" O="$linux_out" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

make -C "$linux_src" O="$linux_out" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" \
    KCFLAGS="-march=$riscv_march" KAFLAGS="-march=$riscv_march" -j "$jobs" Image

echo "Linux build output: $linux_out"
echo "Kernel Image:       $linux_out/arch/riscv/boot/Image"
