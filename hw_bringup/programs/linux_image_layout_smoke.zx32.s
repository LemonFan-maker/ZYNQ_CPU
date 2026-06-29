    lui s0, 0x20010

    lw t0, 768(s0)
    lw t1, 772(s0)

    li t4, 0x80000000
    lw t2, 0(t4)
    sw t2, 908(s0)
    li t4, 0x80100000
    lw t2, 0(t4)
    sw t2, 912(s0)
    li t4, 0x80200000
    lw t2, 0(t4)
    sw t2, 916(s0)
    li t4, 0x80300000
    lw t2, 0(t4)
    sw t2, 920(s0)
    li t4, 0x80400000
    lw t2, 0(t4)
    sw t2, 924(s0)
    li t4, 0x80500000
    lw t2, 0(t4)
    sw t2, 928(s0)
    li t4, 0x82000000
    lw t2, 0(t4)
    sw t2, 932(s0)

    lw t2, 0(t0)
    sw t2, 876(s0)

    lw t2, 8(t0)
    sw t2, 880(s0)

    lw t2, 12(t0)
    sw t2, 884(s0)

    lw t2, 16(t0)
    sw t2, 888(s0)

    lw t2, 20(t0)
    sw t2, 892(s0)

    lw t2, 48(t0)
    sw t2, 896(s0)

    lw t2, 52(t0)
    sw t2, 900(s0)

    lw t2, 56(t0)
    sw t2, 904(s0)

    lw t2, 0(t1)
    sw t2, 816(s0)

    lw t2, 876(s0)
    li t3, 0x0000106f
    bne t2, t3, fail

    lw t2, 880(s0)
    li t3, 0x00400000
    bne t2, t3, fail

    lw t2, 884(s0)
    bne t2, x0, fail

    lw t2, 888(s0)
    beq t2, x0, fail
    li t3, 0x02000000
    bltu t2, t3, size_ok
    j fail

size_ok:
    lw t2, 892(s0)
    bne t2, x0, fail

    lw t2, 896(s0)
    li t3, 0x43534952
    bne t2, t3, fail

    lw t2, 900(s0)
    li t3, 0x00000056
    bne t2, t3, fail

    lw t2, 904(s0)
    li t3, 0x05435352
    bne t2, t3, fail

    lw t2, 816(s0)
    li t3, 0xedfe0dd0
    bne t2, t3, fail

    li t3, 0x00000222
    sw t3, 1008(s0)
done:
    j done

fail:
    li t3, 0x00000333
    sw t3, 1008(s0)
    j done
