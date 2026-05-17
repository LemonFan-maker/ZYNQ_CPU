lui x1, 0x20010
lui x2, 0x20010
lui x3, 0x20000
lui x4, 0x43505
addi x4, x4, 0x521
addi x5, x0, 0x111
wait_start:
sw x5, 1008(x1)
lw x5, 992(x1)
bne x5, x4, wait_start
lw x6, 996(x1)
lw x7, 1000(x1)
lw x8, 1004(x1)
xdm2s x9, x6, x8
sw x9, 1012(x1)
andi x10, x9, 0x10
bne x10, x0, fail
addi x11, x3, 0
addi x12, x2, 0
addi x13, x8, 0
addi x15, x0, 0
copy_loop:
lw x14, 0(x11)
sw x14, 0(x12)
addi x11, x11, 4
addi x12, x12, 4
addi x13, x13, -4
addi x15, x15, 1
bne x13, x0, copy_loop
xds2m x9, x7, x8
sw x9, 1016(x1)
andi x10, x9, 0x20
bne x10, x0, fail
sw x15, 1020(x1)
addi x5, x0, 0x222
sw x5, 1008(x1)
jal x0, 0
fail:
addi x5, x0, 0x333
sw x5, 1008(x1)
jal x0, 0
