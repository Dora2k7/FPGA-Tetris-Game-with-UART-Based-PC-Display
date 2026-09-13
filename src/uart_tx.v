// -----------------------------------------------------------------------------
// MODULE PURPOSE:
// Basic asynchronous UART transmitter.
// input : frame_sender module
// output: uart pin
// This module use to send a byte of data over UART at 115200 baud (under 50MHz clock) to peripheral device. It will send 1 start bit, 8 data bits, and 1 stop bit for each byte of data.
// -----------------------------------------------------------------------------
module uart_tx (
    input  wire       clk,     // 50MHz
    input  wire [7:0] data,       // Byte to send
    input  wire       valid,      // Pulse high 1 clk to send
    output reg        busy,       // High while transmitting
    output reg        tx          // UART TX line (idle high)
);
    localparam CLK_PER_BIT = 434; 

    reg [8:0] clk_cnt = 0;
    reg [3:0] bit_idx = 0;
    reg [9:0] shift   = 10'b1111111111;

    initial begin
        tx   = 1'b1;
        busy = 1'b0;
    end
    always @(posedge clk) begin
        // send data when busy bit is low and valid bit is high 
        if (!busy && valid) begin           
            // Load: START(0) + 8 data bits + STOP(1)
            shift   <= {1'b1, data, 1'b0};
            clk_cnt <= 0;
            bit_idx <= 0;
            busy    <= 1'b1;
        end else if (busy) begin
            if (clk_cnt == CLK_PER_BIT - 9'd1) begin
                clk_cnt <= 0;
                tx      <= shift[bit_idx];
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                end
            end else begin
                clk_cnt <= clk_cnt + 9'd1;
            end
        end
    end
endmodule
