`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/08/02 16:37:55
// Design Name: 
// Module Name: tb_uart
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_uart();
    reg clk_50M = 1;
    reg clk_cpu = 1;
    reg uart_rst_n = 0;
    reg cpu_rst_n = 0;
    
    initial forever #10 clk_50M = ~clk_50M;
    initial forever #8 clk_cpu = ~clk_cpu;
    
    reg rxd = 0;
    wire txd;
    wire rx_ready, tx_ready;
    reg tx_we = 0;
    
    reg [7:0] tx_din = 8'd12;
    
    uart UART(
        .clk_50M    (clk_50M),
        .uart_rst_n (uart_rst_n),
        .clk_cpu    (clk_cpu),
        .cpu_rst_n  (cpu_rst_n),
        .rxd        (rxd),
        .txd        (txd),
        // RX
        .rx_ready   (rx_ready),
        .rx_rd      (),
        .rx_dout    (),
        // TX
        .tx_ready   (tx_ready),
        .tx_we      (tx_we),
        .tx_din     (tx_din)
    );
    
    reg [1:0] cnt1=0, cnt2=0;
    
    always @(posedge clk_50M) begin
        cnt1<=cnt1+1;
        if(cnt1[1])
            uart_rst_n <= 1'b1;
    end
    always @(posedge clk_cpu) begin
        cnt2<=cnt2+1;
        if(cnt2[1])
            cpu_rst_n <= 1'b1;
    end
    
    initial begin
        #32 tx_we = 1'b1;
    end
    
endmodule
