#ifndef PS_UART_PROBE_H
#define PS_UART_PROBE_H

#include "xil_types.h"

#define ZYNQ_CPU_REG_BASE      0x43C00000U
#define ZYNQ_CPU_BUILD_ID      (ZYNQ_CPU_REG_BASE + 0x00U)
#define ZYNQ_CPU_STATUS        (ZYNQ_CPU_REG_BASE + 0x04U)
#define ZYNQ_CPU_SCRATCH       (ZYNQ_CPU_REG_BASE + 0x08U)
#define ZYNQ_CPU_WRITE_COUNT   (ZYNQ_CPU_REG_BASE + 0x0CU)
#define ZYNQ_CPU_READ_COUNT    (ZYNQ_CPU_REG_BASE + 0x10U)

#define ZYNQ_CPU_DMA_BASE      0x43C10000U
#define ZYNQ_CPU_DMA_CTRL      (ZYNQ_CPU_DMA_BASE + 0x00U)
#define ZYNQ_CPU_DMA_STATUS    (ZYNQ_CPU_DMA_BASE + 0x04U)
#define ZYNQ_CPU_DMA_DDR_ADDR  (ZYNQ_CPU_DMA_BASE + 0x08U)
#define ZYNQ_CPU_DMA_LOCAL     (ZYNQ_CPU_DMA_BASE + 0x0CU)
#define ZYNQ_CPU_DMA_LEN       (ZYNQ_CPU_DMA_BASE + 0x10U)
#define ZYNQ_CPU_DMA_TAG       (ZYNQ_CPU_DMA_BASE + 0x14U)
#define ZYNQ_CPU_RX_SCRATCH    (ZYNQ_CPU_DMA_BASE + 0x1000U)
#define ZYNQ_CPU_TX_SCRATCH    (ZYNQ_CPU_DMA_BASE + 0x2000U)
#define ZYNQ_CPU_IMEM_BASE     (ZYNQ_CPU_DMA_BASE + 0x3000U)
#define ZYNQ_CPU_CTRL_BASE     (ZYNQ_CPU_DMA_BASE + 0x7000U)
#define ZYNQ_CPU_CPU_CTRL      (ZYNQ_CPU_CTRL_BASE + 0x00U)
#define ZYNQ_CPU_CPU_STATUS    (ZYNQ_CPU_CTRL_BASE + 0x04U)
#define ZYNQ_CPU_BRAM_WORDS    (ZYNQ_CPU_CTRL_BASE + 0x08U)
#define ZYNQ_CPU_SCRATCH_WORDS (ZYNQ_CPU_CTRL_BASE + 0x0CU)
#define ZYNQ_CPU_RESET_VECTOR  (ZYNQ_CPU_CTRL_BASE + 0x10U)

#define CPU_MAIL_START         (ZYNQ_CPU_TX_SCRATCH + 0x3E0U)
#define CPU_MAIL_SRC           (ZYNQ_CPU_TX_SCRATCH + 0x3E4U)
#define CPU_MAIL_DST           (ZYNQ_CPU_TX_SCRATCH + 0x3E8U)
#define CPU_MAIL_LEN           (ZYNQ_CPU_TX_SCRATCH + 0x3ECU)
#define CPU_MAIL_STATUS        (ZYNQ_CPU_TX_SCRATCH + 0x3F0U)
#define CPU_MAIL_MM2S_STATUS   (ZYNQ_CPU_TX_SCRATCH + 0x3F4U)
#define CPU_MAIL_S2MM_STATUS   (ZYNQ_CPU_TX_SCRATCH + 0x3F8U)
#define CPU_MAIL_COPIED        (ZYNQ_CPU_TX_SCRATCH + 0x3FCU)
#define CPU_SUP_SEPC           (ZYNQ_CPU_TX_SCRATCH + 0x3E0U)
#define CPU_SUP_SCAUSE         (ZYNQ_CPU_TX_SCRATCH + 0x3E4U)
#define CPU_SUP_MARKER         (ZYNQ_CPU_TX_SCRATCH + 0x3E8U)
#define CPU_SUP_STATUS         (ZYNQ_CPU_TX_SCRATCH + 0x3F0U)
#define CPU_BOOT_HARTID        (ZYNQ_CPU_TX_SCRATCH + 0x3C0U)
#define CPU_BOOT_DTB           (ZYNQ_CPU_TX_SCRATCH + 0x3C4U)
#define CPU_BOOT_CYCLE         (ZYNQ_CPU_TX_SCRATCH + 0x3C8U)
#define CPU_BOOT_TIME          (ZYNQ_CPU_TX_SCRATCH + 0x3CCU)
#define CPU_BOOT_INSTRET       (ZYNQ_CPU_TX_SCRATCH + 0x3D0U)
#define CPU_DDR_EXEC_PC        (ZYNQ_CPU_TX_SCRATCH + 0x3C0U)
#define CPU_DDR_EXEC_MARKER    (ZYNQ_CPU_TX_SCRATCH + 0x3C4U)
#define CPU_DDR_EXEC_COUNT     (ZYNQ_CPU_TX_SCRATCH + 0x3C8U)
#define CPU_SBI_PAYLOAD_ENTRY  (ZYNQ_CPU_TX_SCRATCH + 0x380U)
#define CPU_SBI_DTB_ADDR       (ZYNQ_CPU_TX_SCRATCH + 0x384U)
#define CPU_SBI_MCAUSE         (ZYNQ_CPU_TX_SCRATCH + 0x38CU)
#define CPU_SBI_MEPC           (ZYNQ_CPU_TX_SCRATCH + 0x390U)
#define CPU_SBI_EID            (ZYNQ_CPU_TX_SCRATCH + 0x394U)
#define CPU_SBI_ARG0           (ZYNQ_CPU_TX_SCRATCH + 0x398U)
#define CPU_SBI_MARKER         (ZYNQ_CPU_TX_SCRATCH + 0x39CU)
#define CPU_SBI_HARTID         (ZYNQ_CPU_TX_SCRATCH + 0x3A0U)
#define CPU_SBI_PAYLOAD_DTB    (ZYNQ_CPU_TX_SCRATCH + 0x3A4U)
#define CPU_SBI_RETVAL         (ZYNQ_CPU_TX_SCRATCH + 0x3A8U)
#define CPU_SBI_TIMER_ENTRY    (ZYNQ_CPU_TX_SCRATCH + 0x340U)
#define CPU_SBI_TIMER_DTB      (ZYNQ_CPU_TX_SCRATCH + 0x344U)
#define CPU_SBI_TIMER_MCAUSE   (ZYNQ_CPU_TX_SCRATCH + 0x34CU)
#define CPU_SBI_TIMER_MEPC     (ZYNQ_CPU_TX_SCRATCH + 0x350U)
#define CPU_SBI_TIMER_EID      (ZYNQ_CPU_TX_SCRATCH + 0x354U)
#define CPU_SBI_TIMER_FID      (ZYNQ_CPU_TX_SCRATCH + 0x358U)
#define CPU_SBI_TIMER_ARG0     (ZYNQ_CPU_TX_SCRATCH + 0x35CU)
#define CPU_SBI_TIMER_CMP_LO   (ZYNQ_CPU_TX_SCRATCH + 0x360U)
#define CPU_SBI_TIMER_CMP_HI   (ZYNQ_CPU_TX_SCRATCH + 0x364U)
#define CPU_SBI_TIMER_HARTID   (ZYNQ_CPU_TX_SCRATCH + 0x380U)
#define CPU_SBI_TIMER_PAY_DTB  (ZYNQ_CPU_TX_SCRATCH + 0x384U)
#define CPU_SBI_TIMER_RETVAL   (ZYNQ_CPU_TX_SCRATCH + 0x388U)
#define CPU_SBI_TIMER_SCAUSE   (ZYNQ_CPU_TX_SCRATCH + 0x38CU)
#define CPU_SBI_TIMER_SEPC     (ZYNQ_CPU_TX_SCRATCH + 0x390U)
#define CPU_SBI_TIMER_SIE      (ZYNQ_CPU_TX_SCRATCH + 0x394U)
#define CPU_SBI_TIMER_SIP      (ZYNQ_CPU_TX_SCRATCH + 0x398U)
#define CPU_SBI_TIMER_SSTATUS  (ZYNQ_CPU_TX_SCRATCH + 0x39CU)
#define CPU_SBI_TIMER_TIME0    (ZYNQ_CPU_TX_SCRATCH + 0x3A0U)
#define CPU_SBI_TIMER_TIME1    (ZYNQ_CPU_TX_SCRATCH + 0x3A4U)
#define CPU_START_MAGIC        0x43505521U
#define CPU_STATUS_WAITING     0x00000111U
#define CPU_STATUS_PASS        0x00000222U
#define CPU_STATUS_FAIL        0x00000333U
#define CPU_LOAD_TEST_PASS     0xABCD1234U
#define CPU_SUP_TRAP_MARKER    0x0000005AU
#define CPU_BOOT_DTB_VALUE     0x20010000U

#define DMA_ST_MM2S_DONE       0x00000004U
#define DMA_ST_S2MM_DONE       0x00000008U
#define DMA_ST_MM2S_ERR        0x00000010U
#define DMA_ST_S2MM_ERR        0x00000020U
#define DMA_ST_CLEAR_DONE_ERR  0x0000003CU

#define ZYNQ_CPU_DDR_CPU_BASE  0x80000000U
#define ZYNQ_CPU_DDR_PHYS_BASE 0x00100000U
#define CPU_DDR_EXEC_WORDS     64U
#define CPU_SBI_PAYLOAD_WORDS  128U

#define DMA_WORDS              16U
#define DMA_BYTES              (DMA_WORDS * sizeof(u32))

extern u32 dma_src[DMA_WORDS];
extern u32 dma_dst[DMA_WORDS];
extern u32 cpu_dma_src[DMA_WORDS];
extern u32 cpu_dma_dst[DMA_WORDS];
extern u32 cpu_ddr_probe[32];
extern u32 cpu_ddr_exec[CPU_DDR_EXEC_WORDS];
extern u32 cpu_sbi_payload[CPU_SBI_PAYLOAD_WORDS];

int load_zx32_elf_into_imem(const u8 *elf, u32 elf_size, u32 *loaded_words_out, u32 *entry_out);
int wait_for_dma(u32 done_mask, u32 err_mask, u32 *status_out);
int wait_for_cpu(u32 *status_out);

int run_datamover_loopback(void);
int run_cpu_datamover_loopback(void);
int run_cpu_bram_load_test(void);
int run_cpu_elf_load_test(void);
int run_cpu_ddr_access_smoke_test(void);
int run_cpu_custom_datamover_test(void);
int run_cpu_entry_smoke_test(void);
int run_cpu_trap_smoke_test(void);
int run_cpu_ddr_exec_smoke_test(void);
int run_cpu_sbi_smoke_test(void);
int run_cpu_sbi_timer_smoke_test(void);
int run_cpu_supervisor_smoke_test(void);
int run_cpu_supervisor_timer_smoke_test(void);
int run_cpu_boot_payload_smoke_test(void);
int run_cpu_supervisor_counter_smoke_test(void);

#endif
