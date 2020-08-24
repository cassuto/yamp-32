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

module yamp32_wb_mux(
    input wire i_clk,
    input wire i_rst_n,
    // From LSU & EXU
    input wire i_wb_op_mul,
    input wire [4:0] i_wb_mul_reg_adr,
    input wire [31:0] i_wb_mul_dat,
    input wire [4:0]  i_wb_reg_adr,
    input wire [31:0] i_wb_dat,
    input wire        i_wb_we,
    // To regfile
    output wire [4:0]  o_rf_reg_adr,
    output wire [31:0] o_rf_dat,
    output wire        o_rf_we
);
    // DFFs
    reg wb_we_r;
    reg [4:0] wb_reg_adr_r;
    reg [31:0] wb_dat_r;
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            wb_we_r <= 1'b0;
        end else begin
            wb_we_r <= i_wb_we;
            wb_reg_adr_r <= i_wb_reg_adr;
            wb_dat_r <= i_wb_dat;
        end
    end
    
    assign o_rf_we = i_wb_op_mul ? 1'b1 : wb_we_r;
    assign o_rf_reg_adr = i_wb_op_mul ? i_wb_mul_reg_adr : wb_reg_adr_r;
    assign o_rf_dat = i_wb_op_mul ? i_wb_mul_dat : wb_dat_r;

endmodule