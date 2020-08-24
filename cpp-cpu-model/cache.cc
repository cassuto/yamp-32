#include <assert.h>
#include <iostream>
#include "cpu.h"
#include "cache.h"

template <typename T>
static inline T **create_2d(size_t d1, size_t d2) {
    T **ret = new T *[d1];
    for (size_t i = 0; i < d1; ++i) {
        ret[i] = new T[d2];
    }
    return ret;
}

Cache::Cache(bool enabled, int p_ways, int p_sets, int p_line,
        uint64_t hitLatency,
        uint64_t tmissRead, uint64_t tmissWrite,
        uint64_t tmissWriteRead) :
    enabled(enabled),
    tL1_CACHE_HIT_LATENCY(enabled ? hitLatency : 2),
    tL1_CACHE_MISS_WRITE(tmissWrite),
    tL1_CACHE_MISS_READ(tmissRead),
    tL1_CACHE_MISS_WRITE_READ(tmissWriteRead),
    P_WAYS(p_ways),
    P_SETS(p_sets),
    P_LINE(p_line),
    freq_hit(0),
    freq_miss(0),
    freq_miss_writeback(0)
{
    cache_v = create_2d<bool>((1L << P_WAYS), (1L << P_SETS));
    cache_dirty = create_2d<bool>((1L << P_SETS), (1L << P_WAYS));
    cache_lru = create_2d<int>((1L << P_WAYS), (1L << P_SETS));
    cache_addr = create_2d<uint32_t>((1L << P_WAYS), (1L << P_SETS));
    match = new bool[(1L << P_WAYS)];
    sfree = new bool[(1L << P_WAYS)];

    for (int k = 0; k < (1L << P_WAYS); ++k) {
        for (int j = 0; j < (1L << P_SETS); ++j) {
            cache_v[k][j] = 0;
            cache_lru[k][j] = k;
            cache_addr[k][j] = 0;
        }
    }
}

uint64_t Cache::getDelay(uint32_t pa, bool store)
{
    if (!enabled) return tL1_CACHE_HIT_LATENCY;

    int entry_idx = (pa >> P_LINE) & ((1<<P_SETS)-1);
    uint32_t maddr = pa >> (P_LINE + P_SETS);

    char hit = 0;
    char dirty = 0;
    int lru_thresh = 0;
    int free_set_idx = -1;
    uint64_t delta = 0;

    for (int i = 0; i < (1L << P_WAYS); i++)
    {
        match[i] = cache_v[i][entry_idx] && (cache_addr[i][entry_idx] == maddr);
        sfree[i] = cache_lru[i][entry_idx] == 0;

        if (match[i])
        {
            hit = 1;
        }
        if (sfree[i])
        {
            free_set_idx = i;
        }
        if (sfree[i] & cache_dirty[entry_idx][i])
        {
            dirty = 1;
        }
    }

    if (!hit)
    {
        assert(free_set_idx >= 0);

        /* Cache miss */
        cache_v[free_set_idx][entry_idx] = 1;
        cache_addr[free_set_idx][entry_idx] = maddr;
        hit = 1;

        if (dirty)
        {
            delta += tL1_CACHE_MISS_WRITE_READ;
            ++freq_miss_writeback;
        }
        else
        {
            delta += tL1_CACHE_MISS_READ;
        }

        ++freq_miss;
    }
    else
    {
        /* cache hit */
        ++freq_hit;
        delta = tL1_CACHE_HIT_LATENCY;
    }

    for (int i = 0; i < (1L << P_WAYS); i++)
    {
        match[i] = cache_v[i][entry_idx] && (cache_addr[i][entry_idx] == maddr);
        lru_thresh |= match[i] ? cache_lru[i][entry_idx] : 0;
    }

    for (int i = 0; i < (1L << P_WAYS); i++)
    {
        if (hit)
        {
            /* Update LRU priority */
            cache_lru[i][entry_idx] = match[i] ? (1 << P_WAYS) - 1 : (cache_lru[i][entry_idx] - (cache_lru[i][entry_idx] > lru_thresh)) & ((1 << P_WAYS) - 1);
            /* Mark dirty when written */
            if (match[i])
            {
                cache_dirty[entry_idx][i] |= store;
            }
        }
        else if (sfree[i])
        {
            /* Mark clean when entry is freed */
            cache_dirty[entry_idx][i] = 0;
        }
    }

    return delta;
}

uint64_t Cache::flush() {
    if (!enabled) return 0;

    uint64_t delta = 0;
    
    for (int i = 0; i < (1L << P_WAYS); i++) {
        for (uint32_t entry_idx=0; entry_idx < (1L << P_SETS); entry_idx++) {
            if (cache_dirty[entry_idx][i]) {
                cache_dirty[entry_idx][i] = 0;
                /* write back */
                delta += tL1_CACHE_MISS_WRITE;
            }

            /* fls_cnt counter takes one cycle */
            ++delta;
        }
    }
    return delta;
}

void Cache::dump()
{
    std::cout << "Cache dump:" << std::endl;
    std::cout << "\tHit: " << freq_hit << std::endl;
    std::cout << "\tMiss: " << freq_miss << std::endl;
    std::cout << "\t\tWriteback: "<< freq_miss_writeback << std::endl;
    std::cout << "\tP(h) = " << (double)freq_hit / (freq_hit + freq_miss) << std::endl;
}