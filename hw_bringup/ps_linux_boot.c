#include "ps_uart_probe.h"

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "bspconfig.h"
#include "xuartps_hw.h"
#include "zx32_programs.h"

#ifndef ZX32_LINUX_BOOT_TRACE
#define ZX32_LINUX_BOOT_TRACE 0
#endif

static u32 cpu_ddr_to_ps_addr(u32 cpu_addr)
{
    return cpu_addr - ZYNQ_CPU_DDR_CPU_BASE + ZYNQ_CPU_DDR_PHYS_BASE;
}

static void print_sv32_pte(const char *name, const char *slot, u32 idx, u32 pte_addr, u32 pte)
{
    const char *kind = "invalid";

    if ((pte & 0x1U) != 0U) {
        if ((pte & 0xAU) != 0U) {
            kind = "leaf";
        } else {
            kind = "table";
        }
    }

    xil_printf("%s PTE %s[%u] @0x%08x: 0x%08x %s ppn=0x%08x flags=%c%c%c%c%c%c%c%c\r\n",
               name,
               slot,
               (unsigned int)idx,
               (unsigned int)pte_addr,
               (unsigned int)pte,
               kind,
               (unsigned int)(pte >> 10),
               (pte & 0x001U) ? 'V' : '-',
               (pte & 0x002U) ? 'R' : '-',
               (pte & 0x004U) ? 'W' : '-',
               (pte & 0x008U) ? 'X' : '-',
               (pte & 0x010U) ? 'U' : '-',
               (pte & 0x020U) ? 'G' : '-',
               (pte & 0x040U) ? 'A' : '-',
               (pte & 0x080U) ? 'D' : '-');
}

static void print_sv32_root_probe(const char *name, u32 satp_value)
{
    u32 root_cpu = (satp_value & 0x003fffffU) << 12;
    u32 root_ps = cpu_ddr_to_ps_addr(root_cpu);
    u32 phys_idx = ZYNQ_CPU_LINUX_KERNEL_CPU_ADDR >> 22;
    u32 virt_idx = 0xC0000000U >> 22;
    u32 phys_pte_ps = root_ps + phys_idx * 4U;
    u32 virt_pte_ps = root_ps + virt_idx * 4U;
    u32 phys_pte = Xil_In32(phys_pte_ps);
    u32 virt_pte = Xil_In32(virt_pte_ps);

    xil_printf("%s root CPU: 0x%08x PS: 0x%08x\r\n",
               name,
               (unsigned int)root_cpu,
               (unsigned int)root_ps);
    print_sv32_pte(name, "phys", phys_idx, phys_pte_ps, phys_pte);
    print_sv32_pte(name, "virt", virt_idx, virt_pte_ps, virt_pte);
}

static void print_core_debug_probe(void)
{
    u32 state = Xil_In32(ZYNQ_CPU_DBG_STATE);
    u32 bus = Xil_In32(ZYNQ_CPU_DBG_BUS);
    u32 last_bus = Xil_In32(ZYNQ_CPU_DBG_LAST_DDR_STATE);

    xil_printf("Core dbg: raw=0x%08x fsm=%u priv=%u flags=req:%u pa:%u fetch:%u we:%u pf:%u iv:%u ir:%u dv:%u dr:%u\r\n",
               (unsigned int)state,
               (unsigned int)((state >> 9) & 0x1fU),
               (unsigned int)((state >> 14) & 0x3U),
               (unsigned int)((state >> 0) & 0x1U),
               (unsigned int)((state >> 1) & 0x1U),
               (unsigned int)((state >> 2) & 0x1U),
               (unsigned int)((state >> 3) & 0x1U),
               (unsigned int)((state >> 4) & 0x1U),
               (unsigned int)((state >> 5) & 0x1U),
               (unsigned int)((state >> 6) & 0x1U),
               (unsigned int)((state >> 7) & 0x1U),
               (unsigned int)((state >> 8) & 0x1U));
    xil_printf("Core pc: pc=0x%08x satp=0x%08x stvec=0x%08x\r\n",
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_PC),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_SATP),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_STVEC));
    xil_printf("Core trap: sepc=0x%08x scause=0x%08x stval=0x%08x\r\n",
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_SEPC),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_SCAUSE),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_STVAL));
    xil_printf("Core PTW: req_va=0x%08x req_pa=0x%08x pte_addr=0x%08x l1=0x%08x l0=0x%08x\r\n",
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_REQ_VADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_REQ_PADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_PTW_ADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_PTW_L1),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_PTW_L0));
    xil_printf("Core bus: raw=0x%08x ddr_req:%u ddr_we:%u ddr_ready:%u ddr_valid:%u if_ddr:%u bus_valid:%u bus_ready:%u host:%u dv:%u dr:%u iv:%u ir:%u ddr_addr=0x%08x\r\n",
               (unsigned int)bus,
               (unsigned int)((bus >> 11) & 0x1U),
               (unsigned int)((bus >> 10) & 0x1U),
               (unsigned int)((bus >> 9) & 0x1U),
               (unsigned int)((bus >> 8) & 0x1U),
               (unsigned int)((bus >> 7) & 0x1U),
               (unsigned int)((bus >> 6) & 0x1U),
               (unsigned int)((bus >> 5) & 0x1U),
               (unsigned int)((bus >> 4) & 0x1U),
               (unsigned int)((bus >> 3) & 0x1U),
               (unsigned int)((bus >> 2) & 0x1U),
               (unsigned int)((bus >> 1) & 0x1U),
               (unsigned int)((bus >> 0) & 0x1U),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_DDR_ADDR));
    xil_printf("Core addr: imem=0x%08x dmem=0x%08x last_ddr=0x%08x last_axi_ar=0x%08x last_imem=0x%08x last_dmem=0x%08x last_bus=0x%08x\r\n",
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_IMEM_ADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_DMEM_ADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_LAST_DDR_ADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_LAST_AXI_ARADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_LAST_IMEM_ADDR),
               (unsigned int)Xil_In32(ZYNQ_CPU_DBG_LAST_DMEM_ADDR),
               (unsigned int)last_bus);
}

static void print_linux_sbi_counters(void)
{
    xil_printf("SBI counters: trap=%u ecall=%u base=%u time=%u put=%u get=%u dbg=%u unsup=%u last_char=0x%08x time_mepc=0x%08x cons_mepc=0x%08x off_valid=%u off=0x%08x%08x mtime=0x%08x%08x cmp=0x%08x%08x\r\n",
               (unsigned int)Xil_In32(CPU_LINUX_TRAP_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_ECALL_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_BASE_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_TIME_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_CONSOLE_PUT_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_CONSOLE_GET_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_DEBUG_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_UNSUPPORTED_COUNT),
               (unsigned int)Xil_In32(CPU_LINUX_LAST_CHAR),
               (unsigned int)Xil_In32(CPU_LINUX_LAST_TIME_MEPC),
               (unsigned int)Xil_In32(CPU_LINUX_LAST_CONSOLE_MEPC),
               (unsigned int)Xil_In32(CPU_LINUX_TIMER_OFFSET_VALID),
               (unsigned int)Xil_In32(CPU_LINUX_TIMER_OFFSET_HI),
               (unsigned int)Xil_In32(CPU_LINUX_TIMER_OFFSET_LO),
               (unsigned int)Xil_In32(CPU_LINUX_TIMER_MTIME_HI),
               (unsigned int)Xil_In32(CPU_LINUX_TIMER_MTIME_LO),
               (unsigned int)Xil_In32(CPU_LINUX_CMP_HI),
               (unsigned int)Xil_In32(CPU_LINUX_CMP_LO));
}

static int pc_in_linux_memset(u32 pc)
{
    return pc >= 0xC0522680U && pc < 0xC0522790U;
}

static int pc_in_linux_fdt(u32 pc)
{
    return pc >= 0xC0507C30U && pc < 0xC0509400U;
}

static void print_linux_progress_probe(const char *tag, u32 *last_probe_dmem, u32 *last_probe_imem)
{
    u32 pc = Xil_In32(ZYNQ_CPU_DBG_PC);
    u32 state = Xil_In32(ZYNQ_CPU_DBG_STATE);
    u32 bus = Xil_In32(ZYNQ_CPU_DBG_BUS);
    u32 imem = Xil_In32(ZYNQ_CPU_DBG_IMEM_ADDR);
    u32 dmem = Xil_In32(ZYNQ_CPU_DBG_DMEM_ADDR);
    u32 req_va = Xil_In32(ZYNQ_CPU_DBG_REQ_VADDR);
    u32 req_pa = Xil_In32(ZYNQ_CPU_DBG_REQ_PADDR);
    u32 ddr_addr = Xil_In32(ZYNQ_CPU_DBG_DDR_ADDR);
    u32 last_ddr = Xil_In32(ZYNQ_CPU_DBG_LAST_DDR_ADDR);
    u32 last_dmem = Xil_In32(ZYNQ_CPU_DBG_LAST_DMEM_ADDR);
    u32 last_bus = Xil_In32(ZYNQ_CPU_DBG_LAST_DDR_STATE);
    u32 last_axi_ar = Xil_In32(ZYNQ_CPU_DBG_LAST_AXI_ARADDR);

    xil_printf("%s probe: pc=0x%08x imem=0x%08x dmem=0x%08x req=0x%08x->0x%08x ddr=0x%08x last_dmem=0x%08x last_ddr=0x%08x last_axi=0x%08x bus=0x%08x state=0x%08x dmem_delta=0x%08x imem_delta=0x%08x\r\n",
               tag,
               (unsigned int)pc,
               (unsigned int)imem,
               (unsigned int)dmem,
               (unsigned int)req_va,
               (unsigned int)req_pa,
               (unsigned int)ddr_addr,
               (unsigned int)last_dmem,
               (unsigned int)last_ddr,
               (unsigned int)last_axi_ar,
               (unsigned int)last_bus,
               (unsigned int)state,
               (unsigned int)(dmem - *last_probe_dmem),
               (unsigned int)(imem - *last_probe_imem));

    *last_probe_dmem = dmem;
    *last_probe_imem = imem;
}

static void print_linux_memset_probe(u32 *last_probe_dmem, u32 *last_probe_imem)
{
    u32 pc = Xil_In32(ZYNQ_CPU_DBG_PC);

    if (pc_in_linux_memset(pc)) {
        print_linux_progress_probe("Memset", last_probe_dmem, last_probe_imem);
    } else if (pc_in_linux_fdt(pc)) {
        print_linux_progress_probe("FDT", last_probe_dmem, last_probe_imem);
    }
}

static int print_linux_console_mirror(u32 *last_total, int *started)
{
    static const char idle_marker[] = "[zx32-init] idle";
    static u32 idle_match = 0U;
    u32 total = Xil_In32(CPU_LINUX_CONSOLE_RING_TOTAL);
    int idle_seen = 0;

    if (total == *last_total) {
        return 0;
    }

    if (*started == 0) {
        xil_printf("\r\nLinux SBI console mirror\r\n");
        *started = 1;
    }

    if ((total - *last_total) > CPU_LINUX_CONSOLE_RING_BYTES) {
        u32 skipped = (total - *last_total) - CPU_LINUX_CONSOLE_RING_BYTES;
        *last_total = total - CPU_LINUX_CONSOLE_RING_BYTES;
        xil_printf("\r\n[linux console skipped %u chars]\r\n", (unsigned int)skipped);
    }

    while (*last_total != total) {
        u32 idx = *last_total & (CPU_LINUX_CONSOLE_RING_BYTES - 1U);
        u32 word = Xil_In32(CPU_LINUX_CONSOLE_RING_BASE + (idx & ~3U));
        u32 ch = (word >> ((idx & 3U) * 8U)) & 0xffU;

        if (ch == '\n') {
            xil_printf("\r\n");
        } else if (ch != '\r') {
            xil_printf("%c", (char)ch);
        }

        if (ch == (u32)idle_marker[idle_match]) {
            idle_match++;
            if (idle_match == (sizeof(idle_marker) - 1U)) {
                idle_seen = 1;
                idle_match = 0U;
            }
        } else {
            idle_match = (ch == (u32)idle_marker[0]) ? 1U : 0U;
        }

        (*last_total)++;
        Xil_Out32(CPU_LINUX_CONSOLE_RING_HEAD, *last_total);
    }

    return idle_seen;
}

static void pump_linux_console_input(void)
{
    u32 head = Xil_In32(CPU_LINUX_CONSOLE_IN_RING_HEAD);
    u32 tail = Xil_In32(CPU_LINUX_CONSOLE_IN_RING_TAIL);

    while ((tail - head) < CPU_LINUX_CONSOLE_IN_RING_BYTES &&
           XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        u8 ch = XUartPs_RecvByte(STDIN_BASEADDRESS);
        u32 idx = tail & (CPU_LINUX_CONSOLE_IN_RING_BYTES - 1U);
        u32 addr = CPU_LINUX_CONSOLE_IN_RING_BASE + (idx & ~3U);
        u32 shift = (idx & 3U) * 8U;
        u32 word = Xil_In32(addr);

        word &= ~(0xffU << shift);
        word |= ((u32)ch << shift);
        Xil_Out32(addr, word);
        tail++;
        Xil_Out32(CPU_LINUX_CONSOLE_IN_RING_TAIL, tail);
    }

    if (Xil_In32(CPU_LINUX_CONSOLE_IN_VALID) == 0U &&
        XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        u8 ch = XUartPs_RecvByte(STDIN_BASEADDRESS);
        Xil_Out32(CPU_LINUX_CONSOLE_IN_CHAR, (u32)ch);
        Xil_Out32(CPU_LINUX_CONSOLE_IN_VALID, 1U);
    }
}

static void clear_linux_console_mirror(void)
{
    for (u32 i = 0U; i < CPU_LINUX_CONSOLE_RING_WORDS; i++) {
        Xil_Out32(CPU_LINUX_CONSOLE_RING_BASE + i * 4U, 0U);
    }
    Xil_Out32(CPU_LINUX_CONSOLE_RING_HEAD, 0U);
    Xil_Out32(CPU_LINUX_CONSOLE_RING_TOTAL, 0U);
    Xil_Out32(CPU_LINUX_CONSOLE_IN_CHAR, 0U);
    Xil_Out32(CPU_LINUX_CONSOLE_IN_VALID, 0U);
    for (u32 i = 0U; i < (CPU_LINUX_CONSOLE_IN_RING_BYTES / 4U); i++) {
        Xil_Out32(CPU_LINUX_CONSOLE_IN_RING_BASE + i * 4U, 0U);
    }
    Xil_Out32(CPU_LINUX_CONSOLE_IN_RING_HEAD, 0U);
    Xil_Out32(CPU_LINUX_CONSOLE_IN_RING_TAIL, 0U);
}

static void clear_linux_sbi_counters(void)
{
    Xil_Out32(CPU_LINUX_ECALL_COUNT, 0U);
    Xil_Out32(CPU_LINUX_TIME_COUNT, 0U);
    Xil_Out32(CPU_LINUX_BASE_COUNT, 0U);
    Xil_Out32(CPU_LINUX_CONSOLE_PUT_COUNT, 0U);
    Xil_Out32(CPU_LINUX_CONSOLE_GET_COUNT, 0U);
    Xil_Out32(CPU_LINUX_DEBUG_COUNT, 0U);
    Xil_Out32(CPU_LINUX_UNSUPPORTED_COUNT, 0U);
    Xil_Out32(CPU_LINUX_TRAP_COUNT, 0U);
    Xil_Out32(CPU_LINUX_LAST_CHAR, 0xffffffffU);
    Xil_Out32(CPU_LINUX_LAST_TIME_MEPC, 0U);
    Xil_Out32(CPU_LINUX_LAST_CONSOLE_MEPC, 0U);
    Xil_Out32(CPU_LINUX_TIMER_OFFSET_VALID, 0U);
    Xil_Out32(CPU_LINUX_TIMER_OFFSET_LO, 0U);
    Xil_Out32(CPU_LINUX_TIMER_OFFSET_HI, 0U);
    Xil_Out32(CPU_LINUX_TIMER_MTIME_LO, 0U);
    Xil_Out32(CPU_LINUX_TIMER_MTIME_HI, 0U);
    clear_linux_console_mirror();
}

int main(void)
{
    const u32 boot_watchdog_reports = 512U;
    u32 firmware_words = 0U;
    u32 firmware_entry = 0U;
    u32 verify_errors = 0U;
    u32 ps_code0;
    u32 ps_text_lo;
    u32 ps_text_hi;
    u32 ps_magic0;
    u32 ps_magic1;
    u32 ps_magic2;
    u32 ps_dtb_magic;
    u32 scratch_words;
    u32 scratch_bytes;
    u32 ring_offset;
    u32 last_mcause = 0xffffffffU;
    u32 last_mepc = 0xffffffffU;
    u32 last_eid = 0xffffffffU;
    u32 last_fid = 0xffffffffU;
    u32 last_arg0 = 0xffffffffU;
    u32 last_head_marker = 0xffffffffU;
    u32 last_pc = 0xffffffffU;
    u32 last_satp = 0xffffffffU;
    u32 last_ecall_count = 0xffffffffU;
    u32 last_time_count = 0xffffffffU;
    u32 last_base_count = 0xffffffffU;
    u32 last_console_put_count = 0xffffffffU;
    u32 last_console_get_count = 0xffffffffU;
    u32 last_debug_count = 0xffffffffU;
    u32 last_unsupported_count = 0xffffffffU;
    u32 last_trap_count = 0xffffffffU;
    u32 last_console_total = 0U;
    u32 last_probe_dmem = 0U;
    u32 last_probe_imem = 0U;
    u32 report_count = 0U;
    u32 idle_report_count = 0U;
    int linux_console_started = 0;
    int userspace_idle_seen = 0;
    int rc;

    Xil_DCacheDisable();

    xil_printf("\r\n");
    xil_printf("> ZYNQ_CPU Linux boot launcher\r\n");
    xil_printf("Diag rev: linux_bring_up\r\n");

    scratch_words = Xil_In32(ZYNQ_CPU_SCRATCH_WORDS);
    scratch_bytes = scratch_words * 4U;
    ring_offset = CPU_LINUX_CONSOLE_RING_BASE - ZYNQ_CPU_TX_SCRATCH;

    ps_code0 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR);
    ps_text_lo = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 8U);
    ps_text_hi = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 12U);
    ps_magic0 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 48U);
    ps_magic1 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 52U);
    ps_magic2 = Xil_In32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR + 56U);
    ps_dtb_magic = Xil_In32(ZYNQ_CPU_LINUX_DTB_PS_ADDR);

    xil_printf("Kernel PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_KERNEL_PS_ADDR);
    xil_printf("Kernel CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_KERNEL_CPU_ADDR);
    xil_printf("DTB PS: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_DTB_PS_ADDR);
    xil_printf("DTB CPU: 0x%08x\r\n", (unsigned int)ZYNQ_CPU_LINUX_DTB_CPU_ADDR);
    xil_printf("Scratch words: %u\r\n", (unsigned int)scratch_words);
    xil_printf("Console ring: off=0x%08x bytes=%u\r\n",
               (unsigned int)ring_offset,
               (unsigned int)CPU_LINUX_CONSOLE_RING_BYTES);
    xil_printf("PS code0: 0x%08x\r\n", (unsigned int)ps_code0);
    xil_printf("PS text lo: 0x%08x\r\n", (unsigned int)ps_text_lo);
    xil_printf("PS magic0: 0x%08x\r\n", (unsigned int)ps_magic0);
    xil_printf("PS magic1: 0x%08x\r\n", (unsigned int)ps_magic1);
    xil_printf("PS magic2: 0x%08x\r\n", (unsigned int)ps_magic2);
    xil_printf("PS DTB raw: 0x%08x\r\n", (unsigned int)ps_dtb_magic);

    if (ps_code0 != ZYNQ_CPU_LINUX_IMAGE_CODE0 ||
        ps_text_lo != ZYNQ_CPU_LINUX_IMAGE_TEXT_LO ||
        ps_text_hi != 0U ||
        ps_magic0 != ZYNQ_CPU_LINUX_IMAGE_MAGIC0 ||
        ps_magic1 != ZYNQ_CPU_LINUX_IMAGE_MAGIC1 ||
        ps_magic2 != ZYNQ_CPU_LINUX_IMAGE_MAGIC2 ||
        ps_dtb_magic != ZYNQ_CPU_DTB_MAGIC_RAW) {
        xil_printf("Linux boot artifacts missing or at the wrong DDR address\r\n");
        while (1) {
        }
    }

    if (ring_offset > scratch_bytes ||
        CPU_LINUX_CONSOLE_RING_BYTES > (scratch_bytes - ring_offset)) {
        xil_printf("Linux console ring outside TX scratch aperture\r\n");
        while (1) {
        }
    }

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    Xil_Out32(CPU_LINUX_ENTRY, ZYNQ_CPU_LINUX_KERNEL_CPU_ADDR);
    Xil_Out32(CPU_LINUX_DTB, ZYNQ_CPU_LINUX_DTB_CPU_ADDR);
    Xil_Out32(CPU_LINUX_MCAUSE, 0U);
    Xil_Out32(CPU_LINUX_MEPC, 0U);
    Xil_Out32(CPU_LINUX_SBI_EID, 0U);
    Xil_Out32(CPU_LINUX_SBI_FID, 0xffffffffU);
    Xil_Out32(CPU_LINUX_SBI_ARG0, 0U);
    Xil_Out32(CPU_LINUX_SBI_RETVAL, 0xffffffffU);
    Xil_Out32(CPU_LINUX_CMP_LO, 0U);
    Xil_Out32(CPU_LINUX_CMP_HI, 0U);
    Xil_Out32(CPU_LINUX_BASE_VERSION, 0U);
    Xil_Out32(CPU_LINUX_HEAD_MARKER, 0U);
    Xil_Out32(CPU_LINUX_HEAD_A0, 0U);
    Xil_Out32(CPU_LINUX_HEAD_A1, 0U);
    Xil_Out32(CPU_LINUX_HEAD_AMO_OLD, 0xffffffffU);
    Xil_Out32(CPU_LINUX_HEAD_BSS_LO, 0U);
    Xil_Out32(CPU_LINUX_HEAD_BSS_HI, 0U);
    clear_linux_sbi_counters();
    Xil_Out32(CPU_MAIL_STATUS, 0U);

    rc = load_zx32_elf_into_imem(zx32_linux_boot_firmware_elf,
                                 zx32_linux_boot_firmware_elf_size,
                                 &firmware_words,
                                 &firmware_entry);
    if (rc != 0) {
        xil_printf("Linux boot fw ELF rc: %d\r\n", rc);
        while (1) {
        }
    }

    Xil_Out32(ZYNQ_CPU_RESET_VECTOR, firmware_entry);
    for (u32 i = 0U; i < (sizeof(zx32_linux_boot_firmware_program) / sizeof(zx32_linux_boot_firmware_program[0])); i++) {
        if (Xil_In32(ZYNQ_CPU_IMEM_BASE + i * 4U) != zx32_linux_boot_firmware_program[i]) {
            verify_errors++;
        }
    }

    xil_printf("FW words: %u\r\n", (unsigned int)firmware_words);
    xil_printf("FW entry: 0x%08x\r\n", (unsigned int)firmware_entry);
    xil_printf("IMEM verify: %u errors\r\n", (unsigned int)verify_errors);

    if (verify_errors != 0U) {
        while (1) {
        }
    }

    xil_printf("Releasing PL CPU at Linux entry\r\n");
    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 0U);

    while (1) {
        u32 status = Xil_In32(CPU_MAIL_STATUS);
        u32 mcause = Xil_In32(CPU_LINUX_MCAUSE);
        u32 mepc = Xil_In32(CPU_LINUX_MEPC);
        u32 eid = Xil_In32(CPU_LINUX_SBI_EID);
        u32 fid = Xil_In32(CPU_LINUX_SBI_FID);
        u32 arg0 = Xil_In32(CPU_LINUX_SBI_ARG0);
        u32 head_marker = Xil_In32(CPU_LINUX_HEAD_MARKER);
        u32 pc = Xil_In32(ZYNQ_CPU_DBG_PC);
        u32 satp = Xil_In32(ZYNQ_CPU_DBG_SATP);
        u32 ecall_count = Xil_In32(CPU_LINUX_ECALL_COUNT);
        u32 time_count = Xil_In32(CPU_LINUX_TIME_COUNT);
        u32 base_count = Xil_In32(CPU_LINUX_BASE_COUNT);
        u32 console_put_count = Xil_In32(CPU_LINUX_CONSOLE_PUT_COUNT);
        u32 console_get_count = Xil_In32(CPU_LINUX_CONSOLE_GET_COUNT);
        u32 debug_count = Xil_In32(CPU_LINUX_DEBUG_COUNT);
        u32 unsupported_count = Xil_In32(CPU_LINUX_UNSUPPORTED_COUNT);
        u32 trap_count = Xil_In32(CPU_LINUX_TRAP_COUNT);

        pump_linux_console_input();

        if (print_linux_console_mirror(&last_console_total, &linux_console_started) != 0 &&
            userspace_idle_seen == 0) {
            userspace_idle_seen = 1;
            xil_printf("Boot monitor: userspace idle reached\r\n");
            print_linux_sbi_counters();
        }

        {
            int timer_sbi = (mcause == 0x00000009U &&
                             eid == 0x54494D45U &&
                             fid == 0U);
            int console_put_sbi = (mcause == 0x00000009U &&
                                   eid == 1U &&
                                   fid == 0U);
            int console_get_sbi = (mcause == 0x00000009U &&
                                   eid == 2U &&
                                   fid == 0U);
            int noisy_sbi = timer_sbi || console_put_sbi || console_get_sbi;
            int boot_monitor_changed = (mcause != last_mcause ||
                                        mepc != last_mepc ||
                                        eid != last_eid ||
                                        fid != last_fid ||
                                        (!noisy_sbi && arg0 != last_arg0));

            if (ZX32_LINUX_BOOT_TRACE != 0 && boot_monitor_changed && !noisy_sbi) {
                xil_printf("Boot monitor: status=0x%08x mcause=0x%08x mepc=0x%08x eid=0x%08x fid=0x%08x arg0=0x%08x ret=0x%08x val=0x%08x cmp=0x%08x%08x off=0x%08x%08x mtime=0x%08x%08x\r\n",
                           (unsigned int)status,
                           (unsigned int)mcause,
                           (unsigned int)mepc,
                           (unsigned int)eid,
                           (unsigned int)fid,
                           (unsigned int)arg0,
                           (unsigned int)Xil_In32(CPU_LINUX_SBI_RETVAL),
                           (unsigned int)Xil_In32(CPU_LINUX_BASE_VERSION),
                           (unsigned int)Xil_In32(CPU_LINUX_CMP_HI),
                           (unsigned int)Xil_In32(CPU_LINUX_CMP_LO),
                           (unsigned int)Xil_In32(CPU_LINUX_TIMER_OFFSET_HI),
                           (unsigned int)Xil_In32(CPU_LINUX_TIMER_OFFSET_LO),
                           (unsigned int)Xil_In32(CPU_LINUX_TIMER_MTIME_HI),
                           (unsigned int)Xil_In32(CPU_LINUX_TIMER_MTIME_LO));
            }
            last_mcause = mcause;
            last_mepc = mepc;
            last_eid = eid;
            last_fid = fid;
            last_arg0 = arg0;
        }

        if (ZX32_LINUX_BOOT_TRACE != 0 &&
            (last_trap_count == 0xffffffffU ||
             (trap_count - last_trap_count) >= 4096U ||
             base_count != last_base_count ||
             debug_count != last_debug_count ||
             unsupported_count != last_unsupported_count)) {
            print_linux_sbi_counters();
            last_ecall_count = ecall_count;
            last_time_count = time_count;
            last_base_count = base_count;
            last_console_put_count = console_put_count;
            last_console_get_count = console_get_count;
            last_debug_count = debug_count;
            last_unsupported_count = unsupported_count;
            last_trap_count = trap_count;
        }

        if (ZX32_LINUX_BOOT_TRACE != 0 && (last_pc == 0xffffffffU || satp != last_satp)) {
            xil_printf("Boot pc: pc=0x%08x satp=0x%08x scause=0x%08x sepc=0x%08x eid=0x%08x fid=0x%08x arg0=0x%08x\r\n",
                       (unsigned int)pc,
                       (unsigned int)satp,
                       (unsigned int)Xil_In32(ZYNQ_CPU_DBG_SCAUSE),
                       (unsigned int)Xil_In32(ZYNQ_CPU_DBG_SEPC),
                       (unsigned int)eid,
                       (unsigned int)fid,
                       (unsigned int)arg0);
            last_pc = pc;
            last_satp = satp;
        }

        if (ZX32_LINUX_BOOT_TRACE != 0 && head_marker != last_head_marker) {
            u32 head_a0 = Xil_In32(CPU_LINUX_HEAD_A0);
            u32 head_a1 = Xil_In32(CPU_LINUX_HEAD_A1);

            xil_printf("Head marker: mark=0x%08x a0=0x%08x a1=0x%08x amo_old=0x%08x bss=0x%08x..0x%08x\r\n",
                       (unsigned int)head_marker,
                       (unsigned int)head_a0,
                       (unsigned int)head_a1,
                       (unsigned int)Xil_In32(CPU_LINUX_HEAD_AMO_OLD),
                       (unsigned int)Xil_In32(CPU_LINUX_HEAD_BSS_LO),
                       (unsigned int)Xil_In32(CPU_LINUX_HEAD_BSS_HI));
            if (head_marker == 0x4C0DE00AU && head_a0 != 0U && head_a1 != 0U) {
                print_sv32_root_probe("Trampoline", head_a0);
                print_sv32_root_probe("Early", head_a1);
                print_core_debug_probe();
            }
            last_head_marker = head_marker;
        }

        if (status == CPU_STATUS_FAIL) {
            xil_printf("Linux boot firmware trap FAIL\r\n");
            xil_printf("M cause: 0x%08x\r\n", (unsigned int)mcause);
            xil_printf("M epc: 0x%08x\r\n", (unsigned int)mepc);
            xil_printf("Last SBI eid: 0x%08x\r\n", (unsigned int)eid);
            xil_printf("Last SBI fid: 0x%08x\r\n", (unsigned int)fid);
            xil_printf("Last SBI arg0: 0x%08x\r\n", (unsigned int)arg0);
            while (1) {
            }
        }

        if (report_count < boot_watchdog_reports) {
            for (volatile u32 delay = 0U; delay < 200000U; delay++) {
                if ((delay & 0x3ffU) == 0U) {
                    pump_linux_console_input();
                }
            }
            report_count++;
            if (report_count == boot_watchdog_reports) {
                if (ZX32_LINUX_BOOT_TRACE != 0 && userspace_idle_seen != 0) {
                    idle_report_count++;
                    if ((idle_report_count & 0x3U) == 0U) {
                        xil_printf("Boot monitor: userspace idle sample\r\n");
                        print_linux_sbi_counters();
                    }
                } else if (ZX32_LINUX_BOOT_TRACE != 0) {
                    xil_printf("Boot monitor: periodic sample\r\n");
                    print_linux_sbi_counters();
                    print_linux_progress_probe("Progress", &last_probe_dmem, &last_probe_imem);
                    print_core_debug_probe();
                }
                report_count = 0U;
            }
        } else {
            for (volatile u32 delay = 0U; delay < 200000U; delay++) {
                if ((delay & 0x3ffU) == 0U) {
                    pump_linux_console_input();
                }
            }
        }
    }

    return 0;
}
