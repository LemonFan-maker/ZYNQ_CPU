    lui t0, 0x10010
    sw x0, 8(t0)
    sw x0, 12(t0)
    lw t1, 0(t0)
    addi t1, t1, 200
    sw x0, 12(t0)
    sw t1, 8(t0)

    addi t0, x0, timer_trap
    csrw stvec, t0

    li t0, 0x20
    csrw mideleg, t0
    csrw sie, t0

    addi t0, x0, supervisor_wait
    csrw mepc, t0

    li t0, 0x800
    csrw mstatus, t0
    mret

fail:
    lui t0, 0x20010
    li t1, 0x00000333
    sw t1, 1008(t0)
    j fail

supervisor_wait:
    li t0, 0x2
    csrw sstatus, t0
    lui t0, 0x20010
    li t2, 0x5a
wait_for_irq:
    lw t1, 1000(t0)
    bne t1, t2, wait_for_irq
    li t1, 0x00000222
    sw t1, 1008(t0)
    j done

.org 0x80
timer_trap:
    lui t4, 0x10010
    sw x0, 8(t4)
    sw x0, 12(t4)
    lui t4, 0x20010
    csrr t5, sepc
    sw t5, 992(t4)
    csrr t6, scause
    sw t6, 996(t4)
    li t6, 0x5a
    sw t6, 1000(t4)
    sret

done:
    j done
