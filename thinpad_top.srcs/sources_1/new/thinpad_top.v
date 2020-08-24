`default_nettype none

module thinpad_top(
    input wire clk_50M,           //50MHz 时钟输入
    input wire clk_11M0592,       //11.0592MHz 时钟输入（备用，可不用）

    input wire clock_btn,         //BTN5手动时钟按钮开关，带消抖电路，按下时为1
    input wire reset_btn,         //BTN6手动复位按钮开关，带消抖电路，按下时为1

    input  wire[3:0]  touch_btn,  //BTN1~BTN4，按钮开关，按下时为1
    input  wire[31:0] dip_sw,     //32位拨码开关，拨到“ON”时为1
    output wire[15:0] leds,       //16位LED，输出时1点亮
    output wire[7:0]  dpy0,       //数码管低位信号，包括小数点，输出1点亮
    output wire[7:0]  dpy1,       //数码管高位信号，包括小数点，输出1点亮

    //BaseRAM信号
    inout wire[31:0] base_ram_data,  //BaseRAM数据，低8位与CPLD串口控制器共享
    output wire[19:0] base_ram_addr, //BaseRAM地址
    output wire[3:0] base_ram_be_n,  //BaseRAM字节使能，低有效。如果不使用字节使能，请保持为0
    output wire base_ram_ce_n,       //BaseRAM片选，低有效
    output wire base_ram_oe_n,       //BaseRAM读使能，低有效
    output wire base_ram_we_n,       //BaseRAM写使能，低有效

    //ExtRAM信号
    inout wire[31:0] ext_ram_data,  //ExtRAM数据
    output wire[19:0] ext_ram_addr, //ExtRAM地址
    output wire[3:0] ext_ram_be_n,  //ExtRAM字节使能，低有效。如果不使用字节使能，请保持为0
    output wire ext_ram_ce_n,       //ExtRAM片选，低有效
    output wire ext_ram_oe_n,       //ExtRAM读使能，低有效
    output wire ext_ram_we_n,       //ExtRAM写使能，低有效

    //直连串口信号
    output wire txd,  //直连串口发送端
    input  wire rxd,  //直连串口接收端

    //Flash存储器信号，参考 JS28F640 芯片手册
    output wire [22:0]flash_a,      //Flash地址，a0仅在8bit模式有效，16bit模式无意义
    inout  wire [15:0]flash_d,      //Flash数据
    output wire flash_rp_n,         //Flash复位信号，低有效
    output wire flash_vpen,         //Flash写保护信号，低电平时不能擦除、烧写
    output wire flash_ce_n,         //Flash片选信号，低有效
    output wire flash_oe_n,         //Flash读使能信号，低有效
    output wire flash_we_n,         //Flash写使能信号，低有效
    output wire flash_byte_n,       //Flash 8bit模式选择，低有效。在使用flash的16位模式时请设为1

    //图像输出信号
    output wire[2:0] video_red,    //红色像素，3位
    output wire[2:0] video_green,  //绿色像素，3位
    output wire[1:0] video_blue,   //蓝色像素，2位
    output wire video_hsync,       //行同步（水平同步）信号
    output wire video_vsync,       //场同步（垂直同步）信号
    output wire video_clk,         //像素时钟输出
    output wire video_de           //行数据有效信号，用于区分消隐区
);

wire locked, clk_cpu, clk_20M;
// IMPORTANT! PLL out F_{clk_cpu} must be consistent with Fcpu.
parameter Fcpu = 115000000;  // Hz
pll_example clock_gen
 (
  // Clock in ports
  .clk_in1(clk_50M),
  // Clock out ports
  .clk_out1(clk_cpu), // to CPU
  .clk_out2(clk_20M),
  // Status and control signals
  .reset(reset_btn),
  .locked(locked)
 );

reg reset_of_clkcpu;
always@(posedge clk_cpu or negedge locked) begin
    if(~locked) reset_of_clkcpu <= 1'b0;
    else        reset_of_clkcpu <= 1'b1;
end

/* =========== Demo code begin =========== */

//图像输出演示，分辨率800x600@75Hz，像素时钟为50MHz
wire [11:0] hdata;
assign video_red = hdata < 266 ? 3'b111 : 0; //红色竖条
assign video_green = hdata < 532 && hdata >= 266 ? 3'b111 : 0; //绿色竖条
assign video_blue = hdata >= 532 ? 2'b11 : 0; //蓝色竖条
assign video_clk = clk_50M;
vga #(12, 800, 856, 976, 1040, 600, 637, 643, 666, 1, 1) vga800x600at75 (
    .clk(clk_50M), 
    .hdata(hdata), //横坐标
    .vdata(),      //纵坐标
    .hsync(video_hsync),
    .vsync(video_vsync),
    .data_enable(video_de)
);
/* =========== Demo code end =========== */

wire uart_rx_ready;
wire uart_rx_rd;
wire [7:0] uart_rx_dout;
wire uart_tx_ready;
wire uart_tx_we;
wire [7:0] uart_tx_din;

/*fake_*/uart #(
    .F_BAUD_CLK (Fcpu),
    .BAUD_RATE (9600)
)
UART(
    .clk            (clk_cpu),
    .rst_n          (reset_of_clkcpu),
    // TTL 232
    .rxd            (rxd),
    .txd            (txd),
    // RX
    .rx_ready       (uart_rx_ready),
    .rx_rd          (uart_rx_rd),
    .rx_dout        (uart_rx_dout),
    // TX
    .tx_ready       (uart_tx_ready),
    .tx_we          (uart_tx_we),
    .tx_din         (uart_tx_din)
);

wire [31:0]       iram_dout;
wire              iram_br_req;
wire              iram_br_ack;
wire [19:0]       iram_br_addr;

wire              dram_baseram_reqr_valid;
wire              dram_baseram_reqr_ready;
wire [19:0]       dram_baseram_reqr_addr;
wire              dram_baseram_rsp_valid;
wire              dram_baseram_rsp_ready;
wire [31:0]       dram_baseram_dout;
wire              dram_extram_reqr_valid;
wire              dram_extram_reqr_ready;
wire [19:0]       dram_extram_reqr_addr;
wire              dram_extram_rsp_valid;
wire              dram_extram_rsp_ready;
wire [31:0]       dram_extram_dout;

wire              dram_baseram_reqw_valid;
wire              dram_baseram_reqw_ready;
wire [3:0]        dram_baseram_reqw_be;
wire [19:0]       dram_baseram_reqw_addr;
wire [31:0]       dram_baseram_din;
wire              dram_extram_reqw_valid;
wire              dram_extram_reqw_ready;
wire [3:0]        dram_extram_reqw_be;
wire [19:0]       dram_extram_reqw_addr;
wire [31:0]       dram_extram_din;

yamp32_biu BIU(
    // BaseRAM signals
    .base_ram_data      (base_ram_data),
    .base_ram_addr      (base_ram_addr),
    .base_ram_be_n      (base_ram_be_n),
    .base_ram_ce_n      (base_ram_ce_n),
    .base_ram_oe_n      (base_ram_oe_n),
    .base_ram_we_n      (base_ram_we_n),
                                                   
    // ExtRAM signals
    .ext_ram_data       (ext_ram_data),
    .ext_ram_addr       (ext_ram_addr),
    .ext_ram_be_n       (ext_ram_be_n),
    .ext_ram_ce_n       (ext_ram_ce_n),
    .ext_ram_oe_n       (ext_ram_oe_n),
    .ext_ram_we_n       (ext_ram_we_n),
    
    .i_clk              (clk_cpu),
    .i_rst_n            (reset_of_clkcpu),
    
    // CPU IRAM interface
    .o_iram_dout        (iram_dout),
    .i_iram_br_req      (iram_br_req),
    .o_iram_br_ack      (iram_br_ack),
    .i_iram_br_addr     (iram_br_addr),
    
    // CPU DRAM interface
    .i_dram_baseram_reqr_valid  (dram_baseram_reqr_valid),
    .o_dram_baseram_reqr_ready  (dram_baseram_reqr_ready),
    .i_dram_baseram_reqr_addr   (dram_baseram_reqr_addr),
    .o_dram_baseram_rsp_valid   (dram_baseram_rsp_valid),
    .i_dram_baseram_rsp_ready   (dram_baseram_rsp_ready),
    .o_dram_baseram_dout        (dram_baseram_dout),
    .i_dram_extram_reqr_valid   (dram_extram_reqr_valid),
    .o_dram_extram_reqr_ready   (dram_extram_reqr_ready),
    .i_dram_extram_reqr_addr    (dram_extram_reqr_addr),
    .o_dram_extram_rsp_valid    (dram_extram_rsp_valid),
    .i_dram_extram_rsp_ready    (dram_extram_rsp_ready),
    .o_dram_extram_dout         (dram_extram_dout),
    
    .i_dram_baseram_reqw_valid  (dram_baseram_reqw_valid),
    .o_dram_baseram_reqw_ready  (dram_baseram_reqw_ready),
    .i_dram_baseram_reqw_be     (dram_baseram_reqw_be),
    .i_dram_baseram_reqw_addr   (dram_baseram_reqw_addr),
    .i_dram_baseram_din         (dram_baseram_din),
    .i_dram_extram_reqw_valid   (dram_extram_reqw_valid),
    .o_dram_extram_reqw_ready   (dram_extram_reqw_ready),
    .i_dram_extram_reqw_be      (dram_extram_reqw_be),
    .i_dram_extram_reqw_addr    (dram_extram_reqw_addr),
    .i_dram_extram_din          (dram_extram_din)
);

/* =========== CPU Core =========== */
yamp32_core CORE(
    .i_clk      (clk_cpu),
    .i_rst_n    (reset_of_clkcpu),
    
    // Insn RAM interface
    .i_iram_dout        (iram_dout),
    .o_iram_br_req      (iram_br_req),
    .i_iram_br_ack      (iram_br_ack),
    .o_iram_br_addr     (iram_br_addr),
    
    // Data RAM interface
    .o_dram_baseram_reqr_valid  (dram_baseram_reqr_valid),
    .i_dram_baseram_reqr_ready  (dram_baseram_reqr_ready),
    .o_dram_baseram_reqr_addr   (dram_baseram_reqr_addr),
    .i_dram_baseram_rsp_valid   (dram_baseram_rsp_valid),
    .o_dram_baseram_rsp_ready   (dram_baseram_rsp_ready),
    .i_dram_baseram_dout        (dram_baseram_dout),
    .o_dram_extram_reqr_valid   (dram_extram_reqr_valid),
    .i_dram_extram_reqr_ready   (dram_extram_reqr_ready),
    .o_dram_extram_reqr_addr    (dram_extram_reqr_addr),
    .i_dram_extram_rsp_valid    (dram_extram_rsp_valid),
    .o_dram_extram_rsp_ready    (dram_extram_rsp_ready),
    .i_dram_extram_dout         (dram_extram_dout),
    
    .o_dram_baseram_reqw_valid  (dram_baseram_reqw_valid),
    .i_dram_baseram_reqw_ready  (dram_baseram_reqw_ready),
    .o_dram_baseram_reqw_be     (dram_baseram_reqw_be),
    .o_dram_baseram_reqw_addr   (dram_baseram_reqw_addr),
    .o_dram_baseram_din         (dram_baseram_din),
    .o_dram_extram_reqw_valid   (dram_extram_reqw_valid),
    .i_dram_extram_reqw_ready   (dram_extram_reqw_ready),
    .o_dram_extram_reqw_be      (dram_extram_reqw_be),
    .o_dram_extram_reqw_addr    (dram_extram_reqw_addr),
    .o_dram_extram_din          (dram_extram_din),
    
    // UART RX
    .uart_rx_ready              (uart_rx_ready),
    .uart_rx_rd                 (uart_rx_rd),
    .uart_rx_dout               (uart_rx_dout),
    // UART TX
    .uart_tx_ready              (uart_tx_ready),
    .uart_tx_we                 (uart_tx_we),
    .uart_tx_din                (uart_tx_din)
);

/* =========== CPU Core End =========== */

endmodule