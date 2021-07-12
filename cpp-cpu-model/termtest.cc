#include <map>
#include <vector>
#include <string>
#include <cstdlib>
#include <cassert>
#include <cstring>
#include <iostream>
#include "uart.h"
#include "cpu.h"
#include "bin-kernel.h"
#include "bin-matrix.h"
#include "bin-crypto.h"
#include "termtest.h"

#define BootMesg "MONITOR for MIPS32 - initialized."

struct utest_entry {
    uint32_t off, size;
};
enum STATE {
    STATE_WaitBoot,
    STATE_RunA,
    STATE_RunD,
    STATE_RunG,
    STATE_WaitG,
    STATE_Verify,
    STATE_Done
};

static std::map<std::string, utest_entry> utest;
static enum STATE state;
static size_t expectedLen;
static std::vector<char> recvbuf;

static std::string utest_name;
static const unsigned char *test_bin;
static size_t test_bin_len;
static unsigned char testdata[8*1024*1024];
static size_t testdata_len;

static uint64_t time_start, time_elapsed;

static const double clk_period = 1e-8; // s

static void preloadTest(const std::string &name) {
    if (name.compare("STREAM")==0) {
        for(size_t i=0;i<0x300000;++i) {
            basemem[0x100000+i] = rand();
            testdata[i] = basemem[0x100000+i];
        }
        testdata_len = 0x300000;
    } else if(name.compare("MATRIX")==0) {
        assert(g_cbmatrix>=0x30000);
        memcpy(extmem, g_abmatrix, 0x30000);
        memcpy(testdata, g_abmatrix, g_cbmatrix);
        testdata_len = g_cbmatrix;
    } else if(name.compare("CRYPTONIGHT")==0) {
        memcpy(testdata, g_abcrypto, g_cbcrypto);
        testdata_len = g_cbcrypto;
    }

    utest_name = name;
    test_bin = g_abkernel + utest[name].off;
    test_bin_len = utest[name].size;
    assert(test_bin_len);
}

size_t filesize(FILE *fp) {
    size_t pos = ftell(fp);
    fseek(fp, 0, SEEK_END);
    size_t len = ftell(fp);
    fseek(fp, pos, SEEK_SET);
    return len;
}

void termtest_init(const char *kernel_bin, const std::string &name) {
    utest["STREAM"] = (utest_entry){0x300c, 0x30};
    utest["MATRIX"] = (utest_entry){0x303c, 0x88};
    utest["CRYPTONIGHT"] = (utest_entry){0x30c4, 0x98};
    
    memset(extmem, 0, sizeof(extmem));
    memset(basemem, 0, sizeof(basemem));
    FILE *fp = fopen(kernel_bin, "rb");
    size_t len = filesize(fp);
    if (len > BASEMEM_SIZE) {
        assert(0);
    }
    if (fread(basemem, 1, len, fp) != len) {
        assert(0);
    }
    fclose(fp);

    preloadTest(name);

    state = STATE_WaitBoot;
    expectedLen = sizeof(BootMesg)-1;
}

static void tx_int_bytes(uint32_t val) {
    uart_host_tx((val) & 0xff);
    uart_host_tx((val>>8) & 0xff);
    uart_host_tx((val>>16) & 0xff);
    uart_host_tx((val>>24) & 0xff);
}

static bool cmp_buf(const std::vector<char> &dst, const unsigned char *buf, size_t len) {
    if (len > dst.size()) {
        return false;
    }
    for(size_t i=0;i<len;++i) {
        if ((unsigned char)dst[i] != buf[i]) {
            return false;
        }
    }
    return true;
}
static bool cmp_buf(const std::vector<char> &dst, const char *string) {
    return cmp_buf(dst, (const unsigned char *)string, strlen(string));
}
/* data range is [off,end) */
static bool cmp_ram(const char *dst, size_t doff, size_t dend, const unsigned char *src, size_t soff, size_t send) {
    if (dend-doff != send-soff) {
        assert(0);
        return false;
    }
    return memcmp(dst+doff, src+soff, send-soff)==0;
}

bool verifyTestData() {
    if (utest_name.compare("STREAM")==0) {
        return cmp_ram(extmem, 0x40, 0x300000, testdata, 0x40, 0x300000);
    }else if(utest_name.compare("MATRIX")==0) {
        return cmp_ram(extmem, 0x20000, 0x30000, testdata, 0x30000, testdata_len);
    }else if(utest_name.compare("CRYPTONIGHT")==0) {
        return cmp_ram(extmem, 0x0, 0x200000, testdata, 0x0, testdata_len);
    }
    assert(0);
}

static void hexdump(const std::vector<char> &recvbuf) {
    for(size_t i=0;i<recvbuf.size();++i) {
        printf("%02x", (unsigned char)recvbuf[i]);
        printf(((i+1)%16==0) ? "\n" : " ");
    }
    printf("\n");
}

void termtest_clk() {
    static const uint32_t addr = 0x80100000;
    
    if (uart_host_rx_ready()) {
        recvbuf.push_back(uart_host_rx());
    }
    if (recvbuf.size()>=expectedLen) {
        if (recvbuf.size() > expectedLen) {
            std::cout<<"WARNING: extra bytes received"<<std::endl;
        }
        switch(state) {
            case STATE_WaitBoot: {
                std::cout<<"Boot message:";
                for(size_t i=0;i<recvbuf.size();++i) std::cout<<recvbuf[i];
                std::cout<<std::endl;
                if (!cmp_buf(recvbuf, BootMesg)) {
                    std::cout<<"ERROR: incorrect message"<<std::endl;
                    assert(0);
                }
                state = STATE_RunA;
                for(size_t i=0;i<test_bin_len;i+=4) {
                    uart_host_tx('A');
                    tx_int_bytes(addr+i);
                    tx_int_bytes(4);
                    uart_host_tx(test_bin+i, 4);
                }
                std::cout<<"User program written"<<std::endl;

                state = STATE_RunD;
                expectedLen = test_bin_len;

                uart_host_tx('D');
                tx_int_bytes(addr);
                tx_int_bytes(test_bin_len);
                break;
            }

            case STATE_RunD: {
                std::cout<<"  Program Readback:\n"<<std::endl;
                hexdump(recvbuf);
                if (!cmp_buf(recvbuf, test_bin, test_bin_len)) {
                    std::cout<<"ERROR: corrupted user program"<<std::endl;
                    assert(0);
                }
                std::cout<<"Program memory content verified"<<std::endl;

                state = STATE_RunG;
                uart_host_tx('G');
                tx_int_bytes(addr);
                expectedLen = 1;
                break;
            }

            case STATE_RunG: {
                if (recvbuf[0] == '\x80') {
                    std::cout<<"ERROR: exception occurred"<<std::endl;
                    assert(0);
                } else if (recvbuf[0] != '\x06') {
                    hexdump(recvbuf);
                    std::cout<<"ERROR: start mark should be 0x06"<<std::endl;
                    assert(0);
                }

                time_start = cpu_timestamp();
                state = STATE_WaitG;
                expectedLen = 1;
                break;
            }

            case STATE_WaitG: {
                if (recvbuf[0] == '\x80') {
                    std::cout<<"ERROR: exception occurred"<<std::endl;
                    assert(0);
                } else if( recvbuf[0] == '\x07') {
                    time_elapsed = cpu_timestamp() - time_start;
                    state = STATE_Verify;

                    if (verifyTestData()) {
                        std::cout<<"Data memory content verified"<<std::endl;
                        state = STATE_Done;
                        std::cout<<"======="<<std::endl;
                        std::cout<<"Clks: "<<time_elapsed<<std::endl;
                        std::cout<<"Secs: "<<time_elapsed*clk_period<<std::endl;
                        std::cout<<"======="<<std::endl;
                    } else {
                        std::cout<<"ERROR: Data memory content mismatch"<<std::endl;
                        assert(0);
                    }
                } else {
                    std::cout<<"ERROR: Invalid byte 0x"<<std::hex<<(unsigned int)recvbuf[0]<<" received"<<std::endl;
                    assert(0);
                }
                break;
            }
            default:
                std::cout<<"Invalid state"<<std::endl;
                assert(0);
        }
        recvbuf.clear();
    }
}

bool termtest_done() {
    return state == STATE_Done;
}

uint64_t termtest_time() {
    return time_elapsed;
}