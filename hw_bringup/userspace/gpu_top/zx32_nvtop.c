#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <termios.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

#include "zx32_gpu_regs.h"

#define HISTORY_LEN 64
#define DEFAULT_INTERVAL_MS 500u

#define C_RESET   "\033[0m"
#define C_CYAN    "\033[36m"
#define C_GREEN   "\033[32m"
#define C_YELLOW  "\033[33m"
#define C_RED     "\033[31m"
#define C_MAGENTA "\033[35m"
#define C_DIM     "\033[2m"

struct gpu_sample {
    uint32_t control;
    uint32_t status;
    uint32_t fb_addr;
    uint32_t fb_stride;
    uint32_t fb_size;
    uint32_t cur_pixel;
    uint32_t wait_count;
    uint32_t pixel_count;
    uint32_t fifo_status;
    uint32_t cmd_done;
    uint32_t total_cycles;
    uint32_t busy_cycles;
    uint32_t stall_cycles;
    uint32_t write_count;
    double t;
};

static volatile sig_atomic_t g_stop;
static struct termios g_saved_termios;
static int g_have_saved_termios;

static void on_signal(int sig) {
    (void)sig;
    g_stop = 1;
}

static void restore_terminal(void) {
    if (g_have_saved_termios) {
        tcsetattr(STDIN_FILENO, TCSANOW, &g_saved_termios);
        g_have_saved_termios = 0;
    }
    printf("\033[?25h" C_RESET "\n");
    fflush(stdout);
}

static void setup_terminal(void) {
    struct termios raw;

    if (!isatty(STDIN_FILENO)) {
        return;
    }
    if (tcgetattr(STDIN_FILENO, &g_saved_termios) != 0) {
        return;
    }
    raw = g_saved_termios;
    raw.c_lflag &= (tcflag_t)~(ICANON | ECHO);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0) {
        g_have_saved_termios = 1;
        atexit(restore_terminal);
    }
}

static int should_quit_from_stdin(void) {
    struct timeval tv = {0, 0};
    fd_set rfds;
    unsigned char ch;

    if (!isatty(STDIN_FILENO)) {
        return 0;
    }
    FD_ZERO(&rfds);
    FD_SET(STDIN_FILENO, &rfds);
    if (select(STDIN_FILENO + 1, &rfds, NULL, NULL, &tv) <= 0) {
        return 0;
    }
    if (read(STDIN_FILENO, &ch, 1) != 1) {
        return 0;
    }
    return ch == 'q' || ch == 'Q';
}

static void usage(const char *prog) {
    fprintf(stderr,
            "usage: %s [--base ADDR] [--interval MS] [--once] [--clear]\n"
            "       %s status\n",
            prog, prog);
}

static uint32_t parse_u32(const char *s, const char *name) {
    char *end = NULL;
    unsigned long value = strtoul(s, &end, 0);
    if (end == s || *end != '\0' || value > UINT32_MAX) {
        fprintf(stderr, "invalid %s: %s\n", name, s);
        exit(2);
    }
    return (uint32_t)value;
}

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static void *map_phys(int fd, unsigned long phys, size_t size, const char *name) {
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        page_size = 4096;
    }

    unsigned long page_mask = (unsigned long)page_size - 1u;
    unsigned long page_base = phys & ~page_mask;
    unsigned long page_off = phys - page_base;
    size_t map_size = page_off + size;

    void *map = mmap(NULL, map_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)page_base);
    if (map == MAP_FAILED) {
        fprintf(stderr, "mmap %s at 0x%08lx failed: %s\n", name, phys, strerror(errno));
        return MAP_FAILED;
    }

    return (uint8_t *)map + page_off;
}

static uint32_t delta_u32(uint32_t now, uint32_t prev) {
    return now - prev;
}

static unsigned pct_from_delta(uint32_t num, uint32_t den) {
    if (den == 0) {
        return 0;
    }
    uint64_t pct = ((uint64_t)num * 100u + den / 2u) / den;
    return pct > 100u ? 100u : (unsigned)pct;
}

static void sample_gpu(volatile uint32_t *regs, struct gpu_sample *s) {
    s->control = zx32_gpu_rd(regs, ZX32_GPU_CONTROL);
    s->status = zx32_gpu_rd(regs, ZX32_GPU_STATUS);
    s->fb_addr = zx32_gpu_rd(regs, ZX32_GPU_FB_ADDR);
    s->fb_stride = zx32_gpu_rd(regs, ZX32_GPU_FB_STRIDE);
    s->fb_size = zx32_gpu_rd(regs, ZX32_GPU_FB_SIZE);
    s->cur_pixel = zx32_gpu_rd(regs, ZX32_GPU_CUR_PIXEL);
    s->wait_count = zx32_gpu_rd(regs, ZX32_GPU_WAIT_COUNT);
    s->pixel_count = zx32_gpu_rd(regs, ZX32_GPU_PIXEL_COUNT);
    s->fifo_status = zx32_gpu_rd(regs, ZX32_GPU_CMD_SUBMIT);
    s->cmd_done = zx32_gpu_rd(regs, ZX32_GPU_CMD_DONE);
    s->total_cycles = zx32_gpu_rd(regs, ZX32_GPU_TOTAL_CYCLES);
    s->busy_cycles = zx32_gpu_rd(regs, ZX32_GPU_BUSY_CYCLES);
    s->stall_cycles = zx32_gpu_rd(regs, ZX32_GPU_STALL_CYCLES);
    s->write_count = zx32_gpu_rd(regs, ZX32_GPU_WRITE_COUNT);
    s->t = now_sec();
}

static int read_meminfo(uint64_t *total_kib, uint64_t *avail_kib) {
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) {
        return -1;
    }

    char key[64];
    char unit[32];
    uint64_t value;
    *total_kib = 0;
    *avail_kib = 0;
    while (fscanf(f, "%63s %" SCNu64 " %31s\n", key, &value, unit) == 3) {
        if (strcmp(key, "MemTotal:") == 0) {
            *total_kib = value;
        } else if (strcmp(key, "MemAvailable:") == 0) {
            *avail_kib = value;
        }
    }
    fclose(f);
    return *total_kib != 0 ? 0 : -1;
}

static void format_mib(uint64_t kib, char *buf, size_t len) {
    snprintf(buf, len, "%" PRIu64 "MiB", kib / 1024u);
}

static void draw_bar(const char *label, unsigned pct, unsigned width, const char *color) {
    unsigned fill = (pct * width + 50u) / 100u;
    printf("%s%-12s" C_RESET " [", color, label);
    for (unsigned i = 0; i < width; i++) {
        putchar(i < fill ? '#' : ' ');
    }
    printf("] %3u%%\n", pct);
}

static void draw_history(const char *title, const unsigned *values, int count, const char *color) {
    const int rows = 10;
    int start = count > HISTORY_LEN ? count - HISTORY_LEN : 0;
    int visible = count - start;
    if (visible <= 0) {
        visible = 1;
    }

    printf("+");
    for (int i = 0; i < HISTORY_LEN; i++) {
        putchar('-');
    }
    printf("+\n");
    for (int row = rows; row >= 0; row--) {
        unsigned threshold = (unsigned)(row * 10);
        printf("|");
        for (int i = 0; i < HISTORY_LEN; i++) {
            unsigned v = 0;
            int sample = start + i - (HISTORY_LEN - visible);
            if (sample >= 0 && sample < count) {
                v = values[sample % HISTORY_LEN];
            }
            if (v >= threshold && threshold != 0) {
                printf("%s#" C_RESET, color);
            } else if (threshold == 0) {
                putchar('_');
            } else {
                putchar(' ');
            }
        }
        printf("| %3u\n", threshold);
    }
    printf("+");
    for (int i = 0; i < HISTORY_LEN; i++) {
        putchar('-');
    }
    printf("+ %s%s%s\n", color, title, C_RESET);
}

static void print_status_once(const struct gpu_sample *s) {
    uint32_t width = s->fb_size & 0xffffu;
    uint32_t height = s->fb_size >> 16;
    uint64_t fb_bytes = (uint64_t)s->fb_stride * height;
    printf("ZX32 GPU status=0x%08" PRIx32 " busy=%u done=%u error=%u\n",
           s->status,
           !!(s->status & ZX32_GPU_STATUS_BUSY),
           !!(s->status & ZX32_GPU_STATUS_DONE),
           !!(s->status & ZX32_GPU_STATUS_ERROR));
    printf("fb=0x%08" PRIx32 " size=%" PRIu32 "x%" PRIu32 " stride=%" PRIu32
           " vram=%" PRIu64 "KiB/%luKiB\n",
           s->fb_addr, width, height, s->fb_stride, fb_bytes / 1024u, ZX32_VRAM_BYTES / 1024u);
    printf("cycles total=%" PRIu32 " busy=%" PRIu32 " stall=%" PRIu32
           " writes=%" PRIu32 " cmd_done=%" PRIu32 "\n",
           s->total_cycles, s->busy_cycles, s->stall_cycles, s->write_count, s->cmd_done);
}

static void draw_screen(const struct gpu_sample *prev,
                        const struct gpu_sample *cur,
                        unsigned *gpu_hist,
                        unsigned *mem_hist,
                        int hist_count) {
    uint32_t total_delta = delta_u32(cur->total_cycles, prev->total_cycles);
    uint32_t busy_delta = delta_u32(cur->busy_cycles, prev->busy_cycles);
    uint32_t stall_delta = delta_u32(cur->stall_cycles, prev->stall_cycles);
    uint32_t write_delta = delta_u32(cur->write_count, prev->write_count);
    double dt = cur->t - prev->t;
    if (dt <= 0.0) {
        dt = 1.0;
    }

    unsigned gpu_pct = pct_from_delta(busy_delta, total_delta);
    unsigned stall_pct = pct_from_delta(stall_delta, busy_delta);
    uint32_t width = cur->fb_size & 0xffffu;
    uint32_t height = cur->fb_size >> 16;
    uint64_t fb_bytes = (uint64_t)cur->fb_stride * height;
    unsigned mem_pct = ZX32_VRAM_BYTES == 0 ? 0 :
        (unsigned)((fb_bytes * 100u + ZX32_VRAM_BYTES / 2u) / ZX32_VRAM_BYTES);
    if (mem_pct > 100u) {
        mem_pct = 100u;
    }
    double writes_per_sec = (double)write_delta / dt;

    gpu_hist[(hist_count - 1) % HISTORY_LEN] = gpu_pct;
    mem_hist[(hist_count - 1) % HISTORY_LEN] = mem_pct;

    uint64_t mem_total = 0;
    uint64_t mem_avail = 0;
    char host_mem[64] = "N/A";
    if (read_meminfo(&mem_total, &mem_avail) == 0) {
        char total_buf[32];
        char used_buf[32];
        uint64_t used = mem_total > mem_avail ? mem_total - mem_avail : 0;
        format_mib(used, used_buf, sizeof(used_buf));
        format_mib(mem_total, total_buf, sizeof(total_buf));
        snprintf(host_mem, sizeof(host_mem), "%s/%s", used_buf, total_buf);
    }

    printf("\033[H\033[2J");
    printf(C_CYAN "Device 0 " C_RESET "[ZX32 fixed-function GPU] "
           C_CYAN "MMIO " C_RESET "0x%08x "
           C_MAGENTA "VRAM " C_RESET "0x%08x..0x%08lx\n",
           (unsigned)ZX32_GPU_BASE_DEFAULT,
           (unsigned)ZX32_VRAM_BASE_DEFAULT,
           ZX32_VRAM_BASE_DEFAULT + ZX32_VRAM_BYTES - 1UL);
    printf(C_CYAN "GPU " C_RESET "%3u%%  "
           C_CYAN "STALL " C_RESET "%3u%%  "
           C_CYAN "CMD " C_RESET "%" PRIu32 "  "
           C_CYAN "WR " C_RESET "%.0f/s  "
           C_CYAN "HOST MEM " C_RESET "%s\n",
           gpu_pct, stall_pct, cur->cmd_done, writes_per_sec, host_mem);
    printf(C_CYAN "FB  " C_RESET "0x%08" PRIx32 " %" PRIu32 "x%" PRIu32
           " stride=%" PRIu32 "  "
           C_CYAN "GPU MEM " C_RESET "%" PRIu64 "KiB/%luKiB  "
           C_CYAN "STATUS " C_RESET "busy=%u done=%u err=%u fifo=%u\n\n",
           cur->fb_addr, width, height, cur->fb_stride,
           fb_bytes / 1024u, ZX32_VRAM_BYTES / 1024u,
           !!(cur->status & ZX32_GPU_STATUS_BUSY),
           !!(cur->status & ZX32_GPU_STATUS_DONE),
           !!(cur->status & ZX32_GPU_STATUS_ERROR),
           (cur->fifo_status >> 5) & 7u);

    draw_bar("GPU0", gpu_pct, 44, C_CYAN);
    draw_bar("GPU0 mem", mem_pct, 44, C_YELLOW);
    draw_bar("DDR stall", stall_pct, 44, stall_pct > 25u ? C_RED : C_GREEN);
    printf("\n");
    draw_history("GPU0 %", gpu_hist, hist_count, C_CYAN);
    draw_history("GPU0 mem%", mem_hist, hist_count, C_YELLOW);
    printf(C_DIM "\nq/Ctrl-C exits. Use --clear to reset perf counters before sampling.\n" C_RESET);
    fflush(stdout);
}

int main(int argc, char **argv) {
    unsigned long gpu_base = ZX32_GPU_BASE_DEFAULT;
    unsigned interval_ms = DEFAULT_INTERVAL_MS;
    int once = 0;
    int clear = 0;
    int status_cmd = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--base") == 0 && i + 1 < argc) {
            gpu_base = parse_u32(argv[++i], "base");
        } else if (strcmp(argv[i], "--interval") == 0 && i + 1 < argc) {
            interval_ms = parse_u32(argv[++i], "interval");
            if (interval_ms == 0) {
                interval_ms = DEFAULT_INTERVAL_MS;
            }
        } else if (strcmp(argv[i], "--once") == 0) {
            once = 1;
        } else if (strcmp(argv[i], "--clear") == 0) {
            clear = 1;
        } else if (strcmp(argv[i], "status") == 0) {
            status_cmd = 1;
            once = 1;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        return 1;
    }
    volatile uint32_t *regs = (volatile uint32_t *)map_phys(fd, gpu_base, ZX32_GPU_SIZE, "gpu");
    close(fd);
    if (regs == MAP_FAILED) {
        return 1;
    }

    if (clear) {
        zx32_gpu_wr(regs, ZX32_GPU_CONTROL, ZX32_GPU_CONTROL_PERF_CLEAR);
    }

    struct gpu_sample prev;
    struct gpu_sample cur;
    sample_gpu(regs, &prev);
    if (status_cmd) {
        print_status_once(&prev);
        return 0;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    unsigned gpu_hist[HISTORY_LEN] = {0};
    unsigned mem_hist[HISTORY_LEN] = {0};
    int hist_count = 0;

    if (!once) {
        setup_terminal();
        printf("\033[?25l");
    }

    do {
        usleep(interval_ms * 1000u);
        sample_gpu(regs, &cur);
        hist_count++;
        draw_screen(&prev, &cur, gpu_hist, mem_hist, hist_count);
        prev = cur;
        if (should_quit_from_stdin()) {
            g_stop = 1;
        }
    } while (!once && !g_stop);

    if (!once) {
        restore_terminal();
    }
    return 0;
}
