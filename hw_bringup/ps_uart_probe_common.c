#include "ps_uart_probe.h"

#include "xil_io.h"

u32 dma_src[DMA_WORDS] __attribute__((aligned(64)));
u32 dma_dst[DMA_WORDS] __attribute__((aligned(64)));
u32 cpu_dma_src[DMA_WORDS] __attribute__((aligned(64)));
u32 cpu_dma_dst[DMA_WORDS] __attribute__((aligned(64)));
u32 cpu_ddr_probe[32] __attribute__((aligned(64)));
u32 cpu_ddr_exec[CPU_DDR_EXEC_WORDS] __attribute__((aligned(64)));
u32 cpu_sbi_payload[CPU_SBI_PAYLOAD_WORDS] __attribute__((aligned(64)));
u32 cpu_linux_contract[CPU_LINUX_CONTRACT_WORDS] __attribute__((aligned(64)));

static u16 read_u16_le(const u8 *ptr)
{
    return (u16)(ptr[0] | ((u16)ptr[1] << 8));
}

static u32 read_u32_le(const u8 *ptr)
{
    return (u32)ptr[0] |
           ((u32)ptr[1] << 8) |
           ((u32)ptr[2] << 16) |
           ((u32)ptr[3] << 24);
}

int load_zx32_elf_into_imem(const u8 *elf, u32 elf_size, u32 *loaded_words_out, u32 *entry_out)
{
    enum {
        EI_CLASS = 4,
        EI_DATA = 5,
        EI_VERSION = 6,
    };
    const u32 elf_header_size = 52U;
    const u32 phdr_size = 32U;
    u32 entry;
    u32 phoff;
    u16 phentsize;
    u16 phnum;
    u32 loaded_words = 0U;

    if (elf_size < elf_header_size) {
        return -1;
    }
    if (elf[0] != 0x7FU || elf[1] != 'E' || elf[2] != 'L' || elf[3] != 'F') {
        return -2;
    }
    if (elf[EI_CLASS] != 1U || elf[EI_DATA] != 1U || elf[EI_VERSION] != 1U) {
        return -3;
    }
    if (read_u16_le(&elf[16]) != 2U) {
        return -4;
    }
    if (read_u16_le(&elf[18]) != 243U) {
        return -5;
    }
    if (read_u32_le(&elf[28]) != elf_header_size) {
        return -6;
    }
    entry = read_u32_le(&elf[24]);
    phoff = read_u32_le(&elf[28]);
    phentsize = read_u16_le(&elf[42]);
    phnum = read_u16_le(&elf[44]);
    if (phentsize != phdr_size) {
        return -7;
    }
    if (phoff + ((u32)phnum * (u32)phentsize) > elf_size) {
        return -8;
    }

    for (u16 i = 0U; i < phnum; i++) {
        const u8 *ph = &elf[phoff + ((u32)i * (u32)phentsize)];
        u32 p_type = read_u32_le(&ph[0]);
        u32 p_offset = read_u32_le(&ph[4]);
        u32 p_paddr = read_u32_le(&ph[12]);
        u32 p_filesz = read_u32_le(&ph[16]);
        u32 p_memsz = read_u32_le(&ph[20]);

        if (p_type != 1U) {
            continue;
        }
        if ((p_offset & 0x3U) != 0U || (p_paddr & 0x3U) != 0U || (p_filesz & 0x3U) != 0U || (p_memsz & 0x3U) != 0U) {
            return -9;
        }
        if (p_offset + p_filesz > elf_size) {
            return -10;
        }
        if (p_memsz < p_filesz) {
            return -11;
        }

        for (u32 off = 0U; off < p_memsz; off += 4U) {
            u32 word = 0U;
            if (off < p_filesz) {
                word = read_u32_le(&elf[p_offset + off]);
            }
            Xil_Out32(ZYNQ_CPU_IMEM_BASE + p_paddr + off, word);
        }
        loaded_words += p_memsz / 4U;
    }

    *loaded_words_out = loaded_words;
    *entry_out = entry;
    return 0;
}

int wait_for_dma(u32 done_mask, u32 err_mask, u32 *status_out)
{
    u32 status = 0U;

    for (u32 timeout = 0U; timeout < 1000000U; timeout++) {
        status = Xil_In32(ZYNQ_CPU_DMA_STATUS);
        if ((status & err_mask) != 0U) {
            *status_out = status;
            return -1;
        }
        if ((status & done_mask) != 0U) {
            *status_out = status;
            return 0;
        }
    }

    *status_out = status;
    return -2;
}

int wait_for_cpu(u32 *status_out)
{
    u32 status = 0U;

    for (u32 timeout = 0U; timeout < 2000000U; timeout++) {
        status = Xil_In32(CPU_MAIL_STATUS);
        if (status == CPU_STATUS_PASS) {
            *status_out = status;
            return 0;
        }
        if (status == CPU_STATUS_FAIL) {
            *status_out = status;
            return -1;
        }
    }

    *status_out = status;
    return -2;
}
