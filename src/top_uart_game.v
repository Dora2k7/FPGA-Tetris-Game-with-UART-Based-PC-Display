// -----------------------------------------------------------------------------
// MODULE PURPOSE:
// Top-level module for the UART Tetris Game Engine. It connects the hardware
// push buttons to the game logic, manages the heartbeat LED, and streams the
// 10x20 game grid via UART to the laptop at 30 FPS.
//
// INPUTS:
// - clk: 50MHz system clock
// - key0: Button input for moving Left (Active-Low)
// - key1: Button input for moving Right (Active-Low)
// - key2: Button input for Rotate (Active-Low)
//
// OUTPUTS:
// - uart_tx: UART Transmit pin to stream game frames (115200 baud)
// - led[3:0]: 4 LEDs used as a heartbeat indicator
// -----------------------------------------------------------------------------
// top_uart_game.v - Top module: UART Game Engine Demo
// Giao diện:
//   - 3 nút: KEY0=lên, KEY1=xuống, KEY2=reset (Active-Low)
//   - UART TX: stream frame game 30fps về laptop
//   - LED: heartbeat để xác nhận FPGA đang chạy


module top_uart_game (
    input  clk,      // T9 - 50MHz
    input  key0,     // B16 - Trái
    input  key1,     // A15 - Phải
    input  key2,     // C15 - Xoay / Enter
    output uart_tx,  // V8  - UART TX
    output [3:0] led, // Heartbeat
    
    // I2C OLED
    output wire i2c_sclk,
    inout  wire i2c_sdat,
    
    // Buzzer
    output wire beep,
    
    // 7-Segment (74HC595)
    output wire seg_dio,
    output wire seg_rclk,
    output wire seg_sclk
);
    // Heartbeat LED để xác nhận FPGA đang chạy
    reg [24:0] hb_cnt = 0;
    always @(posedge clk) hb_cnt <= hb_cnt + 25'd1;
    assign led = ~hb_cnt[24:21];

    // Các tín hiệu kết nối
    wire [1599:0] grid; 
    wire [1:0] diff_out;
    wire [31:0] score_out;
    wire beep_pulse, beep_cont;

    // Module game logic chính
    game_logic gl (
        .clk            (clk),
        .key0           (key0),
        .key1           (key1),
        .key2           (key2),
        .grid           (grid),
        .difficulty_out (diff_out),
        .score_out      (score_out),
        .beep_pulse     (beep_pulse),
        .beep_cont      (beep_cont)
    );

    // Module hiển thị OLED
    oled_difficulty oled (
        .clk        (clk),
        .difficulty (diff_out),
        .i2c_sclk   (i2c_sclk),
        .i2c_sdat   (i2c_sdat)
    );

    // Module Còi báo
    buzzer buzz (
        .clk        (clk),
        .beep_pulse (beep_pulse),
        .beep_cont  (beep_cont),
        .buzzer_out (beep)
    );

    // Module hiển thị LED 7 Đoạn (SPI)
    seven_seg sseg (
        .clk        (clk),
        .bcd_in     (score_out),
        .ds         (seg_dio),
        .st_cp      (seg_rclk),
        .sh_cp      (seg_sclk)
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
