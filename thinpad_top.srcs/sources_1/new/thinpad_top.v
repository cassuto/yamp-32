`default_nettype none

module thinpad_top(
    input wire clk_50M,           //50MHz ʱ������
    input wire clk_11M0592,       //11.0592MHz ʱ�����루���ã��ɲ��ã�

    input wire clock_btn,         //BTN5�ֶ�ʱ�Ӱ�ť���أ���������·������ʱΪ1
    input wire reset_btn,         //BTN6�ֶ���λ��ť���أ���������·������ʱΪ1

    input  wire[3:0]  touch_btn,  //BTN1~BTN4����ť���أ�����ʱΪ1
    input  wire[31:0] dip_sw,     //32λ���뿪�أ�������ON��ʱΪ1
    output wire[15:0] leds,       //16λLED�����ʱ1����
    output wire[7:0]  dpy0,       //����ܵ�λ�źţ�����С���㣬���1����
    output wire[7:0]  dpy1,       //����ܸ�λ�źţ�����С���㣬���1����

    //BaseRAM�ź�
    inout wire[31:0] base_ram_data,  //BaseRAM���ݣ���8λ��CPLD���ڿ���������
    output wire[19:0] base_ram_addr, //BaseRAM��ַ
    output wire[3:0] base_ram_be_n,  //BaseRAM�ֽ�ʹ�ܣ�����Ч�������ʹ���ֽ�ʹ�ܣ��뱣��Ϊ0
    output wire base_ram_ce_n,       //BaseRAMƬѡ������Ч
    output wire base_ram_oe_n,       //BaseRAM��ʹ�ܣ�����Ч
    output wire base_ram_we_n,       //BaseRAMдʹ�ܣ�����Ч

    //ExtRAM�ź�
    inout wire[31:0] ext_ram_data,  //ExtRAM����
    output wire[19:0] ext_ram_addr, //ExtRAM��ַ
    output wire[3:0] ext_ram_be_n,  //ExtRAM�ֽ�ʹ�ܣ�����Ч�������ʹ���ֽ�ʹ�ܣ��뱣��Ϊ0
    output wire ext_ram_ce_n,       //ExtRAMƬѡ������Ч
    output wire ext_ram_oe_n,       //ExtRAM��ʹ�ܣ�����Ч
    output wire ext_ram_we_n,       //ExtRAMдʹ�ܣ�����Ч

    //ֱ�������ź�
    output wire txd,  //ֱ�����ڷ��Ͷ�
    input  wire rxd,  //ֱ�����ڽ��ն�

    //Flash�洢���źţ��ο� JS28F640 оƬ�ֲ�
    output wire [22:0]flash_a,      //Flash��ַ��a0����8bitģʽ��Ч��16bitģʽ������
    inout  wire [15:0]flash_d,      //Flash����
    output wire flash_rp_n,         //Flash��λ�źţ�����Ч
    output wire flash_vpen,         //Flashд�����źţ��͵�ƽʱ���ܲ�������д
    output wire flash_ce_n,         //FlashƬѡ�źţ�����Ч
    output wire flash_oe_n,         //Flash��ʹ���źţ�����Ч
    output wire flash_we_n,         //Flashдʹ���źţ�����Ч
    output wire flash_byte_n,       //Flash 8bitģʽѡ�񣬵���Ч����ʹ��flash��16λģʽʱ����Ϊ1

    //ͼ������ź�
    output wire[2:0] video_red,    //��ɫ���أ�3λ
    output wire[2:0] video_green,  //��ɫ���أ�3λ
    output wire[1:0] video_blue,   //��ɫ���أ�2λ
    output wire video_hsync,       //��ͬ����ˮƽͬ�����ź�
    output wire video_vsync,       //��ͬ������ֱͬ�����ź�
    output wire video_clk,         //����ʱ�����
    output wire video_de           //��������Ч�źţ���������������
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

//ͼ�������ʾ���ֱ���800x600@75Hz������ʱ��Ϊ50MHz
wire [11:0] hdata;
assign video_red = hdata < 266 ? 3'b111 : 0; //��ɫ����
assign video_green = hdata < 532 && hdata >= 266 ? 3'b111 : 0; //��ɫ����
assign video_blue = hdata >= 532 ? 2'b11 : 0; //��ɫ����
assign video_clk = clk_50M;
vga #(12, 800, 856, 976, 1040, 600, 637, 643, 666, 1, 1) vga800x600at75 (
    .clk(clk_50M), 
    .hdata(hdata), //������
    .vdata(),      //������
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