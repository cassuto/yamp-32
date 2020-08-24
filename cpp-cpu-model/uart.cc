#include <iostream>
#include <queue>
#include <cassert>
#include "uart.h"

static std::queue<char> que_tx, que_rx;

uint8_t uart_status() {
    return 0x1 | ((!que_tx.empty())<<1);
}

void uart_write(uint8_t dat) {
    que_rx.push(dat);
}

uint8_t uart_read() {
    assert(!que_tx.empty());
    char ret = que_tx.front();
    que_tx.pop();
    return ret;
}

void uart_host_tx(char ch) {
    que_tx.push(ch);
}

void uart_host_tx(const unsigned char *buf, size_t len) {
    while(len--) {
        uart_host_tx(*buf++);
    }
}

bool uart_host_rx_ready() {
    return !que_rx.empty();
}

extern char uart_host_rx() {
    assert(!que_rx.empty());
    char ret = que_rx.front();
    que_rx.pop();
    return ret;
}

