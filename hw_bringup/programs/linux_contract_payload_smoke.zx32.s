    lui s0, 0x20010
    sw a0, 808(s0)
    sw a1, 812(s0)

    auipc t0, 0
    li t1, 0x5f4
    add t0, t0, t1
    csrw stvec, t0

    lw t0, 0(a1)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 816(s0)
    li t1, 0xD00DFEED
    bne t2, t1, fail

    lw t0, 4(a1)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 840(s0)
    li t1, 0x100
    bne t2, t1, fail

    lw t0, 8(a1)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 844(s0)
    li t1, 0x38
    bne t2, t1, fail
    add t4, a1, t2

    lw t0, 12(a1)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 848(s0)
    li t1, 0xa0
    bne t2, t1, fail

    lw t0, 0(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 852(s0)
    li t1, 1
    bne t2, t1, fail

    lw t0, 8(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    li t1, 3
    bne t2, t1, fail

    lw t0, 20(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 856(s0)
    li t1, 1
    bne t2, t1, fail

    lw t0, 24(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    li t1, 3
    bne t2, t1, fail

    lw t0, 32(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    li t1, 0xf
    bne t2, t1, fail

    lw t0, 36(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 860(s0)
    li t1, 1
    bne t2, t1, fail

    lw t0, 40(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 864(s0)
    li t1, 1
    bne t2, t1, fail

    lw t0, 60(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    li t1, 3
    bne t2, t1, fail

    lw t0, 68(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    li t1, 0x1b
    bne t2, t1, fail

    lw t0, 72(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 868(s0)
    li t1, 0x80000000
    bne t2, t1, fail

    lw t0, 76(t4)
    li t1, 0x000000ff
    and t2, t0, t1
    slli t2, t2, 24
    li t1, 0x0000ff00
    and t3, t0, t1
    slli t3, t3, 8
    or t2, t2, t3
    li t1, 0x00ff0000
    and t3, t0, t1
    srli t3, t3, 8
    or t2, t2, t3
    srli t3, t0, 24
    or t2, t2, t3
    sw t2, 872(s0)
    li t1, 0x04000000
    bne t2, t1, fail

    li a6, 0
    li a7, 0x10
    ecall
    sw a0, 820(s0)
    li t0, 2
    bne a0, t0, fail

    li t0, 0x20
    csrw sie, t0

    csrr a0, time
    li t1, 4096
    add a0, a0, t1
    li a6, 0
    li a7, 0x54494D45
    ecall
    sw a0, 796(s0)
    bne a0, x0, fail

    csrr t0, time
    sw t0, 832(s0)

    li t0, 0x2
    csrs sstatus, t0

wait_irq:
    lw t1, 824(s0)
    bne t1, x0, irq_seen
    csrr t2, time
    sw t2, 836(s0)
    j wait_irq

irq_seen:
    csrr t2, time
    sw t2, 836(s0)

    li t0, 0x00000222
    sw t0, 1008(s0)

done:
    j done

fail:
    li t0, 0x00000333
    sw t0, 1008(s0)
    j done

.org 0x600
s_trap:
    csrr t1, scause
    sw t1, 824(s0)
    csrr t2, sepc
    sw t2, 828(s0)

    li t3, 0x10010000
    sw x0, 12(t3)
    sw x0, 8(t3)

    sret
