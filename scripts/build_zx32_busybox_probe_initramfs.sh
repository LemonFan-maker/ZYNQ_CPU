#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${ZX32_BUSYBOX_PROBE_SRC:-$repo_dir/linux/initramfs/busybox_probe.S}"
stage_src="${ZX32_BUSYBOX_STAGE_SRC:-$repo_dir/linux/initramfs/busybox_stage.sh}"
buildroot_target="${BUILDROOT_TARGET_DIR:-$repo_dir/build/buildroot-zx32/target}"
out_dir="${ZX32_BUSYBOX_PROBE_OUT:-$repo_dir/build/busybox-probe-initramfs}"
init_mode="${ZX32_BUSYBOX_INIT_MODE:-probe}"
prefix="${CROSS_COMPILE:-}"

if [[ -z "$prefix" ]]; then
    for candidate in \
        "$repo_dir/build/buildroot-zx32/host/bin/riscv32-buildroot-linux-musl-" \
        riscv32-linux-gnu- riscv64-linux-gnu- riscv32-unknown-linux-gnu- riscv64-unknown-linux-gnu-; do
        if command -v "${candidate}as" >/dev/null 2>&1 && command -v "${candidate}ld" >/dev/null 2>&1; then
            prefix="$candidate"
            break
        fi
    done
fi

if [[ -z "$prefix" ]]; then
    echo "No RISC-V assembler/linker found in PATH." >&2
    exit 2
fi

if [[ ! -d "$buildroot_target" ]]; then
    echo "Buildroot target rootfs not found: $buildroot_target" >&2
    echo "Run scripts/build_zx32_busybox_rootfs.sh first." >&2
    exit 2
fi

mkdir -p "$out_dir"

"${prefix}as" -march=rv32ima_zicsr_zifencei -mabi=ilp32 "$src" -o "$out_dir/init.o"
"${prefix}ld" -melf32lriscv -nostdlib -static -e _start "$out_dir/init.o" -o "$out_dir/init"
if command -v "${prefix}strip" >/dev/null 2>&1; then
    "${prefix}strip" "$out_dir/init"
fi

root_dir="$out_dir/root"
rm -rf "$root_dir"
mkdir -p "$root_dir"
cp -a "$buildroot_target"/. "$root_dir"/
rm -f "$root_dir/dev/fd" "$root_dir/dev/stdin" "$root_dir/dev/stdout" "$root_dir/dev/stderr"

cat > "$root_dir/etc/init.d/S02sysctl" <<'EOF'
#!/bin/sh

case "$1" in
    start|restart|reload)
        printf 'Running sysctl: '
        status=0
        for file in /etc/sysctl.d/*.conf /usr/local/lib/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf /etc/sysctl.conf; do
            [ -f "$file" ] || continue
            /sbin/sysctl -p "$file" >/dev/null || status=1
        done
        [ "$status" -eq 0 ] && echo "OK" || echo "FAIL"
        exit "$status"
        ;;
    stop)
        exit 0
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|reload}"
        exit 1
        ;;
esac
EOF
chmod 0755 "$root_dir/etc/init.d/S02sysctl"

case "$init_mode" in
    probe)
        rm -f "$root_dir/init"
        cp "$out_dir/init" "$root_dir/init"
        chmod 0755 "$root_dir/init"
        cp "$stage_src" "$root_dir/zx32-stage"
        chmod 0755 "$root_dir/zx32-stage"
        ;;
    full)
        rm -f "$root_dir/init" "$root_dir/zx32-stage"
        ln -s /sbin/init "$root_dir/init"
        ;;
    *)
        echo "Unknown ZX32_BUSYBOX_INIT_MODE: $init_mode" >&2
        exit 2
        ;;
esac

list="$out_dir/initramfs-probe.list"
gen_init_cpio="${GEN_INIT_CPIO:-$repo_dir/build/linux-mainline-rv32/usr/gen_init_cpio}"
if [[ ! -x "$gen_init_cpio" ]]; then
    echo "gen_init_cpio not found: $gen_init_cpio" >&2
    echo "Build the Linux kernel once first, or set GEN_INIT_CPIO." >&2
    exit 2
fi

emit_entry() {
    local path="$1"
    local rel mode kind

    rel="${path#$root_dir/}"
    [[ "$rel" == "$path" || "$rel" == "." ]] && return
    [[ "$rel" == "THIS_IS_NOT_YOUR_ROOT_FILESYSTEM" ]] && return
    mode="$(stat -c '%a' "$path")"
    kind="$(stat -c '%F' "$path")"

    case "$kind" in
        directory)
            printf 'dir /%s 0%s 0 0\n' "$rel" "$mode"
            ;;
        "symbolic link")
            printf 'slink /%s %s 0%s 0 0\n' "$rel" "$(readlink "$path")" "$mode"
            ;;
        "regular file"|"regular empty file")
            printf 'file /%s %s 0%s 0 0\n' "$rel" "$path" "$mode"
            ;;
    esac
}

{
    find "$root_dir" -xdev -type d -print | LC_ALL=C sort | while IFS= read -r path; do
        emit_entry "$path"
    done
    find "$root_dir" -xdev ! -type d -print | LC_ALL=C sort | while IFS= read -r path; do
        emit_entry "$path"
    done

    echo "nod /dev/console 0600 0 0 c 5 1"
    echo "nod /dev/hvc0 0600 0 0 c 229 0"
    echo "nod /dev/null 0666 0 0 c 1 3"
} > "$list"

"$gen_init_cpio" "$list" > "$out_dir/rootfs-probe.cpio"

echo "Probe init: $out_dir/init"
echo "Probe list: $list"
echo "Probe rootfs: $out_dir/rootfs-probe.cpio"
