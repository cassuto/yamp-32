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

module yamp32_icache
#(
    parameter P_WAYS = -1, // 2^ways
    parameter P_SETS = -1, // 2^sets
    parameter P_LINE = -1, // 2^P_LINE bytes per line (= busrt length of SRAM)
    parameter SRAM_AW = 20
)
(
    input wire            i_clk,
    input wire            i_rst_n,
    // CPU interface
    input wire [31:0]     i_pc_paddr,
    input wire            i_req,
    output wire           o_stall,
    output wire [31:0]    o_insn,
    
    // SRAM interface
    input wire [31:0]     i_sram_dout,
    output wire           o_sram_br_req,
    input wire            i_sram_br_ack,
    output wire [SRAM_AW-1:0] o_sram_br_addr
);
    localparam TAG_ADDR_DW = SRAM_AW+2-P_SETS-P_LINE;
    
    reg mmreq_r;
    reg [31:0] maddr_r;
    wire mmreq = o_stall ? mmreq_r : i_req;
    wire [31:0] maddr = o_stall ? maddr_r : i_pc_paddr;
    
    always @(posedge i_clk or negedge i_rst_n)
        if (~i_rst_n) begin
            mmreq_r <= 1'b0;
        end else if (~o_stall) begin // When stalling we don't accept incoming request and address
            mmreq_r <= i_req;
            maddr_r <= i_pc_paddr;
        end
    
    reg                 nl_rd_r;            // Read from next level cache/memory ?
    reg [SRAM_AW+2-P_LINE-1:0] nl_baddr_r;
    wire                slow_nl_r_pending;  // Is cache line reading from SRAM ?
    wire [31:0]         slow_nl_dout;
    
    // Main FSM states
    localparam S_BOOT = 3'b000;
    localparam S_IDLE = 3'b001;
    localparam S_READ_PENDING_1 = 3'b011;
    localparam S_READ_PENDING_2 = 3'b010;
    
    reg [2:0] status_r;
    wire ch_idle = (status_r == S_IDLE);
    reg [P_LINE-2-1:0] slow_line_adr_cnt;
    reg [P_SETS-1:0] clear_cnt;

    wire [P_SETS-1:0] entry_idx = (status_r==S_BOOT) ? clear_cnt : maddr[P_LINE+P_SETS-1:P_LINE];

    // Read
    wire                    cache_v     [0:(1<<P_WAYS)-1];
    wire [TAG_ADDR_DW-1:0]  cache_addr  [0:(1<<P_WAYS)-1];
    wire [P_WAYS-1:0]       cache_lru   [0:(1<<P_WAYS)-1];
    
    // Write
    reg                     w_cache_v_prv       [0:(1<<P_WAYS)-1];
    reg [TAG_ADDR_DW-1:0]   w_cache_addr_prv    [0:(1<<P_WAYS)-1];
    reg [P_WAYS-1:0]        w_lru_prv           [0:(1<<P_WAYS)-1];
    
    reg [P_SETS-1:0] entry_idx_prv;
    
    always @(posedge i_clk)
        entry_idx_prv <= entry_idx;
    
    localparam TAG_DW = 1+TAG_ADDR_DW;
    
    // Cache entries
generate
    genvar i;
    for(i=0;i<(1<<P_WAYS);i=i+1) begin
        wire [TAG_DW-1:0] tag_dina, tag_doutb;
        wire [P_SETS-1:0] addr_prv = (status_r == S_BOOT) ? entry_idx : entry_idx_prv;
        
        assign tag_dina = {w_cache_v_prv[i], w_cache_addr_prv[i]};
        assign {cache_v[i], cache_addr[i]} = tag_doutb;

        // Tags
        xpm_sdpram_bypass #(
            .ADDR_WIDTH(P_SETS),
            .DATA_WIDTH(TAG_DW)
        )
        cache_tags (
            .clk    (i_clk),
            .rst_n  (i_rst_n),
            // Port A (Write)
            .addra  (addr_prv),
            .dina   (tag_dina),
            .ena    (1'b1),
            .wea    (1'b1),
            // Port B (Read)
            .doutb  (tag_doutb),
            .addrb  (entry_idx),
            .enb    (1'b1)
        );
        
        // LRU
        xpm_sdpram_bypass #(
            .ADDR_WIDTH(P_SETS),
            .DATA_WIDTH(P_WAYS)
        )
        cache_lru (
            .clk    (i_clk),
            .rst_n  (i_rst_n),
            // Port A (Write)
            .addra  (addr_prv),
            .dina   (w_lru_prv[i]),
            .ena    (1'b1),
            .wea    (1'b1),
            // Port B (Read)
            .doutb  (cache_lru[i]),
            .addrb  (entry_idx),
            .enb    (1'b1)
        );
    end
endgenerate
    
    wire [(1<<P_WAYS)-1:0] match;
    wire [(1<<P_WAYS)-1:0] free;
    wire [P_WAYS-1:0] lru[(1<<P_WAYS)-1:0];
generate
    for(i=0; i<(1<<P_WAYS); i=i+1) begin : entry_wires
      assign match[i] = cache_v[i] & (cache_addr[i] == maddr_r[SRAM_AW+2-1:P_LINE+P_SETS]);
      assign free[i] = ~|cache_lru[i];
      assign lru[i] = {P_WAYS{match[i]}} & cache_lru[i];
    end
endgenerate

    wire hit = |match;

    wire [P_WAYS-1:0] match_way;
    wire [P_WAYS-1:0] free_way_idx;
    wire [P_WAYS-1:0] lru_thresh;
    
generate
    if (P_WAYS==2) begin : p_ways_2
        // 4-to-2 binary encoder.
        assign match_way = {|match[3:2], match[3] | match[1]};
        // 4-to-2 binary encoder
        assign free_way_idx = {|free[3:2], free[3] | free[1]};
        // LRU threshold
        assign lru_thresh = lru[0] | lru[1] | lru[2] | lru[3];
    end else if (P_WAYS==1) begin : p_ways_1
        // 1-to-2 binary encoder.
        assign match_way = match[1];
        // 1-to-2 binary encoder
        assign free_way_idx = free[1];
        // LRU threshold
        assign lru_thresh = lru[0] | lru[1];
    end
endgenerate

    // Slow side
    // Maintain the line addr counter,
    // when burst transmitting while cache line filling or writing back
    always @(posedge i_clk or negedge i_rst_n)
        if(~i_rst_n)
            slow_line_adr_cnt <= {P_LINE-2{1'b0}};
        else if(slow_nl_r_pending)
            slow_line_adr_cnt <= slow_line_adr_cnt + 1'b1;

    localparam CH_AW = P_WAYS+P_SETS+P_LINE-2;
    
    wire ch_mem_en_a = slow_nl_r_pending;
    wire ch_mem_we_a = slow_nl_r_pending;
    wire [CH_AW-1:0] ch_mem_addr_a = {match_way, ~entry_idx[P_SETS-1:0], slow_line_adr_cnt[P_LINE-3:0]};
    wire [31:0] ch_mem_din_a = slow_nl_dout;
    wire ch_mem_en_b = mmreq & ch_idle;
    wire [CH_AW-1:0] ch_mem_addr_b = {match_way, ~entry_idx[P_SETS-1:0], maddr[P_LINE-1:2]};
    wire [31:0] ch_mem_dout_b;
    
    // IMPORTANT! regenerate this core after parameters changed
    // Write-First
    blk_mem_icache cache_mem(
        // Slow side (SRAM)
        .clka    (i_clk),
        .addra   (ch_mem_addr_a[CH_AW-1:0]),
        .wea     (ch_mem_we_a),
        .dina    (ch_mem_din_a[31:0]),
        .ena     (ch_mem_en_a),
        // Fast side (CPU)
        .clkb    (i_clk),
        .addrb   (ch_mem_addr_b[CH_AW-1:0]),
        .doutb   (ch_mem_dout_b[31:0]),
        .enb     (ch_mem_en_b)
    );

    assign o_insn = ch_mem_dout_b;

generate
    for(i=0; i<(1<<P_WAYS); i=i+1) begin : gen_wyas
        always @(*) begin
            if(ch_idle & (mmreq_r & hit)) begin
                // Update LRU priority
                w_lru_prv[i] = match[i] ? {P_WAYS{1'b1}} : cache_lru[i] - (cache_lru[i] > lru_thresh); 
            end else if(status_r == S_BOOT) begin
                // Set the initial value of LRU
                w_lru_prv[i] = i;
            end else begin
                w_lru_prv[i] = cache_lru[i];
            end
        end
        
        always @(*) begin
            if (ch_idle & (mmreq_r & ~hit) & (free_way_idx==i)) begin
                // Refill info when cache miss
                w_cache_v_prv[i] = 1'b1;
                w_cache_addr_prv[i] = maddr_r[SRAM_AW+2-1:P_LINE+P_SETS];
            end else if(status_r==S_BOOT) begin
                w_cache_v_prv[i] = 1'b0;
                w_cache_addr_prv[i] = {TAG_ADDR_DW{1'b0}};
            end else begin
                w_cache_v_prv[i] = cache_v[i];
                w_cache_addr_prv[i] = cache_addr[i];
            end
        end
         
    end
endgenerate

    wire line_adr_cnt_msb = slow_line_adr_cnt[P_LINE-3];

    reg s_stall_r;
    assign o_stall = (ch_idle & mmreq_r & ~hit) | s_stall_r;
    
    // Main FSM
    always @(posedge i_clk or negedge i_rst_n) begin
      if(~i_rst_n) begin
         status_r <= S_BOOT;
         clear_cnt <= {P_SETS{1'b1}};
         s_stall_r <= 1'b1;
      end else begin
         // Main FSM
         case(status_r)
            S_BOOT: begin
                // Invalidate cache lines by hardware
                clear_cnt <= clear_cnt - 1'b1;
                if (clear_cnt == {P_SETS{1'b0}}) begin
                    status_r <= S_IDLE;
                    s_stall_r <= 1'b0;
                end
            end
            
            S_IDLE: begin
                nl_baddr_r <= maddr_r[SRAM_AW+2-1:P_LINE];
                if(mmreq_r & ~hit) begin
                  // Cache missed
                  // Fill a free entry.
                  nl_rd_r <= 1'b1;
                  status_r <= S_READ_PENDING_1;
                  s_stall_r <= 1'b1;
                end else begin
                  // Cache hit or idle
                  s_stall_r <= 1'b0;
                end
            end
            // Pending for reading
            S_READ_PENDING_1: begin 
                if(line_adr_cnt_msb)
                  status_r <= S_READ_PENDING_2;
            end
            S_READ_PENDING_2: begin
                nl_rd_r <= 1'b0;
                if(~line_adr_cnt_msb) begin
                  status_r <= S_IDLE;
                end
            end
         endcase
      end
    end

    // Receive signals from nl_*

    assign o_sram_br_req = nl_rd_r;
    assign o_sram_br_addr  = {nl_baddr_r[SRAM_AW+2-P_LINE-1:0], {P_LINE-2{1'b0}}}; // Aligned at 4 bytes
    assign slow_nl_r_pending = i_sram_br_ack;
    assign slow_nl_dout = i_sram_dout;
    
endmodule
