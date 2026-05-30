// UART TX Module with FIFO
//
// Wraps the uart_tx module, adding a FIFO to buffer outgoing data.
//
//

module uart_tx_fifo (
	input clk,
	input rx_we,
	input [7:0] rx_data,
	output reg tx_busy = 1'b0,
	output tx_serial
);

	//
	reg [7:0] mem [0:31];
	reg [4:0] w_addr = 5'd0, r_addr = 5'd0;
	reg [4:0] cnt = 5'd0;
	reg we = 1'b0;
	reg [7:0] data = 8'd0;


	//
	wire uart_busy;

	uart_tx uart (
		.clk (clk),
		.rx_we (we),
		.rx_data (data),
		.tx_busy (uart_busy),
		.tx_serial (tx_serial)
	);


	//
	wire read = ~uart_busy & (cnt > 5'd0) & ~we;
	wire write = rx_we & (cnt < 5'd31);
    
    reg [4:0] baud_counter = 5'd0;
    reg baud_clk = 1'b0;
	always @ (posedge clk)
	begin

		if (baud_counter == 5'd26)
		begin
            baud_clk <= 1'b1;
            baud_counter <= 5'd0;

            if (write & ~read)
                cnt <= cnt + 5'd1;
            else if (read & ~write)
                cnt <= cnt - 5'd1;

            data <= mem[r_addr];

            if (read)
            begin
                r_addr <= r_addr + 5'd1;
                we <= 1'b1;
            end
            else
                we <= 1'b0;

            
            if (write)
            begin
                w_addr <= w_addr + 5'd1;
                mem[w_addr] <= rx_data;
            end
        end
        else
        begin
            baud_clk <= 1'b0;
            baud_counter <= baud_counter + 5'd1;
        end
	end

endmodule


