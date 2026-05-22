.section .rodata
banner:
    .ascii "\n[zx32-init] userspace entered\n"
.set banner_len, . - banner
getpid_ok:
    .ascii "[zx32-init] getpid ok\n"
.set getpid_ok_len, . - getpid_ok
getpid_fail:
    .ascii "[zx32-init] getpid failed\n"
.set getpid_fail_len, . - getpid_fail
tick:
    .ascii "[zx32-init] alive\n"
.set tick_len, . - tick
idle:
    .ascii "[zx32-init] idle\n"
.set idle_len, . - idle

.section .text
.global _start

_start:
    la a1, banner
    li a2, banner_len
    jal write_stdout

    li a7, 172
    ecall
    li t0, 1
    blt a0, t0, getpid_failed
    la a1, getpid_ok
    li a2, getpid_ok_len
    jal write_stdout
    j start_heartbeat

getpid_failed:
    la a1, getpid_fail
    li a2, getpid_fail_len
    jal write_stdout

start_heartbeat:
    li s0, 8

loop:
    la a1, tick
    li a2, tick_len
    jal write_stdout

    addi s0, s0, -1
    beqz s0, idle_loop
    jal busy_delay
    j loop

idle_loop:
    la a1, idle
    li a2, idle_len
    jal write_stdout

quiet_loop:
    jal busy_delay
    j quiet_loop

busy_delay:
    li t0, 0x00040000
1:
    addi t0, t0, -1
    bnez t0, 1b
    ret

sleep_one_second:
    addi sp, sp, -16
    li t0, 1
    sw t0, 0(sp)
    sw zero, 4(sp)
    mv a0, sp
    mv a1, zero
    li a7, 101
    ecall
    addi sp, sp, 16
    ret

write_stdout:
    li a0, 1
    li a7, 64
    ecall
    ret
