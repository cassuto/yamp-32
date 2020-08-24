#ifndef UART_H_
#define UART_H_

#include <cstdint>

extern uint8_t uart_status();
extern void uart_write(uint8_t dat);
extern uint8_t uart_read();

extern void uart_host_tx(char ch);
extern void uart_host_tx(const unsigned char *buf, size_t len);
extern bool uart_host_rx_ready();
extern char uart_host_rx();

#endif // UART_H_