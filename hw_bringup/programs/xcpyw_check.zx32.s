addi x1, x0, 64
addi x2, x0, 68
xcpyw x4, x1, x2
lui x5, 0x20010
lui x6, 0xabcd1
addi x6, x6, 0x234
sw x6, 1008(x5)
jal x0, 0
