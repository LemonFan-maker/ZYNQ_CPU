#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

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

static speed_t baud_to_speed(unsigned baud) {
    switch (baud) {
    case 9600: return B9600;
    case 19200: return B19200;
    case 38400: return B38400;
    case 57600: return B57600;
    case 115200: return B115200;
    case 230400: return B230400;
    case 460800: return B460800;
    case 921600: return B921600;
    default: return 0;
    }
}

static int configure_serial(int fd, unsigned baud) {
    speed_t speed = baud_to_speed(baud);
    if (speed == 0) {
        fprintf(stderr, "unsupported baud: %u\n", baud);
        return -1;
    }

    struct termios tio;
    if (tcgetattr(fd, &tio) != 0) {
        perror("tcgetattr");
        return -1;
    }

    cfmakeraw(&tio);
    cfsetispeed(&tio, speed);
    cfsetospeed(&tio, speed);
    tio.c_cflag |= CLOCAL | CREAD;
#ifdef CRTSCTS
    tio.c_cflag &= ~CRTSCTS;
#endif
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 1;

    if (tcsetattr(fd, TCSANOW, &tio) != 0) {
        perror("tcsetattr");
        return -1;
    }
    tcflush(fd, TCIOFLUSH);
    return 0;
}

static int read_line(int fd, char *line, size_t cap, double timeout_sec) {
    size_t len = 0;
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (;;) {
        char c;
        ssize_t n = read(fd, &c, 1);
        if (n == 1) {
            if (c == '\r') {
                continue;
            }
            if (c == '\n') {
                line[len] = '\0';
                return 0;
            }
            if (len + 1 < cap) {
                line[len++] = c;
            }
        } else if (n < 0 && errno != EAGAIN && errno != EINTR) {
            perror("read");
            return -1;
        }

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double elapsed = (double)(now.tv_sec - start.tv_sec) +
                         (double)(now.tv_nsec - start.tv_nsec) * 1e-9;
        if (elapsed > timeout_sec) {
            fprintf(stderr, "timeout waiting for transfer line\n");
            return -2;
        }
    }
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

static int send_board_command(int fd, const char *board_file) {
    char cmd[384];
    int n = snprintf(cmd, sizeof(cmd), "\nzx32_uart_send %s\n", board_file);
    if (n <= 0 || (size_t)n >= sizeof(cmd)) {
        fprintf(stderr, "board command too long\n");
        return -1;
    }
    if (write(fd, cmd, (size_t)n) != n) {
        perror("write command");
        return -1;
    }
    tcdrain(fd);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 5) {
        fprintf(stderr, "usage: %s <serial-dev> <output-file> [board-file] [baud]\n", argv[0]);
        return 2;
    }

    const char *serial_path = argv[1];
    const char *out_path = argv[2];
    const char *board_file = argc >= 4 ? argv[3] : NULL;
    unsigned baud = argc >= 5 ? (unsigned)strtoul(argv[4], NULL, 0) : 115200u;

    int fd = open(serial_path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        fprintf(stderr, "open %s failed: %s\n", serial_path, strerror(errno));
        return 1;
    }
    if (configure_serial(fd, baud) != 0) {
        close(fd);
        return 1;
    }

    if (board_file != NULL && send_board_command(fd, board_file) != 0) {
        close(fd);
        return 1;
    }

    FILE *out = fopen(out_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "open %s failed: %s\n", out_path, strerror(errno));
        close(fd);
        return 1;
    }

    char line[LINE_MAX_BYTES];
    uint32_t expected_size = 0;
    uint32_t expected_seq = 0;
    uint32_t total_crc = 0;
    uint32_t bytes_written = 0;
    int in_transfer = 0;

    for (;;) {
        int rc = read_line(fd, line, sizeof(line), 20.0);
        if (rc != 0) {
            fclose(out);
            close(fd);
            return 1;
        }

        if (strncmp(line, "ZXU1 BEGIN ", 11) == 0) {
            char name[128];
            if (sscanf(line, "ZXU1 BEGIN %127s %" SCNx32, name, &expected_size) != 2) {
                fprintf(stderr, "bad begin frame: %s\n", line);
                fclose(out);
                close(fd);
                return 1;
            }
            fprintf(stderr, "receiving %s (%" PRIu32 " bytes)\n", name, expected_size);
            in_transfer = 1;
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
                close(fd);
                return 1;
            }

            uint32_t seq = (uint32_t)strtoul(seq_s, NULL, 16);
            size_t len = strtoul(len_s, NULL, 16);
            uint32_t frame_crc = (uint32_t)strtoul(crc_s, NULL, 16);
            if (seq != expected_seq || len > 64 || strlen(hex_s) != len * 2) {
                fprintf(stderr, "bad data metadata: seq=%" PRIu32 " expected=%" PRIu32 " len=%zu\n",
                        seq, expected_seq, len);
                fclose(out);
                close(fd);
                return 1;
            }

            uint8_t data[64];
            if (decode_hex(hex_s, data, len) != 0) {
                fprintf(stderr, "bad hex payload at seq=%" PRIu32 "\n", seq);
                fclose(out);
                close(fd);
                return 1;
            }
            uint32_t got_crc = crc32_update(0, data, len);
            if (got_crc != frame_crc) {
                fprintf(stderr, "crc mismatch at seq=%" PRIu32 ": got=%08" PRIx32 " expected=%08" PRIx32 "\n",
                        seq, got_crc, frame_crc);
                fclose(out);
                close(fd);
                return 1;
            }
            if (fwrite(data, 1, len, out) != len) {
                fprintf(stderr, "write %s failed\n", out_path);
                fclose(out);
                close(fd);
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
                close(fd);
                return 1;
            }
            if (frames != expected_seq || bytes_written != expected_size || total_crc != expected_crc) {
                fprintf(stderr,
                        "transfer mismatch: frames=%" PRIu32 "/%" PRIu32
                        " bytes=%" PRIu32 "/%" PRIu32 " crc=%08" PRIx32 "/%08" PRIx32 "\n",
                        expected_seq, frames, bytes_written, expected_size, total_crc, expected_crc);
                fclose(out);
                close(fd);
                return 1;
            }
            break;
        }
    }

    fclose(out);
    close(fd);
    fprintf(stderr, "wrote %s (%" PRIu32 " bytes, crc=%08" PRIx32 ")\n",
            out_path, bytes_written, total_crc);
    return 0;
}
