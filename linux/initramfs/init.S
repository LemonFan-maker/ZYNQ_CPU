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
uname_ok:
    .ascii "[zx32-init] uname ok\n"
.set uname_ok_len, . - uname_ok
uname_fail:
    .ascii "[zx32-init] uname failed\n"
.set uname_fail_len, . - uname_fail
clock_ok:
    .ascii "[zx32-init] clock_gettime64 ok\n"
.set clock_ok_len, . - clock_ok
clock_fail:
    .ascii "[zx32-init] clock_gettime64 failed\n"
.set clock_fail_len, . - clock_fail
sleep_ok:
    .ascii "[zx32-init] clock_nanosleep64 ok\n"
.set sleep_ok_len, . - sleep_ok
sleep_fail:
    .ascii "[zx32-init] clock_nanosleep64 failed\n"
.set sleep_fail_len, . - sleep_fail
brk_ok:
    .ascii "[zx32-init] brk ok\n"
.set brk_ok_len, . - brk_ok
brk_fail:
    .ascii "[zx32-init] brk failed\n"
.set brk_fail_len, . - brk_fail
mmap_ok:
    .ascii "[zx32-init] mmap ok\n"
.set mmap_ok_len, . - mmap_ok
mmap_fail:
    .ascii "[zx32-init] mmap failed\n"
.set mmap_fail_len, . - mmap_fail
vfs_path:
    .ascii "/init\0"
vfs_ok:
    .ascii "[zx32-init] vfs ok\n"
.set vfs_ok_len, . - vfs_ok
vfs_fail:
    .ascii "[zx32-init] vfs failed\n"
.set vfs_fail_len, . - vfs_fail
root_path:
    .ascii "/\0"
cwd_ok:
    .ascii "[zx32-init] cwd ok\n"
.set cwd_ok_len, . - cwd_ok
cwd_fail:
    .ascii "[zx32-init] cwd failed\n"
.set cwd_fail_len, . - cwd_fail
dir_ok:
    .ascii "[zx32-init] getdents64 ok\n"
.set dir_ok_len, . - dir_ok
dir_fail:
    .ascii "[zx32-init] getdents64 failed\n"
.set dir_fail_len, . - dir_fail
pipe_payload:
    .ascii "zx32"
pipe_ok:
    .ascii "[zx32-init] pipe2 ok\n"
.set pipe_ok_len, . - pipe_ok
pipe_fail:
    .ascii "[zx32-init] pipe2 failed\n"
.set pipe_fail_len, . - pipe_fail
lseek_ok:
    .ascii "[zx32-init] lseek ok\n"
.set lseek_ok_len, . - lseek_ok
lseek_fail:
    .ascii "[zx32-init] lseek failed\n"
.set lseek_fail_len, . - lseek_fail
writev_part0:
    .ascii "[zx32-init] "
.set writev_part0_len, . - writev_part0
writev_part1:
    .ascii "writev ok\n"
.set writev_part1_len, . - writev_part1
writev_fail:
    .ascii "[zx32-init] writev failed\n"
.set writev_fail_len, . - writev_fail
readv_ok:
    .ascii "[zx32-init] readv ok\n"
.set readv_ok_len, . - readv_ok
readv_fail:
    .ascii "[zx32-init] readv failed\n"
.set readv_fail_len, . - readv_fail
clone_child_ok:
    .ascii "[zx32-init] clone child ok\n"
.set clone_child_ok_len, . - clone_child_ok
clone_ok:
    .ascii "[zx32-init] clone/waitid ok\n"
.set clone_ok_len, . - clone_ok
clone_fail:
    .ascii "[zx32-init] clone/waitid failed\n"
.set clone_fail_len, . - clone_fail
clone_wait_echild:
    .ascii "[zx32-init] waitid echild\n"
.set clone_wait_echild_len, . - clone_wait_echild
clone_wait_eintr:
    .ascii "[zx32-init] waitid eintr\n"
.set clone_wait_eintr_len, . - clone_wait_eintr
clone_wait_restart:
    .ascii "[zx32-init] waitid restart\n"
.set clone_wait_restart_len, . - clone_wait_restart
clone_wait_restart_nointr:
    .ascii "[zx32-init] waitid restart-nointr\n"
.set clone_wait_restart_nointr_len, . - clone_wait_restart_nointr
clone_wait_restart_nohand:
    .ascii "[zx32-init] waitid restart-nohand\n"
.set clone_wait_restart_nohand_len, . - clone_wait_restart_nohand
clone_wait_restart_block:
    .ascii "[zx32-init] waitid restart-block\n"
.set clone_wait_restart_block_len, . - clone_wait_restart_block
clone_wait_einval:
    .ascii "[zx32-init] waitid einval\n"
.set clone_wait_einval_len, . - clone_wait_einval
clone_wait_zero:
    .ascii "[zx32-init] waitid zero\n"
.set clone_wait_zero_len, . - clone_wait_zero
clone_wait_ret_prefix:
    .ascii "[zx32-init] waitid ret=0x"
.set clone_wait_ret_prefix_len, . - clone_wait_ret_prefix
clone_wait_status_prefix:
    .ascii "[zx32-init] waitid status=0x"
.set clone_wait_status_prefix_len, . - clone_wait_status_prefix
clone_wait_other:
    .ascii "[zx32-init] waitid other\n"
.set clone_wait_other_len, . - clone_wait_other
busybox_prep_ok:
    .ascii "[zx32-init] busybox prep ok\n"
.set busybox_prep_ok_len, . - busybox_prep_ok
busybox_prep_fail_prefix:
    .ascii "[zx32-init] busybox prep fail=0x"
.set busybox_prep_fail_prefix_len, . - busybox_prep_fail_prefix
linux_prep_ok:
    .ascii "[zx32-init] linux prep ok\n"
.set linux_prep_ok_len, . - linux_prep_ok
linux_prep_fail_prefix:
    .ascii "[zx32-init] linux prep fail=0x"
.set linux_prep_fail_prefix_len, . - linux_prep_fail_prefix
hex_digits:
    .ascii "0123456789ABCDEF"
exec_path:
    .ascii "/bin/zx32-exec-smoke\0"
readlink_path:
    .ascii "/bin/zx32-link\0"
proc_path:
    .ascii "/proc\0"
proc_type:
    .ascii "proc\0"
sys_path:
    .ascii "/sys\0"
sysfs_type:
    .ascii "sysfs\0"
exec_fail:
    .ascii "[zx32-init] execve failed\n"
.set exec_fail_len, . - exec_fail
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
    j run_uname

getpid_failed:
    la a1, getpid_fail
    li a2, getpid_fail_len
    jal write_stdout
    j run_uname

run_uname:
    addi sp, sp, -512
    mv a0, sp
    li a7, 160
    ecall
    addi sp, sp, 512
    bnez a0, uname_failed
    la a1, uname_ok
    li a2, uname_ok_len
    jal write_stdout
    j run_clock_gettime

uname_failed:
    la a1, uname_fail
    li a2, uname_fail_len
    jal write_stdout
    j run_clock_gettime

run_clock_gettime:
    addi sp, sp, -16
    li a0, 1
    mv a1, sp
    li a7, 403
    ecall
    addi sp, sp, 16
    bnez a0, clock_failed
    la a1, clock_ok
    li a2, clock_ok_len
    jal write_stdout
    j run_clock_nanosleep

clock_failed:
    la a1, clock_fail
    li a2, clock_fail_len
    jal write_stdout
    j run_clock_nanosleep

run_clock_nanosleep:
    addi sp, sp, -32
    sw zero, 0(sp)
    sw zero, 4(sp)
    li t0, 1000000
    sw t0, 8(sp)
    sw zero, 12(sp)
    li a0, 1
    mv a1, zero
    mv a2, sp
    addi a3, sp, 16
    li a7, 407
    ecall
    addi sp, sp, 32
    bnez a0, sleep_failed
    la a1, sleep_ok
    li a2, sleep_ok_len
    jal write_stdout
    j run_brk

sleep_failed:
    la a1, sleep_fail
    li a2, sleep_fail_len
    jal write_stdout
    j run_brk

run_brk:
    mv a0, zero
    li a7, 214
    ecall
    beqz a0, brk_failed
    mv s1, a0
    li t0, 4096
    add s2, s1, t0
    mv a0, s2
    li a7, 214
    ecall
    bltu a0, s2, brk_failed
    la a1, brk_ok
    li a2, brk_ok_len
    jal write_stdout
    j run_mmap

brk_failed:
    la a1, brk_fail
    li a2, brk_fail_len
    jal write_stdout
    j run_mmap

run_mmap:
    mv a0, zero
    li a1, 4096
    li a2, 3
    li a3, 0x22
    li a4, -1
    mv a5, zero
    li a7, 222
    ecall
    li t0, -4096
    bgeu a0, t0, mmap_failed
    mv s3, a0
    li t1, 0x5A5A1234
    sw t1, 0(s3)
    lw t2, 0(s3)
    bne t1, t2, mmap_cleanup_failed
    mv a0, s3
    li a1, 4096
    li a7, 215
    ecall
    bnez a0, mmap_failed
    la a1, mmap_ok
    li a2, mmap_ok_len
    jal write_stdout
    j run_vfs

mmap_cleanup_failed:
    mv a0, s3
    li a1, 4096
    li a7, 215
    ecall

mmap_failed:
    la a1, mmap_fail
    li a2, mmap_fail_len
    jal write_stdout
    j run_vfs

run_vfs:
    li a0, -100
    la a1, vfs_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, vfs_failed
    mv s4, a0
    addi sp, sp, -16
    mv a0, s4
    mv a1, sp
    li a2, 4
    li a7, 63
    ecall
    li t0, 4
    bne a0, t0, vfs_close_failed
    lbu t1, 0(sp)
    li t2, 0x7f
    bne t1, t2, vfs_close_failed
    lbu t1, 1(sp)
    li t2, 0x45
    bne t1, t2, vfs_close_failed
    lbu t1, 2(sp)
    li t2, 0x4c
    bne t1, t2, vfs_close_failed
    lbu t1, 3(sp)
    li t2, 0x46
    bne t1, t2, vfs_close_failed
    addi sp, sp, 16
    mv a0, s4
    li a7, 57
    ecall
    bnez a0, vfs_failed
    la a1, vfs_ok
    li a2, vfs_ok_len
    jal write_stdout
    j run_cwd

vfs_close_failed:
    addi sp, sp, 16
    mv a0, s4
    li a7, 57
    ecall

vfs_failed:
    la a1, vfs_fail
    li a2, vfs_fail_len
    jal write_stdout
    j run_cwd

run_cwd:
    addi sp, sp, -128
    mv a0, sp
    li a1, 128
    li a7, 17
    ecall
    bltz a0, cwd_restore_failed
    la a0, root_path
    li a7, 49
    ecall
    bnez a0, cwd_restore_failed
    mv a0, sp
    li a1, 128
    li a7, 17
    ecall
    bltz a0, cwd_restore_failed
    lbu t0, 0(sp)
    li t1, 0x2f
    bne t0, t1, cwd_restore_failed
    lbu t0, 1(sp)
    bnez t0, cwd_restore_failed
    addi sp, sp, 128
    la a1, cwd_ok
    li a2, cwd_ok_len
    jal write_stdout
    j run_getdents

cwd_restore_failed:
    addi sp, sp, 128

cwd_failed:
    la a1, cwd_fail
    li a2, cwd_fail_len
    jal write_stdout
    j run_getdents

run_getdents:
    li a0, -100
    la a1, root_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, dir_failed
    mv s5, a0
    addi sp, sp, -256
    mv a0, s5
    mv a1, sp
    li a2, 256
    li a7, 61
    ecall
    blez a0, dir_close_failed
    addi sp, sp, 256
    mv a0, s5
    li a7, 57
    ecall
    bnez a0, dir_failed
    la a1, dir_ok
    li a2, dir_ok_len
    jal write_stdout
    j run_pipe

dir_close_failed:
    addi sp, sp, 256
    mv a0, s5
    li a7, 57
    ecall

dir_failed:
    la a1, dir_fail
    li a2, dir_fail_len
    jal write_stdout
    j run_pipe

run_pipe:
    addi sp, sp, -16
    mv a0, sp
    mv a1, zero
    li a7, 59
    ecall
    bnez a0, pipe_restore_failed
    lw s6, 0(sp)
    lw s7, 4(sp)
    mv a0, s7
    la a1, pipe_payload
    li a2, 4
    li a7, 64
    ecall
    li t0, 4
    bne a0, t0, pipe_close_failed
    mv a0, s6
    addi a1, sp, 8
    li a2, 4
    li a7, 63
    ecall
    li t0, 4
    bne a0, t0, pipe_close_failed
    lbu t1, 8(sp)
    li t2, 0x7a
    bne t1, t2, pipe_close_failed
    lbu t1, 9(sp)
    li t2, 0x78
    bne t1, t2, pipe_close_failed
    lbu t1, 10(sp)
    li t2, 0x33
    bne t1, t2, pipe_close_failed
    lbu t1, 11(sp)
    li t2, 0x32
    bne t1, t2, pipe_close_failed
    mv a0, s7
    li a7, 57
    ecall
    bnez a0, pipe_read_close_failed
    mv a0, s6
    li a7, 57
    ecall
    bnez a0, pipe_restore_failed
    addi sp, sp, 16
    la a1, pipe_ok
    li a2, pipe_ok_len
    jal write_stdout
    j run_lseek

pipe_close_failed:
    mv a0, s7
    li a7, 57
    ecall

pipe_read_close_failed:
    mv a0, s6
    li a7, 57
    ecall

pipe_restore_failed:
    addi sp, sp, 16

pipe_failed:
    la a1, pipe_fail
    li a2, pipe_fail_len
    jal write_stdout
    j run_lseek

run_lseek:
    li a0, -100
    la a1, vfs_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, lseek_failed
    mv s4, a0
    addi sp, sp, -16
    mv a0, s4
    mv a1, zero
    li a2, 1
    mv a3, sp
    mv a4, zero
    li a7, 62
    ecall
    bnez a0, lseek_read_close_failed
    lw t0, 0(sp)
    li t1, 1
    bne t0, t1, lseek_read_close_failed
    lw t0, 4(sp)
    bnez t0, lseek_read_close_failed
    mv a0, s4
    addi a1, sp, 8
    li a2, 1
    li a7, 63
    ecall
    li t0, 1
    bne a0, t0, lseek_read_close_failed
    lbu t1, 8(sp)
    li t2, 0x45
    bne t1, t2, lseek_read_close_failed
    addi sp, sp, 16
    mv a0, s4
    li a7, 57
    ecall
    bnez a0, lseek_failed
    la a1, lseek_ok
    li a2, lseek_ok_len
    jal write_stdout
    j run_writev

lseek_read_close_failed:
    addi sp, sp, 16

lseek_close_failed:
    mv a0, s4
    li a7, 57
    ecall

lseek_failed:
    la a1, lseek_fail
    li a2, lseek_fail_len
    jal write_stdout
    j run_writev

run_writev:
    addi sp, sp, -16
    la t0, writev_part0
    sw t0, 0(sp)
    li t0, writev_part0_len
    sw t0, 4(sp)
    la t0, writev_part1
    sw t0, 8(sp)
    li t0, writev_part1_len
    sw t0, 12(sp)
    li a0, 1
    mv a1, sp
    li a2, 2
    li a7, 66
    ecall
    li t0, writev_part0_len + writev_part1_len
    addi sp, sp, 16
    bne a0, t0, writev_failed
    j run_readv

writev_failed:
    la a1, writev_fail
    li a2, writev_fail_len
    jal write_stdout
    j run_readv

run_readv:
    li a0, -100
    la a1, vfs_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, readv_failed
    mv s4, a0
    addi sp, sp, -32
    addi t0, sp, 16
    sw t0, 0(sp)
    li t0, 2
    sw t0, 4(sp)
    addi t0, sp, 18
    sw t0, 8(sp)
    li t0, 2
    sw t0, 12(sp)
    mv a0, s4
    mv a1, sp
    li a2, 2
    li a7, 65
    ecall
    li t0, 4
    bne a0, t0, readv_close_failed
    lbu t1, 16(sp)
    li t2, 0x7f
    bne t1, t2, readv_close_failed
    lbu t1, 17(sp)
    li t2, 0x45
    bne t1, t2, readv_close_failed
    lbu t1, 18(sp)
    li t2, 0x4c
    bne t1, t2, readv_close_failed
    lbu t1, 19(sp)
    li t2, 0x46
    bne t1, t2, readv_close_failed
    addi sp, sp, 32
    mv a0, s4
    li a7, 57
    ecall
    bnez a0, readv_failed
    la a1, readv_ok
    li a2, readv_ok_len
    jal write_stdout
    j run_clone

readv_close_failed:
    addi sp, sp, 32
    mv a0, s4
    li a7, 57
    ecall

readv_failed:
    la a1, readv_fail
    li a2, readv_fail_len
    jal write_stdout
    j run_clone

run_clone:
    li a0, 17
    mv a1, zero
    mv a2, zero
    mv a3, zero
    mv a4, zero
    li a7, 220
    ecall
    beqz a0, clone_child
    bltz a0, clone_failed
    jal busy_delay
    addi sp, sp, -128

    li s8, 64
clone_wait_retry:
    sw zero, 0(sp)
    sw zero, 4(sp)
    sw zero, 8(sp)
    sw zero, 12(sp)
    sw zero, 16(sp)
    sw zero, 20(sp)
    li a0, 0
    mv a1, zero
    mv a2, sp
    li a3, 5
    mv a4, zero
    li a7, 95
    ecall
    bnez a0, clone_wait_failed
    lw t0, 0(sp)
    li t1, 17
    beq t0, t1, clone_wait_done
    jal busy_delay
    addi s8, s8, -1
    bnez s8, clone_wait_retry
    mv a0, zero
    j clone_wait_failed

clone_wait_done:
    lw t0, 20(sp)
    bnez t0, clone_wait_status_failed
    addi sp, sp, 128
    la a1, clone_ok
    li a2, clone_ok_len
    jal write_stdout
    j run_busybox_prep

clone_wait_status_failed:
    mv a0, t0
    addi sp, sp, 128
    la a1, clone_wait_status_prefix
    li a2, clone_wait_status_prefix_len
    jal write_hex32_line
    j clone_failed

clone_wait_failed:
    addi sp, sp, 128
    beqz a0, clone_wait_failed_zero
    li t0, -10
    beq a0, t0, clone_wait_failed_echild
    li t0, -4
    beq a0, t0, clone_wait_failed_eintr
    li t0, -22
    beq a0, t0, clone_wait_failed_einval
    li t0, -512
    beq a0, t0, clone_wait_failed_restart
    li t0, -513
    beq a0, t0, clone_wait_failed_restart_nointr
    li t0, -514
    beq a0, t0, clone_wait_failed_restart_nohand
    li t0, -516
    beq a0, t0, clone_wait_failed_restart_block
    la a1, clone_wait_ret_prefix
    li a2, clone_wait_ret_prefix_len
    jal write_hex32_line
    j clone_failed

clone_wait_failed_zero:
    la a1, clone_wait_zero
    li a2, clone_wait_zero_len
    jal write_stdout
    j clone_failed

clone_wait_failed_echild:
    la a1, clone_wait_echild
    li a2, clone_wait_echild_len
    jal write_stdout
    j clone_failed

clone_wait_failed_eintr:
    la a1, clone_wait_eintr
    li a2, clone_wait_eintr_len
    jal write_stdout
    j clone_failed

clone_wait_failed_einval:
    la a1, clone_wait_einval
    li a2, clone_wait_einval_len
    jal write_stdout
    j clone_failed

clone_wait_failed_restart:
    la a1, clone_wait_restart
    li a2, clone_wait_restart_len
    jal write_stdout
    j clone_failed

clone_wait_failed_restart_nointr:
    la a1, clone_wait_restart_nointr
    li a2, clone_wait_restart_nointr_len
    jal write_stdout
    j clone_failed

clone_wait_failed_restart_nohand:
    la a1, clone_wait_restart_nohand
    li a2, clone_wait_restart_nohand_len
    jal write_stdout
    j clone_failed

clone_wait_failed_restart_block:
    la a1, clone_wait_restart_block
    li a2, clone_wait_restart_block_len
    jal write_stdout

clone_failed:
    la a1, clone_fail
    li a2, clone_fail_len
    jal write_stdout
    j run_busybox_prep

clone_child:
    la a1, clone_child_ok
    li a2, clone_child_ok_len
    jal write_stdout
    mv a0, zero
    li a7, 93
    ecall

child_exit_loop:
    j child_exit_loop

run_busybox_prep:
    li a7, 173
    ecall
    bltz a0, busybox_prep_failed_01

    li a7, 174
    ecall
    bnez a0, busybox_prep_failed_02

    li a7, 175
    ecall
    bnez a0, busybox_prep_failed_03

    li a7, 176
    ecall
    bnez a0, busybox_prep_failed_04

    li a7, 177
    ecall
    bnez a0, busybox_prep_failed_05

    li a7, 178
    ecall
    blez a0, busybox_prep_failed_06

    addi sp, sp, -16
    mv a0, zero
    li a1, 7
    mv a2, zero
    mv a3, sp
    li a7, 261
    ecall
    bnez a0, busybox_prep_restore_failed_07
    lw t0, 0(sp)
    lw t1, 4(sp)
    or t0, t0, t1
    beqz t0, busybox_prep_restore_failed_07
    addi sp, sp, 16

    li a0, 1
    li a1, 10
    mv a2, zero
    li a7, 24
    ecall
    li t0, 10
    bne a0, t0, busybox_prep_failed_08
    li a0, 10
    li a1, 1
    mv a2, zero
    li a7, 25
    ecall
    bltz a0, busybox_prep_close_failed_09
    li a0, 10
    li a1, 2
    li a2, 1
    li a7, 25
    ecall
    bnez a0, busybox_prep_close_failed_0a
    li a0, 10
    li a1, 1
    mv a2, zero
    li a7, 25
    ecall
    andi t0, a0, 1
    beqz t0, busybox_prep_close_failed_0b
    li a0, 10
    li a7, 57
    ecall
    bnez a0, busybox_prep_failed_0c

    addi sp, sp, -256
    li a0, -100
    la a1, vfs_path
    mv a2, zero
    li a3, 0x7ff
    mv a4, sp
    li a7, 291
    ecall
    bnez a0, busybox_prep_restore_failed_0d
    lw t0, 0(sp)
    beqz t0, busybox_prep_restore_failed_0d
    lw t0, 40(sp)
    beqz t0, busybox_prep_restore_failed_0d
    addi sp, sp, 256

    addi sp, sp, -64
    li a0, -100
    la a1, readlink_path
    mv a2, sp
    li a3, 64
    li a7, 78
    ecall
    blez a0, busybox_prep_restore_failed_0e
    lbu t0, 0(sp)
    li t1, 0x2f
    bne t0, t1, busybox_prep_restore_failed_0e
    addi sp, sp, 64

    la a1, busybox_prep_ok
    li a2, busybox_prep_ok_len
    jal write_stdout
    j run_linux_prep

busybox_prep_restore_failed_07:
    addi sp, sp, 16
busybox_prep_failed_07:
    li a0, 0x07
    j busybox_prep_failed

busybox_prep_close_failed_09:
    li t0, 0x09
    j busybox_prep_close_failed

busybox_prep_close_failed_0a:
    li t0, 0x0a
    j busybox_prep_close_failed

busybox_prep_close_failed_0b:
    li t0, 0x0b
    j busybox_prep_close_failed

busybox_prep_close_failed:
    li a0, 10
    li a7, 57
    ecall
    mv a0, t0
    j busybox_prep_failed

busybox_prep_restore_failed_0d:
    addi sp, sp, 256
    li a0, 0x0d
    j busybox_prep_failed

busybox_prep_restore_failed_0e:
    addi sp, sp, 64
    li a0, 0x0e
    j busybox_prep_failed

busybox_prep_failed_01:
    li a0, 0x01
    j busybox_prep_failed
busybox_prep_failed_02:
    li a0, 0x02
    j busybox_prep_failed
busybox_prep_failed_03:
    li a0, 0x03
    j busybox_prep_failed
busybox_prep_failed_04:
    li a0, 0x04
    j busybox_prep_failed
busybox_prep_failed_05:
    li a0, 0x05
    j busybox_prep_failed
busybox_prep_failed_06:
    li a0, 0x06
    j busybox_prep_failed
busybox_prep_failed_08:
    li a0, 0x08
    j busybox_prep_failed
busybox_prep_failed_0c:
    li a0, 0x0c
    j busybox_prep_failed

busybox_prep_failed:
    la a1, busybox_prep_fail_prefix
    li a2, busybox_prep_fail_prefix_len
    jal write_hex32_line
    j run_execve

run_linux_prep:
    addi sp, sp, -16
    sw zero, 0(sp)
    sw zero, 4(sp)
    sw zero, 8(sp)
    sw zero, 12(sp)
    mv a0, sp
    li a7, 96
    ecall
    blez a0, linux_prep_restore_failed_10

    mv a0, sp
    li a1, 129
    li a2, 1
    mv a3, zero
    mv a4, zero
    mv a5, zero
    li a7, 422
    ecall
    bltz a0, linux_prep_restore_failed_11
    addi sp, sp, 16

    la a0, proc_type
    la a1, proc_path
    la a2, proc_type
    mv a3, zero
    mv a4, zero
    li a7, 40
    ecall
    bnez a0, linux_prep_failed_12

    li a0, -100
    la a1, proc_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, linux_prep_failed_13
    mv s9, a0
    addi sp, sp, -128
    mv a0, s9
    mv a1, sp
    li a2, 128
    li a7, 61
    ecall
    blez a0, linux_prep_proc_close_failed_14
    addi sp, sp, 128
    mv a0, s9
    li a7, 57
    ecall
    bnez a0, linux_prep_failed_15

    la a0, sysfs_type
    la a1, sys_path
    la a2, sysfs_type
    mv a3, zero
    mv a4, zero
    li a7, 40
    ecall
    bnez a0, linux_prep_failed_16

    li a0, -100
    la a1, sys_path
    mv a2, zero
    mv a3, zero
    li a7, 56
    ecall
    bltz a0, linux_prep_failed_17
    mv s9, a0
    addi sp, sp, -128
    mv a0, s9
    mv a1, sp
    li a2, 128
    li a7, 61
    ecall
    blez a0, linux_prep_sys_close_failed_18
    addi sp, sp, 128
    mv a0, s9
    li a7, 57
    ecall
    bnez a0, linux_prep_failed_19

    la a1, linux_prep_ok
    li a2, linux_prep_ok_len
    jal write_stdout
    j run_execve

linux_prep_restore_failed_10:
    addi sp, sp, 16
    li a0, 0x10
    j linux_prep_failed

linux_prep_restore_failed_11:
    addi sp, sp, 16
    li a0, 0x11
    j linux_prep_failed

linux_prep_proc_close_failed_14:
    addi sp, sp, 128
    li t0, 0x14
    j linux_prep_close_failed

linux_prep_sys_close_failed_18:
    addi sp, sp, 128
    li t0, 0x18
    j linux_prep_close_failed

linux_prep_close_failed:
    mv a0, s9
    li a7, 57
    ecall
    mv a0, t0
    j linux_prep_failed

linux_prep_failed_12:
    li a0, 0x12
    j linux_prep_failed
linux_prep_failed_13:
    li a0, 0x13
    j linux_prep_failed
linux_prep_failed_15:
    li a0, 0x15
    j linux_prep_failed
linux_prep_failed_16:
    li a0, 0x16
    j linux_prep_failed
linux_prep_failed_17:
    li a0, 0x17
    j linux_prep_failed
linux_prep_failed_19:
    li a0, 0x19
    j linux_prep_failed

linux_prep_failed:
    la a1, linux_prep_fail_prefix
    li a2, linux_prep_fail_prefix_len
    jal write_hex32_line
    j run_execve

run_execve:
    addi sp, sp, -16
    la t0, exec_path
    sw t0, 0(sp)
    sw zero, 4(sp)
    sw zero, 8(sp)
    la a0, exec_path
    mv a1, sp
    addi a2, sp, 8
    li a7, 221
    ecall
    addi sp, sp, 16
    la a1, exec_fail
    li a2, exec_fail_len
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

write_hex32_line:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw a0, 24(sp)
    jal write_stdout
    lw t0, 24(sp)
    la t3, hex_digits
    mv t4, sp
    li t5, 28
1:
    srl t1, t0, t5
    andi t1, t1, 0x0F
    add t2, t3, t1
    lbu t2, 0(t2)
    sb t2, 0(t4)
    addi t4, t4, 1
    addi t5, t5, -4
    bgez t5, 1b
    li t2, 0x0A
    sb t2, 0(t4)
    mv a1, sp
    li a2, 9
    jal write_stdout
    lw ra, 28(sp)
    addi sp, sp, 32
    ret
