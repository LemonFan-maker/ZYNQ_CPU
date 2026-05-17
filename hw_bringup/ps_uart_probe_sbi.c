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

