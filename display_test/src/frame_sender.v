// frame_sender.v - Đóng gói và truyền frame game qua UART
// Protocol: [0xAA][0x55][200 bytes grid][1 byte XOR checksum]
// Grid order: col0_row0, col0_row1, ..., col9_row19 (column-major)

module frame_sender (
    input  clk,
    input  [7:0] grid [0:9][0:19],

    // UART interface
    output reg [7:0] uart_data,
    output reg       uart_valid,
    input            uart_busy
);
    localparam COLS = 10;
    localparam ROWS = 20;

    // State machine
    localparam S_SYNC1    = 0;
    localparam S_SYNC2    = 1;
    localparam S_DATA     = 2;
    localparam S_CHECKSUM = 3;
    localparam S_WAIT     = 4;

    reg [2:0] state = S_SYNC1;
    reg [3:0] col   = 0;
    reg [4:0] row   = 0;
    reg [7:0] chk   = 0;

    // Frame rate throttle: gửi 1 frame mỗi ~33ms (30 FPS)
    // 50MHz * 0.033 = 1,650,000 cycles
    localparam FRAME_PERIOD = 1_650_000;
    reg [20:0] frame_cnt = 0;
    reg frame_ready = 0;

    always @(posedge clk) begin
        if (frame_cnt == FRAME_PERIOD - 1) begin
            frame_cnt   <= 0;
            frame_ready <= 1;
        end else begin
            frame_cnt   <= frame_cnt + 1;
            frame_ready <= 0;
        end
    end

    always @(posedge clk) begin
        uart_valid <= 0;

        case (state)
            S_SYNC1: begin
                if (frame_ready && !uart_busy) begin
                    uart_data  <= 8'hAA;
                    uart_valid <= 1;
                    chk        <= 0;
                    state      <= S_SYNC2;
                end
            end

            S_SYNC2: begin
                if (!uart_busy) begin
                    uart_data  <= 8'h55;
                    uart_valid <= 1;
                    col        <= 0;
                    row        <= 0;
                    state      <= S_DATA;
                end
            end

            S_DATA: begin
                if (!uart_busy) begin
                    uart_data  <= grid[col][row];
                    uart_valid <= 1;
                    chk        <= chk ^ grid[col][row];

                    if (col == COLS - 1 && row == ROWS - 1) begin
                        state <= S_CHECKSUM;
                    end else if (row == ROWS - 1) begin
                        row <= 0;
                        col <= col + 1;
                    end else begin
                        row <= row + 1;
                    end
                end
            end

            S_CHECKSUM: begin
                if (!uart_busy) begin
                    uart_data  <= chk;
                    uart_valid <= 1;
                    state      <= S_WAIT;
                end
            end

            S_WAIT: begin
                if (!uart_busy) state <= S_SYNC1;
            end
        endcase
    end
endmodule
