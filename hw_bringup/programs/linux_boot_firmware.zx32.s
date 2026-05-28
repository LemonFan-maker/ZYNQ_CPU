    lui s0, 0x20010
    csrw mscratch, s0

    addi t0, x0, m_trap
    csrw mtvec, t0

    li t0, 0xB1FF
    csrw medeleg, t0
    li t0, 0x20
    csrw mideleg, t0
    li t0, 0x7
    csrw mcounteren, t0

    lw t1, 768(s0)
    lw a1, 772(s0)
    li a0, 0

    csrw mepc, t1
    li t0, 0x800
    csrw mstatus, t0
    mret

m_trap:
    csrrw t6, mscratch, t6
    sw t0, 448(t6)
    sw t1, 452(t6)
    sw t2, 476(t6)
    sw t3, 456(t6)
    sw t4, 460(t6)
    sw t5, 464(t6)
    sw s0, 468(t6)
    sw s1, 472(t6)
    mv s0, t6

    lw t5, 540(s0)
    addi t5, t5, 1
    sw t5, 540(s0)

    csrr t1, mcause
    sw t1, 776(s0)
    csrr s1, mepc
    sw s1, 780(s0)
    sw a7, 784(s0)
    sw a6, 788(s0)
    sw a0, 792(s0)

    li t3, 9
    bne t1, t3, fail

    lw t5, 512(s0)
    addi t5, t5, 1
    sw t5, 512(s0)

    li t3, 0x10
    beq a7, t3, sbi_base
    li t3, 0x54494D45
    beq a7, t3, sbi_time
    li t3, 0x5A444247
    beq a7, t3, sbi_debug_marker
    beq a7, x0, sbi_legacy_timer
    li t3, 1
    beq a7, t3, sbi_console_putchar
    li t3, 2
    beq a7, t3, sbi_console_getchar
    j unsupported

sbi_base:
    lw t5, 520(s0)
    addi t5, t5, 1
    sw t5, 520(s0)
    beq a6, x0, sbi_base_spec
    li t3, 1
    beq a6, t3, sbi_base_impl_id
    li t3, 2
    beq a6, t3, sbi_base_impl_version
    li t3, 3
    beq a6, t3, sbi_base_probe
    li t3, 4
    beq a6, t3, sbi_base_zero_value
    li t3, 5
    beq a6, t3, sbi_base_arch_id
    li t3, 6
    beq a6, t3, sbi_base_zero_value
    j unsupported

sbi_base_spec:
    li a0, 0
    li a1, 2
    j return_sbi

sbi_base_impl_id:
    li a0, 0
    li a1, 0x5a32
    j return_sbi

sbi_base_impl_version:
    li a0, 0
    li a1, 1
    j return_sbi

sbi_base_probe:
    li a1, 0
    li t3, 0x10
    beq a0, t3, probe_supported
    li t3, 0x54494D45
    beq a0, t3, probe_supported
    j probe_done

probe_supported:
    li a1, 1

probe_done:
    li a0, 0
    j return_sbi

sbi_base_arch_id:
    li a0, 0
    li a1, 0x5a32
    j return_sbi

sbi_base_zero_value:
    li a0, 0
    li a1, 0
    j return_sbi

sbi_time:
    bne a6, x0, unsupported
    j program_timer

sbi_legacy_timer:
    j program_timer

program_timer:
    lw t5, 516(s0)
    addi t5, t5, 1
    sw t5, 516(s0)
    sw s1, 548(s0)
    li t4, 0x10010000

read_mtime:
    lw t1, 4(t4)
    lw t0, 0(t4)
    lw t3, 4(t4)
    bne t1, t3, read_mtime
    sw t0, 568(s0)
    sw t1, 572(s0)

read_rdtime:
    csrr t3, timeh
    csrr t2, time
    csrr t5, timeh
    bne t3, t5, read_rdtime

    lw t5, 556(s0)
    bnez t5, load_time_offset

    sub t5, t0, t2
    sltu t2, t0, t2
    sub t3, t1, t3
    sub t3, t3, t2
    sw t5, 560(s0)
    sw t3, 564(s0)
    li t2, 1
    sw t2, 556(s0)

load_time_offset:
    lw t2, 560(s0)
    lw t3, 564(s0)
    add t5, a0, t2
    sltu t2, t5, a0
    add t3, a1, t3
    add t3, t3, t2

    li t2, 0x00010000
    add t0, t0, t2
    sltu t2, t0, t2
    add t1, t1, t2

    bltu t3, t1, program_timer_min
    bne t3, t1, program_timer_req
    bltu t5, t0, program_timer_min

program_timer_req:
    li t2, -1
    sw t2, 12(t4)
    sw t5, 8(t4)
    sw t3, 12(t4)
    sw t5, 800(s0)
    sw t3, 804(s0)
    j program_timer_done

program_timer_min:
    li t2, -1
    sw t2, 12(t4)
    sw t0, 8(t4)
    sw t1, 12(t4)
    sw t0, 800(s0)
    sw t1, 804(s0)

program_timer_done:
    li a0, 0
    li a1, 0
    j return_sbi

sbi_console_putchar:
    lw t5, 524(s0)
    addi t5, t5, 1
    sw t5, 524(s0)
    sw a0, 544(s0)
    sw s1, 552(s0)

console_wait_space:
    lw t0, 260(s0)
    lw t2, 256(s0)
    sub t2, t0, t2
    li t3, 256
    bgeu t2, t3, console_wait_space

    andi t1, t0, 255
    add t1, s0, t1
    sb a0, 0(t1)
    addi t0, t0, 1
    sw t0, 260(s0)
    # Linux boot logs are mirrored through scratch and drained by the PS
    # launcher. Avoid spending one SBI trap per character polling PL UART.
    j return_sbi

sbi_console_getchar:
    lw t5, 528(s0)
    addi t5, t5, 1
    sw t5, 528(s0)
    lw t0, 400(s0)
    lw t2, 404(s0)
    beq t0, t2, sbi_console_getchar_legacy
    andi t1, t0, 127
    addi t1, t1, 272
    add t1, s0, t1
    lbu a0, 0(t1)
    addi t0, t0, 1
    sw t0, 400(s0)
    j return_sbi

sbi_console_getchar_legacy:
    lw t0, 268(s0)
    beq t0, x0, sbi_console_getchar_empty
    lw a0, 264(s0)
    sw x0, 268(s0)
    j return_sbi

sbi_console_getchar_empty:
    li a0, -1
    j return_sbi

sbi_debug_marker:
    lw t5, 532(s0)
    addi t5, t5, 1
    sw t5, 532(s0)
    sw a0, 576(s0)
    sw a1, 580(s0)
    sw a6, 584(s0)
    li a0, 0
    li a1, 0
    j return_sbi

unsupported:
    lw t5, 536(s0)
    addi t5, t5, 1
    sw t5, 536(s0)
    li a0, -2
    li a1, 0

return_sbi:
    sw a0, 796(s0)
    sw a1, 820(s0)
    addi s1, s1, 4
    csrw mepc, s1
    lw t0, 448(s0)
    lw t1, 452(s0)
    lw t2, 476(s0)
    lw t3, 456(s0)
    lw t4, 460(s0)
    lw t5, 464(s0)
    lw s1, 472(s0)
    csrrw t6, mscratch, s0
    lw s0, 468(s0)
    mret

fail:
    li t3, 0x00000333
    sw t3, 1008(s0)
done:
    j done
