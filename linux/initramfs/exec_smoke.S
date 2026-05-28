.section .rodata
exec_ok:
    .ascii "[zx32-init] execve ok\n"
.set exec_ok_len, . - exec_ok
tick:
    .ascii "[zx32-init] alive\n"
.set tick_len, . - tick
idle:
    .ascii "[zx32-init] idle\n"
.set idle_len, . - idle

.section .text
.global _start

_start:
    la a1, exec_ok
    li a2, exec_ok_len
    jal write_stdout

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

write_stdout:
    li a0, 1
    li a7, 64
    ecall
    ret
