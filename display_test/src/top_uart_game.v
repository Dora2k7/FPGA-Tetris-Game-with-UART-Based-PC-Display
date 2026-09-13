// top_uart_game.v - Top module: UART Game Engine Demo
// Giao diện:
//   - 3 nút: KEY0=lên, KEY1=xuống, KEY2=reset (Active-Low)
//   - UART TX: stream frame game 30fps về laptop
//   - LED: heartbeat để xác nhận FPGA đang chạy

module top_uart_game (
    input  clk,      // T9 - 50MHz
    input  key0,     // B16 - Di chuyển lên (Active-Low)
    input  key1,     // A15 - Di chuyển xuống (Active-Low)
    input  key2,     // C15 - Reset (Active-Low)
    output uart_tx,  // V8  - UART TX
    output [3:0] led // D14, C14, B9, A9
);
    // Heartbeat LED để xác nhận FPGA đang chạy
    reg [24:0] hb_cnt = 0;
    always @(posedge clk) hb_cnt <= hb_cnt + 1;
    assign led = ~hb_cnt[24:21];

    // Grid 10 cột x 20 hàng, mỗi ô 1 byte màu
    wire [7:0] grid [0:9][0:19];

    // Module game logic
    game_logic gl (
        .clk  (clk),
        .key0 (key0),
        .key1 (key1),
        .key2 (key2),
        .grid (grid)
    );

    // UART Transmitter
    wire [7:0] uart_data;
    wire       uart_valid;
    wire       uart_busy;

    uart_tx utx (
        .clk   (clk),
        .data  (uart_data),
        .valid (uart_valid),
        .busy  (uart_busy),
        .tx    (uart_tx)
    );

    // Frame sender
    frame_sender fs (
        .clk        (clk),
        .grid       (grid),
        .uart_data  (uart_data),
        .uart_valid (uart_valid),
        .uart_busy  (uart_busy)
    );

endmodule
