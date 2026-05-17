#include "ps_uart_probe.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "zx32_programs.h"

int run_datamover_loopback(void)
{
    u32 status = 0U;
    u32 mismatches = 0U;

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        dma_src[i] = 0x5A000000U | (i * 0x010101U) | i;
        dma_dst[i] = 0U;
    }

    Xil_Out32(ZYNQ_CPU_DMA_STATUS, DMA_ST_CLEAR_DONE_ERR);
    Xil_Out32(ZYNQ_CPU_DMA_DDR_ADDR, (u32)(UINTPTR)&dma_src[0]);
    Xil_Out32(ZYNQ_CPU_DMA_LOCAL, 0U);
    Xil_Out32(ZYNQ_CPU_DMA_LEN, DMA_BYTES);
    Xil_Out32(ZYNQ_CPU_DMA_TAG, 1U);
    Xil_Out32(ZYNQ_CPU_DMA_CTRL, 1U);

    if (wait_for_dma(DMA_ST_MM2S_DONE, DMA_ST_MM2S_ERR, &status) != 0) {
        xil_printf("MM2S status: 0x%08x\r\n", (unsigned int)status);
        return -1;
    }
    xil_printf("MM2S status: 0x%08x\r\n", (unsigned int)status);

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        u32 word = Xil_In32(ZYNQ_CPU_RX_SCRATCH + i * 4U);
        Xil_Out32(ZYNQ_CPU_TX_SCRATCH + i * 4U, word);
    }

    Xil_Out32(ZYNQ_CPU_DMA_STATUS, DMA_ST_CLEAR_DONE_ERR);
    Xil_Out32(ZYNQ_CPU_DMA_DDR_ADDR, (u32)(UINTPTR)&dma_dst[0]);
    Xil_Out32(ZYNQ_CPU_DMA_LOCAL, 0U);
    Xil_Out32(ZYNQ_CPU_DMA_LEN, DMA_BYTES);
    Xil_Out32(ZYNQ_CPU_DMA_TAG, 2U);
    Xil_Out32(ZYNQ_CPU_DMA_CTRL, 2U);

    if (wait_for_dma(DMA_ST_S2MM_DONE, DMA_ST_S2MM_ERR, &status) != 0) {
        xil_printf("S2MM status: 0x%08x\r\n", (unsigned int)status);
        return -2;
    }
    xil_printf("S2MM status: 0x%08x\r\n", (unsigned int)status);

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        if (dma_dst[i] != dma_src[i]) {
            mismatches++;
        }
    }

    xil_printf("DMA src addr: 0x%08x\r\n", (unsigned int)(UINTPTR)&dma_src[0]);
    xil_printf("DMA dst addr: 0x%08x\r\n", (unsigned int)(UINTPTR)&dma_dst[0]);
    xil_printf("DMA words: %u\r\n", (unsigned int)DMA_WORDS);
    xil_printf("DMA first: 0x%08x -> 0x%08x\r\n",
               (unsigned int)dma_src[0], (unsigned int)dma_dst[0]);
    xil_printf("DMA last: 0x%08x -> 0x%08x\r\n",
               (unsigned int)dma_src[DMA_WORDS - 1U], (unsigned int)dma_dst[DMA_WORDS - 1U]);
    xil_printf("DMA mismatch: %u\r\n", (unsigned int)mismatches);

    return (mismatches == 0U) ? 0 : -3;
}

int run_cpu_datamover_loopback(void)
{
    u32 status = 0U;
    u32 mm2s_status;
    u32 s2mm_status;
    u32 copied;
    u32 mismatches = 0U;

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        cpu_dma_src[i] = 0xC5000000U | (i * 0x00010101U) | i;
        cpu_dma_dst[i] = 0U;
    }

    Xil_Out32(CPU_MAIL_START, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);
    Xil_Out32(CPU_MAIL_MM2S_STATUS, 0U);
    Xil_Out32(CPU_MAIL_S2MM_STATUS, 0U);
    Xil_Out32(CPU_MAIL_COPIED, 0U);
    Xil_Out32(CPU_MAIL_SRC, (u32)(UINTPTR)&cpu_dma_src[0]);
    Xil_Out32(CPU_MAIL_DST, (u32)(UINTPTR)&cpu_dma_dst[0]);
    Xil_Out32(CPU_MAIL_LEN, DMA_BYTES);
    Xil_Out32(CPU_MAIL_START, CPU_START_MAGIC);

    if (wait_for_cpu(&status) != 0) {
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        return -1;
    }

    mm2s_status = Xil_In32(CPU_MAIL_MM2S_STATUS);
    s2mm_status = Xil_In32(CPU_MAIL_S2MM_STATUS);
    copied = Xil_In32(CPU_MAIL_COPIED);

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        if (cpu_dma_dst[i] != cpu_dma_src[i]) {
            mismatches++;
        }
    }

    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
    xil_printf("CPU MM2S st: 0x%08x\r\n", (unsigned int)mm2s_status);
    xil_printf("CPU S2MM st: 0x%08x\r\n", (unsigned int)s2mm_status);
    xil_printf("CPU copied: %u words\r\n", (unsigned int)copied);
    xil_printf("CPU src addr: 0x%08x\r\n", (unsigned int)(UINTPTR)&cpu_dma_src[0]);
    xil_printf("CPU dst addr: 0x%08x\r\n", (unsigned int)(UINTPTR)&cpu_dma_dst[0]);
    xil_printf("CPU first: 0x%08x -> 0x%08x\r\n",
               (unsigned int)cpu_dma_src[0], (unsigned int)cpu_dma_dst[0]);
    xil_printf("CPU last: 0x%08x -> 0x%08x\r\n",
               (unsigned int)cpu_dma_src[DMA_WORDS - 1U], (unsigned int)cpu_dma_dst[DMA_WORDS - 1U]);
    xil_printf("CPU mismatch: %u\r\n", (unsigned int)mismatches);

    return (copied == DMA_WORDS && mismatches == 0U) ? 0 : -2;
}

int run_cpu_custom_datamover_test(void)
{
    u32 status = 0U;
    u32 mm2s_status = 0U;
    u32 s2mm_status = 0U;
    u32 copied = 0U;
    u32 mismatches = 0U;
    u32 verify_errors = 0U;
    u32 loaded_words = 0U;
    u32 entry = 0U;
    int rc;

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        cpu_dma_src[i] = 0x6B000000U | (i * 0x00010101U) | i;
        cpu_dma_dst[i] = 0U;
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    Xil_Out32(CPU_MAIL_START, 0U);
    Xil_Out32(CPU_MAIL_STATUS, 0U);
    Xil_Out32(CPU_MAIL_MM2S_STATUS, 0U);
    Xil_Out32(CPU_MAIL_S2MM_STATUS, 0U);
    Xil_Out32(CPU_MAIL_COPIED, 0U);
    Xil_Out32(CPU_MAIL_SRC, (u32)(UINTPTR)&cpu_dma_src[0]);
    Xil_Out32(CPU_MAIL_DST, (u32)(UINTPTR)&cpu_dma_dst[0]);
    Xil_Out32(CPU_MAIL_LEN, DMA_BYTES);

    rc = load_zx32_elf_into_imem(zx32_custom_datamover_elf, zx32_custom_datamover_elf_size, &loaded_words, &entry);
    if (rc != 0) {
        xil_printf("CPU ELF rc: %d\r\n", rc);
        return -1;
    }
    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, entry);

    for (u32 i = 0U; i < (sizeof(zx32_custom_datamover_program) / sizeof(zx32_custom_datamover_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_custom_datamover_program[i]) {
            verify_errors++;
        }
    }
    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);
    Xil_Out32(CPU_MAIL_START, CPU_START_MAGIC);

    if (wait_for_cpu(&status) != 0) {
        xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
        return -1;
    }

    mm2s_status = Xil_In32(CPU_MAIL_MM2S_STATUS);
    s2mm_status = Xil_In32(CPU_MAIL_S2MM_STATUS);
    copied = Xil_In32(CPU_MAIL_COPIED);

    for (u32 i = 0U; i < DMA_WORDS; i++) {
        if (cpu_dma_dst[i] != cpu_dma_src[i]) {
            mismatches++;
        }
    }

    xil_printf("CPU status: 0x%08x\r\n", (unsigned int)status);
    xil_printf("CPU ELF words: %u\r\n", (unsigned int)loaded_words);
    xil_printf("CPU entry PC: 0x%08x\r\n", (unsigned int)entry);
    xil_printf("CPU IMEM err: %u\r\n", (unsigned int)verify_errors);
    xil_printf("CPU MM2S st: 0x%08x\r\n", (unsigned int)mm2s_status);
    xil_printf("CPU S2MM st: 0x%08x\r\n", (unsigned int)s2mm_status);
    xil_printf("CPU copied: %u words\r\n", (unsigned int)copied);
    xil_printf("CPU src addr: 0x%08x\r\n", (unsigned int)(UINTPTR)&cpu_dma_src[0]);
    xil_printf("CPU dst addr: 0x%08x\r\n", (unsigned int)(UINTPTR)&cpu_dma_dst[0]);
    xil_printf("CPU first: 0x%08x -> 0x%08x\r\n",
               (unsigned int)cpu_dma_src[0], (unsigned int)cpu_dma_dst[0]);
    xil_printf("CPU last: 0x%08x -> 0x%08x\r\n",
               (unsigned int)cpu_dma_src[DMA_WORDS - 1U], (unsigned int)cpu_dma_dst[DMA_WORDS - 1U]);
    xil_printf("CPU mismatch: %u\r\n", (unsigned int)mismatches);

    return (status == CPU_STATUS_PASS && copied == DMA_WORDS && mismatches == 0U && verify_errors == 0U) ? 0 : -1;
}

