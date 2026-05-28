    lui s0, 0x20010

    addi t0, x0, m_trap
    csrw mtvec, t0

    li t0, 0x220
    csrw mideleg, t0
    li t0, 0x7
    csrw mcounteren, t0

    lw t1, 640(s0)
    lw a1, 644(s0)
    li a0, 0

    csrw mepc, t1
    li t0, 0x800
    csrw mstatus, t0
    mret

m_trap:
    csrr t1, mcause
    sw t1, 648(s0)
    csrr s1, mepc
    sw s1, 652(s0)
    sw a7, 656(s0)
    sw a6, 660(s0)
    sw a0, 664(s0)

    li t3, 9
    bne t1, t3, fail

    li t3, 0x10
    beq a7, t3, sbi_base
    li t3, 0x54494D45
    beq a7, t3, sbi_time
    beq a7, x0, sbi_legacy_timer
    li t3, 1
    beq a7, t3, sbi_console_putchar
    li t3, 2
    beq a7, t3, sbi_console_getchar
    j unsupported

sbi_base:
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
    li t4, 0x10010000
    li t0, -1
    sw t0, 12(t4)
    sw a0, 8(t4)
    sw a1, 12(t4)
    sw a0, 712(s0)
    sw a1, 716(s0)
    li a0, 0
    li a1, 0
    j return_sbi

sbi_console_putchar:
    sw a0, 700(s0)
    li t4, 0x10000000
    li t5, 10000

uart_wait:
    lw t6, 4(t4)
    andi t6, t6, 1
    bne t6, x0, uart_send
    addi t5, t5, -1
    bne t5, x0, uart_wait

uart_send:
    sw a0, 0(t4)
    j return_sbi

sbi_console_getchar:
    li a0, -1
    j return_sbi

unsupported:
    li a0, -2
    li a1, 0

return_sbi:
    sw a0, 668(s0)
    sw a1, 672(s0)
    addi s1, s1, 4
    csrw mepc, s1
    mret

fail:
    li t3, 0x00000333
    sw t3, 1008(s0)
done:
    j done
