    .option norelax
    .section .text.boot, "ax", @progbits
    .globl _start

    .equ SCRATCH_BASE, 0x20010000
    .equ TIMER_BASE, 0x10010000

    .equ CPU_LINUX_ENTRY_OFF, 0x300
    .equ CPU_LINUX_DTB_OFF, 0x304
    .equ CPU_LINUX_MCAUSE_OFF, 0x308
    .equ CPU_LINUX_MEPC_OFF, 0x30c
    .equ CPU_LINUX_SBI_EID_OFF, 0x310
    .equ CPU_LINUX_SBI_FID_OFF, 0x314
    .equ CPU_LINUX_SBI_ARG0_OFF, 0x318
    .equ CPU_LINUX_SBI_RETVAL_OFF, 0x31c
    .equ CPU_LINUX_CMP_LO_OFF, 0x320
    .equ CPU_LINUX_CMP_HI_OFF, 0x324
    .equ CPU_LINUX_HARTID_OFF, 0x328
    .equ CPU_LINUX_PAYLOAD_DTB_OFF, 0x32c
    .equ CPU_LINUX_BASE_VERSION_OFF, 0x334
    .equ CPU_LINUX_TIME0_OFF, 0x340
    .equ CPU_LINUX_TIME1_OFF, 0x344

    .equ CPU_LINUX_ECALL_COUNT_OFF, 0x200
    .equ CPU_LINUX_TIME_COUNT_OFF, 0x204
    .equ CPU_LINUX_BASE_COUNT_OFF, 0x208
    .equ CPU_LINUX_CONSOLE_PUT_COUNT_OFF, 0x20c
    .equ CPU_LINUX_CONSOLE_GET_COUNT_OFF, 0x210
    .equ CPU_LINUX_DEBUG_COUNT_OFF, 0x214
    .equ CPU_LINUX_UNSUPPORTED_COUNT_OFF, 0x218
    .equ CPU_LINUX_TRAP_COUNT_OFF, 0x21c
    .equ CPU_LINUX_LAST_CHAR_OFF, 0x220
    .equ CPU_LINUX_LAST_TIME_MEPC_OFF, 0x224
    .equ CPU_LINUX_LAST_CONSOLE_MEPC_OFF, 0x228
    .equ CPU_LINUX_TIMER_OFFSET_VALID_OFF, 0x22c
    .equ CPU_LINUX_TIMER_OFFSET_LO_OFF, 0x230
    .equ CPU_LINUX_TIMER_OFFSET_HI_OFF, 0x234
    .equ CPU_LINUX_TIMER_MTIME_LO_OFF, 0x238
    .equ CPU_LINUX_TIMER_MTIME_HI_OFF, 0x23c
    .equ CPU_LINUX_RESET_TYPE_OFF, 0x258
    .equ CPU_LINUX_RESET_REASON_OFF, 0x25c
    .equ CPU_LINUX_RESET_MAGIC_OFF, 0x260

    .equ CPU_LINUX_CONSOLE_RING_HEAD_OFF, 0x100
    .equ CPU_LINUX_CONSOLE_RING_TOTAL_OFF, 0x104
    .equ CPU_LINUX_CONSOLE_IN_CHAR_OFF, 0x108
    .equ CPU_LINUX_CONSOLE_IN_VALID_OFF, 0x10c
    .equ CPU_LINUX_CONSOLE_IN_RING_BASE_OFF, 0x110
    .equ CPU_LINUX_CONSOLE_IN_RING_HEAD_OFF, 0x190
    .equ CPU_LINUX_CONSOLE_IN_RING_TAIL_OFF, 0x194

    .equ CPU_MAIL_STATUS_OFF, 0x3f0
    .equ CPU_STATUS_PASS, 0x00000222

    .equ SAVE_RA_OFF, 0x1a0
    .equ SAVE_T0_OFF, 0x1a8
    .equ SAVE_T1_OFF, 0x1b0
    .equ SAVE_T2_OFF, 0x1b8
    .equ SAVE_T3_OFF, 0x1c0
    .equ SAVE_T4_OFF, 0x1c8
    .equ SAVE_T5_OFF, 0x1d0
    .equ SAVE_T6_OFF, 0x1d8
    .equ SAVE_S0_OFF, 0x1e0
    .equ SAVE_S1_OFF, 0x1e8
    .equ SAVE_A3_OFF, 0x198
    .equ SAVE_A4_OFF, 0x1f0
    .equ SAVE_A5_OFF, 0x1f8

    .equ SBI_SUCCESS, 0
    .equ SBI_ERR_FAILED, -1
    .equ SBI_ERR_NOT_SUPPORTED, -2
    .equ SBI_ERR_INVALID_PARAM, -3
    .equ SBI_ERR_INVALID_ADDRESS, -5
    .equ SBI_ERR_ALREADY_AVAILABLE, -6
    .equ SBI_SPEC_VERSION_2_0, 0x02000000
    .equ SBI_IMPL_ID_ZX64, 0x5a64
    .equ SBI_IMPL_VERSION, 1
    .equ SBI_HSM_STATE_STARTED, 0

    .equ SBI_EXT_BASE, 0x10
    .equ SBI_EXT_TIME, 0x54494d45
    .equ SBI_EXT_IPI, 0x735049
    .equ SBI_EXT_RFENCE, 0x52464e43
    .equ SBI_EXT_HSM, 0x48534d
    .equ SBI_EXT_SRST, 0x53525354
    .equ SBI_EXT_PMU, 0x504d55
    .equ SBI_EXT_DBCN, 0x4442434e
    .equ SBI_EXT_VENDOR_ZXDBG, 0x5a444247

_start:
    lui s0, 0x20010
    csrw mscratch, s0

    la t0, m_trap
    csrw mtvec, t0

    li t0, 0xb1ff
    csrw medeleg, t0
    li t0, 0x220
    csrw mideleg, t0
    li t0, 0x7
    csrw mcounteren, t0

    lwu t1, CPU_LINUX_ENTRY_OFF(s0)
    lwu a1, CPU_LINUX_DTB_OFF(s0)
    li a0, 0
    sw a0, CPU_LINUX_HARTID_OFF(s0)
    sw a1, CPU_LINUX_PAYLOAD_DTB_OFF(s0)

    csrw mepc, t1
    li t0, 0x800
    csrw mstatus, t0
    mret

m_trap:
    csrrw t6, mscratch, t6
    sd ra, SAVE_RA_OFF(t6)
    sd t0, SAVE_T0_OFF(t6)
    csrr t0, mscratch
    sd t0, SAVE_T6_OFF(t6)
    sd t1, SAVE_T1_OFF(t6)
    sd t2, SAVE_T2_OFF(t6)
    sd t3, SAVE_T3_OFF(t6)
    sd t4, SAVE_T4_OFF(t6)
    sd t5, SAVE_T5_OFF(t6)
    sd s0, SAVE_S0_OFF(t6)
    sd s1, SAVE_S1_OFF(t6)
    mv s0, t6

    lw t5, CPU_LINUX_TRAP_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_TRAP_COUNT_OFF(s0)

    csrr t1, mcause
    sw t1, CPU_LINUX_MCAUSE_OFF(s0)
    csrr s1, mepc
    sw s1, CPU_LINUX_MEPC_OFF(s0)
    sw a7, CPU_LINUX_SBI_EID_OFF(s0)
    sw a6, CPU_LINUX_SBI_FID_OFF(s0)
    sw a0, CPU_LINUX_SBI_ARG0_OFF(s0)

    li t3, 9
    bne t1, t3, fail

    lw t5, CPU_LINUX_ECALL_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_ECALL_COUNT_OFF(s0)

    li t3, SBI_EXT_BASE
    beq a7, t3, sbi_base
    li t3, SBI_EXT_TIME
    beq a7, t3, sbi_time
    li t3, SBI_EXT_IPI
    beq a7, t3, sbi_ipi
    li t3, SBI_EXT_RFENCE
    beq a7, t3, sbi_rfence
    li t3, SBI_EXT_HSM
    beq a7, t3, sbi_hsm
    li t3, SBI_EXT_SRST
    beq a7, t3, sbi_system_reset
    li t3, SBI_EXT_PMU
    beq a7, t3, sbi_pmu
    li t3, SBI_EXT_DBCN
    beq a7, t3, sbi_dbcn
    li t3, SBI_EXT_VENDOR_ZXDBG
    beq a7, t3, sbi_debug_marker
    beq a7, x0, sbi_legacy_timer
    li t3, 1
    beq a7, t3, sbi_console_putchar
    li t3, 2
    beq a7, t3, sbi_console_getchar
    li t3, 3
    beq a7, t3, sbi_legacy_clear_ipi
    li t3, 4
    beq a7, t3, sbi_legacy_send_ipi
    li t3, 5
    beq a7, t3, sbi_legacy_remote_fence_i
    li t3, 6
    beq a7, t3, sbi_legacy_remote_sfence_vma
    li t3, 7
    beq a7, t3, sbi_legacy_remote_sfence_vma_asid
    li t3, 8
    beq a7, t3, sbi_legacy_shutdown
    j unsupported

sbi_base:
    lw t5, CPU_LINUX_BASE_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_BASE_COUNT_OFF(s0)
    beq a6, x0, sbi_base_spec
    li t3, 1
    beq a6, t3, sbi_base_impl_id
    li t3, 2
    beq a6, t3, sbi_base_impl_version
    li t3, 3
    beq a6, t3, sbi_base_probe
    li t3, 4
    beq a6, t3, sbi_base_mvendorid
    li t3, 5
    beq a6, t3, sbi_base_marchid
    li t3, 6
    beq a6, t3, sbi_base_mimpid
    j unsupported

sbi_base_spec:
    li a0, SBI_SUCCESS
    li a1, SBI_SPEC_VERSION_2_0
    sw a1, CPU_LINUX_BASE_VERSION_OFF(s0)
    j return_sbi

sbi_base_impl_id:
    li a0, SBI_SUCCESS
    li a1, SBI_IMPL_ID_ZX64
    j return_sbi

sbi_base_impl_version:
    li a0, SBI_SUCCESS
    li a1, SBI_IMPL_VERSION
    j return_sbi

sbi_base_mvendorid:
    li a0, SBI_SUCCESS
    csrr a1, mvendorid
    j return_sbi

sbi_base_marchid:
    li a0, SBI_SUCCESS
    csrr a1, marchid
    j return_sbi

sbi_base_mimpid:
    li a0, SBI_SUCCESS
    csrr a1, mimpid
    j return_sbi

sbi_base_probe:
    li a1, 0
    li t3, 9
    bltu a0, t3, probe_supported
    li t3, SBI_EXT_BASE
    beq a0, t3, probe_supported
    li t3, SBI_EXT_TIME
    beq a0, t3, probe_supported
    li t3, SBI_EXT_IPI
    beq a0, t3, probe_supported
    li t3, SBI_EXT_RFENCE
    beq a0, t3, probe_supported
    li t3, SBI_EXT_HSM
    beq a0, t3, probe_supported
    li t3, SBI_EXT_SRST
    beq a0, t3, probe_supported
    li t3, SBI_EXT_PMU
    beq a0, t3, probe_supported
    li t3, SBI_EXT_DBCN
    beq a0, t3, probe_supported
    j probe_done

probe_supported:
    li a1, 1

probe_done:
    li a0, SBI_SUCCESS
    j return_sbi

sbi_time:
    bne a6, x0, unsupported
    j program_timer

sbi_legacy_timer:
    j program_timer

program_timer:
    lw t5, CPU_LINUX_TIME_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_TIME_COUNT_OFF(s0)
    sw s1, CPU_LINUX_LAST_TIME_MEPC_OFF(s0)
    li t4, TIMER_BASE

read_mtime:
    lw t1, 4(t4)
    lwu t0, 0(t4)
    lw t2, 4(t4)
    bne t1, t2, read_mtime
    sw t0, CPU_LINUX_TIMER_MTIME_LO_OFF(s0)
    sw t1, CPU_LINUX_TIMER_MTIME_HI_OFF(s0)
    slli t1, t1, 32
    or t0, t0, t1

    rdtime t2
    lw t5, CPU_LINUX_TIMER_OFFSET_VALID_OFF(s0)
    bnez t5, load_time_offset

    sub t5, t0, t2
    sw t5, CPU_LINUX_TIMER_OFFSET_LO_OFF(s0)
    srli t3, t5, 32
    sw t3, CPU_LINUX_TIMER_OFFSET_HI_OFF(s0)
    li t3, 1
    sw t3, CPU_LINUX_TIMER_OFFSET_VALID_OFF(s0)

load_time_offset:
    li t3, -1
    beq a0, t3, program_timer_infinite
    lwu t5, CPU_LINUX_TIMER_OFFSET_LO_OFF(s0)
    lwu t3, CPU_LINUX_TIMER_OFFSET_HI_OFF(s0)
    slli t3, t3, 32
    or t5, t5, t3
    add t5, a0, t5

    li t2, 0x00010000
    add t2, t0, t2
    bltu t5, t2, program_timer_min
    mv t2, t5
    j program_timer_min

program_timer_infinite:
    li t2, -1

program_timer_min:
    li t3, -1
    sw t3, 12(t4)
    sw t2, 8(t4)
    srli t3, t2, 32
    sw t3, 12(t4)
    sw t2, CPU_LINUX_CMP_LO_OFF(s0)
    sw t3, CPU_LINUX_CMP_HI_OFF(s0)
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_ipi:
    bne a6, x0, unsupported
    jal ra, sbi_validate_hart_mask
    bnez a0, return_sbi
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_rfence:
    beq a6, x0, sbi_rfence_fence_i
    li t3, 1
    beq a6, t3, sbi_rfence_sfence_vma
    li t3, 2
    beq a6, t3, sbi_rfence_sfence_vma_asid
    li t3, 3
    beq a6, t3, sbi_rfence_hfence_unsupported
    li t3, 4
    beq a6, t3, sbi_rfence_hfence_unsupported
    li t3, 5
    beq a6, t3, sbi_rfence_hfence_unsupported
    li t3, 6
    beq a6, t3, sbi_rfence_hfence_unsupported
    j unsupported

sbi_rfence_fence_i:
    jal ra, sbi_validate_hart_mask
    bnez a0, return_sbi
    fence.i
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_rfence_sfence_vma:
    jal ra, sbi_validate_hart_mask
    bnez a0, return_sbi
    sfence.vma
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_rfence_sfence_vma_asid:
    jal ra, sbi_validate_hart_mask
    bnez a0, return_sbi
    sfence.vma
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_rfence_hfence_unsupported:
    li a0, SBI_ERR_NOT_SUPPORTED
    li a1, 0
    j return_sbi

sbi_validate_hart_mask:
    mv t5, a0
    mv t4, a1
    beqz t5, 3f
    li t3, -1
    beq t4, t3, 3f
    bnez t4, 2f
    li t3, -2
    and t3, t5, t3
    bnez t3, 2f
    li a0, SBI_SUCCESS
    li a1, 0
    ret
2:
    li a0, SBI_ERR_INVALID_PARAM
    li a1, 0
    ret
3:
    li a0, SBI_SUCCESS
    li a1, 0
    ret

sbi_legacy_clear_ipi:
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_legacy_send_ipi:
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_legacy_remote_fence_i:
    fence.i
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_legacy_remote_sfence_vma:
    sfence.vma
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_legacy_remote_sfence_vma_asid:
    sfence.vma
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_legacy_shutdown:
    li a6, 0
    li a0, 0
    li a1, 0
    j sbi_system_reset

sbi_hsm:
    beq a6, x0, sbi_hsm_hart_start
    li t3, 1
    beq a6, t3, sbi_hsm_hart_stop
    li t3, 2
    beq a6, t3, sbi_hsm_hart_get_status
    li t3, 3
    beq a6, t3, sbi_hsm_hart_suspend
    j unsupported

sbi_hsm_hart_start:
    bnez a0, sbi_invalid_param
    li a0, SBI_ERR_ALREADY_AVAILABLE
    li a1, 0
    j return_sbi

sbi_hsm_hart_stop:
    li a0, SBI_ERR_FAILED
    li a1, 0
    j return_sbi

sbi_hsm_hart_get_status:
    bnez a0, sbi_invalid_param
    li a0, SBI_SUCCESS
    li a1, SBI_HSM_STATE_STARTED
    j return_sbi

sbi_hsm_hart_suspend:
    beqz a0, sbi_hsm_suspend_not_supported
    li t3, 0x80000000
    beq a0, t3, sbi_hsm_suspend_not_supported
    j sbi_invalid_param

sbi_hsm_suspend_not_supported:
    li a0, SBI_ERR_NOT_SUPPORTED
    li a1, 0
    j return_sbi

sbi_pmu:
    beq a6, x0, sbi_pmu_num_counters
    li t3, 1
    beq a6, t3, sbi_pmu_counter_get_info
    li t3, 2
    beq a6, t3, sbi_pmu_counter_config_matching
    li t3, 3
    beq a6, t3, sbi_pmu_counter_start
    li t3, 4
    beq a6, t3, sbi_pmu_counter_stop
    li t3, 5
    beq a6, t3, sbi_pmu_counter_fw_read
    li t3, 6
    beq a6, t3, sbi_pmu_counter_fw_read_hi
    li t3, 7
    beq a6, t3, sbi_pmu_snapshot_set_shmem
    li t3, 8
    beq a6, t3, sbi_pmu_event_get_info
    j unsupported

sbi_pmu_num_counters:
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_pmu_counter_get_info:
    j sbi_invalid_param

sbi_pmu_counter_config_matching:
    srli t3, a2, 8
    bnez t3, sbi_invalid_param
    li a0, SBI_ERR_NOT_SUPPORTED
    li a1, 0
    j return_sbi

sbi_pmu_counter_start:
    srli t3, a2, 2
    bnez t3, sbi_invalid_param
    j sbi_invalid_param

sbi_pmu_counter_stop:
    srli t3, a2, 2
    bnez t3, sbi_invalid_param
    j sbi_invalid_param

sbi_pmu_counter_fw_read:
    j sbi_invalid_param

sbi_pmu_counter_fw_read_hi:
    j sbi_invalid_param

sbi_pmu_snapshot_set_shmem:
    bnez a2, sbi_invalid_param
    li t3, -1
    bne a0, t3, 1f
    beq a1, t3, 2f
1:
    srli t3, a0, 12
    slli t3, t3, 12
    bne t3, a0, sbi_invalid_param
2:
    li a0, SBI_ERR_NOT_SUPPORTED
    li a1, 0
    j return_sbi

sbi_pmu_event_get_info:
    bnez a3, sbi_invalid_param
    andi t3, a0, 15
    bnez t3, sbi_invalid_param
    li a0, SBI_ERR_NOT_SUPPORTED
    li a1, 0
    j return_sbi

sbi_dbcn:
    beq a6, x0, sbi_dbcn_write
    li t3, 1
    beq a6, t3, sbi_dbcn_read
    li t3, 2
    beq a6, t3, sbi_dbcn_write_byte
    j unsupported

sbi_dbcn_write:
    jal ra, sbi_dbcn_check_shmem
    bnez t0, sbi_dbcn_invalid_address
    sd a3, SAVE_A3_OFF(s0)
    sd a4, SAVE_A4_OFF(s0)
    sd a5, SAVE_A5_OFF(s0)
    mv a4, a0
    mv a5, a1
    li a3, 0
1:
    beqz a4, 2f
    lbu a0, 0(a5)
    jal ra, console_try_put_byte
    beqz a0, 2f
    addi a5, a5, 1
    addi a4, a4, -1
    addi a3, a3, 1
    j 1b
2:
    li a0, SBI_SUCCESS
    mv a1, a3
    ld a3, SAVE_A3_OFF(s0)
    ld a4, SAVE_A4_OFF(s0)
    ld a5, SAVE_A5_OFF(s0)
    j return_sbi

sbi_dbcn_read:
    jal ra, sbi_dbcn_check_shmem
    bnez t0, sbi_dbcn_invalid_address
    sd a3, SAVE_A3_OFF(s0)
    sd a4, SAVE_A4_OFF(s0)
    sd a5, SAVE_A5_OFF(s0)
    mv a4, a0
    mv a5, a1
    li a3, 0
3:
    beqz a4, 4f
    jal ra, console_get_byte
    bltz a0, 4f
    sb a0, 0(a5)
    addi a5, a5, 1
    addi a4, a4, -1
    addi a3, a3, 1
    j 3b
4:
    li a0, SBI_SUCCESS
    mv a1, a3
    ld a3, SAVE_A3_OFF(s0)
    ld a4, SAVE_A4_OFF(s0)
    ld a5, SAVE_A5_OFF(s0)
    j return_sbi

sbi_dbcn_write_byte:
    jal ra, console_try_put_byte
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_dbcn_check_shmem:
    beqz a0, 1f
    bnez a2, 2f
    beqz a1, 2f
    addi t0, a0, -1
    add t0, a1, t0
    bltu t0, a1, 2f
1:
    li t0, 0
    ret
2:
    li t0, SBI_ERR_INVALID_ADDRESS
    ret

sbi_dbcn_invalid_address:
    li a0, SBI_ERR_INVALID_ADDRESS
    li a1, 0
    j return_sbi

sbi_console_putchar:
    jal ra, console_put_byte
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_console_getchar:
    jal ra, console_get_byte
    li a1, 0
    j return_sbi

console_put_byte:
    lw t5, CPU_LINUX_CONSOLE_PUT_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_CONSOLE_PUT_COUNT_OFF(s0)
    sw a0, CPU_LINUX_LAST_CHAR_OFF(s0)
    sw s1, CPU_LINUX_LAST_CONSOLE_MEPC_OFF(s0)

console_wait_space:
    lw t0, CPU_LINUX_CONSOLE_RING_TOTAL_OFF(s0)
    lw t2, CPU_LINUX_CONSOLE_RING_HEAD_OFF(s0)
    subw t2, t0, t2
    li t3, 256
    bgeu t2, t3, console_wait_space

    andi t1, t0, 255
    add t1, s0, t1
    sb a0, 0(t1)
    addiw t0, t0, 1
    sw t0, CPU_LINUX_CONSOLE_RING_TOTAL_OFF(s0)
    ret

console_try_put_byte:
    lw t0, CPU_LINUX_CONSOLE_RING_TOTAL_OFF(s0)
    lw t2, CPU_LINUX_CONSOLE_RING_HEAD_OFF(s0)
    subw t2, t0, t2
    li t3, 256
    bgeu t2, t3, 1f

    lw t5, CPU_LINUX_CONSOLE_PUT_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_CONSOLE_PUT_COUNT_OFF(s0)
    sw a0, CPU_LINUX_LAST_CHAR_OFF(s0)
    sw s1, CPU_LINUX_LAST_CONSOLE_MEPC_OFF(s0)
    andi t1, t0, 255
    add t1, s0, t1
    sb a0, 0(t1)
    addiw t0, t0, 1
    sw t0, CPU_LINUX_CONSOLE_RING_TOTAL_OFF(s0)
    li a0, 1
    ret
1:
    li a0, 0
    ret

console_get_byte:
    lw t5, CPU_LINUX_CONSOLE_GET_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_CONSOLE_GET_COUNT_OFF(s0)
    lw t0, CPU_LINUX_CONSOLE_IN_RING_TAIL_OFF(s0)
    lw t2, CPU_LINUX_CONSOLE_IN_RING_HEAD_OFF(s0)
    beq t0, t2, console_get_legacy
    andi t1, t0, 127
    addi t1, t1, CPU_LINUX_CONSOLE_IN_RING_BASE_OFF
    add t1, s0, t1
    lbu a0, 0(t1)
    addiw t0, t0, 1
    sw t0, CPU_LINUX_CONSOLE_IN_RING_TAIL_OFF(s0)
    ret

console_get_legacy:
    lw t0, CPU_LINUX_CONSOLE_IN_VALID_OFF(s0)
    beqz t0, console_get_empty
    lw a0, CPU_LINUX_CONSOLE_IN_CHAR_OFF(s0)
    sw x0, CPU_LINUX_CONSOLE_IN_VALID_OFF(s0)
    ret

console_get_empty:
    li a0, -1
    ret

sbi_debug_marker:
    lw t5, CPU_LINUX_DEBUG_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_DEBUG_COUNT_OFF(s0)
    li a0, SBI_SUCCESS
    li a1, 0
    j return_sbi

sbi_system_reset:
    bne a6, x0, unsupported
    li t3, 2
    bltu t3, a0, sbi_invalid_param
    li t3, 1
    bltu t3, a1, sbi_invalid_param
    li t3, 0x53525354
    sw a0, CPU_LINUX_RESET_TYPE_OFF(s0)
    sw a1, CPU_LINUX_RESET_REASON_OFF(s0)
    sw t3, CPU_LINUX_RESET_MAGIC_OFF(s0)
    li t3, CPU_STATUS_PASS
    sw t3, CPU_MAIL_STATUS_OFF(s0)
sbi_system_reset_wait:
    wfi
    j sbi_system_reset_wait

sbi_invalid_param:
    li a0, SBI_ERR_INVALID_PARAM
    li a1, 0
    j return_sbi

unsupported:
    lw t5, CPU_LINUX_UNSUPPORTED_COUNT_OFF(s0)
    addiw t5, t5, 1
    sw t5, CPU_LINUX_UNSUPPORTED_COUNT_OFF(s0)
    li a0, SBI_ERR_NOT_SUPPORTED
    li a1, 0

return_sbi:
    sw a0, CPU_LINUX_SBI_RETVAL_OFF(s0)
    addi s1, s1, 4
    csrw mepc, s1
    ld ra, SAVE_RA_OFF(s0)
    ld t0, SAVE_T0_OFF(s0)
    ld t1, SAVE_T1_OFF(s0)
    ld t2, SAVE_T2_OFF(s0)
    ld t3, SAVE_T3_OFF(s0)
    ld t4, SAVE_T4_OFF(s0)
    ld t5, SAVE_T5_OFF(s0)
    ld t6, SAVE_T6_OFF(s0)
    ld s1, SAVE_S1_OFF(s0)
    csrw mscratch, s0
    ld s0, SAVE_S0_OFF(s0)
    mret

fail:
    li t3, 0x00000333
    sw t3, CPU_MAIL_STATUS_OFF(s0)
done:
    wfi
    j done
