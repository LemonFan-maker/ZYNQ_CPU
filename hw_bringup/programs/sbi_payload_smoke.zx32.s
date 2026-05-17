    lui t0, 0x20010
    sw a0, 928(t0)
    sw a1, 932(t0)

    li a0, 0x12345678
    li a7, 1
    ecall

    sw a0, 936(t0)
    li t1, 0x00000222
    sw t1, 1008(t0)

done:
    j done
