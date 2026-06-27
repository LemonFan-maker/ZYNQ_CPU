#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINE_MAX_BYTES 512

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

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int decode_hex(const char *hex, uint8_t *out, size_t len) {
    for (size_t i = 0; i < len; i++) {
        int hi = hex_nibble(hex[i * 2]);
        int lo = hex_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return -1;
        }
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return 0;
}

static char *strip_line(char *line) {
    while (*line == '\r' || *line == '\n' || *line == ' ' || *line == '\t') {
        line++;
    }

    size_t len = strlen(line);
    while (len > 0) {
        char c = line[len - 1];
        if (c != '\r' && c != '\n' && c != ' ' && c != '\t') {
            break;
        }
        line[--len] = '\0';
    }
    return line;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <input-log|-> <output-file>\n", argv[0]);
        return 2;
    }

    const char *input_path = argv[1];
    const char *out_path = argv[2];

    FILE *in = stdin;
    if (strcmp(input_path, "-") != 0) {
        in = fopen(input_path, "rb");
        if (in == NULL) {
            fprintf(stderr, "open %s failed: %s\n", input_path, strerror(errno));
            return 1;
        }
    }

    FILE *out = fopen(out_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "open %s failed: %s\n", out_path, strerror(errno));
        if (in != stdin) fclose(in);
        return 1;
    }

    char raw[LINE_MAX_BYTES];
    uint32_t expected_size = 0;
    uint32_t expected_seq = 0;
    uint32_t total_crc = 0;
    uint32_t bytes_written = 0;
    int in_transfer = 0;
    int saw_transfer = 0;

    while (fgets(raw, sizeof(raw), in) != NULL) {
        char *line = strip_line(raw);

        if (strncmp(line, "ZXU1 BEGIN ", 11) == 0) {
            char name[128];
            if (sscanf(line, "ZXU1 BEGIN %127s %" SCNx32, name, &expected_size) != 2) {
                fprintf(stderr, "bad begin frame: %s\n", line);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }
            fprintf(stderr, "decoding %s (%" PRIu32 " bytes)\n", name, expected_size);
            in_transfer = 1;
            saw_transfer = 1;
            expected_seq = 0;
            total_crc = 0;
            bytes_written = 0;
            continue;
        }

        if (!in_transfer) {
            continue;
        }

        if (strncmp(line, "ZXU1 DATA ", 10) == 0) {
            char *save = NULL;
            char *tok = strtok_r(line, " ", &save);
            (void)tok;
            tok = strtok_r(NULL, " ", &save);
            (void)tok;
            char *seq_s = strtok_r(NULL, " ", &save);
            char *len_s = strtok_r(NULL, " ", &save);
            char *crc_s = strtok_r(NULL, " ", &save);
            char *hex_s = strtok_r(NULL, " ", &save);
            if (seq_s == NULL || len_s == NULL || crc_s == NULL || hex_s == NULL) {
                fprintf(stderr, "bad data frame\n");
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }

            uint32_t seq = (uint32_t)strtoul(seq_s, NULL, 16);
            size_t len = strtoul(len_s, NULL, 16);
            uint32_t frame_crc = (uint32_t)strtoul(crc_s, NULL, 16);
            if (seq != expected_seq || len > 64 || strlen(hex_s) != len * 2) {
                fprintf(stderr, "bad data metadata: seq=%" PRIu32
                        " expected=%" PRIu32 " len=%zu\n",
                        seq, expected_seq, len);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }

            uint8_t data[64];
            if (decode_hex(hex_s, data, len) != 0) {
                fprintf(stderr, "bad hex payload at seq=%" PRIu32 "\n", seq);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }
            uint32_t got_crc = crc32_update(0, data, len);
            if (got_crc != frame_crc) {
                fprintf(stderr, "crc mismatch at seq=%" PRIu32
                        ": got=%08" PRIx32 " expected=%08" PRIx32 "\n",
                        seq, got_crc, frame_crc);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }
            if (fwrite(data, 1, len, out) != len) {
                fprintf(stderr, "write %s failed\n", out_path);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }
            total_crc = crc32_update(total_crc, data, len);
            bytes_written += (uint32_t)len;
            expected_seq++;
            continue;
        }

        if (strncmp(line, "ZXU1 END ", 9) == 0) {
            uint32_t frames = 0;
            uint32_t expected_crc = 0;
            if (sscanf(line, "ZXU1 END %" SCNx32 " %" SCNx32, &frames, &expected_crc) != 2) {
                fprintf(stderr, "bad end frame: %s\n", line);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }
            if (frames != expected_seq || bytes_written != expected_size || total_crc != expected_crc) {
                fprintf(stderr,
                        "transfer mismatch: frames=%" PRIu32 "/%" PRIu32
                        " bytes=%" PRIu32 "/%" PRIu32 " crc=%08" PRIx32 "/%08" PRIx32 "\n",
                        expected_seq, frames, bytes_written, expected_size, total_crc, expected_crc);
                fclose(out);
                if (in != stdin) fclose(in);
                return 1;
            }
            in_transfer = 0;
            break;
        }
    }

    if (!saw_transfer) {
        fprintf(stderr, "no ZXU1 transfer found in %s\n", input_path);
        fclose(out);
        if (in != stdin) fclose(in);
        return 1;
    }
    if (in_transfer) {
        fprintf(stderr, "incomplete ZXU1 transfer in %s\n", input_path);
        fclose(out);
        if (in != stdin) fclose(in);
        return 1;
    }

    if (fclose(out) != 0) {
        fprintf(stderr, "close %s failed: %s\n", out_path, strerror(errno));
        if (in != stdin) fclose(in);
        return 1;
    }
    if (in != stdin) fclose(in);

    fprintf(stderr, "wrote %s (%" PRIu32 " bytes, crc=%08" PRIx32 ")\n",
            out_path, bytes_written, total_crc);
    return 0;
}
