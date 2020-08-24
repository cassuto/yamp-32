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

module yamp32_lsu(
    input wire                  i_clk,
    input wire                  i_rst_n,
    // DataRAM R inerface
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
    // DataRAM W inerface
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
    output wire [7:0] uart_tx_din,
    // From ALUs
    input wire                  i_load,
    input wire                  i_store,
    input wire [31:0]           i_dat,
    input wire [31:0]           i_addr,
    input wire                  i_dw,
    input wire [4:0]            i_wb_reg_adr,
    input wire [31:0]           i_wb_dat,
    input wire                  i_wb_we,
    // To WB
    output wire [4:0]           o_wb_reg_adr,
    output wire [31:0]          o_wb_dat,
    output wire                 o_wb_we,
    // To ctrl
    output wire                 o_stall
);
    wire [31:0] dc_dat_w;
    reg [7:0] dc_dat_b;
    wire [31:0] dc_o_dat;
    wire [31:0] paddr;

    yamp32_segmap SEGMAP(
        .i_vaddr    (i_addr),
        .o_paddr    (paddr)
    );

    wire lsu_req = (i_load | i_store);
    wire [31:0] lsu_wdat = i_dw ? i_dat  : {i_dat[7:0],i_dat[7:0],i_dat[7:0],i_dat[7:0]};
    
    reg [3:0] bea;
    wire [3:0] lsu_bea = {4{i_dw}} | bea;
    
    always @(paddr)
        case(paddr[1:0])
        2'b00:
            bea = 4'b0001;
        2'b01:
            bea = 4'b0010;
        2'b10:
            bea = 4'b0100;
        2'b11:
            bea = 4'b1000;
        endcase
    
    always @(*)
        case(paddr[1:0])
        2'b00:
            dc_dat_b = dc_dat_w[7:0];
        2'b01:
            dc_dat_b = dc_dat_w[15:8];
        2'b10:
            dc_dat_b = dc_dat_w[23:16];
        2'b11:
            dc_dat_b = dc_dat_w[31:24];
        endcase
    
    assign dc_o_dat = i_dw ? dc_dat_w : {24'b0, dc_dat_b};
    
    // Mapping virtual address to SB_BASERAM, SB_EXTRAM or UART
    wire vmap_uart = i_addr[31]&i_addr[29]&i_addr[28];
    wire vmap_extram = ~vmap_uart & i_addr[22];
    wire vmap_baseram = ~vmap_uart & ~i_addr[22];
    
    // Dispatch LSU operations
    wire store_baseram = vmap_baseram & i_store;
    wire store_extram = vmap_extram & i_store;
    wire load_baseram = vmap_baseram & i_load;
    wire load_extram = vmap_extram & i_load;
    
    // physical address must be algined by 4 bytes
    wire[29:0] lsu_req_addr = paddr[31:2];
    
    localparam SB_DW = 32+20+4; // data + address + be
    
    wire sb_baseram_push;
    wire [SB_DW-1:0] sb_baseram_din;
    wire sb_baseram_pop;
    wire [SB_DW-1:0] sb_baseram_dout;
    wire sb_baseram_empty, sb_baseram_full;
    
    fifo_fwft_sclk #(
        .DEPTH_WIDTH (4),
        .DATA_WIDTH (SB_DW)
    )
    SB_BASERAM(
        .i_clk    (i_clk),
        .i_rst_n   (i_rst_n),
        .o_full   (sb_baseram_full),
        .i_din    (sb_baseram_din),
        .i_push  (sb_baseram_push),
        .o_empty  (sb_baseram_empty),
        .o_dout   (sb_baseram_dout),
        .i_pop  (sb_baseram_pop)
    );
    
    /* =========== SB_BASERAM Pushing =========== */
    
    // StoreBuffer write
    assign sb_baseram_push = ~sb_baseram_full & store_baseram;
    assign sb_baseram_din = {lsu_wdat[31:0], lsu_req_addr[19:0], lsu_bea[3:0]};

    // Stall when store buffer is full and we can't accept new request
    wire stall_sb_baseram = sb_baseram_full & store_baseram;

    /* =========== End SB_BASERAM Pushing =========== */
    
    /* =========== SB_BASERAM Popping =========== */
    
    // Valid-ready handshaking
    assign o_dram_baseram_reqw_valid = ~sb_baseram_empty;
    assign sb_baseram_pop = ~sb_baseram_empty & i_dram_baseram_reqw_ready;
    
    assign {o_dram_baseram_din[31:0],
            o_dram_baseram_reqw_addr[19:0],
            o_dram_baseram_reqw_be[3:0] } = sb_baseram_dout;
    
    wire sb_baseram_busy_n = sb_baseram_empty & i_dram_baseram_reqw_ready;
    
    /* =========== End SB_BASERAM Popping =========== */
    
    wire sb_extram_push;
    wire [SB_DW-1:0] sb_extram_din;
    wire sb_extram_pop;
    wire [SB_DW-1:0] sb_extram_dout;
    wire sb_extram_empty, sb_extram_full;
    
    fifo_fwft_sclk #(
        .DEPTH_WIDTH (4),
        .DATA_WIDTH (SB_DW)
    )
    SB_EXTRAM(
        .i_clk    (i_clk),
        .i_rst_n   (i_rst_n),
        .o_full   (sb_extram_full),
        .i_din    (sb_extram_din),
        .i_push  (sb_extram_push),
        .o_empty  (sb_extram_empty),
        .o_dout   (sb_extram_dout),
        .i_pop  (sb_extram_pop)
    );
    
    /* =========== SB_EXTRAM Pushing =========== */
    
    // StoreBuffer write
    assign sb_extram_push = ~sb_extram_full & store_extram;
    assign sb_extram_din = {lsu_wdat[31:0], lsu_req_addr[19:0], lsu_bea[3:0]};

    // Stall when store buffer is full and we can't accept new request
    wire stall_sb_extram = sb_extram_full & store_extram;

    /* =========== End SB_EXTRAM Pushing =========== */
    
    /* =========== SB_EXTRAM Popping =========== */
    
    // Valid-ready handshaking
    assign o_dram_extram_reqw_valid = ~sb_extram_empty;
    assign sb_extram_pop = ~sb_extram_empty & i_dram_extram_reqw_ready;
    
    assign {o_dram_extram_din[31:0],
            o_dram_extram_reqw_addr[19:0],
            o_dram_extram_reqw_be[3:0] } = sb_extram_dout;
    
    wire sb_extram_busy_n = sb_extram_empty & i_dram_extram_reqw_ready;
    
    /* =========== End SB_EXTRAM Popping =========== */
    
    
    /* =========== baseram Loading =========== */
    
    reg baseram_load_pending_r;
    
    assign o_dram_baseram_reqr_valid = load_baseram;
    
    wire baseram_hds_push = o_dram_baseram_reqr_valid & i_dram_baseram_reqr_ready;
    wire baseram_hds_pop = i_dram_baseram_rsp_valid & o_dram_baseram_rsp_ready;
    
    assign o_dram_baseram_rsp_ready = baseram_load_pending_r;
    
    assign o_dram_baseram_reqr_addr = lsu_req_addr[19:0];
    
    // Handshaking FSM
    reg baseram_load_pending_nxt;
    always @(*) begin
        if (baseram_load_pending_r) begin
            baseram_load_pending_nxt = ~baseram_hds_pop;
        end else begin
            baseram_load_pending_nxt = baseram_hds_push;
        end
    end
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            baseram_load_pending_r <= 1'b0;
        end else begin
            baseram_load_pending_r <= baseram_load_pending_nxt;
        end
    end

    // Stall when BIU don't accept request, or request is not finished
    wire stall_load_baseram = baseram_load_pending_r ? baseram_load_pending_nxt : load_baseram;
    
    /* =========== End baseram Loading =========== */
    
    /* =========== extram Loading =========== */
    
    reg extram_load_pending_r;
    
    assign o_dram_extram_reqr_valid = load_extram;
    
    wire extram_hds_push = o_dram_extram_reqr_valid & i_dram_extram_reqr_ready;
    wire extram_hds_pop = i_dram_extram_rsp_valid & o_dram_extram_rsp_ready;
    
    assign o_dram_extram_rsp_ready = extram_load_pending_r;
    
    assign o_dram_extram_reqr_addr = lsu_req_addr[19:0];
    
    // Handshaking FSM
    reg extram_load_pending_nxt;
    always @(*) begin
        if (extram_load_pending_r) begin
            extram_load_pending_nxt = ~extram_hds_pop;
        end else begin
            extram_load_pending_nxt = extram_hds_push;
        end
    end
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            extram_load_pending_r <= 1'b0;
        end else begin
            extram_load_pending_r <= extram_load_pending_nxt;
        end
    end

    // Stall when BIU don't accept request, or request is not finished
    wire stall_load_extram = extram_load_pending_r ? extram_load_pending_nxt : load_extram;
    
    /* =========== End baseram Loading =========== */
    
    /* =========== UART registers =========== */
    
    // Buffer Register
    wire vmap_uart_BR = vmap_uart & ~i_addr[2];
    // Status Register
    wire vmap_uart_SR = vmap_uart & i_addr[2];
    
    wire store_uart_BR = vmap_uart_BR & i_store;
    wire load_uart_BR = vmap_uart_BR & i_load;
    wire load_uart_SR = vmap_uart_SR & i_load;
    
    wire [31:0] uart_dout;
    reg uart_pending_r;
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n) begin
            uart_pending_r <= 1'b0;
        end else if (load_uart_BR) begin
            uart_pending_r <= ~uart_pending_r;
        end
    end
    
    // Before we send ACK to the terminal, we should ensure the consistency between
    // store buffer and physical RAM 
    wire SR_tx_ready = sb_baseram_busy_n & sb_extram_busy_n & uart_tx_ready;
    
    // Load BR / SR
    assign uart_rx_rd = load_uart_BR & ~uart_pending_r;
    assign uart_dout = {24'b0,
                        ({8{load_uart_BR}} & uart_rx_dout) |
                        {6'b0, {2{load_uart_SR}} & {uart_rx_ready, SR_tx_ready} }
                       };

    // Store BR
    assign uart_tx_we = store_uart_BR;
    assign uart_tx_din = i_dat;
    
    // Read from UART takes 1 cycle
    wire stall_uart = load_uart_BR & ~uart_pending_r;
    
    /* =========== End UART registers =========== */
    
    assign dc_dat_w = ({32{load_baseram}} & i_dram_baseram_dout) |
                      ({32{load_extram}} & i_dram_extram_dout) |
                      ({32{load_uart_SR|uart_pending_r}} & uart_dout);
    
    assign o_stall = stall_sb_baseram | stall_sb_extram | stall_load_baseram | stall_load_extram |
                    stall_uart;

    assign o_wb_we = (i_wb_we | i_load) & ~o_stall;
    assign o_wb_reg_adr = i_wb_reg_adr;
    assign o_wb_dat = i_load ? dc_o_dat : i_wb_dat;
endmodule
