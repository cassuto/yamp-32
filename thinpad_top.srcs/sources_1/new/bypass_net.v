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
module bypass_net(
    input wire i_clk,
    // From IDU
    input wire i_rop1_re,
    input wire [4:0] i_rop1_adr,
    input wire i_rop2_re,
    input wire [4:0] i_rop2_adr,
    input wire [31:0] i_rop1,
    input wire [31:0] i_rop2,
    // From EXU & LSU
    input wire i_lsu_wb_we,
    input wire [4:0] i_lsu_wb_reg_adr,
    input wire [31:0] i_lsu_wb_dat,
    output wire [31:0] o_rop1,
    output wire [31:0] o_rop2,
    input wire [4:0] i_mul_reg_adr,
    input wire i_mul_reg_we,
    // From WB
    input wire i_wb_we,
    input wire [4:0] i_wb_reg_adr,
    input wire [31:0] i_wb_dat,
    // To CTRL
    output wire o_stall
);
    reg [4:0] rop1_adr_r, rop2_adr_r;

    always @(posedge i_clk) begin
        rop1_adr_r <= i_rop1_adr;
        rop2_adr_r <= i_rop2_adr;
    end

    wire bypass_lsu_1 = (i_lsu_wb_we & i_lsu_wb_reg_adr == rop1_adr_r);
    wire bypass_wb_1 = (i_wb_we & i_wb_reg_adr == rop1_adr_r);
    wire bypass_lsu_2 = (i_lsu_wb_we & i_lsu_wb_reg_adr == rop2_adr_r);
    wire bypass_wb_2 = (i_wb_we & i_wb_reg_adr == rop2_adr_r);

    // Priority: EXU > LSU
    assign o_rop1 = bypass_lsu_1 ? i_lsu_wb_dat :
                    bypass_wb_1 ? i_wb_dat : i_rop1;
    assign o_rop2 = bypass_lsu_2 ? i_lsu_wb_dat :
                    bypass_wb_2 ? i_wb_dat : i_rop2;

    assign o_stall = 1'b0; /*(i_mul_reg_we & i_rop1_re & (i_rop1_adr==i_mul_reg_adr)) |
                        (i_mul_reg_we & i_rop2_re & (i_rop2_adr==i_mul_reg_adr));*/
endmodule
