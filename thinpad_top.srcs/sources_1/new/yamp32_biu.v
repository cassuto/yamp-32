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

module yamp32_biu
#(
    parameter P_BASERAM_BURST_LINE = 8 // = 2^P bytes per burst op
)
(
    input wire             i_clk,
    input wire             i_rst_n,
    
    //BaseRAM interface
    inout wire[31:0] base_ram_data,
    output wire[19:0] base_ram_addr,
    output wire[3:0] base_ram_be_n,
    output wire base_ram_ce_n,
    output wire base_ram_oe_n,
    output wire base_ram_we_n,
                                                   
    //ExtRAM interface
    inout wire[31:0] ext_ram_data,
    output wire[19:0] ext_ram_addr,
    output wire[3:0] ext_ram_be_n,
    output wire ext_ram_ce_n,
    output wire ext_ram_oe_n,
    output wire ext_ram_we_n,
    
    // CPU InstRAM interface
    output wire [31:0]      o_iram_dout,
    input wire              i_iram_br_req,
    output reg              o_iram_br_ack,
    input wire [19:0]       i_iram_br_addr,
    
    // CPU DataRAM interface
    input wire                  i_dram_baseram_reqr_valid,
    output wire                 o_dram_baseram_reqr_ready,
    input wire [19:0]           i_dram_baseram_reqr_addr,
    output reg                  o_dram_baseram_rsp_valid,
    input wire                  i_dram_baseram_rsp_ready,
    output wire [31:0]          o_dram_baseram_dout,
    input wire                  i_dram_extram_reqr_valid,
    output wire                 o_dram_extram_reqr_ready,
    input wire [19:0]           i_dram_extram_reqr_addr,
    output reg                  o_dram_extram_rsp_valid,
    input wire                  i_dram_extram_rsp_ready,
    output wire [31:0]          o_dram_extram_dout,
    
    input wire                  i_dram_baseram_reqw_valid,
    output wire                 o_dram_baseram_reqw_ready,
    input wire [3:0]            i_dram_baseram_reqw_be,
    input wire [19:0]           i_dram_baseram_reqw_addr,
    input wire [31:0]           i_dram_baseram_din,
    input wire                  i_dram_extram_reqw_valid,
    output wire                 o_dram_extram_reqw_ready,
    input wire [3:0]            i_dram_extram_reqw_be,
    input wire [19:0]           i_dram_extram_reqw_addr,
    input wire [31:0]           i_dram_extram_din
);

    // BaseRAM burst / one-shot transmission FSM
    localparam BASERAM_IDLE = 3'b000;
    localparam BASERAM_BURST_READ_1 = 3'b001;
    localparam BASERAM_BURST_READ_2 = 3'b011;
    localparam BASERAM_WRITE_1 = 3'b100;
    localparam BASERAM_WRITE_2 = 3'b110;
    localparam BASERAM_READ_1 = 3'b010;
    localparam BASERAM_READ_2 = 3'b111;
    reg [2:0] baseram_status;
    reg [P_BASERAM_BURST_LINE-3:0] baseram_burst_cnt;
    reg [19:0] baseram_addr; /* synthesis syn_useioff = 1 */
    reg baseram_oe_n_r; /* synthesis syn_useioff = 1 */
    reg baseram_we_n_r; /* synthesis syn_useioff = 1 */
    reg [3:0] baseram_be_n_r; /* synthesis syn_useioff = 1 */
    reg [31:0] baseram_wdat_r; /* synthesis syn_useioff = 1 */
    
    // ExtRAM one-shot transmission FSM
    localparam EXTRAM_IDLE = 3'b000;
    localparam EXTRAM_READ_1 = 3'b001;
    localparam EXTRAM_READ_2 = 3'b011;
    localparam EXTRAM_WRITE_1 = 3'b100;
    localparam EXTRAM_WRITE_2 = 3'b110;
    reg [2:0] extram_status;
    reg [19:0] extram_addr; /* synthesis syn_useioff = 1 */
    reg extram_oe_n_r; /* synthesis syn_useioff = 1 */
    reg extram_we_n_r; /* synthesis syn_useioff = 1 */
    reg [3:0] extram_be_n_r; /* synthesis syn_useioff = 1 */
    reg [31:0] extram_wdat_r; /* synthesis syn_useioff = 1 */

    // Priority judge
    assign o_dram_baseram_reqw_ready = (baseram_status==BASERAM_IDLE);
    assign o_dram_baseram_reqr_ready = (baseram_status==BASERAM_IDLE) & ~i_dram_baseram_reqw_valid;

    // BaseRAM FSM
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            baseram_status <= BASERAM_IDLE;
            o_iram_br_ack <= 1'b0;
            baseram_oe_n_r <= 1'b1;
            baseram_we_n_r <= 1'b1;
            baseram_be_n_r <= 4'b0000;
            
            o_dram_baseram_rsp_valid <= 1'b0;
        end else begin
            case(baseram_status)
                BASERAM_IDLE:
                    // Priority judge
                    // When dram-IF is to access baseram
                    // we should not accept iram-IF request util baseram goes free again
                        
                    // Writing baseram through dram-IF
                    if (i_dram_baseram_reqw_valid) begin
                        baseram_addr <= i_dram_baseram_reqw_addr;
                        baseram_wdat_r <= i_dram_baseram_din;
                        baseram_status <= BASERAM_WRITE_1;
                        baseram_we_n_r <= 1'b0;
                        baseram_be_n_r <= ~i_dram_baseram_reqw_be;
                        
                    // Reading baseram through dram IF
                    end else if (i_dram_baseram_reqr_valid) begin
                        baseram_addr <= i_dram_baseram_reqr_addr;
                        baseram_status <= BASERAM_READ_1;
                        baseram_oe_n_r <= 1'b0;
                        baseram_be_n_r <= 4'b0000;
                        o_dram_baseram_rsp_valid <= 1'b0;
                    
                    // Burst reading baseram. (Most likely)
                    end else if (i_iram_br_req) begin
                        baseram_addr <= i_iram_br_addr;
                        baseram_burst_cnt <= {P_BASERAM_BURST_LINE-2{1'b1}};
                        baseram_status <= BASERAM_BURST_READ_1;
                        o_iram_br_ack <= 1'b0;
                        baseram_oe_n_r <= 1'b0;
                        baseram_be_n_r <= 4'b0000;
                    end
                 
                 BASERAM_BURST_READ_1: begin
                    baseram_status <= BASERAM_BURST_READ_2;
                    o_iram_br_ack <= 1'b1;
                 end
                 
                 BASERAM_BURST_READ_2: begin
                    if (baseram_burst_cnt == {P_BASERAM_BURST_LINE-2{1'b0}} ) begin
                        // End reading
                        baseram_status <= BASERAM_IDLE;
                        o_iram_br_ack <= 1'b0;
                        baseram_oe_n_r <= 1'b1;
                    end else begin
                        baseram_addr <= baseram_addr + 1'b1;
                        baseram_burst_cnt <= baseram_burst_cnt - 1'b1;
                        baseram_status <= BASERAM_BURST_READ_1;
                        o_iram_br_ack <= 1'b0;
                    end
                 end
                 
                 BASERAM_WRITE_1: begin
                    baseram_status <= BASERAM_WRITE_2;
                    baseram_we_n_r <= 1'b1; // write on rising edge
                 end
                 
                 BASERAM_WRITE_2: begin
                    baseram_status <= BASERAM_IDLE;
                 end
                 
                 BASERAM_READ_1: begin
                    baseram_status <= BASERAM_READ_2;
                    o_dram_baseram_rsp_valid <= 1'b1;
                 end
                 
                 BASERAM_READ_2: begin
                    if (i_dram_baseram_rsp_ready) begin
                        baseram_status <= BASERAM_IDLE;
                        baseram_oe_n_r <= 1'b1;
                        o_dram_baseram_rsp_valid <= 1'b0;
                    end
                 end
            endcase
        end
    end

    assign base_ram_ce_n = 1'b0;
    assign base_ram_oe_n = baseram_oe_n_r;
    assign base_ram_we_n = baseram_we_n_r;
    assign base_ram_be_n = baseram_be_n_r;
    assign base_ram_addr = baseram_addr;
    assign base_ram_data = base_ram_oe_n ? baseram_wdat_r : 32'bz; // This makes T_hold of data longer when writing
    assign o_iram_dout = base_ram_data;
    assign o_dram_baseram_dout = base_ram_data;
    
    // Priority judge
    assign o_dram_extram_reqw_ready = (extram_status==EXTRAM_IDLE);
    assign o_dram_extram_reqr_ready = (extram_status==EXTRAM_IDLE) & ~i_dram_extram_reqw_valid;
    
    // ExtRAM FSM
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            extram_status <= EXTRAM_IDLE;
            extram_oe_n_r <= 1'b1;
            extram_we_n_r <= 1'b1;
            extram_be_n_r <= 4'b0000;
            
            o_dram_extram_rsp_valid <= 1'b0;
        end else begin
            case(extram_status)
                EXTRAM_IDLE:
                    // Write extram
                    if (i_dram_extram_reqw_valid) begin
                        extram_addr <= i_dram_extram_reqw_addr;
                        extram_wdat_r <= i_dram_extram_din;
                        extram_status <= EXTRAM_WRITE_1;
                        extram_we_n_r <= 1'b0;
                        extram_be_n_r <= ~i_dram_extram_reqw_be;
                        
                    // Read extram
                    end else if (i_dram_extram_reqr_valid) begin
                        extram_addr <= i_dram_extram_reqr_addr;
                        extram_status <= EXTRAM_READ_1;
                        extram_oe_n_r <= 1'b0;
                        extram_be_n_r <= 4'b0000;
                        o_dram_extram_rsp_valid <= 1'b0;
                    end
                    
                EXTRAM_WRITE_1: begin
                    extram_status <= EXTRAM_WRITE_2;
                    extram_we_n_r <= 1'b1; // write on rising edge
                end
                
                EXTRAM_WRITE_2: begin
                    extram_status <= EXTRAM_IDLE;
                end
                    
                EXTRAM_READ_1: begin
                    extram_status <= EXTRAM_READ_2;
                    o_dram_extram_rsp_valid <= 1'b1;
                end
                
                EXTRAM_READ_2: begin
                    if (i_dram_extram_rsp_ready) begin
                        extram_status <= EXTRAM_IDLE;
                        extram_oe_n_r <= 1'b1;
                        o_dram_extram_rsp_valid <= 1'b0;
                    end
                end
            endcase
        end
    end
    
    assign ext_ram_ce_n = 1'b0;
    assign ext_ram_oe_n = extram_oe_n_r;
    assign ext_ram_we_n = extram_we_n_r;
    assign ext_ram_be_n = extram_be_n_r;
    assign ext_ram_addr = extram_addr;
    assign ext_ram_data = ext_ram_oe_n ? extram_wdat_r : 32'bz; // This makes T_hold of data longer when writing
    assign o_dram_extram_dout = ext_ram_data;
    
endmodule