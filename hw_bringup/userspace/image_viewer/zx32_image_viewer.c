#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

#define FB_BASE_DEFAULT 0xbc000000UL
#define VRAM_BYTES      (64u * 1024u * 1024u)

static void usage(const char *argv0) {
    fprintf(stderr,
            "usage:\n"
            "  %s raw <xrgb8888.raw> <width> <height> [dump.ppm] [fb_base]\n"
            "  %s ppm <input.ppm> [dump.ppm] [fb_base]\n"
            "  %s dump <width> <height> <dump.ppm> [out_width] [out_height] [fb_base]\n",
            argv0, argv0, argv0);
}

static unsigned long parse_ulong(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(s, &end, 0);
    if (errno != 0 || end == s || *end != '\0') {
        fprintf(stderr, "invalid %s: %s\n", name, s);
        exit(2);
    }
    return value;
}

static int checked_fb_bytes(uint32_t width, uint32_t height, size_t *bytes_out) {
    if (width == 0u || height == 0u) {
        fprintf(stderr, "image dimensions must be non-zero\n");
        return -1;
    }
    if (width > UINT32_MAX / 4u) {
        fprintf(stderr, "image width is too large: %" PRIu32 "\n", width);
        return -1;
    }

    uint64_t stride = (uint64_t)width * 4u;
    uint64_t bytes = stride * (uint64_t)height;
    if (bytes > VRAM_BYTES) {
        fprintf(stderr,
                "image needs %" PRIu64 " bytes, exceeds 64 MiB VRAM\n",
                bytes);
        return -1;
    }
    *bytes_out = (size_t)bytes;
    return 0;
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

    void *map = mmap(NULL, map_size, PROT_READ | PROT_WRITE, MAP_SHARED,
                     fd, (off_t)page_base);
    if (map == MAP_FAILED) {
        fprintf(stderr, "mmap %s at 0x%08lx failed: %s\n",
                name, phys, strerror(errno));
        return MAP_FAILED;
    }

    return (uint8_t *)map + page_off;
}

static int file_size_matches(FILE *fp, uint64_t expected, const char *path) {
    struct stat st;
    if (fstat(fileno(fp), &st) != 0) {
        fprintf(stderr, "stat %s failed: %s\n", path, strerror(errno));
        return -1;
    }
    if ((uint64_t)st.st_size != expected) {
        fprintf(stderr,
                "%s size mismatch: expected %" PRIu64 " bytes, got %" PRIu64 "\n",
                path, expected, (uint64_t)st.st_size);
        return -1;
    }
    return 0;
}

static int read_token(FILE *fp, char *buf, size_t cap) {
    int ch;
    size_t len = 0;

    do {
        ch = fgetc(fp);
        if (ch == '#') {
            do {
                ch = fgetc(fp);
            } while (ch != EOF && ch != '\n');
        }
    } while (ch != EOF && (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'));

    if (ch == EOF) {
        return -1;
    }

    while (ch != EOF && ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') {
        if (ch == '#') {
            do {
                ch = fgetc(fp);
            } while (ch != EOF && ch != '\n');
            break;
        }
        if (len + 1u >= cap) {
            return -1;
        }
        buf[len++] = (char)ch;
        ch = fgetc(fp);
    }

    buf[len] = '\0';
    return len > 0u ? 0 : -1;
}

static int read_ppm_header(FILE *fp, uint32_t *width, uint32_t *height) {
    char tok[32];

    if (read_token(fp, tok, sizeof(tok)) != 0 || strcmp(tok, "P6") != 0) {
        fprintf(stderr, "PPM input must use binary P6 format\n");
        return -1;
    }
    if (read_token(fp, tok, sizeof(tok)) != 0) {
        fprintf(stderr, "missing PPM width\n");
        return -1;
    }
    *width = (uint32_t)parse_ulong(tok, "PPM width");
    if (read_token(fp, tok, sizeof(tok)) != 0) {
        fprintf(stderr, "missing PPM height\n");
        return -1;
    }
    *height = (uint32_t)parse_ulong(tok, "PPM height");
    if (read_token(fp, tok, sizeof(tok)) != 0) {
        fprintf(stderr, "missing PPM maxval\n");
        return -1;
    }
    unsigned long maxval = parse_ulong(tok, "PPM maxval");
    if (maxval != 255u) {
        fprintf(stderr, "unsupported PPM maxval %lu, expected 255\n", maxval);
        return -1;
    }

    return 0;
}

static int load_raw_xrgb(FILE *fp, const char *path, uint32_t *fb,
                         uint32_t width, uint32_t height) {
    size_t bytes = 0;
    if (checked_fb_bytes(width, height, &bytes) != 0) {
        return -1;
    }
    if (file_size_matches(fp, (uint64_t)bytes, path) != 0) {
        return -1;
    }

    uint32_t *row = malloc((size_t)width * sizeof(uint32_t));
    if (row == NULL) {
        fprintf(stderr, "allocate raw row failed\n");
        return -1;
    }

    for (uint32_t y = 0; y < height; y++) {
        if (fread(row, sizeof(uint32_t), width, fp) != width) {
            fprintf(stderr, "read raw row %" PRIu32 " failed\n", y);
            free(row);
            return -1;
        }
        for (uint32_t x = 0; x < width; x++) {
            fb[(size_t)y * width + x] = row[x];
        }
    }

    free(row);
    return 0;
}

static int load_ppm(FILE *fp, uint32_t *fb, uint32_t width, uint32_t height) {
    uint8_t *row = malloc((size_t)width * 3u);
    if (row == NULL) {
        fprintf(stderr, "allocate PPM row failed\n");
        return -1;
    }

    for (uint32_t y = 0; y < height; y++) {
        if (fread(row, 3u, width, fp) != width) {
            fprintf(stderr, "read PPM row %" PRIu32 " failed\n", y);
            free(row);
            return -1;
        }
        for (uint32_t x = 0; x < width; x++) {
            uint8_t *rgb = &row[(size_t)x * 3u];
            fb[(size_t)y * width + x] =
                ((uint32_t)rgb[0] << 16) | ((uint32_t)rgb[1] << 8) | rgb[2];
        }
    }

    free(row);
    return 0;
}

static int write_ppm(uint32_t *fb, const char *path, uint32_t width, uint32_t height) {
    FILE *fp = fopen(path, "wb");
    if (fp == NULL) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        return -1;
    }

    fprintf(fp, "P6\n%" PRIu32 " %" PRIu32 "\n255\n", width, height);
    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            uint32_t px = fb[(size_t)y * width + x];
            uint8_t rgb[3] = {
                (uint8_t)((px >> 16) & 0xffu),
                (uint8_t)((px >> 8) & 0xffu),
                (uint8_t)(px & 0xffu),
            };
            if (fwrite(rgb, 1u, sizeof(rgb), fp) != sizeof(rgb)) {
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

static int write_ppm_scaled(uint32_t *fb, const char *path,
                            uint32_t width, uint32_t height,
                            uint32_t out_width, uint32_t out_height) {
    FILE *fp = fopen(path, "wb");
    if (fp == NULL) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        return -1;
    }

    fprintf(fp, "P6\n%" PRIu32 " %" PRIu32 "\n255\n", out_width, out_height);
    for (uint32_t y = 0; y < out_height; y++) {
        uint32_t src_y = (uint32_t)(((uint64_t)y * height) / out_height);
        if (src_y >= height) {
            src_y = height - 1u;
        }
        for (uint32_t x = 0; x < out_width; x++) {
            uint32_t src_x = (uint32_t)(((uint64_t)x * width) / out_width);
            if (src_x >= width) {
                src_x = width - 1u;
            }
            uint32_t px = fb[(size_t)src_y * width + src_x];
            uint8_t rgb[3] = {
                (uint8_t)((px >> 16) & 0xffu),
                (uint8_t)((px >> 8) & 0xffu),
                (uint8_t)(px & 0xffu),
            };
            if (fwrite(rgb, 1u, sizeof(rgb), fp) != sizeof(rgb)) {
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
    if (argc < 3) {
        usage(argv[0]);
        return 2;
    }

    const char *mode = argv[1];
    const char *input_path = NULL;
    const char *dump_path = NULL;
    unsigned long fb_base = FB_BASE_DEFAULT;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t out_width = 0;
    uint32_t out_height = 0;
    int should_load = 1;
    FILE *fp = NULL;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    if (strcmp(mode, "raw") == 0) {
        if (argc < 5) {
            usage(argv[0]);
            return 2;
        }
        input_path = argv[2];
        width = (uint32_t)parse_ulong(argv[3], "width");
        height = (uint32_t)parse_ulong(argv[4], "height");
        if (argc >= 6) {
            dump_path = argv[5];
        }
        if (argc >= 7) {
            fb_base = parse_ulong(argv[6], "fb_base");
        }
    } else if (strcmp(mode, "ppm") == 0) {
        input_path = argv[2];
        fp = fopen(input_path, "rb");
        if (fp == NULL) {
            fprintf(stderr, "open %s failed: %s\n", input_path, strerror(errno));
            return 1;
        }
        if (read_ppm_header(fp, &width, &height) != 0) {
            fclose(fp);
            return 1;
        }
        if (argc >= 4) {
            dump_path = argv[3];
        }
        if (argc >= 5) {
            fb_base = parse_ulong(argv[4], "fb_base");
        }
    } else if (strcmp(mode, "dump") == 0) {
        if (argc < 5) {
            usage(argv[0]);
            return 2;
        }
        should_load = 0;
        width = (uint32_t)parse_ulong(argv[2], "width");
        height = (uint32_t)parse_ulong(argv[3], "height");
        dump_path = argv[4];
        out_width = width;
        out_height = height;
        if (argc >= 7) {
            out_width = (uint32_t)parse_ulong(argv[5], "out_width");
            out_height = (uint32_t)parse_ulong(argv[6], "out_height");
        }
        if (argc >= 8) {
            fb_base = parse_ulong(argv[7], "fb_base");
        }
    } else {
        usage(argv[0]);
        return 2;
    }

    if (strcmp(mode, "raw") == 0) {
        fp = fopen(input_path, "rb");
        if (fp == NULL) {
            fprintf(stderr, "open %s failed: %s\n", input_path, strerror(errno));
            return 1;
        }
    }

    size_t fb_bytes = 0;
    if (checked_fb_bytes(width, height, &fb_bytes) != 0) {
        fclose(fp);
        return 1;
    }

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        fclose(fp);
        return 1;
    }

    uint32_t *fb = (uint32_t *)map_phys(fd, fb_base, fb_bytes, "framebuffer");
    close(fd);
    if ((void *)fb == MAP_FAILED) {
        fclose(fp);
        return 1;
    }

    if (should_load) {
        int rc;
        if (strcmp(mode, "raw") == 0) {
            rc = load_raw_xrgb(fp, input_path, fb, width, height);
        } else {
            rc = load_ppm(fp, fb, width, height);
        }
        fclose(fp);
        if (rc != 0) {
            return 1;
        }

        printf("zx32_image_viewer: rendered %s to fb=0x%08lx (%" PRIu32 "x%" PRIu32
               ", %" PRIu64 " bytes)\n",
               input_path, fb_base, width, height, (uint64_t)fb_bytes);
    } else {
        printf("zx32_image_viewer: dumping fb=0x%08lx (%" PRIu32 "x%" PRIu32
               ", %" PRIu64 " bytes)\n",
               fb_base, width, height, (uint64_t)fb_bytes);
    }

    if (dump_path != NULL && dump_path[0] != '\0' && strcmp(dump_path, "-") != 0) {
        int dump_rc;
        if (out_width != 0u && out_height != 0u &&
            (out_width != width || out_height != height)) {
            dump_rc = write_ppm_scaled(fb, dump_path, width, height, out_width, out_height);
        } else {
            dump_rc = write_ppm(fb, dump_path, width, height);
        }
        if (dump_rc != 0) {
            return 1;
        }
        printf("zx32_image_viewer: wrote %s (%" PRIu32 "x%" PRIu32 ")\n",
               dump_path,
               out_width == 0u ? width : out_width,
               out_height == 0u ? height : out_height);
    }

    return 0;
}
