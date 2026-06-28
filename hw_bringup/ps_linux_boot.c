#include "ps_uart_probe.h"

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "bspconfig.h"
#include "xuartps_hw.h"
#include "ps_font8x16_cascadia.h"
#include "zx32_programs.h"

#ifndef ZX32_LINUX_BOOT_TRACE
#define ZX32_LINUX_BOOT_TRACE 0
#endif

#define ZYNQ_SLCR_UNLOCK      0xF8000008U
#define ZYNQ_SLCR_LOCK        0xF8000004U
#define ZYNQ_SLCR_FPGA_RST_CTRL 0xF8000240U
#define ZYNQ_SLCR_UNLOCK_KEY  0x0000DF0DU
#define ZYNQ_SLCR_LOCK_KEY    0x0000767BU
#define ZYNQ_CPU_BOOT_BACKUP_PS_ADDR 0x04100000U
#define ZYNQ_CPU_BOOT_BLOB_BYTES     0x01300000U

static u32 cpu_ddr_to_ps_addr(u32 cpu_addr)
{
    return cpu_addr - ZYNQ_CPU_DDR_CPU_BASE + ZYNQ_CPU_DDR_PHYS_BASE;
}

static void copy_words_32(u32 dst, u32 src, u32 bytes)
{
    for (u32 off = 0U; off < bytes; off += 4U) {
        Xil_Out32(dst + off, Xil_In32(src + off));
    }
}

static u64 boot_elapsed_ms(XTime start, XTime now)
{
    u64 delta = (u64)(now - start);

    return (delta * 1000ULL) / (u64)COUNTS_PER_SECOND;
}

static void print_boot_elapsed(const char *label, XTime start, XTime now)
{
    u64 ms = boot_elapsed_ms(start, now);

    xil_printf("[zx32-boot] %s elapsed=%u.%03us\r\n",
               label,
               (unsigned int)(ms / 1000ULL),
               (unsigned int)(ms % 1000ULL));
}

static void pulse_pl_reset(void)
{
    Xil_Out32(ZYNQ_SLCR_UNLOCK, ZYNQ_SLCR_UNLOCK_KEY);
    Xil_Out32(ZYNQ_SLCR_FPGA_RST_CTRL, 0x0000000FU);
    for (volatile u32 delay = 0U; delay < 10000U; delay++) {
    }
    Xil_Out32(ZYNQ_SLCR_FPGA_RST_CTRL, 0x00000000U);
    for (volatile u32 delay = 0U; delay < 10000U; delay++) {
    }
    Xil_Out32(ZYNQ_SLCR_LOCK, ZYNQ_SLCR_LOCK_KEY);
}

static const char *linux_loglevel_color(u32 level)
{
    switch (level) {
    case 0U:
    case 1U:
    case 2U:
    case 3U:
        return "\x1b[31m";
    case 4U:
        return "\x1b[33m";
    case 5U:
        return "\x1b[35m";
    case 6U:
        return "\x1b[36m";
    case 7U:
        return "\x1b[90m";
    default:
        return "";
    }
}

static u8 hdmi_text_shadow[ZYNQ_CPU_DISPLAY_TEXT_CELLS];
static u32 hdmi_text_row;
static u32 hdmi_text_col;
typedef enum {
    HDMI_ESC_NONE = 0,
    HDMI_ESC_ESC,
    HDMI_ESC_CSI,
} hdmi_esc_state_t;

static hdmi_esc_state_t hdmi_esc_state;
static u32 hdmi_csi_params[4];
static u32 hdmi_csi_param_count;
static u32 hdmi_csi_value;
static int hdmi_csi_have_value;

static void hdmi_console_write_word(u32 word_index)
{
    u32 cell = word_index * 4U;
    u32 word = 0U;

    for (u32 i = 0U; i < 4U; i++) {
        word |= ((u32)hdmi_text_shadow[cell + i]) << (i * 8U);
    }
    Xil_Out32(ZYNQ_CPU_DISPLAY_TEXT_BASE + cell, word);
}

static void hdmi_console_repaint(void)
{
    for (u32 word = 0U; word < (ZYNQ_CPU_DISPLAY_TEXT_CELLS / 4U); word++) {
        hdmi_console_write_word(word);
    }
}

static void hdmi_console_clear_shadow(void)
{
    for (u32 i = 0U; i < ZYNQ_CPU_DISPLAY_TEXT_CELLS; i++) {
        hdmi_text_shadow[i] = ' ';
    }
    hdmi_text_row = 0U;
    hdmi_text_col = 0U;
    hdmi_esc_state = HDMI_ESC_NONE;
}

static void hdmi_console_upload_font(void)
{
    for (u32 word = 0U; word < ZX32_CONSOLE_FONT8X16_WORDS; word++) {
        Xil_Out32(ZYNQ_CPU_DISPLAY_FONT_BASE + (word * 4U),
                  zx32_console_font8x16_words[word]);
    }
}

static void hdmi_console_scroll(void)
{
    for (u32 row = 1U; row < ZYNQ_CPU_DISPLAY_TEXT_ROWS; row++) {
        for (u32 col = 0U; col < ZYNQ_CPU_DISPLAY_TEXT_COLS; col++) {
            hdmi_text_shadow[(row - 1U) * ZYNQ_CPU_DISPLAY_TEXT_COLS + col] =
                hdmi_text_shadow[row * ZYNQ_CPU_DISPLAY_TEXT_COLS + col];
        }
    }
    for (u32 col = 0U; col < ZYNQ_CPU_DISPLAY_TEXT_COLS; col++) {
        hdmi_text_shadow[(ZYNQ_CPU_DISPLAY_TEXT_ROWS - 1U) * ZYNQ_CPU_DISPLAY_TEXT_COLS + col] = ' ';
    }
    hdmi_text_row = ZYNQ_CPU_DISPLAY_TEXT_ROWS - 1U;
    hdmi_text_col = 0U;
    hdmi_console_repaint();
}

static void hdmi_console_newline(void)
{
    hdmi_text_col = 0U;
    hdmi_text_row++;
    if (hdmi_text_row >= ZYNQ_CPU_DISPLAY_TEXT_ROWS) {
        hdmi_console_scroll();
    }
}

static void hdmi_console_put_cell(u32 row, u32 col, u8 ch)
{
    u32 cell = row * ZYNQ_CPU_DISPLAY_TEXT_COLS + col;

    hdmi_text_shadow[cell] = ch;
    hdmi_console_write_word(cell >> 2);
}

static u32 hdmi_console_cell(u32 row, u32 col)
{
    return row * ZYNQ_CPU_DISPLAY_TEXT_COLS + col;
}

static void hdmi_console_clear_cell_range(u32 start_cell, u32 end_cell)
{
    u32 start_word;
    u32 end_word;

    if (start_cell >= ZYNQ_CPU_DISPLAY_TEXT_CELLS) {
        return;
    }
    if (end_cell > ZYNQ_CPU_DISPLAY_TEXT_CELLS) {
        end_cell = ZYNQ_CPU_DISPLAY_TEXT_CELLS;
    }
    if (start_cell >= end_cell) {
        return;
    }

    for (u32 cell = start_cell; cell < end_cell; cell++) {
        hdmi_text_shadow[cell] = ' ';
    }

    start_word = start_cell >> 2;
    end_word = (end_cell - 1U) >> 2;
    for (u32 word = start_word; word <= end_word; word++) {
        hdmi_console_write_word(word);
    }
}

static void hdmi_console_set_cursor(u32 row, u32 col)
{
    if (row >= ZYNQ_CPU_DISPLAY_TEXT_ROWS) {
        row = ZYNQ_CPU_DISPLAY_TEXT_ROWS - 1U;
    }
    if (col >= ZYNQ_CPU_DISPLAY_TEXT_COLS) {
        col = ZYNQ_CPU_DISPLAY_TEXT_COLS - 1U;
    }
    hdmi_text_row = row;
    hdmi_text_col = col;
}

static u32 hdmi_csi_param_or(u32 index, u32 default_value)
{
    if (index >= hdmi_csi_param_count) {
        return default_value;
    }
    if (hdmi_csi_params[index] == 0U) {
        return default_value;
    }
    return hdmi_csi_params[index];
}

static void hdmi_csi_push_param(void)
{
    if (hdmi_csi_param_count < 4U) {
        hdmi_csi_params[hdmi_csi_param_count] =
            hdmi_csi_have_value ? hdmi_csi_value : 0U;
        hdmi_csi_param_count++;
    }
    hdmi_csi_value = 0U;
    hdmi_csi_have_value = 0;
}

static void hdmi_csi_reset(void)
{
    for (u32 i = 0U; i < 4U; i++) {
        hdmi_csi_params[i] = 0U;
    }
    hdmi_csi_param_count = 0U;
    hdmi_csi_value = 0U;
    hdmi_csi_have_value = 0;
}

static void hdmi_console_apply_csi(u32 final_ch)
{
    u32 p0 = (hdmi_csi_param_count > 0U) ? hdmi_csi_params[0] : 0U;
    u32 start;
    u32 end;
    u32 n;

    switch (final_ch) {
    case 'J':
        if (p0 == 2U || p0 == 3U) {
            hdmi_console_clear_shadow();
            hdmi_console_repaint();
        } else if (p0 == 1U) {
            end = hdmi_console_cell(hdmi_text_row, hdmi_text_col) + 1U;
            hdmi_console_clear_cell_range(0U, end);
        } else {
            start = hdmi_console_cell(hdmi_text_row, hdmi_text_col);
            hdmi_console_clear_cell_range(start, ZYNQ_CPU_DISPLAY_TEXT_CELLS);
        }
        break;
    case 'K':
        if (p0 == 2U) {
            start = hdmi_console_cell(hdmi_text_row, 0U);
            end = start + ZYNQ_CPU_DISPLAY_TEXT_COLS;
        } else if (p0 == 1U) {
            start = hdmi_console_cell(hdmi_text_row, 0U);
            end = hdmi_console_cell(hdmi_text_row, hdmi_text_col) + 1U;
        } else {
            start = hdmi_console_cell(hdmi_text_row, hdmi_text_col);
            end = hdmi_console_cell(hdmi_text_row, ZYNQ_CPU_DISPLAY_TEXT_COLS - 1U) + 1U;
        }
        hdmi_console_clear_cell_range(start, end);
        break;
    case 'H':
    case 'f':
        hdmi_console_set_cursor(hdmi_csi_param_or(0U, 1U) - 1U,
                                hdmi_csi_param_or(1U, 1U) - 1U);
        break;
    case 'G':
        hdmi_console_set_cursor(hdmi_text_row, hdmi_csi_param_or(0U, 1U) - 1U);
        break;
    case 'A':
        n = hdmi_csi_param_or(0U, 1U);
        hdmi_text_row = (n > hdmi_text_row) ? 0U : (hdmi_text_row - n);
        break;
    case 'B':
        n = hdmi_csi_param_or(0U, 1U);
        hdmi_console_set_cursor(hdmi_text_row + n, hdmi_text_col);
        break;
    case 'C':
        n = hdmi_csi_param_or(0U, 1U);
        hdmi_console_set_cursor(hdmi_text_row, hdmi_text_col + n);
        break;
    case 'D':
        n = hdmi_csi_param_or(0U, 1U);
        hdmi_text_col = (n > hdmi_text_col) ? 0U : (hdmi_text_col - n);
        break;
    case 'm':
        break;
    default:
        break;
    }
}

static int hdmi_console_consume_ansi(u32 ch)
{
    if (hdmi_esc_state == HDMI_ESC_NONE) {
        if (ch == 0x1bU) {
            hdmi_esc_state = HDMI_ESC_ESC;
            return 1;
        }
        return 0;
    }

    if (hdmi_esc_state == HDMI_ESC_ESC) {
        if (ch == '[') {
            hdmi_csi_reset();
            hdmi_esc_state = HDMI_ESC_CSI;
        } else if (ch == 0x1bU) {
            hdmi_esc_state = HDMI_ESC_ESC;
        } else {
            hdmi_esc_state = HDMI_ESC_NONE;
        }
        return 1;
    }

    if (ch >= '0' && ch <= '9') {
        hdmi_csi_value = hdmi_csi_value * 10U + (ch - '0');
        hdmi_csi_have_value = 1;
        return 1;
    }
    if (ch == ';') {
        hdmi_csi_push_param();
        return 1;
    }
    if (ch == '?' || ch == ' ' || ch == '=') {
        return 1;
    }
    if (ch >= 0x40U && ch <= 0x7eU) {
        if (hdmi_csi_have_value || hdmi_csi_param_count == 0U) {
            hdmi_csi_push_param();
        }
        hdmi_console_apply_csi(ch);
        hdmi_esc_state = HDMI_ESC_NONE;
        return 1;
    }

    hdmi_esc_state = HDMI_ESC_NONE;
    return 1;
}

static void hdmi_console_putc(u32 ch)
{
    if (hdmi_console_consume_ansi(ch)) {
        return;
    }
    if (ch == '\r') {
        hdmi_text_col = 0U;
        return;
    }
    if (ch == '\n') {
        hdmi_console_newline();
        return;
    }
    if (ch == '\t') {
        do {
            hdmi_console_putc(' ');
        } while ((hdmi_text_col & 7U) != 0U);
        return;
    }
    if (ch == 8U || ch == 127U) {
        if (hdmi_text_col > 0U) {
            hdmi_text_col--;
            hdmi_console_put_cell(hdmi_text_row, hdmi_text_col, ' ');
        }
        return;
    }
    if (ch < 32U || ch > 126U) {
        ch = '.';
    }

    hdmi_console_put_cell(hdmi_text_row, hdmi_text_col, (u8)ch);
    hdmi_text_col++;
    if (hdmi_text_col >= ZYNQ_CPU_DISPLAY_TEXT_COLS) {
        hdmi_console_newline();
    }
}

static void hdmi_console_puts(const char *s)
{
    while (*s != '\0') {
        hdmi_console_putc((u8)*s);
        s++;
    }
}

static void hdmi_console_init(void)
{
    hdmi_console_clear_shadow();
    Xil_Out32(ZYNQ_CPU_DISPLAY_MODE, 2U);
    Xil_Out32(ZYNQ_CPU_DISPLAY_BG, 0x00000000U);
    hdmi_console_upload_font();
    Xil_Out32(ZYNQ_CPU_DISPLAY_TEXT_CTRL,
              ZYNQ_CPU_DISPLAY_TEXT_ENABLE | ZYNQ_CPU_DISPLAY_TEXT_CLEAR);
    for (volatile u32 delay = 0U; delay < 10000U; delay++) {
    }
    hdmi_console_repaint();
    Xil_Out32(ZYNQ_CPU_DISPLAY_CONTROL, ZYNQ_CPU_DISPLAY_CONTROL_ENABLE);
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

static u32 print_linux_console_mirror(u32 *last_total, int *started)
{
    static const char idle_marker[] = "[zx32-init] idle";
    static const char welcome_marker[] = "Welcome to Buildroot";
    static const char login_marker[] = "buildroot login:";
    static u32 idle_match = 0U;
    static u32 welcome_match = 0U;
    static u32 login_match = 0U;
    static int at_line_start = 1;
    static int colored_line = 0;
    static u32 loglevel_match = 0U;
    u32 total = Xil_In32(CPU_LINUX_CONSOLE_RING_TOTAL);
    u32 events = 0U;

    if (total == *last_total) {
        return 0;
    }

    if (*started == 0) {
        xil_printf("\r\nLinux SBI console mirror\r\n");
        hdmi_console_puts("\nLinux SBI console mirror\n");
        *started = 1;
    }

    if ((total - *last_total) > CPU_LINUX_CONSOLE_RING_BYTES) {
        u32 skipped = (total - *last_total) - CPU_LINUX_CONSOLE_RING_BYTES;
        *last_total = total - CPU_LINUX_CONSOLE_RING_BYTES;
        xil_printf("\r\n[linux console skipped %u chars]\r\n", (unsigned int)skipped);
        hdmi_console_puts("\n[linux console skipped]\n");
    }

    while (*last_total != total) {
        u32 idx = *last_total & (CPU_LINUX_CONSOLE_RING_BYTES - 1U);
        u32 word = Xil_In32(CPU_LINUX_CONSOLE_RING_BASE + (idx & ~3U));
        u32 ch = (word >> ((idx & 3U) * 8U)) & 0xffU;

        if (ch == '\n') {
            if (colored_line != 0) {
                xil_printf("\x1b[0m");
                colored_line = 0;
            }
            xil_printf("\r\n");
            hdmi_console_putc(ch);
            at_line_start = 1;
            loglevel_match = 0U;
        } else if (ch != '\r') {
            if (loglevel_match == 1U) {
                if (ch >= '0' && ch <= '7') {
                    xil_printf("%s", linux_loglevel_color(ch - '0'));
                    colored_line = 1;
                    loglevel_match = 2U;
                } else {
                    at_line_start = 0;
                    loglevel_match = 0U;
                }
            } else if (loglevel_match == 2U) {
                if (ch == '>') {
                    at_line_start = 0;
                }
                loglevel_match = 0U;
            } else if (at_line_start != 0) {
                if (ch == '<') {
                    loglevel_match = 1U;
                } else {
                    at_line_start = 0;
                }
            }
            xil_printf("%c", (char)ch);
            hdmi_console_putc(ch);
        }

        if (ch == (u32)idle_marker[idle_match]) {
            idle_match++;
            if (idle_match == (sizeof(idle_marker) - 1U)) {
                events |= 1U;
                idle_match = 0U;
            }
        } else {
            idle_match = (ch == (u32)idle_marker[0]) ? 1U : 0U;
        }

        if (ch == (u32)welcome_marker[welcome_match]) {
            welcome_match++;
            if (welcome_match == (sizeof(welcome_marker) - 1U)) {
                events |= 2U;
                welcome_match = 0U;
            }
        } else {
            welcome_match = (ch == (u32)welcome_marker[0]) ? 1U : 0U;
        }

        if (ch == (u32)login_marker[login_match]) {
            login_match++;
            if (login_match == (sizeof(login_marker) - 1U)) {
                events |= 4U;
                login_match = 0U;
            }
        } else {
            login_match = (ch == (u32)login_marker[0]) ? 1U : 0U;
        }

        (*last_total)++;
        Xil_Out32(CPU_LINUX_CONSOLE_RING_HEAD, *last_total);
    }

    return events;
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
    u32 boot_count = 0U;
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
    int welcome_seen = 0;
    int login_seen = 0;
    int boot_artifacts_backed_up = 0;
    XTime boot_start_time;
    int rc;

    Xil_DCacheDisable();

restart_linux_boot:
    boot_count++;
    firmware_words = 0U;
    firmware_entry = 0U;
    verify_errors = 0U;
    last_mcause = 0xffffffffU;
    last_mepc = 0xffffffffU;
    last_eid = 0xffffffffU;
    last_fid = 0xffffffffU;
    last_arg0 = 0xffffffffU;
    last_head_marker = 0xffffffffU;
    last_pc = 0xffffffffU;
    last_satp = 0xffffffffU;
    last_ecall_count = 0xffffffffU;
    last_time_count = 0xffffffffU;
    last_base_count = 0xffffffffU;
    last_console_put_count = 0xffffffffU;
    last_console_get_count = 0xffffffffU;
    last_debug_count = 0xffffffffU;
    last_unsupported_count = 0xffffffffU;
    last_trap_count = 0xffffffffU;
    last_console_total = 0U;
    last_probe_dmem = 0U;
    last_probe_imem = 0U;
    report_count = 0U;
    idle_report_count = 0U;
    linux_console_started = 0;
    userspace_idle_seen = 0;
    welcome_seen = 0;
    login_seen = 0;

    Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
    XTime_GetTime(&boot_start_time);

    hdmi_console_init();
    hdmi_console_puts("ZYNQ_CPU Linux boot launcher\n");

    xil_printf("\r\n");
    xil_printf("> ZYNQ_CPU Linux boot launcher\r\n");
    xil_printf("Diag rev: linux_bring_up\r\n");
    xil_printf("Boot count: %u\r\n", (unsigned int)boot_count);

    if (boot_artifacts_backed_up != 0) {
        copy_words_32(ZYNQ_CPU_LINUX_KERNEL_PS_ADDR,
                      ZYNQ_CPU_BOOT_BACKUP_PS_ADDR,
                      ZYNQ_CPU_BOOT_BLOB_BYTES);
        xil_printf("Boot artifacts restored from PS 0x%08x bytes=0x%08x\r\n",
                   (unsigned int)ZYNQ_CPU_BOOT_BACKUP_PS_ADDR,
                   (unsigned int)ZYNQ_CPU_BOOT_BLOB_BYTES);
    }

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

    if (boot_artifacts_backed_up == 0) {
        copy_words_32(ZYNQ_CPU_BOOT_BACKUP_PS_ADDR,
                      ZYNQ_CPU_LINUX_KERNEL_PS_ADDR,
                      ZYNQ_CPU_BOOT_BLOB_BYTES);
        boot_artifacts_backed_up = 1;
        xil_printf("Boot artifacts backed up to PS 0x%08x bytes=0x%08x\r\n",
                   (unsigned int)ZYNQ_CPU_BOOT_BACKUP_PS_ADDR,
                   (unsigned int)ZYNQ_CPU_BOOT_BLOB_BYTES);
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
    Xil_Out32(CPU_LINUX_RESET_TYPE, 0U);
    Xil_Out32(CPU_LINUX_RESET_REASON, 0U);
    Xil_Out32(CPU_LINUX_RESET_MAGIC, 0U);
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

        {
            u32 console_events = print_linux_console_mirror(&last_console_total, &linux_console_started);

            if ((console_events & 2U) != 0U && welcome_seen == 0) {
                XTime now;

                welcome_seen = 1;
                XTime_GetTime(&now);
                xil_printf("\r\n");
                print_boot_elapsed("Welcome to Buildroot", boot_start_time, now);
            }
            if ((console_events & 4U) != 0U && login_seen == 0) {
                XTime now;

                login_seen = 1;
                XTime_GetTime(&now);
                xil_printf("\r\n");
                print_boot_elapsed("buildroot login", boot_start_time, now);
            }
            if ((console_events & 1U) != 0U && userspace_idle_seen == 0) {
                userspace_idle_seen = 1;
                xil_printf("Boot monitor: userspace idle reached\r\n");
                print_linux_sbi_counters();
            }
        }

        if (Xil_In32(CPU_LINUX_RESET_MAGIC) == CPU_LINUX_RESET_MAGIC_VALUE) {
            XTime now;

            XTime_GetTime(&now);
            print_boot_elapsed("Linux reboot requested", boot_start_time, now);
            xil_printf("Boot monitor: SBI system reset type=0x%08x reason=0x%08x\r\n",
                       (unsigned int)Xil_In32(CPU_LINUX_RESET_TYPE),
                       (unsigned int)Xil_In32(CPU_LINUX_RESET_REASON));
            Xil_Out32(ZYNQ_CPU_CPU_CTRL, 1U);
            pulse_pl_reset();
            goto restart_linux_boot;
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
