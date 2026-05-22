#include "ps_uart_probe.h"

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"

int main(void)
{
    u32 build_id;
    u32 status;
    u32 scratch;
    u32 writes;
    u32 reads;

    Xil_DCacheDisable();

    xil_printf("\r\n");
    xil_printf("> ZYNQ_CPU PL bring-up probe\r\n");

    build_id = Xil_In32(ZYNQ_CPU_BUILD_ID);
    status = Xil_In32(ZYNQ_CPU_STATUS);

    xil_printf("PL base: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_REG_BASE);
    xil_printf("PL build id: 0x%08x\r\n", (unsigned int)build_id);
    xil_printf("PL status: 0x%08x\r\n", (unsigned int)status);

    Xil_Out32(ZYNQ_CPU_SCRATCH, 0x13579BDFU);
    scratch = Xil_In32(ZYNQ_CPU_SCRATCH);
    writes = Xil_In32(ZYNQ_CPU_WRITE_COUNT);
    reads = Xil_In32(ZYNQ_CPU_READ_COUNT);

    xil_printf("Scratch rd: 0x%08x\r\n", (unsigned int)scratch);
    xil_printf("Write count: %u\r\n", (unsigned int)writes);
    xil_printf("Read count: %u\r\n", (unsigned int)reads);

    if (build_id == 0x26051001U && status == 0x00000001U && scratch == 0x13579BDFU) {
        xil_printf("ZYNQ_CPU AXI-Lite probe: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU AXI-Lite probe: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> DataMover HP0 loopback\r\n");
    if (run_datamover_loopback() == 0) {
        xil_printf("ZYNQ_CPU DataMover loopback: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU DataMover loopback: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU initiated DataMover loopback\r\n");
    if (run_cpu_datamover_loopback() == 0) {
        xil_printf("ZYNQ_CPU PL CPU DataMover: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU PL CPU DataMover: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PS-loaded PL CPU program\r\n");
    if (run_cpu_bram_load_test() == 0) {
        xil_printf("ZYNQ_CPU BRAM load/run: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU BRAM load/run: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU ELF load/run\r\n");
    if (run_cpu_elf_load_test() == 0) {
        xil_printf("ZYNQ_CPU ELF load/run: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU ELF load/run: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU entry smoke\r\n");
    if (run_cpu_entry_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU entry smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU entry smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU trap smoke\r\n");
    if (run_cpu_trap_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU trap smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU trap smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU supervisor smoke\r\n");
    if (run_cpu_supervisor_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU supervisor smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU supervisor smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU supervisor timer smoke\r\n");
    if (run_cpu_supervisor_timer_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU supervisor timer smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU supervisor timer smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU boot payload smoke\r\n");
    if (run_cpu_boot_payload_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU boot payload smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU boot payload smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU supervisor counter smoke\r\n");
    if (run_cpu_supervisor_counter_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU supervisor counter smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU supervisor counter smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL custom DataMover instructions\r\n");
    if (run_cpu_custom_datamover_test() == 0) {
        xil_printf("ZYNQ_CPU custom DataMover: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU custom DataMover: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU DDR random access smoke\r\n");
    if (run_cpu_ddr_access_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU DDR access smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU DDR access smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU DDR instruction fetch smoke\r\n");
    if (run_cpu_ddr_exec_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU DDR instruction fetch smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU DDR instruction fetch smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU DDR high random access smoke\r\n");
    if (run_cpu_ddr_high_access_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU DDR high access smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU DDR high access smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU DDR high instruction fetch smoke\r\n");
    if (run_cpu_ddr_high_exec_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU DDR high instruction fetch smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU DDR high instruction fetch smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU DDR high AMO smoke\r\n");
    if (run_cpu_ddr_high_amo_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU DDR high AMO smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU DDR high AMO smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU SBI firmware smoke\r\n");
    if (run_cpu_sbi_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU SBI firmware smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU SBI firmware smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU SBI timer smoke\r\n");
    if (run_cpu_sbi_timer_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU SBI timer smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU SBI timer smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU Linux boot contract smoke\r\n");
    if (run_cpu_linux_contract_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU Linux boot contract smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU Linux boot contract smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU Linux SBI compatibility smoke\r\n");
    if (run_cpu_linux_sbi_smoke_test() == 0) {
        xil_printf("ZYNQ_CPU Linux SBI compatibility smoke: PASS\r\n");
    } else {
        xil_printf("ZYNQ_CPU Linux SBI compatibility smoke: FAIL\r\n");
    }

    xil_printf("\r\n");
    xil_printf("> PL CPU Linux image layout smoke\r\n");
    int linux_image_rc = run_cpu_linux_image_layout_smoke_test();
    if (linux_image_rc == 0) {
        xil_printf("ZYNQ_CPU Linux image layout smoke: PASS\r\n");
    } else if (linux_image_rc > 0) {
        xil_printf("ZYNQ_CPU Linux image layout smoke: SKIP\r\n");
    } else {
        xil_printf("ZYNQ_CPU Linux image layout smoke: FAIL\r\n");
    }

    while (1) {
    }

    return 0;
}
