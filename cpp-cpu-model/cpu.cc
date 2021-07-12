#include <bits/stdc++.h>
#include "uart.h"
#include "termtest.h"
#include "cache.h"
#include "cpu.h"
#include "bpu.h"

#define DIV2

#define SRAM_FCLK_RATIO 2
#ifdef DIV2
#define ICACHE_HANDSHAK_LATENCY 2
#define DCACHE_HANDSHAK_LATENCY 2
#else
#define ICACHE_HANDSHAK_LATENCY 11.5
#define DCACHE_HANDSHAK_LATENCY 11
#endif

#define ENABLE_SB 1
#define STORE_BUFFER_LATENCY 1
#define STORE_BUFFER_SIZE 16

char basemem[BASEMEM_SIZE];
char extmem[EXTMEM_SIZE];
static uint64_t timestamp;
uint32_t regfile[32];
static uint32_t pc = 0x80000000;
static bool delay_jmp;
static uint32_t next_pc;

static Cache *dcache;
static Cache *icache;
static BPU *bpu;
static const char *kernel_bin;

#define gen_mask(len) ((1<<(len))-1)
#define get_field(_tgt, _be, _bs) (_tgt>>(_bs)) & gen_mask((_be)-(_bs)+1)

inline uint32_t segmap(uint32_t addr) {
    return addr & 0x1fffffff;
}
inline int32_t sext16(uint16_t uimm16) {
    return (((int32_t)uimm16) ^ 0x8000) - 0x8000;
}
inline int32_t sext16_disp(uint16_t uimm16) {
    return sext16(uimm16)<<2;
}

template<typename T>
inline T read_m(uint32_t vaddr) {
    uint32_t phyaddr = segmap(vaddr);
    if (phyaddr >= EXTMEM_OFFSET && phyaddr < EXTMEM_OFFSET+EXTMEM_SIZE) {
        phyaddr -= EXTMEM_OFFSET;
        return *((T *)&extmem[phyaddr]); /* little-endian only */
    } else if (phyaddr >= BASEMEM_OFFSET && phyaddr < BASEMEM_OFFSET+BASEMEM_SIZE) {
        phyaddr -= BASEMEM_OFFSET;
        return *((T *)&basemem[phyaddr]); /* little-endian only */
    } else if (vaddr == 0xbfd003f8) {
        return uart_read();
    } else if (vaddr == 0xbfd003fc) {
        return uart_status();
    } else {
        printf("%s(): %x pc=%x\n", __func__, vaddr, pc);
        assert(0);
    }
}

const int n_pc_queue = 64;
uint32_t pc_queue[n_pc_queue];
int pos;


template<typename T>
inline void write_m(uint32_t vaddr, T dat) {
    uint32_t phyaddr = segmap(vaddr);
    if (phyaddr >= EXTMEM_OFFSET && phyaddr < EXTMEM_OFFSET+EXTMEM_SIZE) {
        phyaddr -= EXTMEM_OFFSET;
        *((T *)&extmem[phyaddr]) = dat; /* little-endian only */
    } else if (phyaddr >= BASEMEM_OFFSET && phyaddr < BASEMEM_OFFSET+BASEMEM_SIZE) {
        phyaddr -= BASEMEM_OFFSET;
        *((T *)&basemem[phyaddr]) = dat; /* little-endian only */
    } else if (vaddr == 0xbfd003f8) {
        uart_write(dat);
    } else if (vaddr == 0xbfd003fc) {
        printf("WARNING! unknown writing operation to UART.\n");
    } else {
        printf("%s(): %x pc=%x reg=%x\n", __func__, vaddr, pc, regfile[8]);
        assert(0);
    }
}

inline uint32_t get_regfile(uint8_t addr) {
    return addr==0 ? 0 : regfile[addr];
}
inline void set_regfile(uint8_t addr, uint32_t dat) {
    addr!=0 && (regfile[addr] = dat);
}

void cpu_rst() {
    pc = 0x80000000;
    timestamp = 0;
    delay_jmp = false;
    next_pc = 0x0;
}

int sb_hit, sb_miss;

#if ENABLE_SB
struct node {
    uint64_t start, end;
    uint32_t paddr;
};
std::queue<node> storeBuffer;

void storeBufferPop() {
    node nd = storeBuffer.front();
    storeBuffer.pop();
    if (nd.end > cpu_timestamp()) {
        timestamp += nd.end - cpu_timestamp() + STORE_BUFFER_LATENCY;
        ++sb_miss;
    }
}
#endif

void getStoreDelay(uint32_t paddr) {
#if ENABLE_SB
    if (storeBuffer.size() >= STORE_BUFFER_SIZE) {
        storeBufferPop();
    }
    uint64_t delay = dcache->getDelay(paddr, true);
    node nd;
    nd.paddr = paddr;
    nd.start = cpu_timestamp();
    nd.end = cpu_timestamp() + delay;
    storeBuffer.push(nd);
#else
    timestamp += dcache->getDelay(paddr, true);
#endif
}
void getLoadDelay(uint32_t paddr) {
#if ENABLE_SB
    while (!storeBuffer.empty()) {
        storeBufferPop();
    }
    timestamp += dcache->getDelay(paddr, false);
#else
    timestamp += dcache->getDelay(paddr, false);
#endif
}

void stoerBufferClk() {
#if ENABLE_SB
    if (!storeBuffer.empty()) {
        node nd = storeBuffer.front();
        if (nd.end <= cpu_timestamp()) {
            storeBuffer.pop();
            timestamp += nd.end - cpu_timestamp() + STORE_BUFFER_LATENCY;
            ++sb_miss;
        }
    }
#endif
}

void cpu_clk() {
#define ISSUE_DELAY_JMP(_tgt_addr) \
    do {\
        next_pc = (_tgt_addr); \
        assert(!delay_jmp); \
        delay_jmp = true; \
        goto fetch_next; \
    } while(0)

    timestamp++;

    if (pos < n_pc_queue) {
        pc_queue[pos++] = pc;
    } else {
        memmove(pc_queue, &pc_queue[1], sizeof(pc_queue)-sizeof(uint32_t));
        pc_queue[n_pc_queue-1] = pc;
    }
    
    uint32_t i_insn = read_m<uint32_t>(pc);
    uint8_t f_opcode = get_field(i_insn, 31,26);
    uint8_t f_rs = get_field(i_insn, 25,21);
    uint8_t f_rt = get_field(i_insn, 20,16);
    uint8_t f_rd = get_field(i_insn, 15,11);
    uint8_t f_sa = get_field(i_insn, 10,6);
    uint8_t f_func = get_field(i_insn, 5,0);
    uint16_t f_imm16 = get_field(i_insn, 15,0);
    uint32_t f_disp26 = get_field(i_insn, 25,0);

    timestamp += icache->getDelay(segmap(pc), false);

    /* ==================================*/
    /* Set breakpoints here... */
    
    /*
if(pc==0x80000008) {
printf("op=%x r2=%x\n",f_opcode, get_regfile(2));
exit(1);
}
*/
    /* ==================================*/

    switch(f_opcode) {
        case 0x0:
            switch(f_func) {
                case 0x21: /* addu */
                    set_regfile(f_rd, get_regfile(f_rs) + get_regfile(f_rt));
                    break;
                case 0x24: /* and */
                    set_regfile(f_rd, get_regfile(f_rs) & get_regfile(f_rt));
                    break;
                case 0x25: /* or */
                    set_regfile(f_rd, get_regfile(f_rs) | get_regfile(f_rt));
                    break;
                case 0x26: /* xor */
                    set_regfile(f_rd, get_regfile(f_rs) ^ get_regfile(f_rt));
                    break;
                case 0x0: /* sll */
                    set_regfile(f_rd, get_regfile(f_rt) << f_sa);
                    break;
                case 0x2: /* slr */
                    set_regfile(f_rd, (uint32_t)get_regfile(f_rt) >> f_sa);
                    break;
                case 0x8: { /* jr */
                    uint32_t real = get_regfile(f_rs);
                    uint32_t pred = bpu->predJR();
                    timestamp += bpu->updateJR(pred, real);
                    ISSUE_DELAY_JMP(real);
                    break;
                }
                default:
                    assert(0);
            }
            break;
        
        case 0x9: /* addiu */
            set_regfile(f_rt, (int32_t)get_regfile(f_rs)+sext16(f_imm16));
            break;
        case 0x1c:
            switch(f_func) {
                case 0x2:/* mul */
                    set_regfile(f_rd, (int32_t)get_regfile(f_rs) * (int32_t)get_regfile(f_rt));
                    break;
                default:
                    assert(0);
            }
            break;

        case 0xc: /* andi */
            set_regfile(f_rt, get_regfile(f_rs) & (uint32_t)f_imm16);
            break;
        case 0xf: /* lui */
            set_regfile(f_rt, ((uint32_t)f_imm16)<<16);
            break;
        case 0xd: /* ori */
            set_regfile(f_rt, get_regfile(f_rs) | (uint32_t)f_imm16);
            break;
        case 0xe: /* xori */
            set_regfile(f_rt, get_regfile(f_rs) ^ (uint32_t)f_imm16);
            break;
        case 0x4: { /* be */
            bool real = get_regfile(f_rs)==get_regfile(f_rt);
            bool pred = bpu->predBCC(pc, sext16_disp(f_imm16));
            timestamp += bpu->updateBCC(pred, real);
            if (real) {
                ISSUE_DELAY_JMP(pc+4 + sext16_disp(f_imm16));
            }
            break;
        }
        case 0x5: { /* bne */
            bool real = get_regfile(f_rs)!=get_regfile(f_rt);
            bool pred = bpu->predBCC(pc, sext16_disp(f_imm16));
            timestamp += bpu->updateBCC(pred, real);
            if (real) {
                ISSUE_DELAY_JMP(pc+4 + sext16_disp(f_imm16));
            }
            break;
        }
        case 0x7: { /* bgtz */
            bool real = (int32_t)get_regfile(f_rs)>0;
            bool pred = bpu->predBCC(pc, sext16_disp(f_imm16));
            timestamp += bpu->updateBCC(pred, real);
            if (real) {
                ISSUE_DELAY_JMP(pc+4 + sext16_disp(f_imm16));
            }
            break;
        }
        case 0x2: /* j */
            ISSUE_DELAY_JMP((pc & 0xf0000000) | (f_disp26<<2));
            break;
        case 0x3: /* jal */
            set_regfile(31, pc + 8);
            ISSUE_DELAY_JMP((pc & 0xf0000000) | (f_disp26<<2));
            break;

        case 0x20: { /* lb */
            uint32_t vaddr = get_regfile(f_rs) + sext16(f_imm16);
            int8_t dat = read_m<int8_t>(vaddr);
            set_regfile(f_rt, (int32_t)dat);
            getLoadDelay(segmap(vaddr&(~0x3)));
            break;
        }
        case 0x23: { /* lw */
            uint32_t vaddr = get_regfile(f_rs) + sext16(f_imm16);
            if (vaddr & 0x3) {
                assert(0); /* unaligned */
            }
            uint32_t dat = read_m<uint32_t>(vaddr);
            set_regfile(f_rt, dat);
            getLoadDelay(segmap(vaddr));
            break;
        }
        case 0x28: { /* sb */
            uint32_t vaddr = get_regfile(f_rs) + sext16(f_imm16);
            write_m<uint8_t>(vaddr, (uint8_t)get_regfile(f_rt));
            getStoreDelay(segmap(vaddr&(~0x3)));
            break;
        }
        case 0x2b: { /* sw */
            uint32_t vaddr = get_regfile(f_rs) + sext16(f_imm16);
            if (vaddr & 0x3) {
                assert(0); /* unaligned */
            }
            write_m<uint32_t>(vaddr, get_regfile(f_rt));
            getStoreDelay(segmap(vaddr));
            break;
        }
        default:
            assert(0);
    }
    
    /* check_ds */
    if (delay_jmp) {
        delay_jmp = false;
        pc = next_pc;
        return;
    }
    fetch_next:
        pc += 0x4;
}

uint64_t cpu_timestamp() {
    return timestamp;
}

void optimise_icache() {
    int iter_count = 0;
    uint64_t minTime = LONG_MAX;
    int tgt_p_ways=-1, tgt_p_line=-1, tgt_p_sets=-1;
    uint64_t tgt_testtime[3];

    /*
     * Create DCache
     */
    const int dcache_P_LINE = 1;
    const int dcacheLineSize = (1L<<dcache_P_LINE);
    const int dcacheMissRead = ceil(dcacheLineSize/4*SRAM_FCLK_RATIO)+DCACHE_HANDSHAK_LATENCY;
    const int dcacheMissWrite = ceil(dcacheLineSize/4*SRAM_FCLK_RATIO)+DCACHE_HANDSHAK_LATENCY;
    const int dcacheMissWriteRead = dcacheMissRead + dcacheMissWrite;

    dcache = new Cache(false, 2, 1, dcache_P_LINE, 1, dcacheMissRead, dcacheMissWrite, dcacheMissWriteRead);

    for(int i_pways=1;i_pways<=4;++i_pways) {
        for(int i_psets=1;i_psets<=13; ++i_psets) {
            for(int i_pline=1;i_pline<=13;++i_pline) {

                uint64_t tc_sum = 0;
                uint64_t testtime[3];
                for(int testcase=0;testcase<3;++testcase) {
                    /*
                    * Create ICache
                    */
                    const int icache_P_LINE = i_pline;
                    const int icacheLineSize = (1L<<icache_P_LINE);
                    const int icacheMissRead = ceil(icacheLineSize/4*SRAM_FCLK_RATIO)+ICACHE_HANDSHAK_LATENCY;
                    const int icacheMissWrite = ceil(icacheLineSize/4*SRAM_FCLK_RATIO)+ICACHE_HANDSHAK_LATENCY;
                    const int icacheMissWriteRead = icacheMissRead + icacheMissWrite;

                    icache = new Cache(true, i_pways, i_psets, icache_P_LINE, 0, icacheMissRead, icacheMissWrite, icacheMissWriteRead);

                    const char *testname;
                    switch(testcase) {
                        case 0:
                            testname = "STREAM";
                            break;
                        case 1:
                            testname = "MATRIX";
                            break;
                        case 2:
                            testname = "CRYPTONIGHT";
                            break;
                    }

                    termtest_init(kernel_bin, testname);
                    cpu_rst();

                    for(;;) {
                        cpu_clk();
                        stoerBufferClk();
                        termtest_clk();
                        if (termtest_done()) {
                            break;
                        }
                    }

                    testtime[testcase] = termtest_time() + dcache->flush();
                    tc_sum += testtime[testcase];
                    std::cout<<"testcase "<<testcase << " time="<<testtime[testcase]<<std::endl;
            
                    std::cout<<"DCache"<<std::endl;
                    dcache->dump();
                    std::cout<<"ICache"<<std::endl;
                    icache->dump();
                    
                    delete icache;
                }

                ++iter_count;

                if (minTime > tc_sum) {
                    minTime = tc_sum;
                    memcpy(tgt_testtime, testtime, sizeof(testtime));
                    tgt_p_ways = i_pways;
                    tgt_p_line = i_pline;
                    tgt_p_sets = i_psets;
                    std::cout<<"Current ("<<iter_count<<") min time: "<<minTime<<std::endl;
                }
            }
        }
    }

    delete dcache;

    std::cout<<"\nOptimise result:"<<std::endl;
    std::cout<<"Iter count:"<<iter_count<<std::endl;
    std::cout<<"Min time = "<<minTime<<std::endl;
    std::cout<<"STREAM = "<<tgt_testtime[0]<<std::endl;
    std::cout<<"MATRIX = "<<tgt_testtime[1]<<std::endl;
    std::cout<<"CRYPTO = "<<tgt_testtime[2]<<std::endl;

    std::cout<<"\tP_WAYS="<<tgt_p_ways<<std::endl;
    std::cout<<"\tP_LINE="<<tgt_p_line<<std::endl;
    std::cout<<"\tP_SETS="<<tgt_p_sets<<std::endl;
}


void optimise_dcache() {
    int iter_count = 0;
    uint64_t minSumTime = LONG_MAX;
    int tgt_p_line=-1, tgt_p_sets=-1, tgt_p_ways=-1;
    uint64_t tgt_testtime[3];
    
    uint64_t testtime[3];

    for(int d_pways=1;d_pways<=7;++d_pways) {
        for(int d_psets=1;d_psets<=20; ++d_psets) {
            for(int d_pline=2;d_pline<=20;++d_pline) {
                
                if ((1L<<d_pways)*(1L<<d_psets)*(1L<<d_pline) >= 1572864) { // 1.5MB
                    std::cout<<"************************** skip "<<d_pways<<" "<<d_psets<<" "<<d_pline<<std::endl;
                    continue;
                }

                std::cout<<"Optimizing p_ways="<<d_pways <<" p_sets="<<d_psets<<" p_line="<<d_pline<<std::endl;

                uint64_t timesum = 0;
                for(int testcase=0;testcase<3;testcase++) {
                    /*
                    * Create ICache
                    */
                    const int icache_P_LINE = 8;
                    const int icacheLineSize = (1L<<icache_P_LINE);
                    const int icacheMissRead = ceil(icacheLineSize/4*SRAM_FCLK_RATIO)+ICACHE_HANDSHAK_LATENCY;
                    const int icacheMissWrite = ceil(icacheLineSize/4*SRAM_FCLK_RATIO)+ICACHE_HANDSHAK_LATENCY;
                    const int icacheMissWriteRead = icacheMissRead + icacheMissWrite;

                    icache = new Cache(true, 2, 6, icache_P_LINE, 0, icacheMissRead, icacheMissWrite, icacheMissWriteRead);

                    /*
                    * Create DCache
                    */
                    const int dcache_P_LINE = d_pline;
                    const int dcacheLineSize = (1L<<dcache_P_LINE);
                    const int dcacheMissRead = ceil(dcacheLineSize/4*SRAM_FCLK_RATIO)+DCACHE_HANDSHAK_LATENCY;
                    const int dcacheMissWrite = ceil(dcacheLineSize/4*SRAM_FCLK_RATIO)+DCACHE_HANDSHAK_LATENCY;
                    const int dcacheMissWriteRead = dcacheMissRead + dcacheMissWrite;

                    dcache = new Cache(true, d_pways, d_psets, dcache_P_LINE, 0, dcacheMissRead, dcacheMissWrite, dcacheMissWriteRead);

                    const char *testname;
                    switch(testcase) {
                        case 0:
                            testname = "STREAM";
                            break;
                        case 1:
                            testname = "MATRIX";
                            break;
                        case 2:
                            testname = "CRYPTONIGHT";
                            break;
                    }

                    termtest_init(kernel_bin, testname);
                    cpu_rst();

                    for(;;) {
                        cpu_clk();
                        termtest_clk();
                        if (termtest_done()) {
                            break;
                        }
                    }

                    uint64_t tme = termtest_time() + dcache->flush();

                    testtime[testcase] = tme;

                    timesum += tme;

                    delete dcache;
                    delete icache;
                }

                if (minSumTime > timesum) {
                    minSumTime = timesum;
                    tgt_p_ways = d_pways;
                    tgt_p_line = d_pline;
                    tgt_p_sets = d_psets;
                    memcpy(tgt_testtime, testtime, sizeof(testtime));
                    std::cout<<"Current ("<<iter_count<<") min time: "<<minSumTime<<std::endl;
                }
                ++iter_count;
                
            }
        }
    }

    std::cout<<"\nOptimise result:"<<std::endl;
    std::cout<<"Iter count:"<<iter_count<<std::endl;
    std::cout<<"Min time = "<<minSumTime<<std::endl;
    std::cout<<"STREAM = "<<tgt_testtime[0]<<std::endl;
    std::cout<<"MATRIX = "<<tgt_testtime[1]<<std::endl;
    std::cout<<"CRYPTONIGHT = "<<tgt_testtime[2]<<std::endl;
    std::cout<<"\tP_WAYS="<<tgt_p_ways<<std::endl;
    std::cout<<"\tP_LINE="<<tgt_p_line<<std::endl;
    std::cout<<"\tP_SETS="<<tgt_p_sets<<std::endl;
}

static int usage(const char *exec)
{
    printf("Usage: %s <kernel_bin> <testcase>\nArguments:\n", exec);
    printf(" <kernel_bin>  Binary of supervisor program (In NSCSCC2020, this is 'supervisor_v2.01/kernel/kernel.bin').\n");
    printf(" <testcase>    One of STREAM , MATRIX or CRYPTONIGHT.\n");
    return 1;
}

int main(int argc, char *argv[])
{
  if (argc < 3)
       return usage(argv[0]);
    kernel_bin = argv[1];
    
    bpu = new BPU();
    //optimise();
    //optimise_icache();
    //optimise_dcache();
#if 1
    /*
    * Create DCache
    */
    const int dcache_P_LINE = 3;
    const int dcacheLineSize = (1L<<dcache_P_LINE);
    const int dcacheMissRead = ceil(dcacheLineSize/4*SRAM_FCLK_RATIO)+DCACHE_HANDSHAK_LATENCY;
    const int dcacheMissWrite = ceil(dcacheLineSize/4*SRAM_FCLK_RATIO)+DCACHE_HANDSHAK_LATENCY;
    const int dcacheMissWriteRead = dcacheMissRead + dcacheMissWrite;

    dcache = new Cache(false, 1, 16, dcache_P_LINE, 0, dcacheMissRead, dcacheMissWrite, dcacheMissWriteRead);

    /*
    * Create ICache
    */
    const int icache_P_LINE = 8;
    const int icacheLineSize = (1L<<icache_P_LINE);
    const int icacheMissRead = ceil(icacheLineSize/4*SRAM_FCLK_RATIO)+ICACHE_HANDSHAK_LATENCY;
    const int icacheMissWrite = ceil(icacheLineSize/4*SRAM_FCLK_RATIO)+ICACHE_HANDSHAK_LATENCY;
    const int icacheMissWriteRead = icacheMissRead + icacheMissWrite;

    icache = new Cache(true, 1, 6, icache_P_LINE, 0, icacheMissRead, icacheMissWrite, icacheMissWriteRead);

#if 0
    extern size_t filesize(FILE *fp) ;
    FILE *fp = fopen("../../template/hardloop.bin", "rb");
    size_t len = filesize(fp);
    if (len > BASEMEM_SIZE) {
        assert(0);
    }
    if (fread(basemem, 1, len, fp) != len) {
        assert(0);
    }
    fclose(fp);
#endif

    termtest_init(kernel_bin, argv[2]);
    cpu_rst();

    for(;;) {
        cpu_clk();
        //termtest_clk();
        if (termtest_done()) {
            break;
        }
    }

    std::cout<<"-------clk: "<<(termtest_time()+ dcache->flush())<<std::endl;

    std::cout<<"DCache"<<std::endl;
    dcache->dump();
    std::cout<<"ICache"<<std::endl;
    icache->dump();

    bpu->dump();

    std::cout<<"sb_hit ="<<sb_hit<<" sb_miss="<<sb_miss<<std::endl;
#endif

    return 0;
}
