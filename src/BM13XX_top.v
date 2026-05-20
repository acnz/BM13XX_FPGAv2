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

	//// Main data 
	reg [255:0] state = 0;
	reg [511:0] data = 0;
	reg [31:0] nonce = 32'h00000000;
    //// Hashers
	wire [255:0] hash, hash2;
	reg [5:0] cnt = 6'd0;
	reg feedback = 1'b0;

	sha256_transform #(.LOOP(LOOP)) uut (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input(data),
		.tx_hash(hash)
	);
	sha256_transform #(.LOOP(LOOP)) uut2 (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash}),
		.tx_hash(hash2)
	);

    reg [255:0] midstate_buf = 0, data_buf = 0;
    reg [31:0] golden_nonce = 0;
	//// Control Unit
	reg is_golden_ticket = 1'b0;
	reg feedback_d1 = 1'b1;
	wire [5:0] cnt_next;
	wire [31:0] nonce_next;
	wire feedback_next;
	`ifndef SIM
		wire reset;
		assign reset = 1'b0;
	`else
		reg reset = 1'b0;	// NOTE: Reset is not currently used in the actual FPGA; for simulation only.
	`endif

	assign cnt_next =  reset ? 6'd0 : (LOOP == 1) ? 6'd0 : (cnt + 6'd1) & (LOOP-1);
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (LOOP == 1) ? 1'b0 : (cnt_next != {(LOOP_LOG2){1'b0}});
	assign nonce_next =
		reset ? 32'd0 :
		feedback_next ? nonce : (nonce + 32'd1);

	always @ (posedge hash_clk)
	begin
		midstate_buf <= tx_midstate;
		data_buf <= tx_data;

		cnt <= cnt_next;
		feedback <= feedback_next;
		feedback_d1 <= feedback;

		// Give new data to the hasher
		state <= midstate_buf;
		data <= {384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, nonce_next, data_buf[95:0]};
		nonce <= nonce_next;
        //rx_new_nonce <= nonce_next; // a uart decide se chegou no limite de nonces?


		// Check to see if the last hash generated is valid.
		is_golden_ticket <= (hash2[255:224] == 32'h00000000) && !feedback_d1;
		if(is_golden_ticket)
		begin
			// TODO: Find a more compact calculation for this
			if (LOOP == 1)
				golden_nonce <= nonce - 32'd131;
			else if (LOOP == 2)
				golden_nonce <= nonce - 32'd66;
			else
				golden_nonce <= nonce - GOLDEN_NONCE_OFFSET;
            rx_golden_nonce <= golden_nonce; // aqui ele adiciona o golden_nonce no tx_fifo
		end
	end


endmodule