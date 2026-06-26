/*
 * zx32_membench: micro-benchmark for the PL CPU DDR access path.
 *
 * Measures three regimes that stress the axi4_master_bridge differently:
 *   seq_read   - 8-beat burst refill path (icache/dcache miss)
 *   seq_write  - single-beat write path (write-through, no-allocate)
 *   rand_read  - cold-miss latency (every access trips a refill)
 *
 * Cache geometry (must match rtl/soc/zx32_soc.sv):
 *   ICACHE_LINES = 128, DCACHE_LINES = 128, line = 32 bytes
 *   total dcache size = 128 * 32 = 4 KiB
 * The benchmark uses BUF_BYTES well above that to keep miss rate near 100 %.
 *
 * If /dev/mem is accessible, also dumps SoC perf counters around each run.
 * CTRL aperture lives at PL CPU physical 0x10030000 (CTRL_BASE).
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define LINE_BYTES   32u
#define BUF_BYTES    (256u * 1024u)
#define BUF_WORDS    (BUF_BYTES / 4u)
#define LINES_IN_BUF (BUF_BYTES / LINE_BYTES)

#define CTRL_BASE    0x10030000UL
#define CTRL_SIZE    0x1000UL

/* CTRL register byte offsets (= idx * 4, idx from rtl/soc/zx32_soc.sv ctrl_rdata case) */
#define R_MCYCLE_LO        0x80
#define R_MCYCLE_HI        0x84
#define R_MINSTRET_LO      0x88
#define R_MINSTRET_HI      0x8c
#define R_FETCH_WAIT       0x98
#define R_DMEM_WAIT        0x9c
#define R_IMEM_DDR_REQS    0xa0
#define R_DMEM_DDR_REQS    0xa4
#define R_DDR_WAIT         0xa8
#define R_ICACHE_HITS      0xac
#define R_ICACHE_MISSES    0xb0
#define R_DCACHE_HITS      0xb4
#define R_DCACHE_MISSES    0xb8
#define R_ICACHE_WAIT      0xbc
#define R_DCACHE_WAIT      0xc0
#define R_DMEM_RAW_WAIT    0xc4
#define R_HOST_DDR_WAIT    0xc8
#define R_ICACHE_REFILL_B  0xcc
#define R_DCACHE_REFILL_B  0xd0
#define R_DMEM_RAW_READS   0xd4
#define R_DMEM_RAW_WRITES  0xd8
#define R_HOST_DDR_REQS    0xdc
#define R_CACHE_INVAL      0xe0
#define R_DDR_BUSY         0xe4
#define R_ICACHE_BLOCKED   0xe8

typedef struct {
    uint32_t mcycle_lo;
    uint32_t imem_ddr_reqs;
    uint32_t dmem_ddr_reqs;
    uint32_t ddr_wait;
    uint32_t dcache_hits;
    uint32_t dcache_misses;
    uint32_t dcache_wait;
    uint32_t dcache_refill_beats;
    uint32_t dmem_raw_wait;
    uint32_t dmem_raw_reads;
    uint32_t dmem_raw_writes;
    uint32_t cache_inval;
    uint32_t ddr_busy;
} perf_t;

static volatile uint32_t *g_ctrl = NULL;

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static uint32_t lcg(uint32_t s) {
    return s * 1664525u + 1013904223u;
}

/* Defeat dead-store elimination */
static volatile uint32_t sink;

static int perf_init(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) return -1;
    void *p = mmap(NULL, CTRL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, CTRL_BASE);
    close(fd);
    if (p == MAP_FAILED) return -1;
    g_ctrl = (volatile uint32_t *)p;
    return 0;
}

static uint32_t perf_rd(uint32_t off) {
    return g_ctrl[off >> 2];
}

static void perf_snapshot(perf_t *s) {
    if (!g_ctrl) { memset(s, 0, sizeof(*s)); return; }
    s->mcycle_lo           = perf_rd(R_MCYCLE_LO);
    s->imem_ddr_reqs       = perf_rd(R_IMEM_DDR_REQS);
    s->dmem_ddr_reqs       = perf_rd(R_DMEM_DDR_REQS);
    s->ddr_wait            = perf_rd(R_DDR_WAIT);
    s->dcache_hits         = perf_rd(R_DCACHE_HITS);
    s->dcache_misses       = perf_rd(R_DCACHE_MISSES);
    s->dcache_wait         = perf_rd(R_DCACHE_WAIT);
    s->dcache_refill_beats = perf_rd(R_DCACHE_REFILL_B);
    s->dmem_raw_wait       = perf_rd(R_DMEM_RAW_WAIT);
    s->dmem_raw_reads      = perf_rd(R_DMEM_RAW_READS);
    s->dmem_raw_writes     = perf_rd(R_DMEM_RAW_WRITES);
    s->cache_inval         = perf_rd(R_CACHE_INVAL);
    s->ddr_busy            = perf_rd(R_DDR_BUSY);
}

static void perf_print_delta(const perf_t *a, const perf_t *b) {
    if (!g_ctrl) return;
    uint32_t cyc   = b->mcycle_lo - a->mcycle_lo;
    uint32_t hits  = b->dcache_hits - a->dcache_hits;
    uint32_t miss  = b->dcache_misses - a->dcache_misses;
    uint32_t dcw   = b->dcache_wait - a->dcache_wait;
    uint32_t dcrb  = b->dcache_refill_beats - a->dcache_refill_beats;
    uint32_t dmw_w = b->dmem_raw_wait - a->dmem_raw_wait;
    uint32_t dmr   = b->dmem_raw_reads - a->dmem_raw_reads;
    uint32_t dmw_w_cnt = b->dmem_raw_writes - a->dmem_raw_writes;
    uint32_t inval = b->cache_inval - a->cache_inval;
    uint32_t busy  = b->ddr_busy - a->ddr_busy;
    uint32_t wait  = b->ddr_wait - a->ddr_wait;
    printf("           cyc=%u dcache hit=%u miss=%u (refill_beats=%u, wait=%u)\n",
           cyc, hits, miss, dcrb, dcw);
    printf("           dmem_raw r=%u w=%u (wait=%u) inval=%u  ddr busy=%u wait=%u\n",
           dmr, dmw_w_cnt, dmw_w, inval, busy, wait);
}

static double bench_seq_read(uint32_t *buf) {
    double t0 = now_sec();
    uint32_t acc = 0;
    for (uint32_t i = 0; i < BUF_WORDS; i++) {
        acc += buf[i];
    }
    double t1 = now_sec();
    sink = acc;
    return t1 - t0;
}

static double bench_seq_write(uint32_t *buf) {
    double t0 = now_sec();
    for (uint32_t i = 0; i < BUF_WORDS; i++) {
        buf[i] = i + 1;
    }
    double t1 = now_sec();
    return t1 - t0;
}

static double bench_rand_read(uint32_t *buf) {
    /* Step a different cache line each access; every load is a cold miss
     * because BUF_BYTES greatly exceeds the dcache. */
    uint32_t line_step = LINE_BYTES / 4u;
    uint32_t accesses = LINES_IN_BUF;
    uint32_t state = 0x12345678u;
    uint32_t acc = 0;
    double t0 = now_sec();
    for (uint32_t k = 0; k < accesses; k++) {
        state = lcg(state);
        uint32_t idx = (state % LINES_IN_BUF) * line_step;
        acc += buf[idx];
    }
    double t1 = now_sec();
    sink = acc;
    return t1 - t0;
}

static void run_case(const char *name,
                     double (*fn)(uint32_t *),
                     uint32_t *buf,
                     uint32_t bytes_per_run,
                     int runs) {
    double best = 1e30;
    double sum = 0.0;
    perf_t a, b, best_a, best_b;
    memset(&best_a, 0, sizeof(best_a));
    memset(&best_b, 0, sizeof(best_b));
    for (int r = 0; r < runs; r++) {
        perf_snapshot(&a);
        double dt = fn(buf);
        perf_snapshot(&b);
        if (dt < best) { best = dt; best_a = a; best_b = b; }
        sum += dt;
    }
    double avg = sum / (double)runs;
    double mbps_best = ((double)bytes_per_run / best) / (1024.0 * 1024.0);
    double mbps_avg  = ((double)bytes_per_run / avg)  / (1024.0 * 1024.0);
    double ns_best = (best * 1e9) / ((double)bytes_per_run / 4.0);
    printf("%-10s best=%.3f ms (%.2f MB/s, %.1f ns/word)  "
           "avg=%.3f ms (%.2f MB/s)\n",
           name,
           best * 1e3, mbps_best, ns_best,
           avg * 1e3, mbps_avg);
    perf_print_delta(&best_a, &best_b);
}

int main(int argc, char **argv) {
    int runs = 5;
    if (argc >= 2) {
        runs = atoi(argv[1]);
        if (runs < 1) runs = 1;
    }

    int perf_ok = (perf_init() == 0);

    uint32_t *buf = aligned_alloc(LINE_BYTES, BUF_BYTES);
    if (!buf) {
        fprintf(stderr, "aligned_alloc failed\n");
        return 1;
    }
    memset(buf, 0, BUF_BYTES);

    printf("zx32_membench: BUF=%u KiB, line=%u B, runs=%d  perf=%s\n",
           BUF_BYTES / 1024u, LINE_BYTES, runs,
           perf_ok ? "on" : "off (no /dev/mem)");

    (void)bench_seq_read(buf);

    run_case("seq_read",  bench_seq_read,  buf, BUF_BYTES, runs);
    run_case("seq_write", bench_seq_write, buf, BUF_BYTES, runs);
    run_case("rand_read", bench_rand_read, buf, LINES_IN_BUF * 4u, runs);

    free(buf);
    return 0;
}
