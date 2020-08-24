/***************************************************************************/
/*  yamp32 (Yet Another MIPS Processor)                                    */
/*  Copyright (C) 2020 cassuto <diyer175@hotmail.com>                      */
/*  This project is free edition; you can redistribute it and/or           */
/*  modify it under the terms of the GNU Lesser General Public             */
/*  License(GPL) as published by the Free Software Foundation; either      */
/*  version 2.1 of the License, or (at your option) any later version.     */
/*                                                                         */
/*  This project is distributed in the hope that it will be useful,        */
/*  but WITHOUT ANY WARRANTY; without even the implied warranty of         */
/*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU      */
/*  Lesser General Public License for more details.                        */
/***************************************************************************/

module uart#(
    parameter F_BAUD_CLK = 120000000, // Hz
    parameter BAUD_RATE = 9600
)
(
    input wire clk,
    input wire rst_n,
    // TTL 232
    input wire rxd,
    output wire txd,
    // RX
    output wire rx_ready,
    input wire rx_rd,
    output wire [7:0] rx_dout,
    // TX
    output wire tx_ready,
    input wire tx_we,
    input wire [7:0] tx_din
);
    /* =========== RX =========== */
    
    wire ext_uart_data_ready;
    wire ext_uart_clear;
    
    wire [7:0] queue_rx_din;
    wire queue_rx_full;
    wire queue_rx_empty;
    
    // IMPORTANT! standard mode
    fifo_uart_queue QUEUE_RX(
        .clk    (clk),
        .srst   (~rst_n),
        .full   (queue_rx_full),
        .din    (queue_rx_din),
        .wr_en  (ext_uart_data_ready & ~queue_rx_full),
        .empty  (queue_rx_empty),
        .dout   (rx_dout),
        .rd_en  (rx_rd & ~queue_rx_empty)
    );
    
    assign rx_ready = ~queue_rx_empty;
    
    async_receiver #(.ClkFrequency(F_BAUD_CLK),.Baud(BAUD_RATE))
        ext_uart_r(
            .clk(clk),                       //外部时钟信号
            .RxD(rxd),                           //外部串行信号输入
            .RxD_data_ready(ext_uart_data_ready),  //数据接收到标志
            .RxD_clear(ext_uart_clear),
            .RxD_data(queue_rx_din)
        );
    
    assign ext_uart_clear = ext_uart_data_ready & ~queue_rx_full;
    
    /* =========== End RX =========== */
    
    /* =========== TX =========== */
    
    wire ext_uart_busy;
    reg ext_uart_start;
    wire [7:0] ext_uart_tx;
    
    wire queue_tx_full;
    wire queue_tx_empty;
    wire queue_tx_pop;
    
    // IMPORTANT! standard mode
    fifo_uart_queue QUEUE_TX(
        .clk    (clk),
        .srst   (~rst_n),
        .full   (queue_tx_full),
        .din    (tx_din),
        .wr_en  (tx_we & ~queue_tx_full),
        .empty  (queue_tx_empty),
        .dout   (ext_uart_tx),
        .rd_en  (queue_tx_pop)
    );
    
    assign tx_ready = ~queue_tx_full;
    assign queue_tx_pop = ~(ext_uart_start|ext_uart_busy) & ~queue_tx_empty;
    
    always @(posedge clk) begin
        ext_uart_start <= ~ext_uart_busy & ~queue_tx_empty;
    end
    
    async_transmitter #(.ClkFrequency(F_BAUD_CLK),.Baud(BAUD_RATE))
        ext_uart_t(
            .clk(clk),                  //外部时钟信号
            .TxD(txd),                      //串行信号输出
            .TxD_busy(ext_uart_busy),       //发送器忙状态指示
            .TxD_start(ext_uart_start),    //开始发送信号
            .TxD_data(ext_uart_tx)        //待发送的数据
        );
     
    // synthesis translate_off
`ifndef SYNTHESIS 
    always @(posedge clk) begin
        if (ext_uart_start & ~ext_uart_busy) begin
            $write("%c", ext_uart_tx);
        end
    end
`endif
    // synthesis translate_on
     
    /* =========== End TX =========== */
endmodule
