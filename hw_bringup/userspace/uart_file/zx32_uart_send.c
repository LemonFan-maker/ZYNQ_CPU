#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHUNK_BYTES 32u

static uint32_t crc32_update(uint32_t crc, const uint8_t *data, size_t len) {
    crc = ~crc;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (unsigned bit = 0; bit < 8; bit++) {
            uint32_t mask = 0u - (crc & 1u);
            crc = (crc >> 1) ^ (0xedb88320u & mask);
        }
    }
    return ~crc;
}

static int basename_ascii(const char *path, char *out, size_t out_len) {
    const char *base = strrchr(path, '/');
    base = base == NULL ? path : base + 1;
    if (*base == '\0') {
        base = "uart_file.bin";
    }

    size_t n = 0;
    while (base[n] != '\0' && n + 1 < out_len) {
        unsigned char c = (unsigned char)base[n];
        out[n] = (c >= 33 && c <= 126 && c != ' ') ? (char)c : '_';
        n++;
    }
    out[n] = '\0';
    return n == 0 ? -1 : 0;
}

static int file_size(FILE *fp, uint32_t *size_out) {
    struct stat st;
    if (fstat(fileno(fp), &st) != 0) {
        return -1;
    }
    if (st.st_size < 0 || st.st_size > 0xffffffffLL) {
        errno = EFBIG;
        return -1;
    }
    *size_out = (uint32_t)st.st_size;
    return 0;
}

static void print_hex(const uint8_t *buf, size_t len) {
    static const char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < len; i++) {
        putchar(hex[buf[i] >> 4]);
        putchar(hex[buf[i] & 0xfu]);
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <file>\n", argv[0]);
        return 2;
    }

    const char *path = argv[1];
    FILE *fp = fopen(path, "rb");
    if (fp == NULL) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        return 1;
    }

    uint32_t size = 0;
    if (file_size(fp, &size) != 0) {
        fprintf(stderr, "stat %s failed: %s\n", path, strerror(errno));
        fclose(fp);
        return 1;
    }

    char name[96];
    if (basename_ascii(path, name, sizeof(name)) != 0) {
        fclose(fp);
        return 1;
    }

    setvbuf(stdout, NULL, _IONBF, 0);
    fprintf(stdout, "ZXU1 BEGIN %s %08" PRIx32 "\n", name, size);

    uint8_t buf[CHUNK_BYTES];
    uint32_t seq = 0;
    uint32_t total_crc = 0;
    uint32_t offset = 0;
    while (offset < size) {
        size_t want = size - offset;
        if (want > sizeof(buf)) {
            want = sizeof(buf);
        }
        size_t got = fread(buf, 1, want, fp);
        if (got != want) {
            fprintf(stderr, "read %s failed\n", path);
            fclose(fp);
            return 1;
        }

        uint32_t chunk_crc = crc32_update(0, buf, got);
        total_crc = crc32_update(total_crc, buf, got);
        fprintf(stdout, "ZXU1 DATA %08" PRIx32 " %02zx %08" PRIx32 " ", seq, got, chunk_crc);
        print_hex(buf, got);
        fputc('\n', stdout);

        seq++;
        offset += (uint32_t)got;
    }

    fprintf(stdout, "ZXU1 END %08" PRIx32 " %08" PRIx32 "\n", seq, total_crc);
    fclose(fp);
    return 0;
}
