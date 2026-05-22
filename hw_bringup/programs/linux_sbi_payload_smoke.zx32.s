    lui s0, 0x20010
    sw a0, 676(s0)
    sw a1, 680(s0)

    auipc t0, 0
    li t1, 0x15c
    add t0, t0, t1
    csrw stvec, t0

    li a6, 0
    li a7, 0x10
    ecall
    sw a0, 684(s0)
    sw a1, 688(s0)
    bne a0, x0, fail
    li t0, 2
    bne a1, t0, fail

    li a0, 0x54494D45
    li a6, 3
    li a7, 0x10
    ecall
    sw a0, 692(s0)
    sw a1, 696(s0)
    bne a0, x0, fail
    li t0, 1
    bne a1, t0, fail

    li a0, 0x5a
    li a7, 1
    ecall
    lw t0, 700(s0)
    li t1, 0x5a
    bne t0, t1, fail

    li t0, 0x20
    csrw sie, t0

    csrr a0, time
    sw a0, 740(s0)
    li t1, 4096
    add a0, a0, t1
    li a1, 0
    li a6, 0
    li a7, 0x54494D45
    ecall
    sw a0, 704(s0)
    sw a1, 708(s0)
    bne a0, x0, fail
    bne a1, x0, fail

    csrr t0, sie
    sw t0, 728(s0)
    csrr t0, sip
    sw t0, 732(s0)
    csrr t0, sstatus
    sw t0, 736(s0)

    li t0, 0x2
    csrs sstatus, t0

wait_irq:
    csrr t2, sip
    sw t2, 732(s0)
    csrr t2, sstatus
    sw t2, 736(s0)
    csrr t2, time
    sw t2, 744(s0)
    lw t1, 720(s0)
    beq t1, x0, wait_irq

    li t0, 0x00000222
    sw t0, 1008(s0)

done:
    j done

fail:
    li t0, 0x00000333
    sw t0, 1008(s0)
    j done

.org 0x168
s_trap:
    csrr t1, scause
    sw t1, 720(s0)
    csrr t2, sepc
    sw t2, 724(s0)

    li t3, 0x10010000
    sw x0, 12(t3)
    sw x0, 8(t3)

    sret
