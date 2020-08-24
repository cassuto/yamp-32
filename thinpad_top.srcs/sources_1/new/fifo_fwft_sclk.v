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

module fifo_fwft_sclk
#(
    parameter DEPTH_WIDTH = 4,
    parameter DATA_WIDTH = 52
)
(
    input wire i_clk,
    input wire i_rst_n,
    // Push port
    input wire i_push,
    input wire [DATA_WIDTH-1:0] i_din,
    output wire o_full,
    // Pop port
    input wire i_pop,
    output wire [DATA_WIDTH-1:0] o_dout,
    output wire o_empty
);
    reg status_r;
    reg [DATA_WIDTH-1:0] dat_r;
    wire [DATA_WIDTH-1:0] dout_w;
    
    reg [DEPTH_WIDTH:0]                  w_ptr;
    reg [DEPTH_WIDTH:0]                  r_ptr;

    assign o_full = (w_ptr[DEPTH_WIDTH] != r_ptr[DEPTH_WIDTH]) &&
                   (w_ptr[DEPTH_WIDTH-1:0] == r_ptr[DEPTH_WIDTH-1:0]);
    assign o_empty = ~status_r & (w_ptr == r_ptr);

    assign o_dout = status_r ? dat_r : dout_w;
    
    wire fwft_nxt = ~status_r & o_empty & i_push;
    
    // FWFT FSM
    always @(posedge i_clk or negedge i_rst_n)
        if (~i_rst_n)
            status_r <= 1'b0;
        else begin
            case (status_r)
            1'b0:
                if (fwft_nxt) begin
                    status_r <= 1'b1;
                    dat_r <= i_din;
                end
            1'b1:
                if (i_pop) begin
                    status_r <= 1'b0;
                end
            endcase
        end
    
    always @(posedge i_clk or negedge i_rst_n)
        if (~i_rst_n)
            w_ptr <= 0;
        else if (i_push)
            w_ptr <= w_ptr + 1'd1;

    always @(posedge i_clk or negedge i_rst_n)
        if (~i_rst_n)
            r_ptr <= 0;
        else if (i_pop)
            r_ptr <= r_ptr + 1'd1;

    wire [DEPTH_WIDTH:0] r_ptr_nxt = r_ptr + 1'b1;

    xpm_sdpram_bypass #(
        .ADDR_WIDTH(DEPTH_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    )
    fifo_ram (
        .clk      (i_clk),
        .rst_n    (i_rst_n),
        .doutb    (dout_w),
        .addrb    (r_ptr_nxt[DEPTH_WIDTH-1:0]),
        .enb      (i_pop),
        .addra    (w_ptr[DEPTH_WIDTH-1:0]),
        .wea      (i_push),
        .ena      (i_push),
        .dina     (i_din)
    );

endmodule
