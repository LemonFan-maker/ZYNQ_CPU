    lui s0, 0x20010
    sw a0, 896(s0)
    sw a1, 900(s0)

    auipc t0, 0
    li t1, 0xf4
    add t0, t0, t1
    csrw stvec, t0

    li t0, 0x20
    csrw sie, t0

    csrr a0, time
    li t1, 4096
    add a0, a0, t1
    li a6, 0
    li a7, 0x54494D45
    ecall
    sw a0, 904(s0)

    csrr t0, sie
    sw t0, 916(s0)
    csrr t0, sip
    sw t0, 920(s0)
    csrr t0, sstatus
    sw t0, 924(s0)
    csrr t0, time
    sw t0, 928(s0)

    li t0, 0x2
    csrs sstatus, t0

wait_irq:
    csrr t2, sip
    sw t2, 920(s0)
    csrr t2, sstatus
    sw t2, 924(s0)
    csrr t2, time
    sw t2, 932(s0)
    lw t1, 908(s0)
    beq t1, x0, wait_irq

    li t0, 0x00000222
    sw t0, 1008(s0)

done:
    j done

.org 0x100
s_trap:
    csrr t1, scause
    sw t1, 908(s0)
    csrr t2, sepc
    sw t2, 912(s0)

    li t3, 0x10010000
    sw x0, 12(t3)
    sw x0, 8(t3)

    sret
