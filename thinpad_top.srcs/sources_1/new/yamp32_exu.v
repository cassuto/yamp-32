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

module yamp32_exu(
    // From IDU
    input wire i_clk,
    input wire i_rst_n,
    input wire [31:0] i_pc,
    input wire [29:0] i_ds_pc,
    input wire [29:0] i_ds_pc_nxt,
    input wire [29:0] i_bcc_tgt,
    input wire i_bcc_backward,
    input wire [29:0] i_lnk_retpc,
    input wire i_j_taken,
    input wire i_reg_we,
    input wire [IOPC_W-1:0] i_uop,
    input wire i_type_i,
    input wire i_type_j,
    input wire [31:0] i_rop1,
    input wire [31:0] i_rop2,
    input wire [4:0] i_rop1_adr,
    input wire [4:0] i_rop2_adr,
    input wire [15:0] i_uimm16,
    input wire [25:0] i_disp26,
    input wire [4:0] i_sa,
    input wire [4:0] i_wb_reg_adr,
    // From CTRL
    input wire i_stall,
    input wire i_inv,
    // To IDU
    output wire o_spec_fls,
    // To IFU
    output wire o_ifu_fls,
    output wire [29:0] o_ifu_fls_pc,
    // To LSU
    output reg o_lsu_load,
    output reg o_lsu_store,
    output reg [31:0] o_lsu_dat,
    output reg [31:0] o_lsu_addr,
    output reg o_lsu_dw,
    output reg [4:0] o_lsu_wb_reg_adr,
    output reg [31:0] o_lsu_wb_dat,
    output reg o_lsu_wb_we,
    // To bypass
    output wire [4:0] o_mul_reg_adr,
    output wire o_mul_reg_we,
    // To WB
    output reg o_wb_op_mul,
    output reg [4:0] o_wb_mul_reg_adr,
    output wire [31:0] o_wb_mul_dat
);

    `include "yamp32_parameters.vh"

    wire [4:0] reg_adr_nxt = j_lnk ? 5'd31 : i_wb_reg_adr;

    /* =========== Adder =========== */
    wire [31:0] add_operand1 = i_rop1;
    wire [31:0] add_operand2 = i_type_i ? {{16{i_uimm16[15]}},i_uimm16[15:0]} : i_rop2;
    wire [31:0] wb_adder_nxt;

    assign wb_adder_nxt = add_operand1 + add_operand2;
    wire op_add_nxt = i_uop[IOPC_ADDU] | i_uop[IOPC_ADDIU];
    /* =========== End Adder =========== */
    
    /* =========== Logic Operation */
    wire [31:0] and_operand1 = i_rop1;
    wire [31:0] and_operand2 = i_type_i ? {16'b0,i_uimm16[15:0]} : i_rop2;
    wire [31:0] wb_and_nxt = and_operand1 & and_operand2;
    wire op_and_nxt = i_uop[IOPC_AND] | i_uop[IOPC_ANDI];
    
    wire [31:0] or_operand1 = i_rop1;
    wire [31:0] or_operand2 = i_type_i ? {16'b0,i_uimm16[15:0]} : i_rop2;
    wire [31:0] wb_or_nxt = or_operand1 | or_operand2;
    wire op_or_nxt = i_uop[IOPC_OR] | i_uop[IOPC_ORI];
    
    wire [31:0] xor_operand1 = i_rop1;
    wire [31:0] xor_operand2 = i_type_i ? {16'b0,i_uimm16[15:0]} : i_rop2;
    wire [31:0] wb_xor_nxt = xor_operand1 ^ xor_operand2;
    wire op_xor_nxt = i_uop[IOPC_XOR] | i_uop[IOPC_XORI];
    
    /* =========== End Logic Operation */
    
    /* =========== Shift Operation =========== */
    wire [31:0] sll_operand = i_rop2;
    wire [31:0] wb_sll_nxt = (sll_operand << i_sa);
    wire op_sll_nxt = i_uop[IOPC_SLL];
    
    wire [31:0] srl_operand = i_rop2;
    wire [31:0] wb_srl_nxt = (srl_operand >> i_sa);
    wire op_srl_nxt = i_uop[IOPC_SRL];
    /* =========== End Shift Operation =========== */
   
    /* =========== Mul Operation =========== */
    reg op_mul_r;
    wire [31:0] mul_operand1 = i_rop1;
    wire [31:0] mul_operand2 = i_rop2;
    reg [4:0] mul_reg_adr_r;
    
    // IMPORTANT! latency = 2
    mult_exu MULTIPLIER(
        .CLK    (i_clk),
        .A      (mul_operand1),
        .B      (mul_operand2),
        .CE     (~i_stall),
        .P      (o_wb_mul_dat[31:0])
    );
    
    // 2-stage DFFs
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            op_mul_r <= 1'b0;
        end else if (~i_stall) begin
            op_mul_r <= i_uop[IOPC_MUL];
            o_wb_op_mul <= op_mul_r;
        end
    end
    always @(posedge i_clk) begin
        if (~i_stall) begin
            mul_reg_adr_r <= reg_adr_nxt;
            o_wb_mul_reg_adr <= mul_reg_adr_r;
        end
    end
    
    // To bypass
    assign o_mul_reg_adr = mul_reg_adr_r;
    assign o_mul_reg_we = op_mul_r;
    
    /* =========== End Mul Operation =========== */
    
    /* =========== Move =========== */
    wire [31:0] wb_lui_nxt = {i_uimm16[15:0], 16'b0};
    wire op_lui_nxt = i_uop[IOPC_LUI];
    /* =========== End Move =========== */
    
    
    /* =========== BU =========== */
    
    // BCC
    wire beq = i_uop[IOPC_BEQ] & (i_rop1 == i_rop2);
    wire bne = i_uop[IOPC_BNE] & (i_rop1 != i_rop2);
    wire bgtz = i_uop[IOPC_BGTZ] & (~i_rop1[31] && |i_rop1[30:0]);
    wire bcc_taken =  beq | bne | bgtz;
    wire bcc_op = i_uop[IOPC_BEQ] | i_uop[IOPC_BNE] | i_uop[IOPC_BGTZ];
    // J
    wire j_lnk = i_uop[IOPC_JAL];
    wire [29:0] jrel_tgt = {i_ds_pc[29:26], i_disp26[25:0]};
    wire [29:0] j_tgt =  i_uop[IOPC_JR] ? i_rop1[31:2] : jrel_tgt;
    
    /* =========== End BU =========== */
    
    /* =========== LSU =========== */
    
    wire lsu_load = i_uop[IOPC_LB] | i_uop[IOPC_LW];
    wire lsu_store = i_uop[IOPC_SB] | i_uop[IOPC_SW];
    wire  lsu_dw = i_uop[IOPC_LW] | i_uop[IOPC_SW];
    wire [31:0] lsu_dat = lsu_dw ? i_rop2 : {i_rop2[7:0],i_rop2[7:0],i_rop2[7:0],i_rop2[7:0]};
    wire [31:0] lsu_addr;
    // Calc target address.
    // IMPORTANT! Latency of output = 0
    c_add_s32 LSU_ADDR_ADDER(
        .A(i_rop1),
        .B({{16{i_uimm16[15]}},i_uimm16[15:0]}),
        .S(lsu_addr)
    );
    wire [31:0] lsu_dout;

    /* =========== End LSU =========== */
    
    // MUX of ALU result
    wire [31:0] alu_dat = (
        // Adder
        ({32{op_add_nxt}} & wb_adder_nxt) |
        // Logic Operations
        ({32{op_and_nxt}} & wb_and_nxt) |
        ({32{op_or_nxt}} & wb_or_nxt) |
        ({32{op_xor_nxt}} & wb_xor_nxt) |
        // Shift Operations
        ({32{op_sll_nxt}} & wb_sll_nxt) |
        ({32{op_srl_nxt}} & wb_srl_nxt) |
        // Move
        ({32{op_lui_nxt}} & wb_lui_nxt) |
        // J link
        ({32{j_lnk}} & {i_lnk_retpc[29:0], 2'b00})
    );

    /* =========== DFFs =========== */

    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            o_lsu_load <= 1'b0;
            o_lsu_store <= 1'b0;
        end else if(~i_stall) begin
            o_lsu_load <= lsu_load;
            o_lsu_store <= lsu_store;
            o_lsu_dat <= lsu_dat;
            o_lsu_addr <= lsu_addr;
            o_lsu_dw <= lsu_dw;
            
        end else if(i_inv) begin
            o_lsu_load <= 1'b0;
            o_lsu_store <= 1'b0;
        end
    end
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            o_lsu_wb_we <= 1'b0;
        end else if(~i_stall) begin
            o_lsu_wb_we <= i_reg_we & ~lsu_store & ~lsu_load; // Yes, not lsu_load, which cheats bypass net not to
                                                          // get result of load insn in EXU stage.
                                                          // Because LSU will assert stalling signal util the result goes valid
                                                          // and the result must be got from LSU stage, instead of EXU.
            o_lsu_wb_reg_adr <= reg_adr_nxt;
            o_lsu_wb_dat <= alu_dat;
            
        end else if (i_inv) begin
            o_lsu_wb_we <= 1'b0;
        end
    end
    
    /* =========== End DFFs =========== */
    
    /* =========== BPU & Branching =========== */
    
    wire bp_taken;
    
    yamp32_bpu #(
        .ALGORITHM (BPU_ALGORITHM)
    )
    BPU(
        .i_bcc_op       (bcc_op),
        .i_bcc_backward (i_bcc_backward),
        .o_bp_taken     (bp_taken)
    );
    
    // Flush the speculatively executing insn when BP failed
    wire bcc_spec_fls = bp_taken ^ bcc_taken;
    
    wire [29:0] bcc_spec_tgt = bp_taken ? i_bcc_tgt : i_ds_pc_nxt;
    wire [29:0] bcc_real_tgt = bcc_taken ? i_bcc_tgt : i_ds_pc_nxt;
    
    reg spec_fls_r, spec_fls_rr;
    reg [29:0] spec_fls_pc_r;
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            spec_fls_r <= 1'b0;
            spec_fls_rr <= 1'b0;
        end else if (~i_stall) begin
            spec_fls_r <= (bcc_spec_fls | i_j_taken); // Assert(2008071529)
            spec_fls_rr <= spec_fls_r;
            spec_fls_pc_r <= ({30{bcc_spec_fls}} & bcc_real_tgt) |
                        ({30{i_j_taken}} & j_tgt);
        end
        // Do not invalidate spec_fls
    end

    assign o_spec_fls = i_stall ? spec_fls_rr : spec_fls_r;
    
    wire ifu_fls_nxt = bp_taken | spec_fls_r; // Assert(2008071532)
    wire [29:0] ifu_fls_pc_nxt = ({30{bp_taken}} & bcc_spec_tgt) | spec_fls_pc_r; // Assert(2008071532)
    
    reg ifu_fls_r;
    reg [29:0] ifu_fls_pc_r;
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            ifu_fls_r <= 1'b0;
        end else if (~i_stall) begin
            ifu_fls_r <= ifu_fls_nxt;
            ifu_fls_pc_r <= ifu_fls_pc_nxt;
        end
    end
    
    assign o_ifu_fls = i_stall ? ifu_fls_r : ifu_fls_nxt;
    assign o_ifu_fls_pc = i_stall ? ifu_fls_pc_r : ifu_fls_pc_nxt; 
    
    /* =========== End BPU & Branching =========== */
    
   // synthesis translate_off
`ifndef SYNTHESIS
    // Assert(2008071529)
    always @(posedge i_clk) begin
        if (bcc_spec_fls & i_j_taken == 1'b1) begin
            $fatal ("\n bcc and j must be mutex\n");
        end
    end
    
    // Assert(2008071532)
    always @(posedge i_clk) begin
        if (bp_taken & spec_fls_r == 1'b1) begin
            $fatal ("\n delay slot can NOT be a branching insn\n");
        end
    end
`endif
    // synthesis translate_on
    
endmodule
