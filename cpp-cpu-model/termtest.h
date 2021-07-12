#ifndef TERMTEST_H_
#define TERMTEST_H_

#include <string>

extern void termtest_init(const char *kernel_bin, const std::string &name);
extern void termtest_clk();
extern bool termtest_done();
extern uint64_t termtest_time();

#endif // TERMTEST_H_