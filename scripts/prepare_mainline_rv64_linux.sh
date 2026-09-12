#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PERL5LIB
unset RUBYLIB
unset CMAKE_PREFIX_PATH

linux_src="${LINUX_SRC:-$repo_dir/linux/kernel-v7.1.3}"
linux_tag="${LINUX_TAG:-v7.1.3}"
remote="${LINUX_REMOTE:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"
linux_out="${LINUX_OUT:-$repo_dir/build/linux-mainline-rv64}"
fragment="${LINUX_CONFIG_FRAGMENT:-$repo_dir/linux/zx64_rv64.config}"
base_config="${LINUX_BASE_CONFIG:-allnoconfig}"
riscv_march="${ZX64_RISCV_MARCH:-rv64imafdc_zicsr_zifencei}"
jobs="${JOBS:-$(nproc)}"
initramfs_list="${LINUX_INITRAMFS_SOURCE:-}"
buildroot_cpio="${ZX64_BUILDROOT_CPIO:-$repo_dir/build/buildroot-zx64/images/rootfs.cpio}"

if [[ ! -d "$linux_src/.git" ]]; then
    git clone --branch "$linux_tag" --depth 1 "$remote" "$linux_src"
elif ! git -C "$linux_src" rev-parse --verify --quiet "$linux_tag^{commit}" >/dev/null; then
    git -C "$linux_src" fetch --tags "$remote" "$linux_tag"
fi

if ! git -C "$linux_src" rev-parse --verify --quiet "$linux_tag^{commit}" >/dev/null; then
    echo "Linux tag not present locally: $linux_tag" >&2
    echo "Fetch it with:" >&2
    echo "  git -C $linux_src fetch --tags $remote $linux_tag" >&2
    exit 2
fi

compiler_mode="gnu"
if [[ -z "${CROSS_COMPILE:-}" ]]; then
    for prefix in \
        "$repo_dir/build/buildroot-zx64/host/bin/riscv64-buildroot-linux-musl-" \
        "$repo_dir/build/buildroot-zx64/host/bin/riscv64-linux-" \
        "$repo_dir/build/buildroot-zx64/host/bin/riscv64-buildroot-linux-gnu-" \
        "$repo_dir/build/buildroot-zx64/host/bin/riscv64-linux-gnu-"; do
        if [[ -x "${prefix}gcc" ]]; then
            CROSS_COMPILE="$prefix"
            break
        fi
    done
fi

if [[ -z "${CROSS_COMPILE:-}" ]]; then
    for prefix in riscv64-linux-gnu- riscv64-unknown-linux-gnu-; do
        if command -v "${prefix}gcc" >/dev/null 2>&1; then
            CROSS_COMPILE="$prefix"
            break
        fi
    done
fi

if [[ -z "${CROSS_COMPILE:-}" ]]; then
    if [[ "${ZX64_USE_LLVM:-1}" == "0" ]]; then
        echo "No RV64 Linux cross compiler found in PATH." >&2
        echo "Set CROSS_COMPILE, for example CROSS_COMPILE=/path/to/riscv64-linux-gnu-." >&2
        exit 2
    fi
    for tool in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-readelf llvm-strip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "No RV64 GNU compiler found and LLVM tool is missing: $tool" >&2
            echo "Install a riscv64-linux GNU toolchain, set CROSS_COMPILE, or install LLVM tools." >&2
            exit 2
        fi
    done
    compiler_mode="llvm"
fi

mkdir -p "$linux_out"

make_args=(O="$linux_out" ARCH=riscv)
if [[ "$compiler_mode" == "gnu" ]]; then
    make_args+=(CROSS_COMPILE="$CROSS_COMPILE")
else
    make_args+=(LLVM=1 LLVM_IAS=1)
fi

config_fragment="$fragment"
if [[ "${ZX64_INITRAMFS:-1}" != "0" && -z "$initramfs_list" ]]; then
    if [[ -f "$buildroot_cpio" ]]; then
        initramfs_list="$buildroot_cpio"
    else
        echo "No RV64 initramfs selected; building kernel without embedded initramfs." >&2
        echo "Set LINUX_INITRAMFS_SOURCE, create $buildroot_cpio, or set ZX64_INITRAMFS=0 to silence this." >&2
    fi
fi

if [[ -n "$initramfs_list" ]]; then
    generated_fragment="$linux_out/zx64_rv64.generated.config"
    awk '!/^CONFIG_INITRAMFS_SOURCE=/' "$fragment" > "$generated_fragment"
    printf 'CONFIG_INITRAMFS_SOURCE="%s"\n' "$initramfs_list" >> "$generated_fragment"
    config_fragment="$generated_fragment"
fi

git -C "$linux_src" checkout "$linux_tag"
if [[ -n "$(git -C "$linux_src" status --porcelain)" ]]; then
    echo "Linux source worktree is dirty after checkout: $linux_src" >&2
    echo "Commit, stash, or clean the Linux source before preparing a reproducible Image." >&2
    exit 1
fi

if [[ "$base_config" == "allnoconfig" ]]; then
    if [[ ! -f "$config_fragment" ]]; then
        echo "Config fragment not found: $config_fragment" >&2
        exit 2
    fi
    KCONFIG_ALLCONFIG="$config_fragment" make -C "$linux_src" "${make_args[@]}" allnoconfig
elif [[ -f "$config_fragment" ]]; then
    make -C "$linux_src" "${make_args[@]}" "$base_config"
    "$linux_src/scripts/kconfig/merge_config.sh" -m -O "$linux_out" "$linux_out/.config" "$config_fragment"
else
    make -C "$linux_src" "${make_args[@]}" "$base_config"
fi

make -C "$linux_src" "${make_args[@]}" olddefconfig

make -C "$linux_src" "${make_args[@]}" \
    KCFLAGS="-march=$riscv_march" KAFLAGS="-march=$riscv_march" -j "$jobs" Image

echo "Linux tag:          $linux_tag"
echo "Compiler mode:      $compiler_mode"
echo "Linux build output: $linux_out"
echo "Kernel Image:       $linux_out/arch/riscv/boot/Image"
