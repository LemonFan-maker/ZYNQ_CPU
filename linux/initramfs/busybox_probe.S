.section .rodata
banner:
    .ascii "\n[zx32-bb-probe] entered\n"
.set banner_len, . - banner
open_start:
    .ascii "[zx32-bb-probe] open /bin/busybox\n"
.set open_start_len, . - open_start
open_ok:
    .ascii "[zx32-bb-probe] /bin/busybox readable\n"
.set open_ok_len, . - open_ok
open_fail:
    .ascii "[zx32-bb-probe] /bin/busybox open/read fail=0x"
.set open_fail_len, . - open_fail
magic_fail:
    .ascii "[zx32-bb-probe] /bin/busybox bad elf magic\n"
.set magic_fail_len, . - magic_fail
exec_start:
    .ascii "[zx32-bb-probe] about to execve /bin/busybox\n"
.set exec_start_len, . - exec_start
exec_msg:
    .ascii "[zx32-bb-probe] exec busybox sh -> staged probe\n"
.set exec_msg_len, . - exec_msg
exec_fail:
    .ascii "[zx32-bb-probe] execve fail=0x"
.set exec_fail_len, . - exec_fail
alive:
    .ascii "[zx32-bb-probe] alive\n"
.set alive_len, . - alive
nl:
    .ascii "\n"
hex_digits:
    .ascii "0123456789ABCDEF"
busybox_path:
    .ascii "/bin/busybox\0"
argv0:
    .ascii "busybox\0"
argv1:
    .ascii "sh\0"
argv2:
    .ascii "-c\0"
argv3:
    .ascii "echo '[zx32-bb-probe] busybox shell ok'; exec /bin/sh /zx32-stage\0"

.section .text
.global _start

_start:
    la a1, banner
    li a2, banner_len
    jal write_stdout

    la a1, open_start
    li a2, open_start_len
    jal write_stdout

    li a0, -100
    la a1, busybox_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, open_failed
    mv s0, a0

    addi sp, sp, -16
    mv a0, s0
    mv a1, sp
    li a2, 4
    li a7, 63
    ecall
    li t0, 4
    bne a0, t0, read_failed

    lbu t1, 0(sp)
    li t2, 0x7f
    bne t1, t2, bad_magic
    lbu t1, 1(sp)
    li t2, 0x45
    bne t1, t2, bad_magic
    lbu t1, 2(sp)
    li t2, 0x4c
    bne t1, t2, bad_magic
    lbu t1, 3(sp)
    li t2, 0x46
    bne t1, t2, bad_magic

    addi sp, sp, 16
    mv a0, s0
    li a7, 57
    ecall
    la a1, open_ok
    li a2, open_ok_len
    jal write_stdout
    j run_exec

read_failed:
    mv s1, a0
    addi sp, sp, 16
    mv a0, s0
    li a7, 57
    ecall
    mv a0, s1
    la a1, open_fail
    li a2, open_fail_len
    jal write_hex32_line
    j idle_loop

bad_magic:
    addi sp, sp, 16
    mv a0, s0
    li a7, 57
    ecall
    la a1, magic_fail
    li a2, magic_fail_len
    jal write_stdout
    j idle_loop

open_failed:
    la a1, open_fail
    li a2, open_fail_len
    jal write_hex32_line
    j idle_loop

run_exec:
    la a1, exec_msg
    li a2, exec_msg_len
    jal write_stdout

    addi sp, sp, -32
    la t0, argv0
    sw t0, 0(sp)
    la t0, argv1
    sw t0, 4(sp)
    la t0, argv2
    sw t0, 8(sp)
    la t0, argv3
    sw t0, 12(sp)
    sw zero, 16(sp)

    la a1, exec_start
    li a2, exec_start_len
    jal write_stdout

    la a0, busybox_path
    mv a1, sp
    mv a2, zero
    li a7, 221
    ecall

    addi sp, sp, 32
    la a1, exec_fail
    li a2, exec_fail_len
    jal write_hex32_line

idle_loop:
    la a1, alive
    li a2, alive_len
    jal write_stdout
    jal sleep_short
    j idle_loop

sleep_short:
    addi sp, sp, -32
    sw zero, 0(sp)
    sw zero, 4(sp)
    li t0, 500000000
    sw t0, 8(sp)
    sw zero, 12(sp)
    li a0, 1
    mv a1, zero
    mv a2, sp
    addi a3, sp, 16
    li a7, 407
    ecall
    addi sp, sp, 32
    ret

busy_delay:
    li t0, 0x400000
busy_delay_loop:
    addi t0, t0, -1
    bnez t0, busy_delay_loop
    ret

write_stdout:
    li a0, 1
    li a7, 64
    ecall
    j sleep_short

write_hex32_line:
    mv s2, a0
    jal write_stdout
    addi sp, sp, -16
    li t0, 8
    mv t1, s2
    la t2, hex_digits
    mv t3, sp
hex_loop:
    srli t4, t1, 28
    add t5, t2, t4
    lbu t6, 0(t5)
    sb t6, 0(t3)
    slli t1, t1, 4
    addi t3, t3, 1
    addi t0, t0, -1
    bnez t0, hex_loop
    li a0, 1
    mv a1, sp
    li a2, 8
    li a7, 64
    ecall
    li a0, 1
    la a1, nl
    li a2, 1
    li a7, 64
    ecall
    addi sp, sp, 16
    j sleep_short
