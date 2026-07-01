#ifndef ZX32_SYSMON_H
#define ZX32_SYSMON_H

#include <stdint.h>

#define ZX32_CTRL_BASE_DEFAULT 0x10030000UL
#define ZX32_CTRL_SIZE 0x1000UL

#define ZX32_SYSMON_STATUS     0x0ecu
#define ZX32_SYSMON_TEMP_RAW   0x0f0u
#define ZX32_SYSMON_TEMP_MC    0x0f4u
#define ZX32_SYSMON_SAMPLE_SEQ 0x0f8u

#define ZX32_SYSMON_STATUS_VALID  0x00000001u
#define ZX32_SYSMON_STATUS_XADCIF 0x00000002u

struct zx32_sysmon_sample {
    uint32_t status;
    uint32_t temp_raw;
    int32_t temp_millic;
    uint32_t sample_seq;
};

static inline uint32_t zx32_sysmon_rd(volatile uint32_t *regs, uint32_t off) {
    return regs[off / 4u];
}

static inline void zx32_sysmon_sample(volatile uint32_t *regs,
                                      struct zx32_sysmon_sample *s) {
    s->status = zx32_sysmon_rd(regs, ZX32_SYSMON_STATUS);
    s->temp_raw = zx32_sysmon_rd(regs, ZX32_SYSMON_TEMP_RAW);
    s->temp_millic = (int32_t)zx32_sysmon_rd(regs, ZX32_SYSMON_TEMP_MC);
    s->sample_seq = zx32_sysmon_rd(regs, ZX32_SYSMON_SAMPLE_SEQ);
}

static inline int zx32_sysmon_temp_valid(const struct zx32_sysmon_sample *s) {
    return (s->status & ZX32_SYSMON_STATUS_VALID) != 0u;
}

#endif
