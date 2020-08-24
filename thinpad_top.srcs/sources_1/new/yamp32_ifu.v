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

module yamp32_ifu(
    input wire i_clk,
    input wire i_rst_n,
    output wire [31:0] o_insn,
    output wire [31:0] o_pc,
    
    // Insn RAM Interface
    input wire [31:0]      i_iram_dout,
    output wire            o_iram_br_req,
    input wire             i_iram_br_ack,
    output wire [19:0]     o_iram_br_addr,
    
    // To CTRL
    output wire o_ic_stall,
    
    input wire i_fls,
    input wire [29:0] i_fls_pc,
    input wire i_stall
);
    `include "yamp32_parameters.vh"
    
    reg [29:0] pc_r;
    wire [29:0] pc_nxt;
    wire [31:0] insn_paddr;
    wire [31:0] insn;
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n)
            pc_r <= 30'h20000000-1'b1; // Reset Vector
        else if (~i_stall) begin
            pc_r <= pc_nxt;
        end
    end
    assign pc_nxt = i_fls ? i_fls_pc : pc_r + 1'b1;

    yamp32_segmap SEGMAP(
        .i_vaddr    ({pc_nxt[29:0], 2'b00}),
        .o_paddr    (insn_paddr)
    );
    
    yamp32_icache #(
        .P_WAYS  (ICACHE_P_WAYS),
        .P_SETS  (ICACHE_P_SETS),
        .P_LINE  (ICACHE_P_LINE),
        .SRAM_AW (20)
    )
    ICACHE(
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        // CPU interface
        .i_pc_paddr (insn_paddr),
        .i_req      (i_rst_n & ~i_stall), // to boot cache up
        .o_stall    (o_ic_stall),
        .o_insn     (insn),
        // SRAM interface
        .i_sram_dout    (i_iram_dout),
        .o_sram_br_req  (o_iram_br_req),
        .i_sram_br_ack  (i_iram_br_ack),
        .o_sram_br_addr (o_iram_br_addr)
    );

    reg [31:0] insn_r;
    reg [31:0] pc_rr;
    always @(posedge i_clk or negedge i_rst_n)
        if (~i_rst_n) begin
            insn_r <= 32'b0;
        end else if (~i_stall) begin
            insn_r <= insn;
            pc_rr <= {pc_r[29:0], 2'b00};
        end

    // Simply stall 2 inputs of IDU here, so we can save resources and improve
    // timing performance.
    // When stalling we don't issue new insn
    assign o_insn = i_stall ? insn_r : insn;
    assign o_pc = i_stall ? pc_rr : {pc_r[29:0], 2'b00};

endmodule
