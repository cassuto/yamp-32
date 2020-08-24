/**@file
 * A fake UART used for debugging
 */

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

// synthesis translate_off
`ifndef SYNTHESIS

module fake_uart #(
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
    output wire rx_rd,
    output reg [7:0] rx_dout,
    // TX
    output wire tx_ready,
    input wire tx_we,
    input wire [7:0] tx_din
);
    /* =========== RX =========== */
    
    reg [5:0] rx_cnt;
    reg [5:0] rx_pos;
    reg [7:0] rx_dats[63:0];
    
    task send_cmd_D;
        input [31:0] addr;
        input [31:0] len;
        begin
            rx_dats[0+rx_cnt] = "D";
            // Addr
            rx_dats[1+rx_cnt] = addr[7:0];
            rx_dats[2+rx_cnt] = addr[15:8];
            rx_dats[3+rx_cnt] = addr[23:16];
            rx_dats[4+rx_cnt] = addr[31:24];
            // Len
            rx_dats[5+rx_cnt] = len[7:0];
            rx_dats[6+rx_cnt] = len[15:8];
            rx_dats[7+rx_cnt] = len[23:16];
            rx_dats[8+rx_cnt] = len[31:24];
            rx_cnt = rx_cnt + 6'd9;
        end
    endtask
    
    task send_cmd_A;
        input [31:0] addr;
        input [31:0] insn;
        begin
            rx_dats[0+rx_cnt] = "A";
            // Addr
            rx_dats[1+rx_cnt] = addr[7:0];
            rx_dats[2+rx_cnt] = addr[15:8];
            rx_dats[3+rx_cnt] = addr[23:16];
            rx_dats[4+rx_cnt] = addr[31:24];
            // Len
            rx_dats[5+rx_cnt] = 8'd4;
            rx_dats[6+rx_cnt] = 8'd0;
            rx_dats[7+rx_cnt] = 8'd0;
            rx_dats[8+rx_cnt] = 8'd0;
            // Insn
            rx_dats[9+rx_cnt] = insn[7:0];
            rx_dats[10+rx_cnt] = insn[15:8];
            rx_dats[11+rx_cnt] = insn[23:16];
            rx_dats[12+rx_cnt] = insn[31:24];
            rx_cnt = rx_cnt + 6'd13;
        end
    endtask
    
    initial begin
        rx_cnt = 6'd0;
        rx_pos = 6'd0;
        
        send_cmd_A(32'h80100000, 32'h01000834);
        //send_cmd_D(32'h80100000, 32'd64);
    end
    
    always @(posedge clk)
        if (rx_rd & rx_ready) begin
            rx_dout <= rx_dats[rx_pos];
            rx_pos <= rx_pos + 1'b1;
            rx_cnt <= rx_cnt - 1'b1;
        end
    assign rx_ready = rx_cnt != 6'd0;
    
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
    
    assign ext_uart_busy = 1'b0;

    always @(posedge clk) begin
        if (ext_uart_start) begin
            $write("%c", ext_uart_tx);
        end
    end

    /* =========== End TX =========== */
endmodule

`endif
// synthesis translate_on
