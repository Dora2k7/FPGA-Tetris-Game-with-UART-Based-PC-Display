// -----------------------------------------------------------------------------
// MODULE PURPOSE:
// Frame packager using an optimized 4-state 3-block FSM.
// This module is designed to receive the 1600-bit(200 bytes) flat game grid continuously
// attach 2 sync headers (0xAA, 0x55)+ 200 bytes of data + an XOR checksum byte, and push all 203 bytes via UART to the peripheral device.
// send 203 bytes to uart_tx module sequentially, 1 byte(8bits) per time, and uart_tx will convert it to serial data and send it to periheral device through uart pin. 
// besides that, this module also recieve uart_busy signal from uart_tx module to know when uart_tx is busy and when it is ready to send next byte.
// -----------------------------------------------------------------------------
module frame_sender (
    input  wire clk,
    input  wire [1599:0] grid,
    input  wire      uart_busy,
    output reg [7:0] uart_data = 0,        // 8-bit data to send to uart_tx module
    output reg       uart_valid = 0        // pulse high 1 clk to send data to uart_tx module
);

    // Frame timer: 30 FPS @ 50MHz
    // FRAME_TICK change to high for 1 clk every 1_650_000 clk cycles, which is 30 FPS
    localparam NUM_PERIODS_OF_FRAME = 1_650_000;
    reg [20:0] frame_cnt  = 0;
    reg        frame_tick = 0;

    always @(posedge clk) begin
        if (frame_cnt == NUM_PERIODS_OF_FRAME - 21'd1) begin
            frame_cnt  <= 0;
            frame_tick <= 1'b1;
        end else begin
            frame_cnt  <= frame_cnt + 21'd1;
            frame_tick <= 1'b0;
        end
    end

    // ── 3-Block FSM for Frame Sending (Optimized 3 States) ──────
    localparam S_IDLE = 2'd0,
               S_SEND = 2'd1,
               S_WAIT = 2'd2;

    reg [1:0] current_state = S_IDLE;
    reg [1:0] next_state;

    reg [7:0]  tx_step  = 0;
    reg [10:0] grid_ptr = 0;
    reg [7:0]  chk      = 0;

    wire [7:0] grid_byte = grid[grid_ptr +: 8];

    // Block 1: State Register
    always @(posedge clk) begin
        current_state <= next_state;
    end

    // Block 2: Next State Logic
    always @(*) begin
        next_state = current_state;
        case (current_state)
            S_IDLE: begin
                if (frame_tick) next_state = S_SEND;
            end
            S_SEND: begin
                if (uart_busy) next_state = S_WAIT;
            end
            S_WAIT: begin
                if (!uart_busy) begin
                    if (tx_step == 8'd202) next_state = S_IDLE;
                    else next_state = S_SEND;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end

    // Block 3: Output Logic
    always @(posedge clk) begin
        uart_valid <= 1'b0;
        case (current_state)
            S_IDLE: begin
                if (frame_tick) begin
                    tx_step  <= 8'd0;
                    grid_ptr <= 11'd0;
                    chk      <= 8'd0;
                end
            end
            S_SEND: begin
                uart_valid <= 1'b1;
                if (tx_step == 8'd0)        uart_data <= 8'hAA;
                else if (tx_step == 8'd1)   uart_data <= 8'h55;
                else if (tx_step == 8'd202) uart_data <= chk;
                else                        uart_data <= grid_byte;
            end
            S_WAIT: begin
                if (!uart_busy) begin
                    if (tx_step >= 2 && tx_step <= 201) begin
                        chk      <= chk ^ uart_data;
                        grid_ptr <= grid_ptr + 11'd8;
                    end
                    tx_step <= tx_step + 8'd1;
                end
            end
        endcase
    end
endmodule
