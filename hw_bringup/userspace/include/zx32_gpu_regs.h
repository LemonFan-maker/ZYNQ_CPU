#ifndef ZX32_GPU_REGS_H
#define ZX32_GPU_REGS_H

#include <stdint.h>

#define ZX32_GPU_BASE_DEFAULT 0x10070000UL
#define ZX32_GPU_SIZE         0x1000UL

#define ZX32_VRAM_BASE_DEFAULT 0xbc000000UL
#define ZX32_VRAM_BYTES        (64UL * 1024UL * 1024UL)

#define ZX32_GPU_CONTROL       0x00u
#define ZX32_GPU_STATUS        0x04u
#define ZX32_GPU_FB_ADDR       0x08u
#define ZX32_GPU_FB_STRIDE     0x0cu
#define ZX32_GPU_FB_SIZE       0x10u
#define ZX32_GPU_COLOR         0x14u
#define ZX32_GPU_RECT_ORIGIN   0x18u
#define ZX32_GPU_RECT_SIZE     0x1cu
#define ZX32_GPU_CUR_PIXEL     0x20u
#define ZX32_GPU_WAIT_COUNT    0x24u
#define ZX32_GPU_PIXEL_COUNT   0x28u
#define ZX32_GPU_LAST_CTRL     0x2cu
#define ZX32_GPU_CUR_ADDR      0x30u
#define ZX32_GPU_CMD_SUBMIT    0x34u
#define ZX32_GPU_CMD_DONE      0x38u
#define ZX32_GPU_TOTAL_CYCLES  0x3cu
#define ZX32_GPU_BUSY_CYCLES   0x40u
#define ZX32_GPU_STALL_CYCLES  0x44u
#define ZX32_GPU_WRITE_COUNT   0x48u
#define ZX32_GPU_SRC_ADDR      0x4cu
#define ZX32_GPU_SRC_STRIDE    0x50u

#define ZX32_GPU_CONTROL_START      (1u << 0)
#define ZX32_GPU_CONTROL_PERF_CLEAR (1u << 30)
#define ZX32_GPU_CONTROL_RESET      (1u << 31)

#define ZX32_GPU_STATUS_BUSY  (1u << 0)
#define ZX32_GPU_STATUS_DONE  (1u << 1)
#define ZX32_GPU_STATUS_ERROR (1u << 2)

#define ZX32_GPU_OP_CLEAR     1u
#define ZX32_GPU_OP_FILL_RECT 2u
#define ZX32_GPU_OP_DRAW_LINE 3u
#define ZX32_GPU_OP_BLIT      4u
#define ZX32_GPU_OP_COLOR_KEY_BLIT 5u

static inline uint32_t zx32_gpu_rd(volatile uint32_t *regs, uint32_t off) {
    return regs[off >> 2];
}

static inline void zx32_gpu_wr(volatile uint32_t *regs, uint32_t off, uint32_t value) {
    regs[off >> 2] = value;
    __asm__ __volatile__("" ::: "memory");
}

#endif
