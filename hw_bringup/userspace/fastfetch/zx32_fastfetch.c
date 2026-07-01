#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

#include "zx32_gpu_regs.h"
#include "zx32_sysmon.h"

#define C_RESET   "\033[0m"
#define C_CYAN    "\033[36m"
#define C_GREEN   "\033[32m"
#define C_YELLOW  "\033[33m"
#define C_MAGENTA "\033[35m"

struct gpu_sample {
    uint32_t status;
    uint32_t fb_addr;
    uint32_t fb_stride;
    uint32_t fb_size;
    uint32_t total_cycles;
    uint32_t busy_cycles;
};

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

static void sample_gpu(volatile uint32_t *regs, struct gpu_sample *s) {
    s->status = zx32_gpu_rd(regs, ZX32_GPU_STATUS);
    s->fb_addr = zx32_gpu_rd(regs, ZX32_GPU_FB_ADDR);
    s->fb_stride = zx32_gpu_rd(regs, ZX32_GPU_FB_STRIDE);
    s->fb_size = zx32_gpu_rd(regs, ZX32_GPU_FB_SIZE);
    s->total_cycles = zx32_gpu_rd(regs, ZX32_GPU_TOTAL_CYCLES);
    s->busy_cycles = zx32_gpu_rd(regs, ZX32_GPU_BUSY_CYCLES);
}

static unsigned pct_from_delta(uint32_t num, uint32_t den) {
    if (den == 0) {
        return 0;
    }
    uint64_t pct = ((uint64_t)num * 100u + den / 2u) / den;
    return pct > 100u ? 100u : (unsigned)pct;
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

static void print_uptime(void) {
    FILE *f = fopen("/proc/uptime", "r");
    double uptime = 0.0;
    if (f) {
        if (fscanf(f, "%lf", &uptime) != 1) {
            uptime = 0.0;
        }
        fclose(f);
    }
    unsigned total = (unsigned)uptime;
    printf(C_CYAN "Uptime: " C_RESET "%ud %02uh %02um %02us\n",
           total / 86400u, (total / 3600u) % 24u, (total / 60u) % 60u, total % 60u);
}

static void print_kernel(void) {
    struct utsname uts;
    if (uname(&uts) == 0) {
        printf(C_CYAN "Kernel: " C_RESET "%s %s %s\n", uts.sysname, uts.release, uts.machine);
    } else {
        printf(C_CYAN "Kernel: " C_RESET "unknown\n");
    }
}

static void print_memory(void) {
    uint64_t total = 0;
    uint64_t avail = 0;
    if (read_meminfo(&total, &avail) == 0) {
        uint64_t used = total > avail ? total - avail : 0;
        unsigned pct = total == 0 ? 0 : (unsigned)((used * 100u + total / 2u) / total);
        printf(C_CYAN "Memory: " C_RESET "%" PRIu64 "MiB / %" PRIu64 "MiB (%u%%)\n",
               used / 1024u, total / 1024u, pct);
    } else {
        printf(C_CYAN "Memory: " C_RESET "N/A\n");
    }
}

static void print_gpu(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        printf(C_CYAN "GPU: " C_RESET "ZX32 fixed-function GPU (/dev/mem unavailable: %s)\n",
               strerror(errno));
        return;
    }

    volatile uint32_t *regs = (volatile uint32_t *)map_phys(fd, ZX32_GPU_BASE_DEFAULT,
                                                            ZX32_GPU_SIZE, "gpu");
    close(fd);
    if (regs == MAP_FAILED) {
        printf(C_CYAN "GPU: " C_RESET "ZX32 fixed-function GPU (MMIO map failed)\n");
        return;
    }

    struct gpu_sample a;
    struct gpu_sample b;
    double t0 = now_sec();
    sample_gpu(regs, &a);
    usleep(100000);
    sample_gpu(regs, &b);
    double dt = now_sec() - t0;
    if (dt <= 0.0) {
        dt = 0.1;
    }

    unsigned util = pct_from_delta(b.busy_cycles - a.busy_cycles,
                                   b.total_cycles - a.total_cycles);
    uint32_t width = b.fb_size & 0xffffu;
    uint32_t height = b.fb_size >> 16;
    uint64_t fb_bytes = (uint64_t)b.fb_stride * height;
    unsigned mem_pct = (unsigned)((fb_bytes * 100u + ZX32_VRAM_BYTES / 2u) / ZX32_VRAM_BYTES);
    if (mem_pct > 100u) {
        mem_pct = 100u;
    }

    printf(C_CYAN "GPU: " C_RESET "ZX32 fixed-function renderer @ 0x%08x\n",
           (unsigned)ZX32_GPU_BASE_DEFAULT);
    printf(C_CYAN "GPU Load: " C_RESET "%u%%  status busy=%u done=%u error=%u\n",
           util,
           !!(b.status & ZX32_GPU_STATUS_BUSY),
           !!(b.status & ZX32_GPU_STATUS_DONE),
           !!(b.status & ZX32_GPU_STATUS_ERROR));
    printf(C_CYAN "VRAM: " C_RESET "%" PRIu64 "KiB / %luKiB (%u%%), fb=0x%08" PRIx32
           " %" PRIu32 "x%" PRIu32 "\n",
           fb_bytes / 1024u, ZX32_VRAM_BYTES / 1024u, mem_pct,
           b.fb_addr, width, height);
}

static void print_zynq_temp(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        printf(C_CYAN "Zynq Temp: " C_RESET "N/A (/dev/mem unavailable: %s)\n",
               strerror(errno));
        return;
    }

    volatile uint32_t *regs = (volatile uint32_t *)map_phys(fd, ZX32_CTRL_BASE_DEFAULT,
                                                            ZX32_CTRL_SIZE, "zx32-ctrl");
    close(fd);
    if (regs == MAP_FAILED) {
        printf(C_CYAN "Zynq Temp: " C_RESET "N/A (MMIO map failed)\n");
        return;
    }

    struct zx32_sysmon_sample s;
    zx32_sysmon_sample(regs, &s);
    if (!zx32_sysmon_temp_valid(&s)) {
        printf(C_CYAN "Zynq Temp: " C_RESET "N/A status=0x%08" PRIx32 "\n", s.status);
        return;
    }

    int32_t mc = s.temp_millic;
    const char *sign = "";
    if (mc < 0) {
        sign = "-";
        mc = -mc;
    }
    printf(C_CYAN "Zynq Temp: " C_RESET "%s%" PRId32 ".%03" PRId32 " C raw=0x%04" PRIx32 "\n",
           sign, mc / 1000, mc % 1000, s.temp_raw & 0xffffu);
}

int main(void) {
    printf(C_GREEN "        ____  __  _____ ___\n");
    printf("       /_  / / / / / _ \\__ \\\n");
    printf("        / /_/ /_/ / // /_/ /\n");
    printf("       /___/\\____/____/____/\n" C_RESET);
    printf(C_MAGENTA "       ZYNQ CPU / ZX32 Linux\n\n" C_RESET);

    printf(C_CYAN "OS: " C_RESET "Buildroot BusyBox initramfs\n");
    print_kernel();
    print_uptime();
    print_memory();
    print_zynq_temp();
    print_gpu();
    printf(C_CYAN "Display: " C_RESET "HDMI text console / 1080p60 timing\n");
    printf(C_CYAN "Tools: " C_RESET "zx32_fastfetch, zx32_nvtop, zx32_gpu_smoke\n");
    return 0;
}
