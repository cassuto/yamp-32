`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/08/05 09:22:17
// Design Name: 
// Module Name: tb_fifo_fwft
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_fifo_fwft();

    reg clk = 1'b1;
    reg rst_n = 1'b0;
    reg push = 1'b0;
    reg pop = 1'b0;
    
    reg [51:0] din = 51'h1234;
    wire full;
    wire [51:0] dout;
    wire empty;

    fifo_fwft_sclk #(
        .DEPTH_WIDTH (2),
        .DATA_WIDTH (52)
    )
    FIFO (
        .i_clk  (clk),
        .i_rst_n    (rst_n),
        // Push port
        .i_push  (push & ~full),
        .i_din  (din),
        .o_full (full),
        // Pop port
        .i_pop  (pop & ~empty),
        .o_dout (dout),
        .o_empty (empty)
    );
    
    always @(posedge clk)
        if (push)
            din <= din + 1'b1;
    
    initial forever #5 clk = ~clk;
    
    initial #30 rst_n = 1'b1;
    
    initial #35 push = 1'b1;
    initial #75 push = 1'b0;
    
    initial #105 push = 1'b1;
    initial #145 push = 1'b0;
    
    //assign pop =1'b0;// ~empty;
    initial #75 pop=1'b1;
    
endmodule
