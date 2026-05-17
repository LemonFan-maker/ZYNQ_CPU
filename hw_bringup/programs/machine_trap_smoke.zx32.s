addi t0, x0, 0x20
addi t1, x0, 0
csrw mtvec, t0
ecall
addi t2, x0, 0x99
sw t2, 84(x0)
j done
.org 0x20
trap:
csrr t3, mepc
sw t3, 80(x0)
csrr t4, mcause
sw t4, 88(x0)
addi t3, t3, 4
csrw mepc, t3
mret
done:
j done
