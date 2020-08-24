#ifndef CACHE_H_
#define CACHE_H_

class Cache {
public:
    Cache(bool enabled, int p_ways, int p_sets, int p_line, uint64_t hitLatency, uint64_t tmissRead, uint64_t tmissWrite, uint64_t tmissWriteRead);
    uint64_t getDelay(uint32_t pa, bool store);
    uint64_t flush();
    void dump();

private:
    bool enabled;
    uint64_t tL1_CACHE_HIT_LATENCY;
    uint64_t tL1_CACHE_MISS_WRITE;
    uint64_t tL1_CACHE_MISS_READ;
    uint64_t tL1_CACHE_MISS_WRITE_READ;
    int P_WAYS, P_SETS, P_LINE;

    bool **cache_v;
    bool **cache_dirty;
    int **cache_lru;
    uint32_t **cache_addr;

    bool *match;
    bool *sfree;

    uint64_t freq_hit, freq_miss, freq_miss_writeback;
};

#endif // CACHE_H_
