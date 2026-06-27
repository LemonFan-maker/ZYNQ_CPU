#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_dir/build/zx32sim-smokes"
mkdir -p "$build_dir"

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/entry_smoke.zx32.s" \
    -o "$build_dir/entry_smoke.elf" \
    --load-addr 0x0

python3 -m tools.zx32sim.main "$build_dir/entry_smoke.elf" \
    --max-steps 1000 \
    --stop-pc 0x20 \
    --expect-word 0x200103f0=0xabcd1234

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/machine_trap_smoke.zx32.s" \
    -o "$build_dir/machine_trap_smoke.elf" \
    --load-addr 0x0

python3 -m tools.zx32sim.main "$build_dir/machine_trap_smoke.elf" \
    --max-steps 1000 \
    --stop-pc 0x3c \
    --expect-word 80=12 \
    --expect-word 84=0x99 \
    --expect-word 88=11

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/supervisor_smoke.zx32.s" \
    -o "$build_dir/supervisor_smoke.elf" \
    --load-addr 0x0

python3 -m tools.zx32sim.main "$build_dir/supervisor_smoke.elf" \
    --max-steps 1000 \
    --stop-pc 0xa8 \
    --expect-word 0x200103e0=0x38 \
    --expect-word 0x200103e4=9 \
    --expect-word 0x200103e8=0x5a \
    --expect-word 0x200103f0=0x222

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/supervisor_timer_smoke.zx32.s" \
    -o "$build_dir/supervisor_timer_smoke.elf" \
    --load-addr 0x0

python3 -m tools.zx32sim.main "$build_dir/supervisor_timer_smoke.elf" \
    --max-steps 1000 \
    --stop-pc 0xac \
    --expect-word 0x200103e4=0x80000005 \
    --expect-word 0x200103e8=0x5a \
    --expect-word 0x200103f0=0x222

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/sbi_firmware_smoke.zx32.s" \
    -o "$build_dir/sbi_firmware_smoke.elf" \
    --load-addr 0x0

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/sbi_payload_smoke.zx32.s" \
    -o "$build_dir/sbi_payload_smoke.elf" \
    --load-addr 0x80000000

python3 -m tools.zx32sim.main "$build_dir/sbi_firmware_smoke.elf" \
    --load-elf "$build_dir/sbi_payload_smoke.elf" \
    --max-steps 1000 \
    --stop-pc 0x80000028 \
    --poke-word 0x20010380=0x80000000 \
    --poke-word 0x20010384=0x80001000 \
    --expect-word 0x2001038c=9 \
    --expect-word 0x20010394=1 \
    --expect-word 0x20010398=0x12345678 \
    --expect-word 0x2001039c=0x53424921 \
    --expect-word 0x200103a0=0 \
    --expect-word 0x200103a4=0x80001000 \
    --expect-word 0x200103a8=0 \
    --expect-word 0x200103f0=0x222

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/sbi_timer_firmware_smoke.zx32.s" \
    -o "$build_dir/sbi_timer_firmware_smoke.elf" \
    --load-addr 0x0

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/sbi_timer_payload_smoke.zx32.s" \
    -o "$build_dir/sbi_timer_payload_smoke.elf" \
    --load-addr 0x80000000

python3 -m tools.zx32sim.main "$build_dir/sbi_timer_firmware_smoke.elf" \
    --load-elf "$build_dir/sbi_timer_payload_smoke.elf" \
    --max-steps 10000 \
    --stop-pc 0x80000098 \
    --poke-word 0x20010340=0x80000000 \
    --poke-word 0x20010344=0x80001000 \
    --expect-word 0x2001034c=9 \
    --expect-word 0x20010354=0x54494d45 \
    --expect-word 0x20010358=0 \
    --expect-word 0x20010380=0 \
    --expect-word 0x20010384=0x80001000 \
    --expect-word 0x20010388=0 \
    --expect-word 0x2001038c=0x80000005 \
    --expect-word 0x200103f0=0x222

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/linux_contract_firmware_smoke.zx32.s" \
    -o "$build_dir/linux_contract_firmware_smoke.elf" \
    --load-addr 0x0

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/linux_contract_payload_smoke.zx32.s" \
    -o "$build_dir/linux_contract_payload_smoke.elf" \
    --load-addr 0x80000000

python3 "$repo_dir/scripts/make_zx32sim_contract_dtb.py" \
    "$build_dir/linux_contract_dtb.bin"

python3 -m tools.zx32sim.main "$build_dir/linux_contract_firmware_smoke.elf" \
    --load-elf "$build_dir/linux_contract_payload_smoke.elf" \
    --load-raw 0x80000800="$build_dir/linux_contract_dtb.bin" \
    --max-steps 10000 \
    --stop-pc 0x80000508 \
    --poke-word 0x20010300=0x80000000 \
    --poke-word 0x20010304=0x80000800 \
    --expect-word 0x20010308=9 \
    --expect-word 0x20010310=0x54494d45 \
    --expect-word 0x20010314=0 \
    --expect-word 0x2001031c=0 \
    --expect-word 0x20010328=0 \
    --expect-word 0x2001032c=0x80000800 \
    --expect-word 0x20010330=0xd00dfeed \
    --expect-word 0x20010334=2 \
    --expect-word 0x20010338=0x80000005 \
    --expect-word 0x20010348=0x100 \
    --expect-word 0x2001034c=0x38 \
    --expect-word 0x20010350=0xa0 \
    --expect-word 0x20010354=1 \
    --expect-word 0x20010358=1 \
    --expect-word 0x2001035c=1 \
    --expect-word 0x20010360=1 \
    --expect-word 0x20010364=0x80000000 \
    --expect-word 0x20010368=0x40000000 \
    --expect-word 0x200103f0=0x222

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/linux_sbi_firmware_smoke.zx32.s" \
    -o "$build_dir/linux_sbi_firmware_smoke.elf" \
    --load-addr 0x0

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/linux_sbi_payload_smoke.zx32.s" \
    -o "$build_dir/linux_sbi_payload_smoke.elf" \
    --load-addr 0x80000000

python3 -m tools.zx32sim.main "$build_dir/linux_sbi_firmware_smoke.elf" \
    --load-elf "$build_dir/linux_sbi_payload_smoke.elf" \
    --max-steps 10000 \
    --stop-pc 0x80000104 \
    --poke-word 0x20010280=0x80000000 \
    --poke-word 0x20010284=0x80001000 \
    --expect-word 0x20010288=9 \
    --expect-word 0x20010290=0x54494d45 \
    --expect-word 0x20010294=0 \
    --expect-word 0x2001029c=0 \
    --expect-word 0x200102a0=0 \
    --expect-word 0x200102a4=0 \
    --expect-word 0x200102a8=0x80001000 \
    --expect-word 0x200102ac=0 \
    --expect-word 0x200102b0=2 \
    --expect-word 0x200102b4=0 \
    --expect-word 0x200102b8=1 \
    --expect-word 0x200102bc=0x5a \
    --expect-word 0x200102c0=0 \
    --expect-word 0x200102c4=0 \
    --expect-word 0x200102cc=0 \
    --expect-word 0x200102d0=0x80000005 \
    --expect-word 0x200102d8=0x20 \
    --expect-word 0x200103f0=0x222

python3 "$repo_dir/tools/zx32elf.py" \
    "$repo_dir/hw_bringup/programs/linux_image_layout_smoke.zx32.s" \
    -o "$build_dir/linux_image_layout_smoke.elf" \
    --load-addr 0x0

python3 "$repo_dir/scripts/make_zx32sim_linux_layout_blobs.py" \
    "$build_dir/linux_image.bin" \
    "$build_dir/linux_dtb.bin"

python3 -m tools.zx32sim.main "$build_dir/linux_image_layout_smoke.elf" \
    --load-raw 0x80400000="$build_dir/linux_image.bin" \
    --load-raw 0x81600000="$build_dir/linux_dtb.bin" \
    --max-steps 1000 \
    --stop-pc 0x150 \
    --poke-word 0x20010300=0x80400000 \
    --poke-word 0x20010304=0x81600000 \
    --expect-word 0x20010330=0xedfe0dd0 \
    --expect-word 0x2001036c=0x0000106f \
    --expect-word 0x20010370=0x00400000 \
    --expect-word 0x20010374=0 \
    --expect-word 0x20010378=0x00100000 \
    --expect-word 0x2001037c=0 \
    --expect-word 0x20010380=0x43534952 \
    --expect-word 0x20010384=0x00000056 \
    --expect-word 0x20010388=0x05435352 \
    --expect-word 0x2001039c=0x0000106f \
    --expect-word 0x200103a4=0xedfe0dd0 \
    --expect-word 0x200103f0=0x222

cat >"$build_dir/block_device_smoke.zx32.s" <<'EOF'
    li t0, 0x10050000
    li t1, 0x2000
    li t2, 0x5a5a1234
    sw t2, 0(t1)
    sw x0, 8(t0)
    sw t1, 16(t0)
    li t2, 1
    sw t2, 20(t0)
    li t2, 2
    sw t2, 4(t0)
    lw t3, 0(t0)
    sw t3, 0x3e0(x0)
    wfi
EOF

python3 "$repo_dir/tools/zx32elf.py" \
    "$build_dir/block_device_smoke.zx32.s" \
    -o "$build_dir/block_device_smoke.elf" \
    --load-addr 0x0

python3 - <<'PY' "$build_dir/sd.img"
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_bytes(b"\0" * 512)
PY

python3 -m tools.zx32sim.main "$build_dir/block_device_smoke.elf" \
    --block-image "$build_dir/sd.img" \
    --max-steps 100 \
    --expect-word 0x3e0=0x5

actual="$(od -An -tx4 -N4 "$build_dir/sd.img" | tr -d '[:space:]')"
if [[ "$actual" != "5a5a1234" ]]; then
    echo "block-device smoke wrote $actual, expected 5a5a1234" >&2
    exit 1
fi

cat >"$build_dir/virtio_block_smoke.zx32.s" <<'EOF'
    li t0, 0x10060000
    li s3, 0x2000
    li t4, 0x2300
    sw t4, 0(s3)
    sw x0, 4(s3)
    li t4, 16
    sw t4, 8(s3)
    li t4, 0x00010001
    sw t4, 12(s3)
    li t4, 0x2400
    sw t4, 16(s3)
    sw x0, 20(s3)
    li t4, 512
    sw t4, 24(s3)
    li t4, 0x00020001
    sw t4, 28(s3)
    li t4, 0x2500
    sw t4, 32(s3)
    sw x0, 36(s3)
    li t4, 1
    sw t4, 40(s3)
    li t4, 2
    sw t4, 44(s3)
    li t4, 1
    li s0, 0x2300
    sw t4, 0(s0)
    sw x0, 4(s0)
    sw x0, 8(s0)
    sw x0, 12(s0)
    li s1, 0x2400
    li t4, 0x5a5a1234
    sw t4, 0(s1)
    li s2, 0x2500
    sw x0, 0(s2)
    li t4, 0x00010000
    li s4, 0x2100
    sw t4, 0(s4)
    li t4, 8
    sw x0, 0x30(t0)
    sw t4, 0x38(t0)
    li t4, 0x2000
    sw t4, 0x80(t0)
    sw x0, 0x84(t0)
    li t4, 0x2100
    sw t4, 0x90(t0)
    sw x0, 0x94(t0)
    li t4, 0x2200
    sw t4, 0xa0(t0)
    sw x0, 0xa4(t0)
    li t4, 1
    sw t4, 0x44(t0)
    sw x0, 0x50(t0)
    lbu t4, 0(s2)
    li s4, 0x3e0
    sw t4, 0(s4)
    wfi
EOF

python3 "$repo_dir/tools/zx32elf.py" \
    "$build_dir/virtio_block_smoke.zx32.s" \
    -o "$build_dir/virtio_block_smoke.elf" \
    --load-addr 0x0

python3 - <<'PY' "$build_dir/virtio-sd.img"
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_bytes(b"\0" * 512)
PY

python3 -m tools.zx32sim.main "$build_dir/virtio_block_smoke.elf" \
    --virtio-block-image "$build_dir/virtio-sd.img" \
    --max-steps 300 \
    --poke-word 0x3e0=0xffffffff \
    --stop-word 0x3e0=0 \
    --expect-word 0x3e0=0

actual="$(od -An -tx4 -N4 "$build_dir/virtio-sd.img" | tr -d '[:space:]')"
if [[ "$actual" != "5a5a1234" ]]; then
    echo "virtio block smoke wrote $actual, expected 5a5a1234" >&2
    exit 1
fi
