#ifndef ZX32_ISA_H
#define ZX32_ISA_H

#include "xil_types.h"

#define ZX32_OPCODE_CUSTOM0 0x0BU

#define ZX32_RTYPE_CUSTOM(funct7, rs2, rs1, funct3, rd) \
    ((((u32)(funct7) & 0x7FU) << 25) | \
     (((u32)(rs2) & 0x1FU) << 20) | \
     (((u32)(rs1) & 0x1FU) << 15) | \
     (((u32)(funct3) & 0x7U) << 12) | \
     (((u32)(rd) & 0x1FU) << 7) | ZX32_OPCODE_CUSTOM0)

#define ZX32_XCPYW(rd, rs1, rs2)  ZX32_RTYPE_CUSTOM(0, rs2, rs1, 0, rd)
#define ZX32_XDM2S(rd, rs1, rs2)  ZX32_RTYPE_CUSTOM(0, rs2, rs1, 1, rd)
#define ZX32_XDS2M(rd, rs1, rs2)  ZX32_RTYPE_CUSTOM(0, rs2, rs1, 2, rd)
#define ZX32_XDS2MM(rd, rs1, rs2) ZX32_XDS2M(rd, rs1, rs2)

#endif
