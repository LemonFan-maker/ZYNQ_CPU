    addi t0, x0, fail
    csrw mtvec, t0

    li t0, 0x7
    csrw mcounteren, t0

    addi t0, x0, supervisor_main
    csrw mepc, t0

    li t0, 0x800
    csrw mstatus, t0
    mret

fail:
    lui t0, 0x20010
    li t1, 0x00000333
    sw t1, 1008(t0)
    j fail

supervisor_main:
    lui t0, 0x20010
    csrr t1, cycle
    sw t1, 968(t0)
    csrr t2, time
    sw t2, 972(t0)
    csrr t3, instret
    sw t3, 976(t0)
    li t1, 0x00000222
    sw t1, 1008(t0)

done:
    j done
