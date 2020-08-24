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
module yamp32_idu(
    input wire i_clk,
    input wire i_rst_n,
    // From IDU
    input wire [31:0] i_pc,
    input wire [31:0] i_insn,
    // To EXU
    output reg [31:0] o_exu_pc,
    output reg [29:0] o_exu_ds_pc,
    output reg [29:0] o_exu_ds_pc_nxt,
    output reg [29:0] o_exu_bcc_tgt,
    output reg o_exu_bcc_backward,
    output reg [29:0] o_exu_lnk_retpc,
    output reg o_exu_j_taken,
    output reg o_exu_reg_we,
    output reg [IOPC_W-1:0] o_exu_uop,
    output reg [15:0] o_exu_uimm16 = 16'b0,
    output reg [25:0] o_exu_disp26,
    output reg [4:0] o_exu_sa,
    output reg [4:0] o_exu_wb_reg_adr,
    output reg o_exu_type_i,
    output reg o_exu_type_j,
    output reg [4:0] o_exu_rop1_adr,
    output reg [4:0] o_exu_rop2_adr,
    // From EXU
    input wire i_spec_fls,
    // To RF
    output wire o_rf_re1,
    output wire [4:0] o_rf_addr1,
    output wire o_rf_re2,
    output wire [4:0] o_rf_addr2
);
    `include "yamp32_parameters.vh"
    
    wire [IOPC_W-1:0] uop;
    wire type_r, type_j, type_i;
    wire [4:0] rs,rt,rd;
    wire [15:0] uimm16;
    wire [25:0] disp26;
    wire [4:0] sa;
    
    yamp32_idec YAMP32_IDEC(
        .i_insn     (i_insn),
        .o_uop      (uop),
        .o_type_r   (type_r),
        .o_type_j   (type_j),
        .o_type_i   (type_i),
        .o_uimm16   (uimm16),
        .o_disp26   (disp26),
        .o_sa       (sa),
        .o_rs       (rs),
        .o_rt       (rt),
        .o_rd       (rd)
    );
    
    assign o_rf_re1 = ~type_j;
    assign o_rf_re2 = ~type_j & ~(uop[IOPC_LB] | uop[IOPC_LW]); // load insn will write rt instead read
    assign o_rf_addr1 = rs;
    assign o_rf_addr2 = rt;
    
    // Delay slot address of this insn
    wire [29:0] ds_pc_nxt = i_pc[31:2] + 1'b1;
    // BCC target
    wire [29:0] bcc_tgt_nxt = ds_pc_nxt + {{14{uimm16[15]}}, uimm16[15:0]};
    // J link address
    wire [29:0] lnk_retpc_nxt = ds_pc_nxt + 1'b1;
    
    // DFFs
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            o_exu_uop <= {IOPC_W{1'b0}};
            o_exu_j_taken <= 1'b0;
            o_exu_reg_we <= 1'b0;
        end else begin
            o_exu_uop <= uop & {IOPC_W{~i_spec_fls}};
            o_exu_j_taken <= (uop[IOPC_J] | uop[IOPC_JAL] | uop[IOPC_JR]) & ~i_spec_fls;
            o_exu_reg_we <= (~(uop[IOPC_BEQ] | uop[IOPC_BNE] | uop[IOPC_BGTZ] | uop[IOPC_J] | uop[IOPC_JR]))
                                & ~i_spec_fls;
        end
    end
    always @(posedge i_clk) begin
        o_exu_pc <= i_pc;
        o_exu_ds_pc <= ds_pc_nxt;
        o_exu_ds_pc_nxt <= ds_pc_nxt + 1'b1;
        o_exu_bcc_tgt <= bcc_tgt_nxt;
        o_exu_bcc_backward <= uimm16[15]; // branching forward when sign bit of offset is 1 (offset<0)
        o_exu_lnk_retpc <= lnk_retpc_nxt;
        o_exu_uimm16 <= uimm16;
        o_exu_disp26 <= disp26;
        o_exu_sa <= sa;
        o_exu_type_i <= type_i;
        o_exu_type_j <= type_j;
        o_exu_wb_reg_adr <= type_r ? rd : rt;
        o_exu_rop1_adr <= o_rf_addr1;
        o_exu_rop2_adr <= o_rf_addr2;
    end
endmodule
