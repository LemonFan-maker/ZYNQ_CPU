#include "ps_uart_probe.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "zx32_programs.h"

int run_cpu_bram_load_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_STATUS, 0U);

    for (u32 i = 0U; i < (sizeof(zx32_ps_bram_load_program) / sizeof(zx32_ps_bram_load_program[0])); i++) {
        Xil_Out32(ZYNQ_CPU_IMEM_BASE + i * 4U, zx32_ps_bram_load_program[i]);
    }
    for (u32 i = 0U; i < (sizeof(zx32_ps_bram_load_program) / sizeof(zx32_ps_bram_load_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_ps_bram_load_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_MAIL_STATUS);
        if (status == CPU_LOAD_TEST_PASS) {
            break;
        }
    }

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("Load words: %u\r\n", (unsigned int)(sizeof(zx32_ps_bram_load_program) / sizeof(zx32_ps_bram_load_program[0])));
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U || status != CPU_LOAD_TEST_PASS) {
        return -1;
    }

    u32 copy_verify = 0U;
    u32 copy_status = 0U;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);
    for (u32 i = 0U; i < (sizeof(zx32_xcpyw_check_program) / sizeof(zx32_xcpyw_check_program[0])); i++) {
        Xil_Out32(ZYNQ_CPU_IMEM_BASE + i * 4U, zx32_xcpyw_check_program[i]);
    }
    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 16U * 4U, 0x12345678U);
    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 17U * 4U, 0x00000000U);
    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        copy_status = Xil_In32(CPU_MAIL_STATUS);
        if (copy_status == CPU_LOAD_TEST_PASS) {
            break;
        }
    }

    if (Xil_In32(ZYNQ_CPU_IMEM_BASE + 17U * 4U) != 0x12345678U) {
        copy_verify++;
    }

    xil_printf("\r\n");
    xil_printf("PL custom xcpyw instruction\r\n");
    xil_printf("Copy status: 0x%08x\r\n", (unsigned int)copy_status);
    xil_printf("Copy verify: %u errors\r\n", (unsigned int)copy_verify);
    xil_printf("Copy rd x4: 0x%08x\r\n", (unsigned int)Xil_In32(ZYNQ_CPU_IMEM_BASE + 17U * 4U));

    return (copy_verify == 0U && copy_status == CPU_LOAD_TEST_PASS) ? 0 : -1;
}

int run_cpu_elf_load_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_xcpyw_check_elf, zx32_xcpyw_check_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_xcpyw_check_program) / sizeof(zx32_xcpyw_check_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_xcpyw_check_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 16U * 4U, 0x12345678U);
    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 17U * 4U, 0x00000000U);
    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_MAIL_STATUS);
        if (status == CPU_LOAD_TEST_PASS) {
            break;
        }
    }

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U || status != CPU_LOAD_TEST_PASS) {
        return -1;
    }

    return 0;
}

int run_cpu_ddr_access_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 probe_phys = (u32)(UINTPTR)&cpu_ddr_probe[0];
    u32 probe_cpu_addr = probe_phys - ZYNQ_CPU_DDR_PHYS_BASE + ZYNQ_CPU_DDR_CPU_BASE;
    int rc;

    for (u32 i = 0U; i < (sizeof(cpu_ddr_probe) / sizeof(cpu_ddr_probe[0])); i++) {
        cpu_ddr_probe[i] = 0U;
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_START, 0U);
    Xil_Out32(CPU_MAIL_SRC, probe_cpu_addr);
    Xil_Out32(CPU_MAIL_DST, 0U);
    Xil_Out32(CPU_MAIL_LEN, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_ddr_access_smoke_elf, zx32_ddr_access_smoke_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_ddr_access_smoke_program) / sizeof(zx32_ddr_access_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_ddr_access_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        u32 diag_test = Xil_In32(CPU_MAIL_START);
        u32 diag_expect = Xil_In32(CPU_MAIL_SRC);
        u32 diag_actual = Xil_In32(CPU_MAIL_DST);
        u32 diag_addr = Xil_In32(CPU_MAIL_LEN);
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        xil_printf("Diag test#: %u\r\n", (unsigned int)diag_test);
        xil_printf("Diag expect: 0x%08x\r\n", (unsigned int)diag_expect);
        xil_printf("Diag actual: 0x%08x\r\n", (unsigned int)diag_actual);
        xil_printf("Diag address: 0x%08x\r\n", (unsigned int)diag_addr);
        xil_printf("Probe phys: 0x%08x\r\n", (unsigned int)probe_phys);
        xil_printf("Probe CPU: 0x%08x\r\n", (unsigned int)probe_cpu_addr);
        return -1;
    }

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
    xil_printf("Probe phys: 0x%08x\r\n", (unsigned int)probe_phys);
    xil_printf("Probe CPU: 0x%08x\r\n", (unsigned int)probe_cpu_addr);
    xil_printf("Probe [0]: 0x%08x\r\n", (unsigned int)cpu_ddr_probe[0]);
    xil_printf("Probe [1]: 0x%08x\r\n", (unsigned int)cpu_ddr_probe[1]);
    xil_printf("Probe [16]: 0x%08x\r\n", (unsigned int)cpu_ddr_probe[16]);

    if (cpu_ddr_probe[0] != 0xDEADBEEFU ||
        cpu_ddr_probe[1] != 0xCAFEBABEU ||
        cpu_ddr_probe[16] != 0x13579BDFU) {
        return -1;
    }

    if (verify_errors != 0U || status != CPU_STATUS_PASS) {
        return -1;
    }

    return 0;
}

int run_cpu_entry_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_entry_smoke_elf, zx32_entry_smoke_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_entry_smoke_program) / sizeof(zx32_entry_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_entry_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_MAIL_STATUS);
        if (status == CPU_LOAD_TEST_PASS) {
            break;
        }
    }

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U || status != CPU_LOAD_TEST_PASS) {
        return -1;
    }

    return 0;
}

int run_cpu_trap_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_machine_trap_smoke_elf, zx32_machine_trap_smoke_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_machine_trap_smoke_program) / sizeof(zx32_machine_trap_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_machine_trap_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 20U * 4U, 0U);
    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 21U * 4U, 0U);
    Xil_Out32(ZYNQ_CPU_IMEM_BASE + 22U * 4U, 0U);

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + 20U * 4U) == 0x0000000CU &&
            Xil_In32(ZYNQ_CPU_IMEM_BASE + 21U * 4U) == 0x00000099U &&
            Xil_In32(ZYNQ_CPU_IMEM_BASE + 22U * 4U) == 0x0000000BU) {
            status = CPU_LOAD_TEST_PASS;
            break;
        }
    }

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Mepc save: 0x%08x\r\n", (unsigned int)Xil_In32(ZYNQ_CPU_IMEM_BASE + 20U * 4U));
    xil_printf("Mcause save: 0x%08x\r\n", (unsigned int)Xil_In32(ZYNQ_CPU_IMEM_BASE + 22U * 4U));
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U || status != CPU_LOAD_TEST_PASS) {
        return -1;
    }

    return 0;
}

int run_cpu_ddr_exec_smoke_test(void)
{
    u32 status = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 exec_phys = (u32)(UINTPTR)&cpu_ddr_exec[0];
    u32 exec_cpu_addr = exec_phys - ZYNQ_CPU_DDR_PHYS_BASE + ZYNQ_CPU_DDR_CPU_BASE;
    u32 observed_pc;
    u32 marker;
    u32 loop_count;
    u32 program_words = sizeof(zx32_ddr_exec_smoke_program) / sizeof(zx32_ddr_exec_smoke_program[0]);

    if (program_words > CPU_DDR_EXEC_WORDS) {
        xil_printf("DDR exec program too large: %u words\r\n", (unsigned int)program_words);
        return -1;
    }

    for (u32 i = 0U; i < CPU_DDR_EXEC_WORDS; i++) {
        cpu_ddr_exec[i] = 0U;
    }
    for (u32 i = 0U; i < program_words; i++) {
        cpu_ddr_exec[i] = zx32_ddr_exec_smoke_program[i];
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_DDR_EXEC_PC, 0U);
    Xil_Out32(CPU_DDR_EXEC_MARKER, 0U);
    Xil_Out32(CPU_DDR_EXEC_COUNT, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, exec_cpu_addr);
    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        xil_printf("Exec phys: 0x%08x\r\n", (unsigned int)exec_phys);
        xil_printf("Exec CPU: 0x%08x\r\n", (unsigned int)exec_cpu_addr);
        return -1;
    }

    observed_pc = Xil_In32(CPU_DDR_EXEC_PC);
    marker = Xil_In32(CPU_DDR_EXEC_MARKER);
    loop_count = Xil_In32(CPU_DDR_EXEC_COUNT);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("Exec words: %u\r\n", (unsigned int)program_words);
    xil_printf("Exec phys: 0x%08x\r\n", (unsigned int)exec_phys);
    xil_printf("Exec CPU: 0x%08x\r\n", (unsigned int)exec_cpu_addr);
    xil_printf("Observed PC: 0x%08x\r\n", (unsigned int)observed_pc);
    xil_printf("Marker: 0x%08x\r\n", (unsigned int)marker);
    xil_printf("Loop count: %u\r\n", (unsigned int)loop_count);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (observed_pc != exec_cpu_addr ||
        marker != 0xA5A55A5AU ||
        loop_count != 16U ||
        status != CPU_STATUS_PASS) {
        return -1;
    }

    return 0;
}

int run_cpu_ddr_high_access_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 ps_probe0;
    u32 ps_probe1;
    u32 ps_probe16;
    int rc;

    for (u32 i = 0U; i < 32U; i++) {
        Xil_Out32(ZYNQ_CPU_DDR_HIGH_DATA_PS_ADDR + i * 4U, 0U);
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_START, 0U);
    Xil_Out32(CPU_MAIL_SRC, ZYNQ_CPU_DDR_HIGH_DATA_CPU_ADDR);
    Xil_Out32(CPU_MAIL_DST, 0U);
    Xil_Out32(CPU_MAIL_LEN, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_ddr_access_smoke_elf, zx32_ddr_access_smoke_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("High DDR access ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_ddr_access_smoke_program) / sizeof(zx32_ddr_access_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_ddr_access_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        u32 diag_test = Xil_In32(CPU_MAIL_START);
        u32 diag_expect = Xil_In32(CPU_MAIL_SRC);
        u32 diag_actual = Xil_In32(CPU_MAIL_DST);
        u32 diag_addr = Xil_In32(CPU_MAIL_LEN);
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        xil_printf("Diag test#: %u\r\n", (unsigned int)diag_test);
        xil_printf("Diag expect: 0x%08x\r\n", (unsigned int)diag_expect);
        xil_printf("Diag actual: 0x%08x\r\n", (unsigned int)diag_actual);
        xil_printf("Diag address: 0x%08x\r\n", (unsigned int)diag_addr);
        xil_printf("Probe PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_DATA_PS_ADDR);
        xil_printf("Probe CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_DATA_CPU_ADDR);
        return -1;
    }

    ps_probe0 = Xil_In32(ZYNQ_CPU_DDR_HIGH_DATA_PS_ADDR);
    ps_probe1 = Xil_In32(ZYNQ_CPU_DDR_HIGH_DATA_PS_ADDR + 4U);
    ps_probe16 = Xil_In32(ZYNQ_CPU_DDR_HIGH_DATA_PS_ADDR + 16U * 4U);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Probe PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_DATA_PS_ADDR);
    xil_printf("Probe CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_DATA_CPU_ADDR);
    xil_printf("Probe [0]: 0x%08x\r\n", (unsigned int)ps_probe0);
    xil_printf("Probe [1]: 0x%08x\r\n", (unsigned int)ps_probe1);
    xil_printf("Probe [16]: 0x%08x\r\n", (unsigned int)ps_probe16);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        ps_probe0 != 0xDEADBEEFU ||
        ps_probe1 != 0xCAFEBABEU ||
        ps_probe16 != 0x13579BDFU) {
        return -1;
    }

    return 0;
}

int run_cpu_ddr_high_exec_smoke_test(void)
{
    u32 status = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 observed_pc;
    u32 marker;
    u32 loop_count;
    u32 ps_first;
    u32 ps_last;
    u32 program_words = sizeof(zx32_ddr_exec_smoke_program) / sizeof(zx32_ddr_exec_smoke_program[0]);

    for (u32 i = 0U; i < program_words; i++) {
        Xil_Out32(ZYNQ_CPU_DDR_HIGH_EXEC_PS_ADDR + i * 4U, zx32_ddr_exec_smoke_program[i]);
    }
    for (u32 i = program_words; i < CPU_DDR_EXEC_WORDS; i++) {
        Xil_Out32(ZYNQ_CPU_DDR_HIGH_EXEC_PS_ADDR + i * 4U, 0U);
    }

    ps_first = Xil_In32(ZYNQ_CPU_DDR_HIGH_EXEC_PS_ADDR);
    ps_last = Xil_In32(ZYNQ_CPU_DDR_HIGH_EXEC_PS_ADDR + (program_words - 1U) * 4U);

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_DDR_EXEC_PC, 0U);
    Xil_Out32(CPU_DDR_EXEC_MARKER, 0U);
    Xil_Out32(CPU_DDR_EXEC_COUNT, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, ZYNQ_CPU_DDR_HIGH_EXEC_CPU_ADDR);
    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        xil_printf("Exec PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_EXEC_PS_ADDR);
        xil_printf("Exec CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_EXEC_CPU_ADDR);
        xil_printf("PS first: 0x%08x\r\n", (unsigned int)ps_first);
        xil_printf("PS last: 0x%08x\r\n", (unsigned int)ps_last);
        return -1;
    }

    observed_pc = Xil_In32(CPU_DDR_EXEC_PC);
    marker = Xil_In32(CPU_DDR_EXEC_MARKER);
    loop_count = Xil_In32(CPU_DDR_EXEC_COUNT);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("Exec words: %u\r\n", (unsigned int)program_words);
    xil_printf("Exec PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_EXEC_PS_ADDR);
    xil_printf("Exec CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_EXEC_CPU_ADDR);
    xil_printf("PS first: 0x%08x\r\n", (unsigned int)ps_first);
    xil_printf("PS last: 0x%08x\r\n", (unsigned int)ps_last);
    xil_printf("Observed PC: 0x%08x\r\n", (unsigned int)observed_pc);
    xil_printf("Marker: 0x%08x\r\n", (unsigned int)marker);
    xil_printf("Loop count: %u\r\n", (unsigned int)loop_count);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (observed_pc != ZYNQ_CPU_DDR_HIGH_EXEC_CPU_ADDR ||
        marker != 0xA5A55A5AU ||
        loop_count != 16U ||
        status != CPU_STATUS_PASS) {
        return -1;
    }

    return 0;
}

int run_cpu_ddr_high_amo_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 ps_final;
    u32 diag_step;
    u32 diag_old;
    u32 diag_final;
    u32 diag_addr;
    int rc;

    Xil_Out32(ZYNQ_CPU_DDR_HIGH_AMO_PS_ADDR, 0xFFFFFFFFU);

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_MAIL_START, 0U);
    Xil_Out32(CPU_MAIL_SRC, ZYNQ_CPU_DDR_HIGH_AMO_CPU_ADDR);
    Xil_Out32(CPU_MAIL_DST, 0U);
    Xil_Out32(CPU_MAIL_LEN, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_ddr_high_amo_smoke_elf,
                                 zx32_ddr_high_amo_smoke_elf_size,
                                 &loaded_words,
                                 &entry);
    if (rc != 0) {
        xil_printf("High DDR AMO ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_ddr_high_amo_smoke_program) / sizeof(zx32_ddr_high_amo_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_ddr_high_amo_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        diag_step = Xil_In32(CPU_MAIL_START);
        diag_old = Xil_In32(CPU_MAIL_SRC);
        diag_final = Xil_In32(CPU_MAIL_DST);
        diag_addr = Xil_In32(CPU_MAIL_LEN);
        ps_final = Xil_In32(ZYNQ_CPU_DDR_HIGH_AMO_PS_ADDR);
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        xil_printf("Diag step: %u\r\n", (unsigned int)diag_step);
        xil_printf("Diag old: 0x%08x\r\n", (unsigned int)diag_old);
        xil_printf("Diag final: 0x%08x\r\n", (unsigned int)diag_final);
        xil_printf("Diag addr: 0x%08x\r\n", (unsigned int)diag_addr);
        xil_printf("Probe PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_AMO_PS_ADDR);
        xil_printf("Probe CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_AMO_CPU_ADDR);
        xil_printf("PS final: 0x%08x\r\n", (unsigned int)ps_final);
        return -1;
    }

    diag_step = Xil_In32(CPU_MAIL_START);
    diag_old = Xil_In32(CPU_MAIL_SRC);
    diag_final = Xil_In32(CPU_MAIL_DST);
    diag_addr = Xil_In32(CPU_MAIL_LEN);
    ps_final = Xil_In32(ZYNQ_CPU_DDR_HIGH_AMO_PS_ADDR);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Probe PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_AMO_PS_ADDR);
    xil_printf("Probe CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_DDR_HIGH_AMO_CPU_ADDR);
    xil_printf("AMO old: 0x%08x\r\n", (unsigned int)diag_old);
    xil_printf("AMO final: 0x%08x\r\n", (unsigned int)diag_final);
    xil_printf("AMO addr: 0x%08x\r\n", (unsigned int)diag_addr);
    xil_printf("PS final: 0x%08x\r\n", (unsigned int)ps_final);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        diag_step != 0U ||
        diag_old != 1U ||
        diag_final != 3U ||
        diag_addr != ZYNQ_CPU_DDR_HIGH_AMO_CPU_ADDR ||
        ps_final != 3U) {
        return -1;
    }

    return 0;
}

int run_cpu_supervisor_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 sepc;
    u32 scause;
    u32 marker;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_SUP_SEPC, 0U);
    Xil_Out32(CPU_SUP_SCAUSE, 0U);
    Xil_Out32(CPU_SUP_MARKER, 0U);
    Xil_Out32(CPU_SUP_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_supervisor_smoke_elf, zx32_supervisor_smoke_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_supervisor_smoke_program) / sizeof(zx32_supervisor_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_supervisor_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_SUP_STATUS);
        if (status == CPU_STATUS_PASS || status == CPU_STATUS_FAIL) {
            break;
        }
    }

    sepc = Xil_In32(CPU_SUP_SEPC);
    scause = Xil_In32(CPU_SUP_SCAUSE);
    marker = Xil_In32(CPU_SUP_MARKER);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Sepc save: 0x%08x\r\n", (unsigned int)sepc);
    xil_printf("Scause save: 0x%08x\r\n", (unsigned int)scause);
    xil_printf("Trap marker: 0x%08x\r\n", (unsigned int)marker);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        scause != 0x00000009U ||
        marker != CPU_SUP_TRAP_MARKER) {
        return -1;
    }

    return 0;
}

int run_cpu_supervisor_timer_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 sepc;
    u32 scause;
    u32 marker;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_SUP_SEPC, 0U);
    Xil_Out32(CPU_SUP_SCAUSE, 0U);
    Xil_Out32(CPU_SUP_MARKER, 0U);
    Xil_Out32(CPU_SUP_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_supervisor_timer_smoke_elf,
                                 zx32_supervisor_timer_smoke_elf_size,
                                 &loaded_words,
                                 &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_supervisor_timer_smoke_program) / sizeof(zx32_supervisor_timer_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_supervisor_timer_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_SUP_STATUS);
        if (status == CPU_STATUS_PASS || status == CPU_STATUS_FAIL) {
            break;
        }
    }

    sepc = Xil_In32(CPU_SUP_SEPC);
    scause = Xil_In32(CPU_SUP_SCAUSE);
    marker = Xil_In32(CPU_SUP_MARKER);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Sepc save: 0x%08x\r\n", (unsigned int)sepc);
    xil_printf("Scause save: 0x%08x\r\n", (unsigned int)scause);
    xil_printf("Trap marker: 0x%08x\r\n", (unsigned int)marker);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        scause != 0x80000005U ||
        marker != CPU_SUP_TRAP_MARKER) {
        return -1;
    }

    return 0;
}

int run_cpu_boot_payload_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 hartid;
    u32 dtb;
    u32 cycle;
    u32 time;
    u32 instret;
    u32 sepc;
    u32 scause;
    u32 marker;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_BOOT_HARTID, 0xffffffffU);
    Xil_Out32(CPU_BOOT_DTB, 0U);
    Xil_Out32(CPU_BOOT_CYCLE, 0U);
    Xil_Out32(CPU_BOOT_TIME, 0U);
    Xil_Out32(CPU_BOOT_INSTRET, 0U);
    Xil_Out32(CPU_SUP_SEPC, 0U);
    Xil_Out32(CPU_SUP_SCAUSE, 0U);
    Xil_Out32(CPU_SUP_MARKER, 0U);
    Xil_Out32(CPU_SUP_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_boot_payload_smoke_elf,
                                 zx32_boot_payload_smoke_elf_size,
                                 &loaded_words,
                                 &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_boot_payload_smoke_program) / sizeof(zx32_boot_payload_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_boot_payload_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_SUP_STATUS);
        if (status == CPU_STATUS_PASS || status == CPU_STATUS_FAIL) {
            break;
        }
    }

    hartid = Xil_In32(CPU_BOOT_HARTID);
    dtb = Xil_In32(CPU_BOOT_DTB);
    cycle = Xil_In32(CPU_BOOT_CYCLE);
    time = Xil_In32(CPU_BOOT_TIME);
    instret = Xil_In32(CPU_BOOT_INSTRET);
    sepc = Xil_In32(CPU_SUP_SEPC);
    scause = Xil_In32(CPU_SUP_SCAUSE);
    marker = Xil_In32(CPU_SUP_MARKER);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Boot hartid: 0x%08x\r\n", (unsigned int)hartid);
    xil_printf("Boot dtb: 0x%08x\r\n", (unsigned int)dtb);
    xil_printf("S cycle: 0x%08x\r\n", (unsigned int)cycle);
    xil_printf("S time: 0x%08x\r\n", (unsigned int)time);
    xil_printf("S instret: 0x%08x\r\n", (unsigned int)instret);
    xil_printf("Sepc save: 0x%08x\r\n", (unsigned int)sepc);
    xil_printf("Scause save: 0x%08x\r\n", (unsigned int)scause);
    xil_printf("Trap marker: 0x%08x\r\n", (unsigned int)marker);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        hartid != 0U ||
        dtb != CPU_BOOT_DTB_VALUE ||
        scause != 0x00000002U ||
        marker != CPU_SUP_TRAP_MARKER) {
        return -1;
    }

    return 0;
}

int run_cpu_supervisor_counter_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 cycle;
    u32 time;
    u32 instret;
    int rc;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_BOOT_CYCLE, 0U);
    Xil_Out32(CPU_BOOT_TIME, 0U);
    Xil_Out32(CPU_BOOT_INSTRET, 0U);
    Xil_Out32(CPU_SUP_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_supervisor_counter_smoke_elf,
                                 zx32_supervisor_counter_smoke_elf_size,
                                 &loaded_words,
                                 &entry);
    if (rc != 0) {
        xil_printf("ELF load rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_supervisor_counter_smoke_program) / sizeof(zx32_supervisor_counter_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_supervisor_counter_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(CPU_SUP_STATUS);
        if (status == CPU_STATUS_PASS || status == CPU_STATUS_FAIL) {
            break;
        }
    }

    cycle = Xil_In32(CPU_BOOT_CYCLE);
    time = Xil_In32(CPU_BOOT_TIME);
    instret = Xil_In32(CPU_BOOT_INSTRET);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("S cycle: 0x%08x\r\n", (unsigned int)cycle);
    xil_printf("S time: 0x%08x\r\n", (unsigned int)time);
    xil_printf("S instret: 0x%08x\r\n", (unsigned int)instret);
    xil_printf("Load status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        cycle == 0U ||
        time == 0U ||
        instret == 0U) {
        return -1;
    }

    return 0;
}
