#include "ps_uart_probe.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "zx32_programs.h"

int run_cpu_sbi_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 firmware_words = 0U;
    u32 firmware_entry = 0U;
    u32 payload_words = sizeof(zx32_sbi_payload_smoke_program) / sizeof(zx32_sbi_payload_smoke_program[0]);
    u32 payload_phys = (u32)(UINTPTR)&cpu_sbi_payload[0];
    u32 payload_cpu_addr = payload_phys - ZYNQ_CPU_DDR_PHYS_BASE + ZYNQ_CPU_DDR_CPU_BASE;
    u32 dtb_cpu_addr = payload_cpu_addr + 0x1000U;
    u32 mcause;
    u32 mepc;
    u32 eid;
    u32 arg0;
    u32 marker;
    u32 hartid;
    u32 payload_dtb;
    u32 retval;
    int rc;

    if (payload_words > CPU_SBI_PAYLOAD_WORDS) {
        xil_printf("SBI payload too large: %u words\r\n", (unsigned int)payload_words);
        return -1;
    }

    for (u32 i = 0U; i < CPU_SBI_PAYLOAD_WORDS; i++) {
        cpu_sbi_payload[i] = 0U;
    }
    for (u32 i = 0U; i < payload_words; i++) {
        cpu_sbi_payload[i] = zx32_sbi_payload_smoke_program[i];
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_SBI_PAYLOAD_ENTRY, payload_cpu_addr);
    Xil_Out32(CPU_SBI_DTB_ADDR, dtb_cpu_addr);
    Xil_Out32(CPU_SBI_MCAUSE, 0U);
    Xil_Out32(CPU_SBI_MEPC, 0U);
    Xil_Out32(CPU_SBI_EID, 0U);
    Xil_Out32(CPU_SBI_ARG0, 0U);
    Xil_Out32(CPU_SBI_MARKER, 0U);
    Xil_Out32(CPU_SBI_HARTID, 0xffffffffU);
    Xil_Out32(CPU_SBI_PAYLOAD_DTB, 0U);
    Xil_Out32(CPU_SBI_RETVAL, 0xffffffffU);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_sbi_firmware_smoke_elf,
                                 zx32_sbi_firmware_smoke_elf_size,
                                 &firmware_words,
                                 &firmware_entry);
    if (rc != 0) {
        xil_printf("SBI fw ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, firmware_entry);

    for (u32 i = 0U; i < (sizeof(zx32_sbi_firmware_smoke_program) / sizeof(zx32_sbi_firmware_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_sbi_firmware_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        xil_printf("Payload phys: 0x%08x\r\n", (unsigned int)payload_phys);
        xil_printf("Payload CPU: 0x%08x\r\n", (unsigned int)payload_cpu_addr);
        return -1;
    }

    mcause = Xil_In32(CPU_SBI_MCAUSE);
    mepc = Xil_In32(CPU_SBI_MEPC);
    eid = Xil_In32(CPU_SBI_EID);
    arg0 = Xil_In32(CPU_SBI_ARG0);
    marker = Xil_In32(CPU_SBI_MARKER);
    hartid = Xil_In32(CPU_SBI_HARTID);
    payload_dtb = Xil_In32(CPU_SBI_PAYLOAD_DTB);
    retval = Xil_In32(CPU_SBI_RETVAL);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("FW words: %u\r\n", (unsigned int)firmware_words);
    xil_printf("FW entry: 0x%08x\r\n", (unsigned int)firmware_entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Payload words:%u\r\n", (unsigned int)payload_words);
    xil_printf("Payload phys: 0x%08x\r\n", (unsigned int)payload_phys);
    xil_printf("Payload CPU: 0x%08x\r\n", (unsigned int)payload_cpu_addr);
    xil_printf("DTB CPU: 0x%08x\r\n", (unsigned int)dtb_cpu_addr);
    xil_printf("M cause: 0x%08x\r\n", (unsigned int)mcause);
    xil_printf("M epc: 0x%08x\r\n", (unsigned int)mepc);
    xil_printf("SBI eid: 0x%08x\r\n", (unsigned int)eid);
    xil_printf("SBI arg0: 0x%08x\r\n", (unsigned int)arg0);
    xil_printf("SBI marker: 0x%08x\r\n", (unsigned int)marker);
    xil_printf("S hartid: 0x%08x\r\n", (unsigned int)hartid);
    xil_printf("S dtb: 0x%08x\r\n", (unsigned int)payload_dtb);
    xil_printf("SBI retval: 0x%08x\r\n", (unsigned int)retval);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        mcause != 9U ||
        mepc != payload_cpu_addr + 24U ||
        eid != 1U ||
        arg0 != 0x12345678U ||
        marker != 0x53424921U ||
        hartid != 0U ||
        payload_dtb != dtb_cpu_addr ||
        retval != 0U) {
        return -1;
    }

    return 0;
}

int run_cpu_sbi_timer_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 firmware_words = 0U;
    u32 firmware_entry = 0U;
    u32 payload_words = sizeof(zx32_sbi_timer_payload_smoke_program) / sizeof(zx32_sbi_timer_payload_smoke_program[0]);
    u32 payload_phys = (u32)(UINTPTR)&cpu_sbi_payload[0];
    u32 payload_cpu_addr = payload_phys - ZYNQ_CPU_DDR_PHYS_BASE + ZYNQ_CPU_DDR_CPU_BASE;
    u32 dtb_cpu_addr = payload_cpu_addr + 0x1000U;
    u32 mcause;
    u32 mepc;
    u32 eid;
    u32 fid;
    u32 arg0;
    u32 cmp_lo;
    u32 cmp_hi;
    u32 hartid;
    u32 payload_dtb;
    u32 retval;
    u32 scause;
    u32 sepc;
    u32 sie;
    u32 sip;
    u32 sstatus;
    u32 time0;
    u32 time1;
    int rc;

    if (payload_words > CPU_SBI_PAYLOAD_WORDS) {
        xil_printf("SBI timer payload too large: %u words\r\n", (unsigned int)payload_words);
        return -1;
    }

    for (u32 i = 0U; i < CPU_SBI_PAYLOAD_WORDS; i++) {
        cpu_sbi_payload[i] = 0U;
    }
    for (u32 i = 0U; i < payload_words; i++) {
        cpu_sbi_payload[i] = zx32_sbi_timer_payload_smoke_program[i];
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    Xil_Out32(CPU_SBI_TIMER_ENTRY, payload_cpu_addr);
    Xil_Out32(CPU_SBI_TIMER_DTB, dtb_cpu_addr);
    Xil_Out32(CPU_SBI_TIMER_MCAUSE, 0U);
    Xil_Out32(CPU_SBI_TIMER_MEPC, 0U);
    Xil_Out32(CPU_SBI_TIMER_EID, 0U);
    Xil_Out32(CPU_SBI_TIMER_FID, 0xffffffffU);
    Xil_Out32(CPU_SBI_TIMER_ARG0, 0U);
    Xil_Out32(CPU_SBI_TIMER_CMP_LO, 0U);
    Xil_Out32(CPU_SBI_TIMER_CMP_HI, 0U);
    Xil_Out32(CPU_SBI_TIMER_HARTID, 0xffffffffU);
    Xil_Out32(CPU_SBI_TIMER_PAY_DTB, 0U);
    Xil_Out32(CPU_SBI_TIMER_RETVAL, 0xffffffffU);
    Xil_Out32(CPU_SBI_TIMER_SCAUSE, 0U);
    Xil_Out32(CPU_SBI_TIMER_SEPC, 0U);
    Xil_Out32(CPU_SBI_TIMER_SIE, 0U);
    Xil_Out32(CPU_SBI_TIMER_SIP, 0U);
    Xil_Out32(CPU_SBI_TIMER_SSTATUS, 0U);
    Xil_Out32(CPU_SBI_TIMER_TIME0, 0U);
    Xil_Out32(CPU_SBI_TIMER_TIME1, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_sbi_timer_firmware_smoke_elf,
                                 zx32_sbi_timer_firmware_smoke_elf_size,
                                 &firmware_words,
                                 &firmware_entry);
    if (rc != 0) {
        xil_printf("SBI timer fw ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, firmware_entry);

    for (u32 i = 0U; i < (sizeof(zx32_sbi_timer_firmware_smoke_program) / sizeof(zx32_sbi_timer_firmware_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_sbi_timer_firmware_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        status = Xil_In32(CPU_MAIL_STATUS);
    }

    mcause = Xil_In32(CPU_SBI_TIMER_MCAUSE);
    mepc = Xil_In32(CPU_SBI_TIMER_MEPC);
    eid = Xil_In32(CPU_SBI_TIMER_EID);
    fid = Xil_In32(CPU_SBI_TIMER_FID);
    arg0 = Xil_In32(CPU_SBI_TIMER_ARG0);
    cmp_lo = Xil_In32(CPU_SBI_TIMER_CMP_LO);
    cmp_hi = Xil_In32(CPU_SBI_TIMER_CMP_HI);
    hartid = Xil_In32(CPU_SBI_TIMER_HARTID);
    payload_dtb = Xil_In32(CPU_SBI_TIMER_PAY_DTB);
    retval = Xil_In32(CPU_SBI_TIMER_RETVAL);
    scause = Xil_In32(CPU_SBI_TIMER_SCAUSE);
    sepc = Xil_In32(CPU_SBI_TIMER_SEPC);
    sie = Xil_In32(CPU_SBI_TIMER_SIE);
    sip = Xil_In32(CPU_SBI_TIMER_SIP);
    sstatus = Xil_In32(CPU_SBI_TIMER_SSTATUS);
    time0 = Xil_In32(CPU_SBI_TIMER_TIME0);
    time1 = Xil_In32(CPU_SBI_TIMER_TIME1);

    xil_printf("FW words: %u\r\n", (unsigned int)firmware_words);
    xil_printf("FW entry: 0x%08x\r\n", (unsigned int)firmware_entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Payload words: %u\r\n", (unsigned int)payload_words);
    xil_printf("Payload CPU: 0x%08x\r\n", (unsigned int)payload_cpu_addr);
    xil_printf("M cause: 0x%08x\r\n", (unsigned int)mcause);
    xil_printf("M epc: 0x%08x\r\n", (unsigned int)mepc);
    xil_printf("SBI eid: 0x%08x\r\n", (unsigned int)eid);
    xil_printf("SBI fid: 0x%08x\r\n", (unsigned int)fid);
    xil_printf("SBI arg0: 0x%08x\r\n", (unsigned int)arg0);
    xil_printf("Timer cmp lo: 0x%08x\r\n", (unsigned int)cmp_lo);
    xil_printf("Timer cmp hi: 0x%08x\r\n", (unsigned int)cmp_hi);
    xil_printf("S hartid: 0x%08x\r\n", (unsigned int)hartid);
    xil_printf("S dtb: 0x%08x\r\n", (unsigned int)payload_dtb);
    xil_printf("SBI retval: 0x%08x\r\n", (unsigned int)retval);
    xil_printf("S scause: 0x%08x\r\n", (unsigned int)scause);
    xil_printf("S sepc: 0x%08x\r\n", (unsigned int)sepc);
    xil_printf("S sie: 0x%08x\r\n", (unsigned int)sie);
    xil_printf("S sip: 0x%08x\r\n", (unsigned int)sip);
    xil_printf("S status: 0x%08x\r\n", (unsigned int)sstatus);
    xil_printf("S time0: 0x%08x\r\n", (unsigned int)time0);
    xil_printf("S time1: 0x%08x\r\n", (unsigned int)time1);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        mcause != 9U ||
        eid != 0x54494D45U ||
        fid != 0U ||
        hartid != 0U ||
        payload_dtb != dtb_cpu_addr ||
        retval != 0U ||
        scause != 0x80000005U) {
        return -1;
    }

    return 0;
}

int run_cpu_linux_contract_smoke_test(void)
{
    const u32 dtb_word_offset = 512U;
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 firmware_words = 0U;
    u32 firmware_entry = 0U;
    u32 payload_words = sizeof(zx32_linux_contract_payload_smoke_program) / sizeof(zx32_linux_contract_payload_smoke_program[0]);
    u32 payload_phys = (u32)(UINTPTR)&cpu_linux_contract[0];
    u32 payload_cpu_addr = payload_phys - ZYNQ_CPU_DDR_PHYS_BASE + ZYNQ_CPU_DDR_CPU_BASE;
    u32 dtb_cpu_addr = payload_cpu_addr + dtb_word_offset * 4U;
    u32 mcause;
    u32 mepc;
    u32 eid;
    u32 fid;
    u32 arg0;
    u32 retval;
    u32 cmp_lo;
    u32 cmp_hi;
    u32 hartid;
    u32 payload_dtb;
    u32 dtb_magic;
    u32 base_version;
    u32 scause;
    u32 sepc;
    u32 time0;
    u32 time1;
    u32 dtb_total;
    u32 dtb_struct;
    u32 dtb_strings;
    u32 fdt_root;
    u32 addr_cells;
    u32 size_cells;
    u32 fdt_memory;
    u32 reg_addr;
    u32 reg_size;
    int rc;

    if (payload_words >= dtb_word_offset) {
        xil_printf("Linux contract payload too large: %u words\r\n", (unsigned int)payload_words);
        return -1;
    }

    for (u32 i = 0U; i < CPU_LINUX_CONTRACT_WORDS; i++) {
        cpu_linux_contract[i] = 0U;
    }
    for (u32 i = 0U; i < payload_words; i++) {
        cpu_linux_contract[i] = zx32_linux_contract_payload_smoke_program[i];
    }
    cpu_linux_contract[dtb_word_offset + 0U] = 0xEDFE0DD0U;
    cpu_linux_contract[dtb_word_offset + 1U] = 0x00010000U;
    cpu_linux_contract[dtb_word_offset + 2U] = 0x38000000U;
    cpu_linux_contract[dtb_word_offset + 3U] = 0xA0000000U;
    cpu_linux_contract[dtb_word_offset + 4U] = 0x28000000U;
    cpu_linux_contract[dtb_word_offset + 5U] = 0x11000000U;
    cpu_linux_contract[dtb_word_offset + 6U] = 0x10000000U;
    cpu_linux_contract[dtb_word_offset + 7U] = 0x00000000U;
    cpu_linux_contract[dtb_word_offset + 8U] = 0x40000000U;
    cpu_linux_contract[dtb_word_offset + 9U] = 0x5C000000U;
    cpu_linux_contract[dtb_word_offset + 14U] = 0x01000000U;
    cpu_linux_contract[dtb_word_offset + 15U] = 0x00000000U;
    cpu_linux_contract[dtb_word_offset + 16U] = 0x03000000U;
    cpu_linux_contract[dtb_word_offset + 17U] = 0x04000000U;
    cpu_linux_contract[dtb_word_offset + 18U] = 0x00000000U;
    cpu_linux_contract[dtb_word_offset + 19U] = 0x01000000U;
    cpu_linux_contract[dtb_word_offset + 20U] = 0x03000000U;
    cpu_linux_contract[dtb_word_offset + 21U] = 0x04000000U;
    cpu_linux_contract[dtb_word_offset + 22U] = 0x0F000000U;
    cpu_linux_contract[dtb_word_offset + 23U] = 0x01000000U;
    cpu_linux_contract[dtb_word_offset + 24U] = 0x01000000U;
    cpu_linux_contract[dtb_word_offset + 25U] = 0x6F6D656DU;
    cpu_linux_contract[dtb_word_offset + 26U] = 0x38407972U;
    cpu_linux_contract[dtb_word_offset + 27U] = 0x30303030U;
    cpu_linux_contract[dtb_word_offset + 28U] = 0x00303030U;
    cpu_linux_contract[dtb_word_offset + 29U] = 0x03000000U;
    cpu_linux_contract[dtb_word_offset + 30U] = 0x08000000U;
    cpu_linux_contract[dtb_word_offset + 31U] = 0x1B000000U;
    cpu_linux_contract[dtb_word_offset + 32U] = 0x00000080U;
    cpu_linux_contract[dtb_word_offset + 33U] = 0x00000004U;
    cpu_linux_contract[dtb_word_offset + 34U] = 0x02000000U;
    cpu_linux_contract[dtb_word_offset + 35U] = 0x02000000U;
    cpu_linux_contract[dtb_word_offset + 36U] = 0x09000000U;
    cpu_linux_contract[dtb_word_offset + 40U] = 0x64646123U;
    cpu_linux_contract[dtb_word_offset + 41U] = 0x73736572U;
    cpu_linux_contract[dtb_word_offset + 42U] = 0x6C65632DU;
    cpu_linux_contract[dtb_word_offset + 43U] = 0x2300736CU;
    cpu_linux_contract[dtb_word_offset + 44U] = 0x657A6973U;
    cpu_linux_contract[dtb_word_offset + 45U] = 0x6C65632DU;
    cpu_linux_contract[dtb_word_offset + 46U] = 0x7200736CU;
    cpu_linux_contract[dtb_word_offset + 47U] = 0x00006765U;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    Xil_Out32(CPU_LINUX_ENTRY, payload_cpu_addr);
    Xil_Out32(CPU_LINUX_DTB, dtb_cpu_addr);
    Xil_Out32(CPU_LINUX_MCAUSE, 0U);
    Xil_Out32(CPU_LINUX_MEPC, 0U);
    Xil_Out32(CPU_LINUX_SBI_EID, 0U);
    Xil_Out32(CPU_LINUX_SBI_FID, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_ARG0, 0U);
    Xil_Out32(CPU_LINUX_SBI_RETVAL, 0xffffffffU);
    Xil_Out32(CPU_LINUX_CMP_LO, 0U);
    Xil_Out32(CPU_LINUX_CMP_HI, 0U);
    Xil_Out32(CPU_LINUX_HARTID, 0xffffffffU);
    Xil_Out32(CPU_LINUX_PAYLOAD_DTB, 0U);
    Xil_Out32(CPU_LINUX_DTB_MAGIC, 0U);
    Xil_Out32(CPU_LINUX_BASE_VERSION, 0U);
    Xil_Out32(CPU_LINUX_SCAUSE, 0U);
    Xil_Out32(CPU_LINUX_SEPC, 0U);
    Xil_Out32(CPU_LINUX_TIME0, 0U);
    Xil_Out32(CPU_LINUX_TIME1, 0U);
    Xil_Out32(CPU_LINUX_DTB_TOTAL, 0U);
    Xil_Out32(CPU_LINUX_DTB_STRUCT, 0U);
    Xil_Out32(CPU_LINUX_DTB_STRINGS, 0U);
    Xil_Out32(CPU_LINUX_FDT_ROOT, 0U);
    Xil_Out32(CPU_LINUX_ADDR_CELLS, 0U);
    Xil_Out32(CPU_LINUX_SIZE_CELLS, 0U);
    Xil_Out32(CPU_LINUX_FDT_MEMORY, 0U);
    Xil_Out32(CPU_LINUX_REG_ADDR, 0U);
    Xil_Out32(CPU_LINUX_REG_SIZE, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_linux_contract_firmware_smoke_elf,
                                 zx32_linux_contract_firmware_smoke_elf_size,
                                 &firmware_words,
                                 &firmware_entry);
    if (rc != 0) {
        xil_printf("Linux contract fw ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, firmware_entry);

    for (u32 i = 0U; i < (sizeof(zx32_linux_contract_firmware_smoke_program) / sizeof(zx32_linux_contract_firmware_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_linux_contract_firmware_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        status = Xil_In32(CPU_MAIL_STATUS);
    }

    mcause = Xil_In32(CPU_LINUX_MCAUSE);
    mepc = Xil_In32(CPU_LINUX_MEPC);
    eid = Xil_In32(CPU_LINUX_SBI_EID);
    fid = Xil_In32(CPU_LINUX_SBI_FID);
    arg0 = Xil_In32(CPU_LINUX_SBI_ARG0);
    retval = Xil_In32(CPU_LINUX_SBI_RETVAL);
    cmp_lo = Xil_In32(CPU_LINUX_CMP_LO);
    cmp_hi = Xil_In32(CPU_LINUX_CMP_HI);
    hartid = Xil_In32(CPU_LINUX_HARTID);
    payload_dtb = Xil_In32(CPU_LINUX_PAYLOAD_DTB);
    dtb_magic = Xil_In32(CPU_LINUX_DTB_MAGIC);
    base_version = Xil_In32(CPU_LINUX_BASE_VERSION);
    scause = Xil_In32(CPU_LINUX_SCAUSE);
    sepc = Xil_In32(CPU_LINUX_SEPC);
    time0 = Xil_In32(CPU_LINUX_TIME0);
    time1 = Xil_In32(CPU_LINUX_TIME1);
    dtb_total = Xil_In32(CPU_LINUX_DTB_TOTAL);
    dtb_struct = Xil_In32(CPU_LINUX_DTB_STRUCT);
    dtb_strings = Xil_In32(CPU_LINUX_DTB_STRINGS);
    fdt_root = Xil_In32(CPU_LINUX_FDT_ROOT);
    addr_cells = Xil_In32(CPU_LINUX_ADDR_CELLS);
    size_cells = Xil_In32(CPU_LINUX_SIZE_CELLS);
    fdt_memory = Xil_In32(CPU_LINUX_FDT_MEMORY);
    reg_addr = Xil_In32(CPU_LINUX_REG_ADDR);
    reg_size = Xil_In32(CPU_LINUX_REG_SIZE);

    xil_printf("FW words: %u\r\n", (unsigned int)firmware_words);
    xil_printf("FW entry: 0x%08x\r\n", (unsigned int)firmware_entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Payload words: %u\r\n", (unsigned int)payload_words);
    xil_printf("Payload CPU: 0x%08x\r\n", (unsigned int)payload_cpu_addr);
    xil_printf("DTB CPU: 0x%08x\r\n", (unsigned int)dtb_cpu_addr);
    xil_printf("DTB magic: 0x%08x\r\n", (unsigned int)dtb_magic);
    xil_printf("DTB total: 0x%08x\r\n", (unsigned int)dtb_total);
    xil_printf("DTB struct: 0x%08x\r\n", (unsigned int)dtb_struct);
    xil_printf("DTB strings: 0x%08x\r\n", (unsigned int)dtb_strings);
    xil_printf("FDT root token: 0x%08x\r\n", (unsigned int)fdt_root);
    xil_printf("FDT #address-cells: %u\r\n", (unsigned int)addr_cells);
    xil_printf("FDT #size-cells: %u\r\n", (unsigned int)size_cells);
    xil_printf("FDT memory token: 0x%08x\r\n", (unsigned int)fdt_memory);
    xil_printf("FDT reg addr: 0x%08x\r\n", (unsigned int)reg_addr);
    xil_printf("FDT reg size: 0x%08x\r\n", (unsigned int)reg_size);
    xil_printf("S hartid: 0x%08x\r\n", (unsigned int)hartid);
    xil_printf("S dtb: 0x%08x\r\n", (unsigned int)payload_dtb);
    xil_printf("SBI base version: 0x%08x\r\n", (unsigned int)base_version);
    xil_printf("SBI eid: 0x%08x\r\n", (unsigned int)eid);
    xil_printf("SBI fid: 0x%08x\r\n", (unsigned int)fid);
    xil_printf("SBI arg0: 0x%08x\r\n", (unsigned int)arg0);
    xil_printf("SBI retval: 0x%08x\r\n", (unsigned int)retval);
    xil_printf("Timer cmp lo: 0x%08x\r\n", (unsigned int)cmp_lo);
    xil_printf("Timer cmp hi: 0x%08x\r\n", (unsigned int)cmp_hi);
    xil_printf("M cause: 0x%08x\r\n", (unsigned int)mcause);
    xil_printf("M epc: 0x%08x\r\n", (unsigned int)mepc);
    xil_printf("S scause: 0x%08x\r\n", (unsigned int)scause);
    xil_printf("S sepc: 0x%08x\r\n", (unsigned int)sepc);
    xil_printf("S time0: 0x%08x\r\n", (unsigned int)time0);
    xil_printf("S time1: 0x%08x\r\n", (unsigned int)time1);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        mcause != 9U ||
        eid != 0x54494D45U ||
        fid != 0U ||
        retval != 0U ||
        hartid != 0U ||
        payload_dtb != dtb_cpu_addr ||
        dtb_magic != 0xD00DFEEDU ||
        dtb_total != 0x100U ||
        dtb_struct != 0x38U ||
        dtb_strings != 0xA0U ||
        fdt_root != 1U ||
        addr_cells != 1U ||
        size_cells != 1U ||
        fdt_memory != 1U ||
        reg_addr != 0x80000000U ||
        reg_size != 0x04000000U ||
        base_version != 2U ||
        scause != 0x80000005U) {
        return -1;
    }

    return 0;
}

int run_cpu_linux_image_layout_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    u32 ps_code0 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR);
    u32 ps_text_lo = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 8U);
    u32 ps_text_hi = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 12U);
    u32 ps_magic0 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 48U);
    u32 ps_magic1 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 52U);
    u32 ps_magic2 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 56U);
    u32 ps_dtb_magic = Xil_In32(ZYNQ_CPU_LINUX_DTB_PS_ADDR);
    u32 ps_alias_00100000 = Xil_In32(0x00100000U);
    u32 ps_alias_00200000 = Xil_In32(0x00200000U);
    u32 ps_alias_00300000 = Xil_In32(0x00300000U);
    u32 ps_alias_00400000 = Xil_In32(0x00400000U);
    u32 ps_alias_00500000 = Xil_In32(0x00500000U);
    u32 ps_alias_00600000 = Xil_In32(0x00600000U);
    u32 ps_dtb_alias = Xil_In32(ZYNQ_CPU_LINUX_DTB_PS_ADDR);
    u32 image_code0;
    u32 image_text_lo;
    u32 image_text_hi;
    u32 image_size_lo;
    u32 image_size_hi;
    u32 image_magic0;
    u32 image_magic1;
    u32 image_magic2;
    u32 dtb_magic;
    u32 alias_80000000;
    u32 alias_80100000;
    u32 alias_80200000;
    u32 alias_80300000;
    u32 alias_80400000;
    u32 alias_80500000;
    u32 alias_dtb;
    int rc;

    xil_printf("Kernel PS:  0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_KERNEL_PS_ADDR);
    xil_printf("Kernel CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_KERNEL_CPU_ADDR);
    xil_printf("DTB PS:     0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_DTB_PS_ADDR);
    xil_printf("DTB CPU:    0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_DTB_CPU_ADDR);
    xil_printf("PS code0:   0x%08x\r\n", (unsigned int)ps_code0);
    xil_printf("PS text lo: 0x%08x\r\n", (unsigned int)ps_text_lo);
    xil_printf("PS magic0:  0x%08x\r\n", (unsigned int)ps_magic0);
    xil_printf("PS magic1:  0x%08x\r\n", (unsigned int)ps_magic1);
    xil_printf("PS magic2:  0x%08x\r\n", (unsigned int)ps_magic2);
    xil_printf("PS DTB raw: 0x%08x\r\n", (unsigned int)ps_dtb_magic);
    xil_printf("PS 0x00100000: 0x%08x\r\n", (unsigned int)ps_alias_00100000);
    xil_printf("PS 0x00200000: 0x%08x\r\n", (unsigned int)ps_alias_00200000);
    xil_printf("PS 0x00300000: 0x%08x\r\n", (unsigned int)ps_alias_00300000);
    xil_printf("PS 0x00400000: 0x%08x\r\n", (unsigned int)ps_alias_00400000);
    xil_printf("PS 0x00500000: 0x%08x\r\n", (unsigned int)ps_alias_00500000);
    xil_printf("PS 0x00600000: 0x%08x\r\n", (unsigned int)ps_alias_00600000);
    xil_printf("PS DTB alias: 0x%08x\r\n", (unsigned int)ps_dtb_alias);

    if (ps_code0 != ZYNQ_CPU_LINUX_IMAGE_CODE0 ||
        ps_text_lo != ZYNQ_CPU_LINUX_IMAGE_TEXT_LO ||
        ps_text_hi != 0U ||
        ps_magic0 != ZYNQ_CPU_LINUX_IMAGE_MAGIC0 ||
        ps_magic1 != ZYNQ_CPU_LINUX_IMAGE_MAGIC1 ||
        ps_magic2 != ZYNQ_CPU_LINUX_IMAGE_MAGIC2 ||
        ps_dtb_magic != ZYNQ_CPU_DTB_MAGIC_RAW) {
        xil_printf("Linux boot artifacts not present; run prepare_linux_boot_artifacts.sh and download_zynq_cpu_linux_boot.xsbl\r\n");
        return 1;
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    Xil_Out32(CPU_LINUX_ENTRY, ZYNQ_CPU_LINUX_KERNEL_CPU_ADDR);
    Xil_Out32(CPU_LINUX_DTB, ZYNQ_CPU_LINUX_DTB_CPU_ADDR);
    Xil_Out32(CPU_LINUX_DTB_MAGIC, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_CODE0, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_TEXT_LO, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_TEXT_HI, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_SIZE_LO, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_SIZE_HI, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_MAGIC0, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_MAGIC1, 0U);
    Xil_Out32(CPU_LINUX_IMAGE_MAGIC2, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_80000000, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_80100000, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_80200000, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_80300000, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_80400000, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_80500000, 0U);
    Xil_Out32(CPU_LINUX_ALIAS_DTB, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_linux_image_layout_smoke_elf,
                                 zx32_linux_image_layout_smoke_elf_size,
                                 &loaded_words,
                                 &entry);
    if (rc != 0) {
        xil_printf("Linux image layout ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_linux_image_layout_smoke_program) / sizeof(zx32_linux_image_layout_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_linux_image_layout_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        status = Xil_In32(CPU_MAIL_STATUS);
    }

    image_code0 = Xil_In32(CPU_LINUX_IMAGE_CODE0);
    image_text_lo = Xil_In32(CPU_LINUX_IMAGE_TEXT_LO);
    image_text_hi = Xil_In32(CPU_LINUX_IMAGE_TEXT_HI);
    image_size_lo = Xil_In32(CPU_LINUX_IMAGE_SIZE_LO);
    image_size_hi = Xil_In32(CPU_LINUX_IMAGE_SIZE_HI);
    image_magic0 = Xil_In32(CPU_LINUX_IMAGE_MAGIC0);
    image_magic1 = Xil_In32(CPU_LINUX_IMAGE_MAGIC1);
    image_magic2 = Xil_In32(CPU_LINUX_IMAGE_MAGIC2);
    dtb_magic = Xil_In32(CPU_LINUX_DTB_MAGIC);
    alias_80000000 = Xil_In32(CPU_LINUX_ALIAS_80000000);
    alias_80100000 = Xil_In32(CPU_LINUX_ALIAS_80100000);
    alias_80200000 = Xil_In32(CPU_LINUX_ALIAS_80200000);
    alias_80300000 = Xil_In32(CPU_LINUX_ALIAS_80300000);
    alias_80400000 = Xil_In32(CPU_LINUX_ALIAS_80400000);
    alias_80500000 = Xil_In32(CPU_LINUX_ALIAS_80500000);
    alias_dtb = Xil_In32(CPU_LINUX_ALIAS_DTB);

    xil_printf("ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("Entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Image code0: 0x%08x\r\n", (unsigned int)image_code0);
    xil_printf("Image text: 0x%08x%08x\r\n", (unsigned int)image_text_hi, (unsigned int)image_text_lo);
    xil_printf("Image size: 0x%08x%08x\r\n", (unsigned int)image_size_hi, (unsigned int)image_size_lo);
    xil_printf("Image magic0:0x%08x\r\n", (unsigned int)image_magic0);
    xil_printf("Image magic1:0x%08x\r\n", (unsigned int)image_magic1);
    xil_printf("Image magic2:0x%08x\r\n", (unsigned int)image_magic2);
    xil_printf("DTB raw: 0x%08x\r\n", (unsigned int)dtb_magic);
    xil_printf("CPU 0x80000000: 0x%08x\r\n", (unsigned int)alias_80000000);
    xil_printf("CPU 0x80100000: 0x%08x\r\n", (unsigned int)alias_80100000);
    xil_printf("CPU 0x80200000: 0x%08x\r\n", (unsigned int)alias_80200000);
    xil_printf("CPU 0x80300000: 0x%08x\r\n", (unsigned int)alias_80300000);
    xil_printf("CPU 0x80400000: 0x%08x\r\n", (unsigned int)alias_80400000);
    xil_printf("CPU 0x80500000: 0x%08x\r\n", (unsigned int)alias_80500000);
    xil_printf("CPU DTB addr: 0x%08x\r\n", (unsigned int)alias_dtb);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        image_code0 != ZYNQ_CPU_LINUX_IMAGE_CODE0 ||
        image_text_lo != ZYNQ_CPU_LINUX_IMAGE_TEXT_LO ||
        image_text_hi != 0U ||
        image_size_lo == 0U ||
        image_size_hi != 0U ||
        image_magic0 != ZYNQ_CPU_LINUX_IMAGE_MAGIC0 ||
        image_magic1 != ZYNQ_CPU_LINUX_IMAGE_MAGIC1 ||
        image_magic2 != ZYNQ_CPU_LINUX_IMAGE_MAGIC2 ||
        dtb_magic != ZYNQ_CPU_DTB_MAGIC_RAW) {
        return -1;
    }

    return 0;
}

int run_cpu_linux_sbi_smoke_test(void)
{
    u32 status = 0U;
    u32 verify_errors = 0U;
    u32 ctrl_status;
    u32 bram_words;
    u32 scratch_words;
    u32 firmware_words = 0U;
    u32 firmware_entry = 0U;
    u32 payload_words = sizeof(zx32_linux_sbi_payload_smoke_program) / sizeof(zx32_linux_sbi_payload_smoke_program[0]);
    u32 payload_phys = (u32)(UINTPTR)&cpu_sbi_payload[0];
    u32 payload_cpu_addr = payload_phys - ZYNQ_CPU_DDR_PHYS_BASE + ZYNQ_CPU_DDR_CPU_BASE;
    u32 dtb_cpu_addr = payload_cpu_addr + 0x1000U;
    u32 mcause;
    u32 mepc;
    u32 last_eid;
    u32 last_fid;
    u32 last_arg0;
    u32 last_err;
    u32 last_value;
    u32 hartid;
    u32 payload_dtb;
    u32 spec_err;
    u32 spec_value;
    u32 probe_err;
    u32 probe_value;
    u32 console_char;
    u32 timer_err;
    u32 timer_value;
    u32 cmp_lo;
    u32 cmp_hi;
    u32 scause;
    u32 sepc;
    u32 sie;
    u32 sip;
    u32 sstatus;
    u32 time0;
    u32 time1;
    int rc;

    if (payload_words > CPU_SBI_PAYLOAD_WORDS) {
        xil_printf("Linux SBI payload too large: %u words\r\n", (unsigned int)payload_words);
        return -1;
    }

    for (u32 i = 0U; i < CPU_SBI_PAYLOAD_WORDS; i++) {
        cpu_sbi_payload[i] = 0U;
    }
    for (u32 i = 0U; i < payload_words; i++) {
        cpu_sbi_payload[i] = zx32_linux_sbi_payload_smoke_program[i];
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    ctrl_status = Xil_In32(ZYNQ_CPU_CPU_STATUS);
    bram_words = Xil_In32(ZYNQ_CPU_BRAM_WORDS);
    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);

    Xil_Out32(CPU_LINUX_SBI_ENTRY, payload_cpu_addr);
    Xil_Out32(CPU_LINUX_SBI_DTB, dtb_cpu_addr);
    Xil_Out32(CPU_LINUX_SBI_MCAUSE, 0U);
    Xil_Out32(CPU_LINUX_SBI_MEPC, 0U);
    Xil_Out32(CPU_LINUX_SBI_LAST_EID, 0U);
    Xil_Out32(CPU_LINUX_SBI_LAST_FID, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_LAST_ARG0, 0U);
    Xil_Out32(CPU_LINUX_SBI_LAST_ERR, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_LAST_VALUE, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_HARTID, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_PAYLOAD_DTB, 0U);
    Xil_Out32(CPU_LINUX_SBI_SPEC_ERR, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_SPEC_VALUE, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_PROBE_ERR, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_PROBE_VALUE, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_CONSOLE_CHAR, 0U);
    Xil_Out32(CPU_LINUX_SBI_TIMER_ERR, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_TIMER_VALUE, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_CMP_LO, 0U);
    Xil_Out32(CPU_LINUX_SBI_CMP_HI, 0U);
    Xil_Out32(CPU_LINUX_SBI_SCAUSE, 0U);
    Xil_Out32(CPU_LINUX_SBI_SEPC, 0U);
    Xil_Out32(CPU_LINUX_SBI_SIE, 0U);
    Xil_Out32(CPU_LINUX_SBI_SIP, 0U);
    Xil_Out32(CPU_LINUX_SBI_SSTATUS, 0U);
    Xil_Out32(CPU_LINUX_SBI_TIME0, 0U);
    Xil_Out32(CPU_LINUX_SBI_TIME1, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_linux_sbi_firmware_smoke_elf,
                                 zx32_linux_sbi_firmware_smoke_elf_size,
                                 &firmware_words,
                                 &firmware_entry);
    if (rc != 0) {
        xil_printf("Linux SBI fw ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, firmware_entry);

    for (u32 i = 0U; i < (sizeof(zx32_linux_sbi_firmware_smoke_program) / sizeof(zx32_linux_sbi_firmware_smoke_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_linux_sbi_firmware_smoke_program[i]) {
            verify_errors++;
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    if (wait_for_cpu(&status) != 0) {
        status = Xil_In32(CPU_MAIL_STATUS);
    }

    mcause = Xil_In32(CPU_LINUX_SBI_MCAUSE);
    mepc = Xil_In32(CPU_LINUX_SBI_MEPC);
    last_eid = Xil_In32(CPU_LINUX_SBI_LAST_EID);
    last_fid = Xil_In32(CPU_LINUX_SBI_LAST_FID);
    last_arg0 = Xil_In32(CPU_LINUX_SBI_LAST_ARG0);
    last_err = Xil_In32(CPU_LINUX_SBI_LAST_ERR);
    last_value = Xil_In32(CPU_LINUX_SBI_LAST_VALUE);
    hartid = Xil_In32(CPU_LINUX_SBI_HARTID);
    payload_dtb = Xil_In32(CPU_LINUX_SBI_PAYLOAD_DTB);
    spec_err = Xil_In32(CPU_LINUX_SBI_SPEC_ERR);
    spec_value = Xil_In32(CPU_LINUX_SBI_SPEC_VALUE);
    probe_err = Xil_In32(CPU_LINUX_SBI_PROBE_ERR);
    probe_value = Xil_In32(CPU_LINUX_SBI_PROBE_VALUE);
    console_char = Xil_In32(CPU_LINUX_SBI_CONSOLE_CHAR);
    timer_err = Xil_In32(CPU_LINUX_SBI_TIMER_ERR);
    timer_value = Xil_In32(CPU_LINUX_SBI_TIMER_VALUE);
    cmp_lo = Xil_In32(CPU_LINUX_SBI_CMP_LO);
    cmp_hi = Xil_In32(CPU_LINUX_SBI_CMP_HI);
    scause = Xil_In32(CPU_LINUX_SBI_SCAUSE);
    sepc = Xil_In32(CPU_LINUX_SBI_SEPC);
    sie = Xil_In32(CPU_LINUX_SBI_SIE);
    sip = Xil_In32(CPU_LINUX_SBI_SIP);
    sstatus = Xil_In32(CPU_LINUX_SBI_SSTATUS);
    time0 = Xil_In32(CPU_LINUX_SBI_TIME0);
    time1 = Xil_In32(CPU_LINUX_SBI_TIME1);

    xil_printf("CPU ctrl st: 0x%08x\r\n", (unsigned int)ctrl_status);
    xil_printf("CPU BRAM: %u words\r\n", (unsigned int)bram_words);
    xil_printf("CPU scratch: %u words\r\n", (unsigned int)scratch_words);
    xil_printf("FW words: %u\r\n", (unsigned int)firmware_words);
    xil_printf("FW entry: 0x%08x\r\n", (unsigned int)firmware_entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);
    xil_printf("Payload words: %u\r\n", (unsigned int)payload_words);
    xil_printf("Payload CPU: 0x%08x\r\n", (unsigned int)payload_cpu_addr);
    xil_printf("M cause: 0x%08x\r\n", (unsigned int)mcause);
    xil_printf("M epc: 0x%08x\r\n", (unsigned int)mepc);
    xil_printf("Last SBI eid: 0x%08x\r\n", (unsigned int)last_eid);
    xil_printf("Last SBI fid: 0x%08x\r\n", (unsigned int)last_fid);
    xil_printf("Last SBI arg0: 0x%08x\r\n", (unsigned int)last_arg0);
    xil_printf("Last SBI err: 0x%08x\r\n", (unsigned int)last_err);
    xil_printf("Last SBI val: 0x%08x\r\n", (unsigned int)last_value);
    xil_printf("S hartid: 0x%08x\r\n", (unsigned int)hartid);
    xil_printf("S dtb: 0x%08x\r\n", (unsigned int)payload_dtb);
    xil_printf("Base err: 0x%08x\r\n", (unsigned int)spec_err);
    xil_printf("Base version: 0x%08x\r\n", (unsigned int)spec_value);
    xil_printf("Probe err: 0x%08x\r\n", (unsigned int)probe_err);
    xil_printf("Probe TIME: 0x%08x\r\n", (unsigned int)probe_value);
    xil_printf("Console char: 0x%08x\r\n", (unsigned int)console_char);
    xil_printf("Timer err: 0x%08x\r\n", (unsigned int)timer_err);
    xil_printf("Timer value: 0x%08x\r\n", (unsigned int)timer_value);
    xil_printf("Timer cmp lo: 0x%08x\r\n", (unsigned int)cmp_lo);
    xil_printf("Timer cmp hi: 0x%08x\r\n", (unsigned int)cmp_hi);
    xil_printf("S scause: 0x%08x\r\n", (unsigned int)scause);
    xil_printf("S sepc: 0x%08x\r\n", (unsigned int)sepc);
    xil_printf("S sie: 0x%08x\r\n", (unsigned int)sie);
    xil_printf("S sip: 0x%08x\r\n", (unsigned int)sip);
    xil_printf("S status: 0x%08x\r\n", (unsigned int)sstatus);
    xil_printf("S time0: 0x%08x\r\n", (unsigned int)time0);
    xil_printf("S time1: 0x%08x\r\n", (unsigned int)time1);
    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);

    if (verify_errors != 0U ||
        status != CPU_STATUS_PASS ||
        mcause != 9U ||
        last_eid != 0x54494D45U ||
        last_fid != 0U ||
        last_err != 0U ||
        last_value != 0U ||
        hartid != 0U ||
        payload_dtb != dtb_cpu_addr ||
        spec_err != 0U ||
        spec_value != 2U ||
        probe_err != 0U ||
        probe_value != 1U ||
        console_char != 0x5aU ||
        timer_err != 0U ||
        timer_value != 0U ||
        cmp_lo == 0U ||
        cmp_hi != 0U ||
        scause != 0x80000005U ||
        sepc == 0U ||
        (sie & 0x20U) == 0U ||
        time1 <= time0) {
        return -1;
    }

    return 0;
}
