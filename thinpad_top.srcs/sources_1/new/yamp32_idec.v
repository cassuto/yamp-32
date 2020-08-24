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

module yamp32_idec(
    input wire [31:0] i_insn,
    output wire [IOPC_W-1:0] o_uop,
    output wire o_type_r,
    output wire o_type_j,
    output wire o_type_i,
    output wire [15:0] o_uimm16,
    output wire [25:0] o_disp26,
    output wire [4:0] o_sa,
    output wire [4:0] o_rs, o_rd, o_rt
);
    `include "yamp32_parameters.vh"

    // Upack insn fields
    wire [5:0] f_opcode = i_insn[31:26];
    wire [4:0] f_rs = i_insn[25:21];
    wire [4:0] f_rt = i_insn[20:16];
    wire [4:0] f_rd = i_insn[15:11];
    wire [4:0] f_sa = i_insn[10:6];
    wire [5:0] f_func = i_insn[5:0];
    wire [15:0] f_imm16 = i_insn[15:0];
    wire [25:0] f_disp26 = i_insn[25:0];
   
    // Decode insn
    assign o_uop[IOPC_ADDU] = (f_opcode == 6'b000000) & (f_func == 6'b100001);
    assign o_uop[IOPC_ADDIU] = f_opcode == 6'b001001;
    assign o_uop[IOPC_MUL] = (f_opcode == 6'b011100) & (f_func == 6'b000010);
    assign o_uop[IOPC_AND] = (f_opcode == 6'b000000) & (f_func == 6'b100100);
    assign o_uop[IOPC_ANDI] = (f_opcode == 6'b001100);
    assign o_uop[IOPC_LUI] = (f_opcode == 6'b001111);
    assign o_uop[IOPC_OR] = (f_opcode == 6'b000000) & (f_func == 6'b100101);
    assign o_uop[IOPC_ORI] = (f_opcode == 6'b001101);
    assign o_uop[IOPC_XOR] = (f_opcode == 6'b000000) & (f_func == 6'b100110);
    assign o_uop[IOPC_XORI] = (f_opcode == 6'b001110);
    assign o_uop[IOPC_SLL] = (f_opcode == 6'b000000) & (f_func == 6'b000000);
    assign o_uop[IOPC_SRL] = (f_opcode == 6'b000000) & (f_func == 6'b000010);
    assign o_uop[IOPC_BEQ] = (f_opcode == 6'b000100);
    assign o_uop[IOPC_BNE] = (f_opcode == 6'b000101);
    assign o_uop[IOPC_BGTZ] = (f_opcode == 6'b000111);
    assign o_uop[IOPC_J] = (f_opcode == 6'b000010);
    assign o_uop[IOPC_JAL] = (f_opcode == 6'b000011);
    assign o_uop[IOPC_JR] = (f_opcode == 6'b000000) & (f_func == 6'b001000);
    assign o_uop[IOPC_LB] = (f_opcode == 6'b100000);
    assign o_uop[IOPC_LW] = (f_opcode == 6'b100011);
    assign o_uop[IOPC_SB] = (f_opcode == 6'b101000);
    assign o_uop[IOPC_SW] = (f_opcode == 6'b101011);
    
    assign o_type_r = (f_opcode == 6'b000000) | (f_opcode == 6'b011100);
    assign o_type_j = o_uop[IOPC_J] | o_uop[IOPC_JAL];
    assign o_type_i = ~o_type_r & ~o_type_j;
    
    assign o_uimm16 = f_imm16[15:0];
    assign o_disp26 = f_disp26[25:0];
    
    assign {o_rs,o_rt,o_rd} = {f_rs,f_rt,f_rd};
    assign o_sa = f_sa;
    
endmodule