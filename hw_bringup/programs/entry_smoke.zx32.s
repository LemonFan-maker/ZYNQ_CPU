j fail
_start:
    lui t0, 0x20010
    jal ra, main
    sw a0, 1008(t0)
    jal x0, done
main:
    lui a0, 0xabcd1
    addi a0, a0, 0x234
    ret
done:
    jal x0, done
fail:
    jal x0, fail
