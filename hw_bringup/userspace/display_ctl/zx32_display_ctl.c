#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define DISPLAY_BASE_DEFAULT 0x10080000UL
#define DISPLAY_SIZE         0x1000UL

#define DISP_CONTROL         0x00u
#define DISP_STATUS          0x04u
#define DISP_FB_ADDR         0x08u
#define DISP_FB_STRIDE       0x0cu
#define DISP_FB_SIZE         0x10u
#define DISP_MODE            0x14u
#define DISP_BG_COLOR        0x18u
#define DISP_UNDERFLOW_COUNT 0x1cu
#define DISP_SCAN_POS        0x20u

#define CONTROL_ENABLE       (1u << 0)
#define CONTROL_RESET        (1u << 1)
#define CONTROL_TEST_PATTERN (1u << 2)

static volatile uint32_t *g_regs;

static void usage(const char *prog) {
    fprintf(stderr,
            "usage: %s [--base ADDR] status\n"
            "       %s [--base ADDR] enable [--fb ADDR] [--stride BYTES] [--size WxH] [--mode 0|1|2] [--bg COLOR] [--no-test]\n"
            "       %s [--base ADDR] disable\n"
            "       %s [--base ADDR] mode 0|1|2\n"
            "       %s [--base ADDR] bg COLOR\n",
            prog, prog, prog, prog, prog);
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

static void parse_size(const char *s, uint16_t *width, uint16_t *height) {
    char *end = NULL;
    unsigned long w = strtoul(s, &end, 0);
    if (end == s || (*end != 'x' && *end != 'X')) {
        fprintf(stderr, "invalid size: %s\n", s);
        exit(2);
    }
    const char *hstr = end + 1;
    unsigned long h = strtoul(hstr, &end, 0);
    if (end == hstr || *end != '\0' || w == 0 || h == 0 || w > UINT16_MAX || h > UINT16_MAX) {
        fprintf(stderr, "invalid size: %s\n", s);
        exit(2);
    }
    *width = (uint16_t)w;
    *height = (uint16_t)h;
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

static uint32_t rd(uint32_t off) {
    return g_regs[off >> 2];
}

static void wr(uint32_t off, uint32_t value) {
    g_regs[off >> 2] = value;
    __asm__ __volatile__("" ::: "memory");
}

static void print_status(void) {
    uint32_t control = rd(DISP_CONTROL);
    uint32_t status = rd(DISP_STATUS);
    uint32_t fb_addr = rd(DISP_FB_ADDR);
    uint32_t stride = rd(DISP_FB_STRIDE);
    uint32_t size = rd(DISP_FB_SIZE);
    uint32_t mode = rd(DISP_MODE);
    uint32_t bg = rd(DISP_BG_COLOR);
    uint32_t underflow = rd(DISP_UNDERFLOW_COUNT);
    uint32_t scan = rd(DISP_SCAN_POS);

    printf("control=0x%08" PRIx32 " enable=%u test_pattern=%u\n",
           control, !!(control & CONTROL_ENABLE), !!(control & CONTROL_TEST_PATTERN));
    printf("status=0x%08" PRIx32 " enabled=%u locked=%u hpd=%u underflow=%u frame_done=%u\n",
           status, !!(status & (1u << 0)), !!(status & (1u << 1)), !!(status & (1u << 2)),
           !!(status & (1u << 3)), !!(status & (1u << 4)));
    printf("fb=0x%08" PRIx32 " stride=%" PRIu32 " size=%" PRIu32 "x%" PRIu32
           " mode=%" PRIu32 " bg=0x%08" PRIx32 "\n",
           fb_addr, stride, size & 0xffffu, size >> 16, mode & 3u, bg);
    printf("underflow_count=%" PRIu32 " scan=%" PRIu32 ",%" PRIu32 "\n",
           underflow, scan & 0xffffu, scan >> 16);
}

int main(int argc, char **argv) {
    unsigned long base = DISPLAY_BASE_DEFAULT;
    int argi = 1;

    while (argi < argc && strcmp(argv[argi], "--base") == 0) {
        if (argi + 1 >= argc) {
            usage(argv[0]);
            return 2;
        }
        base = parse_u32(argv[argi + 1], "base");
        argi += 2;
    }

    if (argi >= argc) {
        usage(argv[0]);
        return 2;
    }

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        return 1;
    }

    g_regs = (volatile uint32_t *)map_phys(fd, base, DISPLAY_SIZE, "display");
    close(fd);
    if (g_regs == MAP_FAILED) {
        return 1;
    }

    const char *cmd = argv[argi++];
    if (strcmp(cmd, "status") == 0) {
        print_status();
        return 0;
    }

    if (strcmp(cmd, "disable") == 0) {
        wr(DISP_CONTROL, 0);
        print_status();
        return 0;
    }

    if (strcmp(cmd, "mode") == 0) {
        if (argi >= argc) {
            usage(argv[0]);
            return 2;
        }
        wr(DISP_MODE, parse_u32(argv[argi], "mode") & 3u);
        print_status();
        return 0;
    }

    if (strcmp(cmd, "bg") == 0) {
        if (argi >= argc) {
            usage(argv[0]);
            return 2;
        }
        wr(DISP_BG_COLOR, parse_u32(argv[argi], "bg"));
        print_status();
        return 0;
    }

    if (strcmp(cmd, "enable") == 0) {
        uint32_t control = CONTROL_ENABLE | CONTROL_TEST_PATTERN;
        while (argi < argc) {
            if (strcmp(argv[argi], "--fb") == 0 && argi + 1 < argc) {
                wr(DISP_FB_ADDR, parse_u32(argv[argi + 1], "fb"));
                argi += 2;
            } else if (strcmp(argv[argi], "--stride") == 0 && argi + 1 < argc) {
                wr(DISP_FB_STRIDE, parse_u32(argv[argi + 1], "stride"));
                argi += 2;
            } else if (strcmp(argv[argi], "--size") == 0 && argi + 1 < argc) {
                uint16_t width;
                uint16_t height;
                parse_size(argv[argi + 1], &width, &height);
                wr(DISP_FB_SIZE, ((uint32_t)height << 16) | width);
                argi += 2;
            } else if (strcmp(argv[argi], "--mode") == 0 && argi + 1 < argc) {
                wr(DISP_MODE, parse_u32(argv[argi + 1], "mode") & 3u);
                argi += 2;
            } else if (strcmp(argv[argi], "--bg") == 0 && argi + 1 < argc) {
                wr(DISP_BG_COLOR, parse_u32(argv[argi + 1], "bg"));
                argi += 2;
            } else if (strcmp(argv[argi], "--no-test") == 0) {
                control &= ~CONTROL_TEST_PATTERN;
                argi++;
            } else {
                usage(argv[0]);
                return 2;
            }
        }
        wr(DISP_CONTROL, CONTROL_RESET);
        wr(DISP_CONTROL, control);
        print_status();
        return 0;
    }

    usage(argv[0]);
    return 2;
}
