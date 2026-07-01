#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "zx32_sysmon.h"

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

int main(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        return 1;
    }

    volatile uint32_t *regs = (volatile uint32_t *)map_phys(fd, ZX32_CTRL_BASE_DEFAULT,
                                                            ZX32_CTRL_SIZE, "zx32-ctrl");
    close(fd);
    if (regs == MAP_FAILED) {
        return 1;
    }

    struct zx32_sysmon_sample s;
    zx32_sysmon_sample(regs, &s);
    if (!zx32_sysmon_temp_valid(&s)) {
        printf("Zynq temperature: N/A status=0x%08x seq=%u\n", s.status, s.sample_seq);
        return 2;
    }

    int32_t mc = s.temp_millic;
    const char *sign = "";
    if (mc < 0) {
        sign = "-";
        mc = -mc;
    }
    printf("Zynq temperature: %s%ld.%03ld C raw=0x%04x seq=%u status=0x%08x\n",
           sign, (long)(mc / 1000), (long)(mc % 1000),
           (unsigned)(s.temp_raw & 0xffffu), s.sample_seq, s.status);
    return 0;
}
