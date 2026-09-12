#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
elf="$repo_dir/hw_bringup/build/elf/linux_boot_firmware.rv64.elf"
raw="$repo_dir/hw_bringup/build/elf/linux_boot_firmware.rv64.bin"

"$repo_dir/scripts/build_zx32_programs.sh" >/dev/null

python3 - "$elf" "$raw" <<'PY'
from __future__ import annotations

import pathlib
import struct
import sys

elf_path = pathlib.Path(sys.argv[1])
raw_path = pathlib.Path(sys.argv[2])
elf = elf_path.read_bytes()
raw = raw_path.read_bytes()

if elf[:4] != b"\x7fELF":
    raise SystemExit(f"{elf_path}: not an ELF file")
if elf[4] != 2 or elf[5] != 1:
    raise SystemExit(f"{elf_path}: expected little-endian ELF64")
if struct.unpack_from("<H", elf, 18)[0] != 243:
    raise SystemExit(f"{elf_path}: expected EM_RISCV")
entry = struct.unpack_from("<Q", elf, 24)[0]
if entry != 0:
    raise SystemExit(f"{elf_path}: expected entry 0, got 0x{entry:x}")

phoff = struct.unpack_from("<Q", elf, 32)[0]
ehsize = struct.unpack_from("<H", elf, 52)[0]
phentsize = struct.unpack_from("<H", elf, 54)[0]
phnum = struct.unpack_from("<H", elf, 56)[0]
if ehsize != 64 or phentsize != 56:
    raise SystemExit(f"{elf_path}: unexpected ELF64 header sizes")

exec_load = False
for i in range(phnum):
    off = phoff + i * phentsize
    p_type, p_flags = struct.unpack_from("<II", elf, off)
    p_paddr = struct.unpack_from("<Q", elf, off + 24)[0]
    p_filesz = struct.unpack_from("<Q", elf, off + 32)[0]
    p_memsz = struct.unpack_from("<Q", elf, off + 40)[0]
    if p_type != 1:
        continue
    if p_paddr >> 32:
        raise SystemExit(f"{elf_path}: LOAD paddr exceeds IMEM loader range")
    if p_filesz % 4 or p_memsz % 4:
        raise SystemExit(f"{elf_path}: LOAD segment is not 32-bit aligned")
    if (p_flags & 0x1) and p_paddr == 0:
        exec_load = True

if not exec_load:
    raise SystemExit(f"{elf_path}: no executable LOAD segment at paddr 0")
if len(raw) == 0 or len(raw) % 4:
    raise SystemExit(f"{raw_path}: raw text must be non-empty and 32-bit aligned")

print(f"ZX64 Linux boot firmware: ELF64 entry=0 raw_words={len(raw) // 4}")
PY

required_symbols=(
    _start
    m_trap
    sbi_base
    sbi_base_probe
    sbi_base_mvendorid
    sbi_base_marchid
    sbi_base_mimpid
    sbi_time
    sbi_legacy_timer
    sbi_legacy_clear_ipi
    sbi_legacy_send_ipi
    sbi_legacy_remote_fence_i
    sbi_legacy_remote_sfence_vma
    sbi_legacy_remote_sfence_vma_asid
    sbi_legacy_shutdown
    sbi_ipi
    sbi_rfence
    sbi_rfence_fence_i
    sbi_rfence_sfence_vma
    sbi_rfence_sfence_vma_asid
    sbi_rfence_hfence_unsupported
    sbi_validate_hart_mask
    sbi_hsm
    sbi_hsm_hart_start
    sbi_hsm_hart_stop
    sbi_hsm_hart_get_status
    sbi_hsm_hart_suspend
    sbi_hsm_suspend_not_supported
    sbi_pmu
    sbi_pmu_num_counters
    sbi_pmu_counter_get_info
    sbi_pmu_counter_config_matching
    sbi_pmu_counter_start
    sbi_pmu_counter_stop
    sbi_pmu_counter_fw_read
    sbi_pmu_counter_fw_read_hi
    sbi_pmu_snapshot_set_shmem
    sbi_pmu_event_get_info
    sbi_dbcn
    sbi_dbcn_write
    sbi_dbcn_read
    sbi_dbcn_write_byte
    sbi_console_putchar
    sbi_console_getchar
    console_put_byte
    console_wait_space
    console_get_byte
    console_get_legacy
    console_get_empty
    sbi_system_reset
    sbi_invalid_param
    sbi_debug_marker
    unsupported
)

nm_out="$(llvm-nm --defined-only "$elf")"

for sym in "${required_symbols[@]}"; do
    if ! awk '{print $3}' <<<"$nm_out" | grep -qx "$sym"; then
        echo "Missing RV64 firmware symbol: $sym" >&2
        exit 1
    fi
done

required_abs_symbols=(
    "SBI_ERR_FAILED ffffffffffffffff"
    "SBI_ERR_NOT_SUPPORTED fffffffffffffffe"
    "SBI_ERR_INVALID_PARAM fffffffffffffffd"
    "SBI_ERR_INVALID_ADDRESS fffffffffffffffb"
    "SBI_ERR_ALREADY_AVAILABLE fffffffffffffffa"
    "SBI_SPEC_VERSION_2_0 0000000002000000"
    "SBI_HSM_STATE_STARTED 0000000000000000"
    "SBI_EXT_BASE 0000000000000010"
    "SBI_EXT_TIME 0000000054494d45"
    "SBI_EXT_IPI 0000000000735049"
    "SBI_EXT_RFENCE 0000000052464e43"
    "SBI_EXT_HSM 000000000048534d"
    "SBI_EXT_SRST 0000000053525354"
    "SBI_EXT_PMU 0000000000504d55"
    "SBI_EXT_DBCN 000000004442434e"
)

for spec in "${required_abs_symbols[@]}"; do
    sym="${spec%% *}"
    value="${spec##* }"
    if ! awk -v value="$value" -v sym="$sym" '$1 == value && $3 == sym { found = 1 } END { exit !found }' <<<"$nm_out"; then
        echo "Unexpected or missing RV64 firmware absolute symbol: $sym=$value" >&2
        exit 1
    fi
done

echo "ZX64 Linux boot firmware symbols: OK (boot-minimal SBI BASE/TIME/IPI/RFENCE/HSM/PMU/DBCN/SRST)"
