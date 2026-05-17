    lui s0, 0x20010

    addi t0, x0, m_trap
    csrw mtvec, t0

    lw t1, 896(s0)
    lw a1, 900(s0)
    li a0, 0

    csrw mepc, t1
    li t0, 0x800
    csrw mstatus, t0
    mret

m_trap:
    csrr t1, mcause
    sw t1, 908(s0)
    csrr t2, mepc
    sw t2, 912(s0)
    sw a7, 916(s0)
    sw a0, 920(s0)

    li t3, 9
    bne t1, t3, fail
    li t3, 1
    bne a7, t3, fail

    li t3, 0x53424921
    sw t3, 924(s0)
    li a0, 0
    addi t2, t2, 4
    csrw mepc, t2
    mret

fail:
    li t3, 0x00000333
    sw t3, 1008(s0)
done:
    j done
