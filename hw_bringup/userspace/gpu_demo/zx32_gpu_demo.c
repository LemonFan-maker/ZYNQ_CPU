#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define GPU_BASE_DEFAULT 0x10070000UL
#define GPU_SIZE         0x1000UL

#define FB_BASE_DEFAULT  0xbc000000UL
#define FB_WIDTH         128u
#define FB_HEIGHT        64u
#define FB_STRIDE        (FB_WIDTH * 4u)
#define FB_BYTES         (FB_STRIDE * FB_HEIGHT)
#define ASCII_X_STEP     2u
#define ASCII_Y_STEP     2u

#define GPU_CONTROL      0x00u
#define GPU_STATUS       0x04u
#define GPU_FB_ADDR      0x08u
#define GPU_FB_STRIDE    0x0cu
#define GPU_FB_SIZE      0x10u
#define GPU_COLOR        0x14u
#define GPU_RECT_ORIGIN  0x18u
#define GPU_RECT_SIZE    0x1cu
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
#define GPU_FIFO_EMPTY   (1u << 0)
#define GPU_FIFO_FULL    (1u << 1)

#define COLOR_BG         0x00101820u
#define COLOR_GRID       0x00304850u
#define COLOR_AXIS       0x0080a0b0u
#define COLOR_FACE       0x00203080u
#define COLOR_EDGE       0x00f0d070u
#define COLOR_HILITE     0x00ff6060u

static volatile uint32_t *g_gpu;

static uint32_t mmio_read(uint32_t off) {
    return g_gpu[off >> 2];
}

static void mmio_write(uint32_t off, uint32_t value) {
    g_gpu[off >> 2] = value;
    __asm__ __volatile__("" ::: "memory");
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

static int wait_done(double timeout_sec) {
    double start = now_sec();
    unsigned polls = 0;

    for (;;) {
        uint32_t status = mmio_read(GPU_STATUS);
        if ((status & GPU_STATUS_ERROR) != 0u) {
            fprintf(stderr,
                    "GPU error: status=0x%08" PRIx32 " wait=%" PRIu32
                    " pixels=%" PRIu32 " last=0x%08" PRIx32 " addr=0x%08" PRIx32 "\n",
                    status, mmio_read(GPU_WAIT_COUNT), mmio_read(GPU_PIXEL_COUNT),
                    mmio_read(GPU_LAST_CTRL), mmio_read(GPU_CUR_ADDR));
            return -1;
        }
        if ((status & GPU_STATUS_DONE) != 0u && (status & GPU_STATUS_BUSY) == 0u) {
            return 0;
        }
        if ((now_sec() - start) > timeout_sec) {
            fprintf(stderr,
                    "GPU timeout: polls=%u status=0x%08" PRIx32 " done=%" PRIu32
                    " wait=%" PRIu32 " pixels=%" PRIu32 "\n",
                    polls, status, mmio_read(GPU_CMD_DONE), mmio_read(GPU_WAIT_COUNT),
                    mmio_read(GPU_PIXEL_COUNT));
            return -2;
        }
        polls++;
    }
}

static int wait_fifo_space(double timeout_sec) {
    double start = now_sec();

    for (;;) {
        uint32_t fifo = mmio_read(GPU_CMD_SUBMIT);
        uint32_t status = mmio_read(GPU_STATUS);
        if ((status & GPU_STATUS_ERROR) != 0u) {
            fprintf(stderr, "GPU error while waiting fifo: status=0x%08" PRIx32 "\n", status);
            return -1;
        }
        if ((fifo & GPU_FIFO_FULL) == 0u) {
            return 0;
        }
        if ((now_sec() - start) > timeout_sec) {
            fprintf(stderr, "GPU fifo full timeout: fifo=0x%08" PRIx32
                    " status=0x%08" PRIx32 " done=%" PRIu32 "\n",
                    fifo, status, mmio_read(GPU_CMD_DONE));
            return -2;
        }
    }
}

static int submit_cmd(uint32_t op, uint32_t color, uint32_t x0, uint32_t y0, uint32_t x1, uint32_t y1) {
    if (wait_fifo_space(1.0) != 0) {
        return -1;
    }

    mmio_write(GPU_COLOR, color);
    mmio_write(GPU_RECT_ORIGIN, (y0 << 16) | x0);
    mmio_write(GPU_RECT_SIZE, (y1 << 16) | x1);
    mmio_write(GPU_CMD_SUBMIT, (op << 4) | 1u);

    uint32_t status = mmio_read(GPU_STATUS);
    if ((status & GPU_STATUS_ERROR) != 0u) {
        fprintf(stderr, "GPU submit failed: op=%" PRIu32 " status=0x%08" PRIx32 "\n", op, status);
        return -1;
    }
    return 0;
}

static int draw_line(uint32_t color, uint32_t x0, uint32_t y0, uint32_t x1, uint32_t y1) {
    return submit_cmd(GPU_OP_DRAW_LINE, color, x0, y0, x1, y1);
}

static int fill_rect(uint32_t color, uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    return submit_cmd(GPU_OP_FILL_RECT, color, x, y, w, h);
}

static int render_scene(void) {
    uint32_t before = mmio_read(GPU_CMD_DONE);

    mmio_write(GPU_CONTROL, 1u << 31);
    mmio_write(GPU_FB_ADDR, FB_BASE_DEFAULT);
    mmio_write(GPU_FB_STRIDE, FB_STRIDE);
    mmio_write(GPU_FB_SIZE, (FB_HEIGHT << 16) | FB_WIDTH);

    if (submit_cmd(GPU_OP_CLEAR, COLOR_BG, 0, 0, 0, 0) != 0) return -1;

    for (uint32_t x = 0; x < FB_WIDTH; x += 16u) {
        if (draw_line(COLOR_GRID, x, 0, x, FB_HEIGHT - 1u) != 0) return -1;
    }
    for (uint32_t y = 0; y < FB_HEIGHT; y += 8u) {
        if (draw_line(COLOR_GRID, 0, y, FB_WIDTH - 1u, y) != 0) return -1;
    }

    if (draw_line(COLOR_AXIS, 0, FB_HEIGHT / 2u, FB_WIDTH - 1u, FB_HEIGHT / 2u) != 0) return -1;
    if (draw_line(COLOR_AXIS, FB_WIDTH / 2u, 0, FB_WIDTH / 2u, FB_HEIGHT - 1u) != 0) return -1;

    if (fill_rect(COLOR_FACE, 45, 22, 36, 20) != 0) return -1;

    if (draw_line(COLOR_EDGE, 34, 16, 78, 10) != 0) return -1;
    if (draw_line(COLOR_EDGE, 78, 10, 100, 29) != 0) return -1;
    if (draw_line(COLOR_EDGE, 100, 29, 56, 35) != 0) return -1;
    if (draw_line(COLOR_EDGE, 56, 35, 34, 16) != 0) return -1;

    if (draw_line(COLOR_EDGE, 46, 40, 90, 34) != 0) return -1;
    if (draw_line(COLOR_EDGE, 90, 34, 108, 50) != 0) return -1;
    if (draw_line(COLOR_EDGE, 108, 50, 64, 57) != 0) return -1;
    if (draw_line(COLOR_EDGE, 64, 57, 46, 40) != 0) return -1;

    if (draw_line(COLOR_EDGE, 34, 16, 46, 40) != 0) return -1;
    if (draw_line(COLOR_EDGE, 78, 10, 90, 34) != 0) return -1;
    if (draw_line(COLOR_EDGE, 100, 29, 108, 50) != 0) return -1;
    if (draw_line(COLOR_EDGE, 56, 35, 64, 57) != 0) return -1;

    if (draw_line(COLOR_HILITE, 16, 56, 116, 8) != 0) return -1;
    if (draw_line(COLOR_HILITE, 14, 8, 112, 58) != 0) return -1;

    if (wait_done(2.0) != 0) {
        return -1;
    }

    uint32_t after = mmio_read(GPU_CMD_DONE);
    printf("zx32_gpu_demo: rendered %u commands\n", after - before);
    return 0;
}

static char pixel_char(uint32_t px) {
    if (px == COLOR_BG) return ' ';
    if (px == COLOR_GRID) return '.';
    if (px == COLOR_AXIS) return '+';
    if (px == COLOR_FACE) return '=';
    if (px == COLOR_EDGE) return '#';
    if (px == COLOR_HILITE) return '*';
    return '@';
}

static unsigned pixel_priority(uint32_t px) {
    if (px == COLOR_HILITE) return 6;
    if (px == COLOR_EDGE) return 5;
    if (px == COLOR_FACE) return 4;
    if (px == COLOR_AXIS) return 3;
    if (px == COLOR_GRID) return 2;
    if (px == COLOR_BG) return 0;
    return 1;
}

static void print_ascii(volatile uint32_t *fb) {
    for (uint32_t y = 0; y < FB_HEIGHT; y += ASCII_Y_STEP) {
        for (uint32_t x = 0; x < FB_WIDTH; x += ASCII_X_STEP) {
            uint32_t chosen = COLOR_BG;
            unsigned chosen_prio = 0;
            for (uint32_t yy = 0; yy < ASCII_Y_STEP && (y + yy) < FB_HEIGHT; yy++) {
                for (uint32_t xx = 0; xx < ASCII_X_STEP && (x + xx) < FB_WIDTH; xx++) {
                    uint32_t px = fb[(y + yy) * FB_WIDTH + (x + xx)];
                    unsigned prio = pixel_priority(px);
                    if (prio >= chosen_prio) {
                        chosen = px;
                        chosen_prio = prio;
                    }
                }
            }
            putchar(pixel_char(chosen));
        }
        putchar('\n');
    }
}

static int write_ppm(volatile uint32_t *fb, const char *path) {
    FILE *fp = fopen(path, "wb");
    if (fp == NULL) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        return -1;
    }

    fprintf(fp, "P6\n%u %u\n255\n", FB_WIDTH, FB_HEIGHT);
    for (uint32_t y = 0; y < FB_HEIGHT; y++) {
        for (uint32_t x = 0; x < FB_WIDTH; x++) {
            uint32_t px = fb[y * FB_WIDTH + x];
            uint8_t rgb[3] = {
                (uint8_t)((px >> 16) & 0xffu),
                (uint8_t)((px >> 8) & 0xffu),
                (uint8_t)(px & 0xffu),
            };
            if (fwrite(rgb, 1, sizeof(rgb), fp) != sizeof(rgb)) {
                fclose(fp);
                fprintf(stderr, "write %s failed\n", path);
                return -1;
            }
        }
    }

    if (fclose(fp) != 0) {
        fprintf(stderr, "close %s failed: %s\n", path, strerror(errno));
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *mode = argc >= 2 ? argv[1] : "ascii";
    const char *ppm_path = argc >= 3 ? argv[2] : "/tmp/zx32_gpu_demo.ppm";

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        return 1;
    }

    g_gpu = (volatile uint32_t *)map_phys(fd, GPU_BASE_DEFAULT, GPU_SIZE, "gpu");
    volatile uint32_t *fb = (volatile uint32_t *)map_phys(fd, FB_BASE_DEFAULT, FB_BYTES, "framebuffer");
    close(fd);
    if (g_gpu == MAP_FAILED || fb == MAP_FAILED) {
        return 1;
    }

    for (uint32_t i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        fb[i] = 0u;
    }
    (void)fb[0];

    if (render_scene() != 0) {
        return 1;
    }

    if (strcmp(mode, "ascii") == 0) {
        print_ascii(fb);
    } else if (strcmp(mode, "ppm") == 0) {
        if (write_ppm(fb, ppm_path) != 0) {
            return 1;
        }
        printf("zx32_gpu_demo: wrote %s (%ux%u)\n", ppm_path, FB_WIDTH, FB_HEIGHT);
    } else {
        fprintf(stderr, "usage: %s [ascii|ppm] [ppm_path]\n", argv[0]);
        return 2;
    }

    return 0;
}
