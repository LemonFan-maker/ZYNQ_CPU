    addi t0, x0, supervisor_trap
    csrw stvec, t0

    li t0, 0x4
    csrw medeleg, t0

    li a0, 0x0
    li a1, 0x20010000

    addi t0, x0, supervisor_payload
    csrw mepc, t0

    li t0, 0x800
    csrw mstatus, t0
    mret

fail:
    lui t0, 0x20010
    li t1, 0x00000333
    sw t1, 1008(t0)
    j fail

supervisor_payload:
    lui t0, 0x20010
    sw a0, 960(t0)
    sw a1, 964(t0)

    csrr t4, mstatus

    li t1, 0x5a
    lw t2, 1000(t0)
    bne t2, t1, fail
    li t1, 0x00000222
    sw t1, 1008(t0)
    j done

.org 0x100
supervisor_trap:
    lui t4, 0x20010
    csrr t5, sepc
    sw t5, 992(t4)
    csrr t6, scause
    sw t6, 996(t4)
    li t6, 0x5a
    sw t6, 1000(t4)
    addi t5, t5, 4
    csrw sepc, t5
    sret

done:
    j done
