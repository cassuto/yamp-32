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

module yamp32_core(
    input wire i_clk,
    input wire i_rst_n,
    
    // Insn SRAM Interface
    input wire [31:0]      i_iram_dout,
    output wire            o_iram_br_req,
    input wire             i_iram_br_ack,
    output wire [19:0]     o_iram_br_addr,
    
    // DataRAM interafce
    output wire                 o_dram_baseram_reqr_valid,
    input wire                  i_dram_baseram_reqr_ready,
    output wire [19:0]          o_dram_baseram_reqr_addr,
    input wire                  i_dram_baseram_rsp_valid,
    output wire                 o_dram_baseram_rsp_ready,
    input wire [31:0]           i_dram_baseram_dout,
    output wire                 o_dram_extram_reqr_valid,
    input wire                  i_dram_extram_reqr_ready,
    output wire [19:0]          o_dram_extram_reqr_addr,
    input wire                  i_dram_extram_rsp_valid,
    output wire                 o_dram_extram_rsp_ready,
    input wire [31:0]           i_dram_extram_dout,
    
    output wire                 o_dram_baseram_reqw_valid,
    input wire                  i_dram_baseram_reqw_ready,
    output wire [3:0]           o_dram_baseram_reqw_be,
    output wire [19:0]          o_dram_baseram_reqw_addr,
    output wire [31:0]          o_dram_baseram_din,
    output wire                 o_dram_extram_reqw_valid,
    input wire                  i_dram_extram_reqw_ready,
    output wire [3:0]           o_dram_extram_reqw_be,
    output wire [19:0]          o_dram_extram_reqw_addr,
    output wire [31:0]          o_dram_extram_din,
    
    // UART RX
    input wire uart_rx_ready,
    output wire uart_rx_rd,
    input wire [7:0] uart_rx_dout,
    // UART TX
    input wire uart_tx_ready,
    output wire uart_tx_we,
    output wire [7:0] uart_tx_din
);
    `include "yamp32_parameters.vh"
    
    // To IFU
    wire ifu_fls;
    wire [29:0] ifu_fls_pc;
    wire ifu_stall;
    // To IDU
    wire [31:0] idu_pc;
    wire [31:0] idu_insn;
    wire idu_spec_fls;
    // To EXU
    wire [31:0] exu_pc;
    wire [29:0] exu_ds_pc;
    wire [29:0] exu_ds_pc_nxt;
    wire [29:0] exu_bcc_tgt;
    wire exu_bcc_backward;
    wire [29:0] exu_lnk_retpc;
    wire exu_j_taken;
    wire exu_reg_we;
    wire [IOPC_W-1:0] exu_uop;
    wire [31:0] exu_rop1, exu_rop2;
    wire [15:0] exu_uimm16;
    wire [25:0] exu_disp26;
    wire [4:0] exu_sa;
    wire [4:0] exu_wb_reg_adr;
    wire exu_type_i, exu_type_j;
    wire [4:0] exu_rop1_adr;
    wire [4:0] exu_rop2_adr;
    wire exu_stall;
    wire exu_inv;
    // To LSU
    wire lsu_load;
    wire lsu_store;
    wire [31:0] lsu_dat;
    wire [31:0] lsu_addr;
    wire lsu_dw;
    wire [4:0] lsu_wb_reg_adr;
    wire lsu_wb_we;
    wire [31:0] lsu_wb_dat;
    // To WB
    wire [4:0] wb_reg_adr;
    wire [31:0] wb_dat;
    wire wb_we;
    wire [4:0] wb_mul_reg_adr;
    wire [31:0] wb_mul_dat;
    wire wb_op_mul;
    // To ctrl
    wire ctrl_ic_stall;
    wire ctrl_lsu_stall;
    wire ctrl_bypass_stall;
    // To RF
    wire rf_re1, rf_re2;
    wire [4:0] rf_r_addr1, rf_r_addr2;
    wire [4:0] rf_w_adr;
    wire [31:0] rf_w_dat;
    wire rf_w_we;
    // To Bypass
    wire [31:0] bypass_rop1;
    wire [31:0] bypass_rop2;
    wire [4:0] bypass_mul_reg_adr;
    wire bypass_mul_reg_we;
    
    yamp32_ifu IFU(
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_fls          (ifu_fls),
        .i_fls_pc       (ifu_fls_pc),
        // To IDU
        .o_insn         (idu_insn),
        .o_pc           (idu_pc),
        // To CTRL
        .o_ic_stall     (ctrl_ic_stall),
        // To/From IRAM
        .i_iram_dout        (i_iram_dout),
        .o_iram_br_req      (o_iram_br_req),
        .i_iram_br_ack      (i_iram_br_ack),
        .o_iram_br_addr     (o_iram_br_addr),
        // From ctrl
        .i_stall            (ifu_stall)
    );

    yamp32_idu IDU(
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        // From IFU
        .i_pc           (idu_pc),
        .i_insn         (idu_insn),
        // To EXU
        .o_exu_pc       (exu_pc),
        .o_exu_ds_pc    (exu_ds_pc),
        .o_exu_ds_pc_nxt (exu_ds_pc_nxt),
        .o_exu_bcc_tgt  (exu_bcc_tgt),
        .o_exu_bcc_backward (exu_bcc_backward),
        .o_exu_lnk_retpc (exu_lnk_retpc),
        .o_exu_j_taken  (exu_j_taken),
        .o_exu_reg_we   (exu_reg_we),
        .o_exu_uop      (exu_uop),
        .o_exu_uimm16   (exu_uimm16),
        .o_exu_disp26   (exu_disp26),
        .o_exu_sa       (exu_sa),
        .o_exu_wb_reg_adr (exu_wb_reg_adr),
        .o_exu_type_i   (exu_type_i),
        .o_exu_type_j   (exu_type_j),
        .o_exu_rop1_adr (exu_rop1_adr),
        .o_exu_rop2_adr (exu_rop2_adr),
        // From EXU
        .i_spec_fls     (idu_spec_fls),
        // To RF
        .o_rf_re1       (rf_re1),
        .o_rf_addr1     (rf_r_addr1),
        .o_rf_re2       (rf_re2),
        .o_rf_addr2     (rf_r_addr2)
    );
    
    yamp32_regfile RF(
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_re1      (rf_re1),
        .i_r_addr1  (rf_r_addr1),
        .i_re2      (rf_re2),
        .i_r_addr2  (rf_r_addr2),
        .o_r_dat1   (bypass_rop1),
        .o_r_dat2   (bypass_rop2),
        .i_w_addr   (rf_w_adr),
        .i_w_dat    (rf_w_dat),
        .i_we       (rf_w_we)
    );
    
    bypass_net BYPASS_NET(
        .i_clk  (i_clk),
        // From IDU
        .i_rop1_re  (rf_re1),
        .i_rop1_adr (rf_r_addr1),
        .i_rop2_re  (rf_re2),
        .i_rop2_adr (rf_r_addr2),
        // From RF
        .i_rop1     (bypass_rop1),
        .i_rop2     (bypass_rop2),
        // From EXU & LSU
        .i_lsu_wb_we (wb_we),
        .i_lsu_wb_reg_adr (wb_reg_adr),
        .i_lsu_wb_dat (wb_dat),
        .i_mul_reg_adr (bypass_mul_reg_adr),
        .i_mul_reg_we (bypass_mul_reg_we),
        // From WB
        .i_wb_we (rf_w_we),
        .i_wb_reg_adr (rf_w_adr),
        .i_wb_dat   (rf_w_dat),
        // To EXU
        .o_rop1 (exu_rop1),
        .o_rop2 (exu_rop2),
        // To CTRL
        .o_stall (ctrl_bypass_stall)
    );
    
    yamp32_exu EXU(
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        // From IDU
        .i_pc       (exu_pc),
        .i_ds_pc    (exu_ds_pc),
        .i_ds_pc_nxt (exu_ds_pc_nxt),
        .i_bcc_tgt  (exu_bcc_tgt),
        .i_bcc_backward (exu_bcc_backward),
        .i_lnk_retpc(exu_lnk_retpc),
        .i_j_taken  (exu_j_taken),
        .i_reg_we   (exu_reg_we),
        .i_uop      (exu_uop),
        .i_type_i   (exu_type_i),
        .i_type_j   (exu_type_j),
        .i_rop1     (exu_rop1),
        .i_rop2     (exu_rop2),
        .i_rop1_adr (exu_rop1_adr),
        .i_rop2_adr (exu_rop2_adr),
        .i_uimm16   (exu_uimm16),
        .i_disp26   (exu_disp26),
        .i_sa       (exu_sa),
        .i_wb_reg_adr   (exu_wb_reg_adr),
        // To IDU
        .o_spec_fls     (idu_spec_fls),
        // To IFU
        .o_ifu_fls      (ifu_fls),
        .o_ifu_fls_pc   (ifu_fls_pc),
        // To LSU
        .o_lsu_load   (lsu_load),
        .o_lsu_store  (lsu_store),
        .o_lsu_dat    (lsu_dat),
        .o_lsu_addr   (lsu_addr),
        .o_lsu_dw     (lsu_dw),
        .o_lsu_wb_reg_adr (lsu_wb_reg_adr),
        .o_lsu_wb_dat     (lsu_wb_dat),
        .o_lsu_wb_we      (lsu_wb_we),
        // To bypass
        .o_mul_reg_adr (bypass_mul_reg_adr),
        .o_mul_reg_we (bypass_mul_reg_we),
        // To WB
        .o_wb_op_mul    (wb_op_mul),
        .o_wb_mul_reg_adr   (wb_mul_reg_adr),
        .o_wb_mul_dat   (wb_mul_dat),
        // From ctrl
        .i_stall    (exu_stall),
        .i_inv      (exu_inv)
    );
    
    yamp32_lsu LSU(
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        // From EXU
        .i_load     (lsu_load),
        .i_store    (lsu_store),
        .i_dat      (lsu_dat),
        .i_addr     (lsu_addr),
        .i_dw       (lsu_dw),
        .i_wb_reg_adr (lsu_wb_reg_adr),
        .i_wb_dat     (lsu_wb_dat),
        .i_wb_we      (lsu_wb_we),
        // To WB
        .o_wb_reg_adr (wb_reg_adr),
        .o_wb_dat     (wb_dat),
        .o_wb_we      (wb_we),
        // DataRAM R inerface
        .o_dram_baseram_reqr_valid  (o_dram_baseram_reqr_valid),
        .i_dram_baseram_reqr_ready  (i_dram_baseram_reqr_ready),
        .o_dram_baseram_reqr_addr   (o_dram_baseram_reqr_addr),
        .i_dram_baseram_rsp_valid   (i_dram_baseram_rsp_valid),
        .o_dram_baseram_rsp_ready   (o_dram_baseram_rsp_ready),
        .i_dram_baseram_dout        (i_dram_baseram_dout),
        .o_dram_extram_reqr_valid   (o_dram_extram_reqr_valid),
        .i_dram_extram_reqr_ready   (i_dram_extram_reqr_ready),
        .o_dram_extram_reqr_addr    (o_dram_extram_reqr_addr),
        .i_dram_extram_rsp_valid    (i_dram_extram_rsp_valid),
        .o_dram_extram_rsp_ready    (o_dram_extram_rsp_ready),
        .i_dram_extram_dout         (i_dram_extram_dout),
        // DataRAM W interface
        .o_dram_baseram_reqw_valid  (o_dram_baseram_reqw_valid),
        .i_dram_baseram_reqw_ready  (i_dram_baseram_reqw_ready),
        .o_dram_baseram_reqw_be     (o_dram_baseram_reqw_be),
        .o_dram_baseram_reqw_addr   (o_dram_baseram_reqw_addr),
        .o_dram_baseram_din         (o_dram_baseram_din),
        .o_dram_extram_reqw_valid   (o_dram_extram_reqw_valid),
        .i_dram_extram_reqw_ready   (i_dram_extram_reqw_ready),
        .o_dram_extram_reqw_be      (o_dram_extram_reqw_be),
        .o_dram_extram_reqw_addr    (o_dram_extram_reqw_addr),
        .o_dram_extram_din          (o_dram_extram_din),
        // UART RX
        .uart_rx_ready              (uart_rx_ready),
        .uart_rx_rd                 (uart_rx_rd),
        .uart_rx_dout               (uart_rx_dout),
        // UART TX
        .uart_tx_ready              (uart_tx_ready),
        .uart_tx_we                 (uart_tx_we),
        .uart_tx_din                (uart_tx_din),
        // To ctrl
        .o_stall                    (ctrl_lsu_stall)
    );
    
    yamp32_wb_mux WB_MUX(
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        // From LSU & EXU
        .i_wb_op_mul    (wb_op_mul),
        .i_wb_mul_reg_adr   (wb_mul_reg_adr),
        .i_wb_mul_dat   (wb_mul_dat),
        .i_wb_reg_adr   (wb_reg_adr),
        .i_wb_dat       (wb_dat),
        .i_wb_we        (wb_we),
        // To regfile
        .o_rf_reg_adr   (rf_w_adr),
        .o_rf_dat       (rf_w_dat),
        .o_rf_we        (rf_w_we)
    );
    
    yamp32_ctrl CTRL(
        .i_ic_stall     (ctrl_ic_stall),
        .i_lsu_stall    (ctrl_lsu_stall),
        .i_bypass_stall (ctrl_bypass_stall),
        .o_ifu_stall    (ifu_stall),
        .o_exu_stall    (exu_stall),
        .o_exu_inv      (exu_inv)
    );
    
endmodule