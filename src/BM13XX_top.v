`timescale 1ns/1ps

module BM13XX_top (clk_50m);

	input clk_50m;

	//// PLL
	wire hash_clk;
	`ifndef SIM
		Gowin_PLL gowin_plla(
            .clkout0(clk_50m), //output clkout0
            .clkin(hash_clk) //input clkin
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
	reg [255:0] state = 0;
	reg [511:0] data = 0;
	reg [31:0] nonce = 32'h00000000;

endmodule