#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define GPU_BASE_DEFAULT 0x10070000UL
#define GPU_SIZE         0x1000UL

#define FB_BASE_DEFAULT  0xbc000000UL
#define FB_WIDTH         8u
#define FB_HEIGHT        4u
#define FB_STRIDE        (FB_WIDTH * 4u)
#define FB_BYTES         (FB_STRIDE * FB_HEIGHT)
#define BLIT_SRC_OFFSET  FB_BYTES
#define FB_MAP_BYTES     (FB_BYTES + FB_STRIDE * 2u)

#define GPU_CONTROL      0x00u
#define GPU_STATUS       0x04u
#define GPU_FB_ADDR      0x08u
#define GPU_FB_STRIDE    0x0cu
#define GPU_FB_SIZE      0x10u
#define GPU_COLOR        0x14u
#define GPU_RECT_ORIGIN  0x18u
#define GPU_RECT_SIZE    0x1cu
#define GPU_CUR_PIXEL    0x20u
#define GPU_WAIT_COUNT   0x24u
#define GPU_PIXEL_COUNT  0x28u
#define GPU_LAST_CTRL    0x2cu
#define GPU_CUR_ADDR     0x30u
#define GPU_CMD_SUBMIT   0x34u
#define GPU_CMD_DONE     0x38u
#define GPU_SRC_ADDR     0x4cu
#define GPU_SRC_STRIDE   0x50u

#define GPU_OP_CLEAR     1u
#define GPU_OP_FILL_RECT 2u
#define GPU_OP_DRAW_LINE 3u
#define GPU_OP_BLIT      4u
#define GPU_OP_COLOR_KEY_BLIT 5u
#define GPU_STATUS_BUSY  (1u << 0)
#define GPU_STATUS_DONE  (1u << 1)
#define GPU_STATUS_ERROR (1u << 2)

#define CLEAR_COLOR      0xaabbccddu
#define RECT_COLOR       0x11223344u
#define LINE_COLOR       0xff00ff00u
#define BLIT_SRC0        0x01020304u
#define BLIT_SRC1        0x11121314u
#define BLIT_SRC2        0x21222324u
#define BLIT_SRC3        0x31323334u
#define COLOR_KEY        0x00ff00ffu
#define KEY_DST_SENTINEL 0x55667788u

static volatile uint32_t *g_gpu;
static int g_verbose = 1;

static void gpu_log(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    fflush(stderr);
    va_end(ap);
}

static uint32_t mmio_read(uint32_t off) {
    return g_gpu[off >> 2];
}

static void mmio_write(uint32_t off, uint32_t value) {
    g_gpu[off >> 2] = value;
    __asm__ __volatile__("" ::: "memory");
}

static void short_delay(void) {
    for (volatile unsigned int i = 0; i < 256u; i++) {
    }
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

static int wait_done(double timeout_sec, uint32_t *final_status) {
    double start = now_sec();
    int polls = 0;

    for (;;) {
        uint32_t status = mmio_read(GPU_STATUS);
        if (g_verbose && (polls == 0 || (polls % 10000) == 0)) {
            uint32_t cur = mmio_read(GPU_CUR_PIXEL);
            uint32_t wait_count = mmio_read(GPU_WAIT_COUNT);
            uint32_t pixel_count = mmio_read(GPU_PIXEL_COUNT);
            uint32_t last_ctrl = mmio_read(GPU_LAST_CTRL);
            uint32_t cur_addr = mmio_read(GPU_CUR_ADDR);
            gpu_log("[gpu_smoke] wait: poll=%d status=0x%08" PRIx32
                    " busy=%u done=%u error=%u cur=0x%08" PRIx32
                    " wait=%" PRIu32 " pixels=%" PRIu32
                    " last_ctrl=0x%08" PRIx32 " cur_addr=0x%08" PRIx32,
                    polls, status, !!(status & GPU_STATUS_BUSY),
                    !!(status & GPU_STATUS_DONE), !!(status & GPU_STATUS_ERROR),
                    cur, wait_count, pixel_count, last_ctrl, cur_addr);
        }
        polls++;
        if (status & GPU_STATUS_ERROR) {
            *final_status = status;
            return -1;
        }
        if ((status & GPU_STATUS_DONE) && !(status & GPU_STATUS_BUSY)) {
            *final_status = status;
            return 0;
        }
        if ((now_sec() - start) > timeout_sec) {
            *final_status = status;
            return -2;
        }
    }
}

static int start_gpu(uint32_t op, uint32_t *final_status) {
    gpu_log("[gpu_smoke] soft reset status");
    mmio_write(GPU_STATUS, GPU_STATUS_DONE | GPU_STATUS_ERROR);
    gpu_log("[gpu_smoke] status after clear=0x%08" PRIx32, mmio_read(GPU_STATUS));
    gpu_log("[gpu_smoke] start op=0x%x", op);
    mmio_write(GPU_CONTROL, (op << 4) | 1u);
    gpu_log("[gpu_smoke] start write returned");
    short_delay();
    return wait_done(1.0, final_status);
}

static void submit_gpu(uint32_t op) {
    gpu_log("[gpu_smoke] fifo submit op=0x%x", op);
    mmio_write(GPU_CMD_SUBMIT, (op << 4) | 1u);
}

static int is_line_pixel(uint32_t x, uint32_t y) {
    return (x == 0u && y == 3u) ||
           (x == 1u && y == 3u) ||
           (x == 2u && y == 2u) ||
           (x == 3u && y == 2u) ||
           (x == 4u && y == 1u) ||
           (x == 5u && y == 1u) ||
           (x == 6u && y == 0u) ||
           (x == 7u && y == 0u);
}

static int verify_pixels(volatile uint32_t *fb) {
    int errors = 0;

    for (uint32_t y = 0; y < FB_HEIGHT; y++) {
        for (uint32_t x = 0; x < FB_WIDTH; x++) {
            uint32_t expected = CLEAR_COLOR;
            if (x >= 2u && x < 5u && y >= 1u && y < 3u) {
                expected = RECT_COLOR;
            }
            if (is_line_pixel(x, y)) {
                expected = LINE_COLOR;
            }
            uint32_t got = fb[y * FB_WIDTH + x];
            if (got != expected) {
                fprintf(stderr,
                        "pixel[%u,%u] expected 0x%08" PRIx32 ", got 0x%08" PRIx32 "\n",
                        x, y, expected, got);
                if (++errors >= 8) {
                    return -1;
                }
            }
        }
    }

    return errors == 0 ? 0 : -1;
}

static int verify_blit_pixels(volatile uint32_t *fb) {
    if (fb[1u + 1u * FB_WIDTH] != BLIT_SRC0 ||
        fb[2u + 1u * FB_WIDTH] != BLIT_SRC1 ||
        fb[1u + 2u * FB_WIDTH] != BLIT_SRC2 ||
        fb[2u + 2u * FB_WIDTH] != BLIT_SRC3) {
        fprintf(stderr,
                "blit verify failed: %08" PRIx32 " %08" PRIx32 " %08" PRIx32 " %08" PRIx32 "\n",
                fb[1u + 1u * FB_WIDTH], fb[2u + 1u * FB_WIDTH],
                fb[1u + 2u * FB_WIDTH], fb[2u + 2u * FB_WIDTH]);
        return -1;
    }
    return 0;
}

static int verify_color_key_pixels(volatile uint32_t *fb) {
    if (fb[4u + 1u * FB_WIDTH] != BLIT_SRC0 ||
        fb[5u + 1u * FB_WIDTH] != KEY_DST_SENTINEL ||
        fb[4u + 2u * FB_WIDTH] != BLIT_SRC2 ||
        fb[5u + 2u * FB_WIDTH] != BLIT_SRC3) {
        fprintf(stderr,
                "color-key blit verify failed: %08" PRIx32 " %08" PRIx32
                " %08" PRIx32 " %08" PRIx32 "\n",
                fb[4u + 1u * FB_WIDTH], fb[5u + 1u * FB_WIDTH],
                fb[4u + 2u * FB_WIDTH], fb[5u + 2u * FB_WIDTH]);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    unsigned long gpu_base = GPU_BASE_DEFAULT;
    unsigned long fb_base = FB_BASE_DEFAULT;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    gpu_log("[gpu_smoke] begin");

    if (argc >= 2) {
        fb_base = strtoul(argv[1], NULL, 0);
    }
    if (argc >= 3) {
        gpu_base = strtoul(argv[2], NULL, 0);
    }

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        return 1;
    }
    gpu_log("[gpu_smoke] /dev/mem opened");

    g_gpu = (volatile uint32_t *)map_phys(fd, gpu_base, GPU_SIZE, "gpu");
    volatile uint32_t *fb = (volatile uint32_t *)map_phys(fd, fb_base, FB_MAP_BYTES, "framebuffer");
    close(fd);
    if (g_gpu == MAP_FAILED || fb == MAP_FAILED) {
        return 1;
    }
    gpu_log("[gpu_smoke] mapped gpu=0x%08lx fb=0x%08lx fb_bytes=%u map_bytes=%u",
            gpu_base, fb_base, FB_BYTES, FB_MAP_BYTES);

    for (uint32_t i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        fb[i] = 0u;
    }
    (void)fb[0];
    gpu_log("[gpu_smoke] framebuffer zeroed");

    mmio_write(GPU_CONTROL, 1u << 31);
    gpu_log("[gpu_smoke] control soft reset written");
    mmio_write(GPU_FB_ADDR, (uint32_t)fb_base);
    gpu_log("[gpu_smoke] fb addr written 0x%08lx", fb_base);
    mmio_write(GPU_FB_STRIDE, FB_STRIDE);
    gpu_log("[gpu_smoke] fb stride written %u", FB_STRIDE);
    mmio_write(GPU_FB_SIZE, (FB_HEIGHT << 16) | FB_WIDTH);
    gpu_log("[gpu_smoke] fb size written %ux%u", FB_WIDTH, FB_HEIGHT);
    mmio_write(GPU_COLOR, CLEAR_COLOR);
    gpu_log("[gpu_smoke] clear color written 0x%08" PRIx32, CLEAR_COLOR);

    uint32_t status = 0;
    int rc = start_gpu(GPU_OP_CLEAR, &status);
    if (rc != 0) {
        fprintf(stderr, "GPU clear failed: rc=%d status=0x%08" PRIx32 "\n", rc, status);
        return 1;
    }
    gpu_log("[gpu_smoke] clear complete status=0x%08" PRIx32, status);

    for (uint32_t i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        if (fb[i] != CLEAR_COLOR) {
            fprintf(stderr, "clear verify failed at word %u: 0x%08" PRIx32 "\n", i, fb[i]);
            return 1;
        }
    }
    gpu_log("[gpu_smoke] clear verify passed");

    mmio_write(GPU_COLOR, RECT_COLOR);
    gpu_log("[gpu_smoke] rect color written 0x%08" PRIx32, RECT_COLOR);
    mmio_write(GPU_RECT_ORIGIN, (1u << 16) | 2u);
    gpu_log("[gpu_smoke] rect origin written x=2 y=1");
    mmio_write(GPU_RECT_SIZE, (2u << 16) | 3u);
    gpu_log("[gpu_smoke] rect size written w=3 h=2");

    rc = start_gpu(GPU_OP_FILL_RECT, &status);
    if (rc != 0) {
        fprintf(stderr, "GPU fill-rect failed: rc=%d status=0x%08" PRIx32 "\n", rc, status);
        return 1;
    }
    gpu_log("[gpu_smoke] fill-rect complete status=0x%08" PRIx32, status);

    mmio_write(GPU_COLOR, LINE_COLOR);
    gpu_log("[gpu_smoke] line color written 0x%08" PRIx32, LINE_COLOR);
    mmio_write(GPU_RECT_ORIGIN, (3u << 16) | 0u);
    gpu_log("[gpu_smoke] line origin written x=0 y=3");
    mmio_write(GPU_RECT_SIZE, (0u << 16) | 7u);
    gpu_log("[gpu_smoke] line end written x=7 y=0");

    rc = start_gpu(GPU_OP_DRAW_LINE, &status);
    if (rc != 0) {
        fprintf(stderr, "GPU draw-line failed: rc=%d status=0x%08" PRIx32 "\n", rc, status);
        return 1;
    }
    gpu_log("[gpu_smoke] draw-line complete status=0x%08" PRIx32, status);

    if (verify_pixels(fb) != 0) {
        return 1;
    }
    gpu_log("[gpu_smoke] pixel verify passed");

    for (uint32_t i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        fb[i] = 0u;
    }
    (void)fb[0];
    gpu_log("[gpu_smoke] framebuffer zeroed for fifo batch");
    mmio_write(GPU_CONTROL, 1u << 31);
    gpu_log("[gpu_smoke] control soft reset written for fifo batch");
    mmio_write(GPU_FB_ADDR, (uint32_t)fb_base);
    mmio_write(GPU_FB_STRIDE, FB_STRIDE);
    mmio_write(GPU_FB_SIZE, (FB_HEIGHT << 16) | FB_WIDTH);

    mmio_write(GPU_COLOR, CLEAR_COLOR);
    submit_gpu(GPU_OP_CLEAR);
    mmio_write(GPU_COLOR, RECT_COLOR);
    mmio_write(GPU_RECT_ORIGIN, (1u << 16) | 2u);
    mmio_write(GPU_RECT_SIZE, (2u << 16) | 3u);
    submit_gpu(GPU_OP_FILL_RECT);
    mmio_write(GPU_COLOR, LINE_COLOR);
    mmio_write(GPU_RECT_ORIGIN, (3u << 16) | 0u);
    mmio_write(GPU_RECT_SIZE, (0u << 16) | 7u);
    submit_gpu(GPU_OP_DRAW_LINE);

    rc = wait_done(1.0, &status);
    if (rc != 0) {
        fprintf(stderr, "GPU fifo batch failed: rc=%d status=0x%08" PRIx32 "\n", rc, status);
        return 1;
    }
    gpu_log("[gpu_smoke] fifo batch complete status=0x%08" PRIx32
            " done_count=%" PRIu32,
            status, mmio_read(GPU_CMD_DONE));
    if (mmio_read(GPU_CMD_DONE) != 3u) {
        fprintf(stderr, "GPU fifo done count mismatch: %" PRIu32 "\n", mmio_read(GPU_CMD_DONE));
        return 1;
    }
    if (verify_pixels(fb) != 0) {
        return 1;
    }
    gpu_log("[gpu_smoke] fifo pixel verify passed");

    for (uint32_t i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        fb[i] = 0u;
    }
    (void)fb[0];
    volatile uint32_t *blit_src = (volatile uint32_t *)((volatile uint8_t *)fb + BLIT_SRC_OFFSET);
    blit_src[0] = BLIT_SRC0;
    blit_src[1] = BLIT_SRC1;
    blit_src[FB_WIDTH] = BLIT_SRC2;
    blit_src[FB_WIDTH + 1u] = BLIT_SRC3;
    gpu_log("[gpu_smoke] framebuffer prepared for blit src_offset=%u", BLIT_SRC_OFFSET);
    mmio_write(GPU_CONTROL, 1u << 31);
    mmio_write(GPU_FB_ADDR, (uint32_t)fb_base);
    mmio_write(GPU_FB_STRIDE, FB_STRIDE);
    mmio_write(GPU_FB_SIZE, (FB_HEIGHT << 16) | FB_WIDTH);
    mmio_write(GPU_RECT_ORIGIN, (1u << 16) | 1u);
    mmio_write(GPU_RECT_SIZE, (2u << 16) | 2u);
    mmio_write(GPU_SRC_ADDR, (uint32_t)(fb_base + BLIT_SRC_OFFSET));
    mmio_write(GPU_SRC_STRIDE, FB_STRIDE);

    rc = start_gpu(GPU_OP_BLIT, &status);
    if (rc != 0) {
        fprintf(stderr, "GPU blit failed: rc=%d status=0x%08" PRIx32 "\n", rc, status);
        return 1;
    }
    gpu_log("[gpu_smoke] blit complete status=0x%08" PRIx32, status);
    if (verify_blit_pixels(fb) != 0) {
        return 1;
    }
    gpu_log("[gpu_smoke] blit verify passed");

    for (uint32_t i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        fb[i] = 0u;
    }
    fb[4u + 1u * FB_WIDTH] = KEY_DST_SENTINEL;
    fb[5u + 1u * FB_WIDTH] = KEY_DST_SENTINEL;
    fb[4u + 2u * FB_WIDTH] = KEY_DST_SENTINEL;
    fb[5u + 2u * FB_WIDTH] = KEY_DST_SENTINEL;
    blit_src[0] = BLIT_SRC0;
    blit_src[1] = COLOR_KEY;
    blit_src[FB_WIDTH] = BLIT_SRC2;
    blit_src[FB_WIDTH + 1u] = BLIT_SRC3;
    gpu_log("[gpu_smoke] framebuffer prepared for color-key blit key=0x%08" PRIx32,
            COLOR_KEY);
    mmio_write(GPU_CONTROL, 1u << 31);
    mmio_write(GPU_FB_ADDR, (uint32_t)fb_base);
    mmio_write(GPU_FB_STRIDE, FB_STRIDE);
    mmio_write(GPU_FB_SIZE, (FB_HEIGHT << 16) | FB_WIDTH);
    mmio_write(GPU_COLOR, COLOR_KEY);
    mmio_write(GPU_RECT_ORIGIN, (1u << 16) | 4u);
    mmio_write(GPU_RECT_SIZE, (2u << 16) | 2u);
    mmio_write(GPU_SRC_ADDR, (uint32_t)(fb_base + BLIT_SRC_OFFSET));
    mmio_write(GPU_SRC_STRIDE, FB_STRIDE);

    rc = start_gpu(GPU_OP_COLOR_KEY_BLIT, &status);
    if (rc != 0) {
        fprintf(stderr, "GPU color-key blit failed: rc=%d status=0x%08" PRIx32 "\n",
                rc, status);
        return 1;
    }
    gpu_log("[gpu_smoke] color-key blit complete status=0x%08" PRIx32, status);
    if (verify_color_key_pixels(fb) != 0) {
        return 1;
    }
    gpu_log("[gpu_smoke] color-key blit verify passed");

    printf("zx32_gpu_smoke: PASS fb=0x%08lx gpu=0x%08lx size=%ux%u stride=%u\n",
           fb_base, gpu_base, FB_WIDTH, FB_HEIGHT, FB_STRIDE);
    return 0;
}
