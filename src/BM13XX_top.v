`timescale 1ns/1ps

module BM13XX_top (
	input clk_50m,
    input urx,
    input rst_n,
    output utx,
    output led_done);

	//// PLL
	wire hash_clk;
	`ifndef SIM
		Gowin_PLL gowin_plla(
            .clkout0(hash_clk), //output clkout0
            .clkin(clk_50m) //input clkin
        );
	`else
		assign hash_clk = clk_50m;
	`endif
    
    reg [4:0] baud_counter = 5'd0;
    reg baud_clk = 1'b0;
    always @ (posedge clk_50m)
    begin
		if (baud_counter == 5'd26)
		begin
            baud_clk <= 1'b1;
            baud_counter <= 5'd0;
        end
        else
        begin
            baud_clk <= 1'b0;
            baud_counter <= baud_counter + 5'd1;
        end
    end

    
	// The LOOP_LOG2 parameter determines how unrolled the SHA-256
	// calculations are. For example, a setting of 0 will completely
	// unroll the calculations, resulting in 128 rounds and a large, but
	// fast design.
	//
	// A setting of 1 will result in 64 rounds, with half the size and
	// half the speed. 2 will be 32 rounds, with 1/4th the size and speed.
	// And so on.
	//
	// Valid range: [0, 5]

`ifdef CONFIG_LOOP_LOG2
	parameter LOOP_LOG2 = `CONFIG_LOOP_LOG2;
`else
	parameter LOOP_LOG2 = 0;
`endif

    // No need to adjust these parameters
	localparam [5:0] LOOP = (6'd1 << LOOP_LOG2);
	// The nonce will always be larger at the time we discover a valid
	// hash. This is its offset from the nonce that gave rise to the valid
	// hash (except when LOOP_LOG2 == 0 or 1, where the offset is 131 or
	// 66 respectively).
	localparam [31:0] GOLDEN_NONCE_OFFSET = (32'd1 << (7 - LOOP_LOG2)) + 32'd1;

    //// 
	wire [255:0] state;
	wire [511:0] data;
	wire [31:0] nonce;

    wire tx_new_work;
    wire [255:0] tx_midstate;
    wire [95:0] tx_data;
    wire [31:0] tx_noncemin;
    wire [31:0] tx_noncemax;
    wire rx_need_work;
    wire rx_new_nonce;
    wire [31:0] rx_golden_nonce;

    uart_comm uart_comm (
        // Hashing Clock Domain
        .hash_clk(hash_clk),
        .rx_need_work(rx_need_work),
        .rx_new_nonce(rx_new_nonce),
        .rx_golden_nonce(rx_golden_nonce),
        .tx_new_work(tx_new_work),
        .tx_midstate(tx_midstate),
        .tx_data(tx_data),
        .tx_noncemin(tx_noncemin),
        .tx_noncemax(tx_noncemax),
        // UART Clock Domain
        .comm_clk(baud_clk),
        .rx_serial(urx),
        .tx_serial(utx)
    );


endmodule