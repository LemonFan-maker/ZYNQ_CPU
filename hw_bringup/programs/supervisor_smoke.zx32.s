    addi t0, x0, supervisor_trap
    csrw stvec, t0

    li t0, 0x200
    csrw medeleg, t0

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
    ecall
    lui t0, 0x20010
    li t1, 0x00000222
    sw t1, 1008(t0)
    j done

.org 0x80
supervisor_trap:
    lui t0, 0x20010
    csrr t1, sepc
    sw t1, 992(t0)
    csrr t2, scause
    sw t2, 996(t0)
    li t3, 0x5a
    sw t3, 1000(t0)
    addi t1, t1, 4
    csrw sepc, t1
    sret

done:
    j done
