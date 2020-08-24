#ifndef CPU_H_
#define CPU_H_

#include <string>

#define BASEMEM_OFFSET 0x0
#define BASEMEM_SIZE 0x400000
#define EXTMEM_OFFSET BASEMEM_SIZE
#define EXTMEM_SIZE 0x400000

extern char basemem[BASEMEM_SIZE];
extern char extmem[EXTMEM_SIZE];

extern uint32_t regfile[32];

extern uint64_t cpu_timestamp();

#endif // CPU_H_
