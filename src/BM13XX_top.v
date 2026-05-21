`timescale 1ns/1ps

module BM13XX_top (
	input clk_50m,
    input urx,
    input rst_n,
    output utx,
    output led_done);

	//// PLL
	wire hash_clk;
    Gowin_PLL gowin_plla(
        .clkout0(hash_clk), //output clkout0
        .clkin(clk_50m) //input clkin
    );

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

//    reg [20:0] led_counter = 21'd0;
//    reg led_state = 1'b0;
//    assign led_done = led_state; 
//    always @ (posedge baud_clk)
//    begin
//		if (led_counter == 21'd1851852/5)
//		begin
//            led_state <= ~led_state;
//            led_counter <= 21'd0;
//        end
//        else
//        begin
//            led_counter <= led_counter + 21'd1;
//        end
//    end

    
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

	parameter LOOP_LOG2 = 4;

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
    reg rx_need_work;
    reg rx_new_nonce;
    reg [31:0] rx_golden_nonce;

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
    wire [31:0] ncores = 32'd1;
    wire [31:0] core_id = 32'd0;


	assign cnt_next =  tx_new_work ? 6'd0 : (LOOP == 1) ? 6'd0 : (cnt + 6'd1) & (LOOP-1);
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (LOOP == 1) ? 1'b0 : (cnt_next != {(LOOP_LOG2){1'b0}});
	assign nonce_next =
		tx_new_work ? tx_noncemin + core_id :
		feedback_next ? nonce : (nonce + 32'd1 * ncores );

    reg led_state = 1'b0;
    assign led_done = led_state; 

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
        if (tx_new_work) begin
            // PRIORIDADE 1: O Chefe (UART) mandou trabalho novo!
            nonce <= nonce_next;  // A sua matemática já garante que aqui é tx_noncemin + core_id
            rx_need_work <= 1'b0; // Abaixa a bandeira de pedir trabalho
        end else if(nonce >= tx_noncemax) begin
            nonce <= nonce;
            rx_need_work <= 1'b1;
        end else begin
            // PRIORIDADE 3: Minerando normalmente...
            nonce <= nonce_next;  // Vai somar +ncores graças ao seu assign lá em cima!
            rx_need_work <= 1'b0;
        end

		// Check to see if the last hash generated is valid.
		is_golden_ticket <= (hash2[255:224] == 32'h00000000) && !feedback_d1;
		if(is_golden_ticket)
		begin
			// TODO: Find a more compact calculation for this
            led_state = 1'b1;
			if (LOOP == 1)
				rx_golden_nonce <= nonce - 32'd131;
			else if (LOOP == 2)
				rx_golden_nonce <= nonce - 32'd66;
			else
				rx_golden_nonce <= nonce - GOLDEN_NONCE_OFFSET;
            rx_new_nonce <= 1'b1; // Dispara o gatilho!
		end else begin
            rx_new_nonce <= 1'b0; // Fica quieto nos outros 99.99% do tempo
        end
	end


endmodule