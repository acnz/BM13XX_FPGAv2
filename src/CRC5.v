module crc5 (
    input wire clk,
    input wire reset,
    input wire rx_we,
    input wire [7:0] rx_byte,
    output wire [4:0] tx_crc
);

    reg [4:0] lfsr;
    reg [4:0] next_lfsr;
    integer i;

    assign tx_crc = lfsr;

    // Cálculo combinacional do próximo CRC5 (Bit mais significativo primeiro)
    always @(*) begin
        next_lfsr = lfsr;
        for (i = 7; i >= 0; i = i - 1) begin
            if (next_lfsr[4] ^ rx_byte[i]) begin
                // Desloca 1 bit e faz XOR com o polinômio 0x05 (00101)
                next_lfsr = (next_lfsr << 1) ^ 5'b00101;
            end else begin
                next_lfsr = (next_lfsr << 1);
            end
        end
    end

    // Atualização síncrona do registrador
    always @(posedge clk) begin
        if (reset) begin
            lfsr <= 5'h1F; // Valor inicial do protocolo BM13xx
        end else if (rx_we) begin
            lfsr <= next_lfsr;
        end
    end

endmodule