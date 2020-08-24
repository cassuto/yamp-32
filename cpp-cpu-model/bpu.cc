#include "bpu.h"
#include "cpu.h"
#include <iostream>

#define BPU_FAIL_LATENCY 1

BPU::BPU() :
    JR_hit(0),
    JR_miss(0),
    BCC_hit(0),
    BCC_miss(0)
{
}

uint32_t BPU::predJR() {
    return regfile[31];
}

uint64_t BPU::updateJR(uint32_t pred, uint32_t real)
{
    if (pred==real) {
        ++JR_hit;
        return 0;
    } else {
        ++JR_miss;
        return BPU_FAIL_LATENCY;
    }
}

bool BPU::predBCC(uint32_t pc, int32_t offset)
{
    if (offset > 0) {
        return false;
    } else {
        return true;
    }
}
uint64_t BPU::updateBCC(bool pred, bool real)
{
    if (pred==real) {
        ++BCC_hit;
        return 0;
    } else {
        ++BCC_miss;
        return BPU_FAIL_LATENCY;
    }
}

void BPU::dump()
{
    std::cout<<"=================="<<std::endl;
    std::cout<<"BPU dump:"<<std::endl;
    std::cout<<"\tJR"<<std::endl;
    std::cout<<"\tJR Hit:"<<JR_hit<<std::endl;
    std::cout<<"\tJR Miss:"<<JR_miss<<std::endl;
    std::cout<<"\tJR P(h):"<<(double)JR_hit/(JR_hit+JR_miss)<<std::endl;
    std::cout<<"\tBCC"<<std::endl;
    std::cout<<"\tBCC Hit:"<<BCC_hit<<std::endl;
    std::cout<<"\tBCC Miss:"<<BCC_miss<<std::endl;
    std::cout<<"\tBCC P(h):"<<(double)BCC_hit/(BCC_hit+BCC_miss)<<std::endl;
}