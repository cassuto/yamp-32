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

module xpm_sdpram_bypass #(
    parameter ADDR_WIDTH = -1,
    parameter DATA_WIDTH = -1
)
(
    input wire clk,
    input wire rst_n,
    
    // Port A (Write)
    input wire [ADDR_WIDTH-1:0] addra,
    input wire [DATA_WIDTH-1:0] dina,
    input wire ena,
    input wire wea,
    
    // Port B (Read)
    output wire [DATA_WIDTH-1:0] doutb,
    input wire [ADDR_WIDTH-1:0] addrb,
    input wire enb
);

    reg bypass_r;
    reg [DATA_WIDTH-1:0] bypass_dat_r;
    wire [DATA_WIDTH-1:0] doutb_w;

    wire bypass_nxt = enb & wea & (addra==addrb);
    
    // Bypass to avoid write-read collision
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            bypass_r <= 1'b0;
        else if (enb) begin
            bypass_r <= bypass_nxt;
            bypass_dat_r <= dina;
        end
    end
    assign doutb = bypass_r ? bypass_dat_r : doutb_w;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_WIDTH),               // DECIMAL
        .ADDR_WIDTH_B(ADDR_WIDTH),               // DECIMAL
        .AUTO_SLEEP_TIME(0),            // DECIMAL
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH),        // DECIMAL
        .CASCADE_HEIGHT(0),             // DECIMAL
        .CLOCKING_MODE("common_clock"), // String
        .ECC_MODE("no_ecc"),            // String
        .MEMORY_INIT_FILE("none"),      // String
        .MEMORY_INIT_PARAM("0"),        // String
        .MEMORY_OPTIMIZATION("true"),   // String
        .MEMORY_PRIMITIVE("auto"),      // String
        .MEMORY_SIZE(DATA_WIDTH*(1<<ADDR_WIDTH)), // DECIMAL
        .MESSAGE_CONTROL(0),            // DECIMAL
        .READ_DATA_WIDTH_B(DATA_WIDTH),  // DECIMAL
        .READ_LATENCY_B(1),             // DECIMAL
        .READ_RESET_VALUE_B("0"),       // String
        .RST_MODE_A("SYNC"),            // String
        .RST_MODE_B("SYNC"),            // String
        .SIM_ASSERT_CHK(1),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
        .USE_MEM_INIT(0),               // DECIMAL
        .WAKEUP_TIME("disable_sleep"),  // String
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),  // DECIMAL
        .WRITE_MODE_B("read_first")      // String
    )
    memory (
        .clka(clk),
        .addra(addra),
        .dina(dina),
        .ena(ena),
        .wea(wea),
        .clkb(clk),
        .doutb(doutb_w),
        .addrb(addrb),
        .enb(enb & ~bypass_nxt),
        .rstb(~rst_n),

        // DoNotCare
        .dbiterrb(),
        .sbiterrb(),
        .injectdbiterra(1'b0),
        .injectsbiterra(1'b0),
        .regceb(1'b1),
        .sleep(1'b0)
    );
    
endmodule