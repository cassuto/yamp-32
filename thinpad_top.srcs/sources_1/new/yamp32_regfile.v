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

module yamp32_regfile(
    input wire i_clk,
    input wire i_rst_n,
    input wire i_re1,
    input wire [4:0] i_r_addr1,
    input wire i_re2,
    input wire [4:0] i_r_addr2,
    output wire [31:0] o_r_dat1,
    output wire [31:0] o_r_dat2,
    input wire [4:0] i_w_addr,
    input wire [31:0] i_w_dat,
    input wire i_we
);
    reg [1:0] bypass_r;
    reg  [1:0] zero_n_r;
    reg [31:0] w_dat_r;
    wire [1:0] re_w;
    wire [31:0] op1_w, op2_w;
    
    wire bypass1_nxt = (i_w_addr == i_r_addr1) & i_we & i_re1;
    wire bypass2_nxt = (i_w_addr == i_r_addr2) & i_we & i_re2;
    
    // For operand #1
    blk_mem_regfile mem0(
        .clka   (i_clk),
        .addra  (i_w_addr),
        .dina   (i_w_dat),
        .ena    (i_we),
        .wea    (i_we & (|i_w_addr)),
        .clkb   (i_clk),
        .addrb  (i_r_addr1),
        .doutb  (op1_w),
        .enb    (re_w[0] & ~bypass1_nxt)
    );
    
    // For operand #2
    blk_mem_regfile mem1(
        .clka   (i_clk),
        .addra  (i_w_addr),
        .dina   (i_w_dat),
        .ena    (i_we),
        .wea    (i_we & (|i_w_addr)),
        .clkb   (i_clk),
        .addrb  (i_r_addr2),
        .doutb  (op2_w),
        .enb    (re_w[1] & ~bypass2_nxt)
    );
    
    // Bypass
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            bypass_r <= 2'b0;
        end else  begin
            if (i_re1) // Keep bypass valid till the next Read
                bypass_r[0] <= bypass1_nxt;
            if (i_re2)
                bypass_r[1] <= bypass2_nxt;
        end
    end
    
    always @(posedge i_clk) begin
        if (i_re1 | i_re2)
            w_dat_r <= i_w_dat;
    end
    
    always @(posedge i_clk) begin
        zero_n_r[0] = |i_r_addr1;
        zero_n_r[1] = |i_r_addr2;
    end
    
    assign re_w[0] = i_re1;
    assign re_w[1] = i_re2;
    
    assign o_r_dat1 = {32{zero_n_r[0]}} & (bypass_r[0] ? w_dat_r : op1_w);
    assign o_r_dat2 = {32{zero_n_r[1]}} & (bypass_r[1] ? w_dat_r : op2_w);

endmodule
