// uart_tx.v - UART Transmitter, 115200 baud @ 50MHz
// 50_000_000 / 115200 = ~434 clock cycles per bit

module uart_tx (
    input  clk,        // 50MHz
    input  [7:0] data, // Byte to send
    input  valid,      // Pulse high 1 clk to send
    output reg busy,   // High while transmitting
    output reg tx      // UART TX line (idle high)
);
    localparam CLK_PER_BIT = 434;

    reg [8:0]  clk_cnt  = 0;
    reg [3:0]  bit_idx  = 0;
    reg [9:0]  shift    = 10'b1111111111; // idle

    initial begin
        tx   = 1'b1;
        busy = 1'b0;
    end

    always @(posedge clk) begin
        if (!busy && valid) begin
            // Load: START(0) + 8 data bits + STOP(1)
            shift   <= {1'b1, data, 1'b0};
            clk_cnt <= 0;
            bit_idx <= 0;
            busy    <= 1'b1;
        end else if (busy) begin
            if (clk_cnt == CLK_PER_BIT - 1) begin
                clk_cnt <= 0;
                tx      <= shift[bit_idx];
                if (bit_idx == 9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 1;
                end
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end
endmodule
