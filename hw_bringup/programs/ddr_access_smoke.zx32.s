    lui t0, 0x20010
    lw t1, 0x3E4(t0)

    li t2, 0xDEADBEEF
    sw t2, 0(t1)
    lw t3, 0(t1)
    bne t2, t3, fail1

    li t2, 0xCAFEBABE
    sw t2, 4(t1)
    lw t3, 4(t1)
    bne t2, t3, fail2

    li t2, 0x13579BDF
    sw t2, 0x40(t1)
    lw t3, 0x40(t1)
    bne t2, t3, fail3

    sw t2, 0x3E4(t0)
    sw t3, 0x3E8(t0)
    sw t1, 0x3EC(t0)

pass:
    lui t0, 0x20010
    li t1, 0x00000222
    sw t1, 0x3F0(t0)
    j done

fail1:
    li t4, 1
    j fail

fail2:
    li t4, 2
    j fail

fail3:
    li t4, 3
    j fail

fail:
    lui t0, 0x20010
    sw t4, 0x3E0(t0)
    sw t2, 0x3E4(t0)
    sw t3, 0x3E8(t0)
    sw t1, 0x3EC(t0)
    li t4, 0x00000333
    sw t4, 0x3F0(t0)
fail_done:
    j fail_done

done:
    j done
