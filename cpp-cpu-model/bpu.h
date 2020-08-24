#ifndef BPU_H_
#define BPU_H_

#include <stdint.h>

class BPU {
public:
    BPU();
    uint32_t predJR();
    uint64_t updateJR(uint32_t pred, uint32_t real);

    bool predBCC(uint32_t pc, int32_t offset);
    uint64_t updateBCC(bool pred, bool real);

    void dump();

    int JR_hit, JR_miss;
    int BCC_hit, BCC_miss;
};

#endif // BPU_H