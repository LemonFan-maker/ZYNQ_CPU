    lui t0, 0x20010
    lw t1, 0x3E4(t0)

    sw x0, 0(t1)

    li t2, 1
    amoadd.w t3, t2, 0(t1)
    bne t3, x0, fail1

    lw t4, 0(t1)
    bne t4, t2, fail2

    li t2, 2
    amoadd.w t3, t2, 0(t1)
    li t5, 1
    bne t3, t5, fail3

    lw t4, 0(t1)
    li t5, 3
    bne t4, t5, fail4

    sw t3, 0x3E4(t0)
    sw t4, 0x3E8(t0)
    sw t1, 0x3EC(t0)

pass:
    lui t0, 0x20010
    li t1, 0x00000222
    sw t1, 0x3F0(t0)
    j done

fail1:
    li t6, 1
    j fail

fail2:
    li t6, 2
    j fail

fail3:
    li t6, 3
    j fail

fail4:
    li t6, 4
    j fail

fail:
    lui t0, 0x20010
    sw t6, 0x3E0(t0)
    sw t3, 0x3E4(t0)
    sw t4, 0x3E8(t0)
    sw t1, 0x3EC(t0)
    li t6, 0x00000333
    sw t6, 0x3F0(t0)
fail_done:
    j fail_done

done:
    j done
