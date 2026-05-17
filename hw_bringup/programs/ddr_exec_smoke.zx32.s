    auipc t1, 0
    lui t0, 0x20010
    sw t1, 960(t0)

    li t2, 0xA5A55A5A
    sw t2, 964(t0)

    li t3, 0
loop:
    addi t3, t3, 1
    li t4, 16
    bne t3, t4, loop
    sw t3, 968(t0)

    li t2, 0x00000222
    sw t2, 1008(t0)

done:
    j done
