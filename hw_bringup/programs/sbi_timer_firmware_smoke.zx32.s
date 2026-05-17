    lui s0, 0x20010

    addi t0, x0, m_trap
    csrw mtvec, t0

    li t0, 0x20
    csrw mideleg, t0
    li t0, 0x7
    csrw mcounteren, t0

    lw t1, 832(s0)
    lw a1, 836(s0)
    li a0, 0

    csrw mepc, t1
    li t0, 0x800
    csrw mstatus, t0
    mret

m_trap:
    csrr t1, mcause
    sw t1, 844(s0)
    csrr s1, mepc
    sw s1, 848(s0)
    sw a7, 852(s0)
    sw a6, 856(s0)
    sw a0, 860(s0)

    li t3, 9
    bne t1, t3, fail
    li t3, 0x54494D45
    bne a7, t3, fail
    bne a6, x0, fail

    csrr t3, time
    bltu a0, t3, timer_expired
    sub t3, a0, t3
    li t0, 32
    bltu t3, t0, timer_min_delta
    j timer_delta_ready

timer_expired:
    li t3, 32
    j timer_delta_ready

timer_min_delta:
    li t3, 32

timer_delta_ready:
    li t4, 0x10010000
    lw t5, 0(t4)
    lw t6, 4(t4)
    add t2, t5, t3
    sltu t0, t2, t5
    add t6, t6, t0

    li t0, -1
    sw t0, 12(t4)
    sw t2, 8(t4)
    sw t6, 12(t4)

    sw t2, 864(s0)
    sw t6, 868(s0)

    li a0, 0
    li a1, 0
    addi s1, s1, 4
    csrw mepc, s1
    mret

fail:
    li t3, 0x00000333
    sw t3, 1008(s0)
done:
    j done
