module oled_difficulty (
    input wire clk,
    input wire [1:0] difficulty, // 0-3 (4 mức độ)
    output wire i2c_sclk,
    inout wire i2c_sdat
);
    // Delay 1 giây khi khởi động
    reg [25:0] boot_delay_cnt = 0;
    wire boot_done = (boot_delay_cnt >= 50_000_000);
    always @(posedge clk) begin
        if (!boot_done) boot_delay_cnt <= boot_delay_cnt + 1'b1;
    end

    // Tốc độ I2C ~390kHz (50MHz / 128)
    reg [5:0] div_cnt = 0;
    wire tick = (div_cnt == 0);
    always @(posedge clk) div_cnt <= div_cnt + 1'b1;

    // I2C Master Signals
    reg [7:0] i2c_data;
    reg i2c_start = 0, i2c_write = 0, i2c_stop = 0;
    wire i2c_ready;

    i2c_tx tx_inst (
        .clk(clk),
        .tick(tick),
        .start(i2c_start),
        .write(i2c_write),
        .stop(i2c_stop),
        .data_in(i2c_data),
        .ready(i2c_ready),
        .scl(i2c_sclk),
        .sda(i2c_sdat)
    );

    // Lệnh khởi tạo SSD1306/SH1106
    reg [7:0] init_cmd [0:24];
    initial begin
        init_cmd[0] = 8'hAE; // Display OFF
        init_cmd[1] = 8'hD5; // Clock Divide Ratio
        init_cmd[2] = 8'h80;
        init_cmd[3] = 8'hA8; // Multiplex Ratio
        init_cmd[4] = 8'h3F; // 64MUX
        init_cmd[5] = 8'hD3; // Display Offset
        init_cmd[6] = 8'h00;
        init_cmd[7] = 8'h40; // Display Start Line 0
        init_cmd[8] = 8'h8D; // Charge Pump
        init_cmd[9] = 8'h14; // Enable
        init_cmd[10] = 8'h20; // Memory Addressing Mode
        init_cmd[11] = 8'h02; // Page Addressing Mode
        init_cmd[12] = 8'hA1; // Segment Re-map
        init_cmd[13] = 8'hC8; // COM Scan Direction
        init_cmd[14] = 8'hDA; // COM Pins Config
        init_cmd[15] = 8'h12;
        init_cmd[16] = 8'h81; // Contrast Control
        init_cmd[17] = 8'hCF;
        init_cmd[18] = 8'hD9; // Pre-charge
        init_cmd[19] = 8'hF1;
        init_cmd[20] = 8'hDB; // VCOMH Deselect
        init_cmd[21] = 8'h40;
        init_cmd[22] = 8'hA4; // Entire Display ON
        init_cmd[23] = 8'hA6; // Normal Display
        init_cmd[24] = 8'hAF; // Display ON
    end

    reg [7:0] main_state = 0;
    reg [7:0] cmd_idx = 0;
    reg [7:0] pixel_cnt = 0; // 0 -> 127
    reg [2:0] page_cnt = 0;  // 0 -> 7
    reg init_done = 0;

    // Logic vẽ các thanh độ khó (Difficulty Bars)
    wire in_bar1 = (pixel_cnt >= 18 && pixel_cnt <= 34);
    wire in_bar2 = (pixel_cnt >= 44 && pixel_cnt <= 60);
    wire in_bar3 = (pixel_cnt >= 70 && pixel_cnt <= 86);
    wire in_bar4 = (pixel_cnt >= 96 && pixel_cnt <= 112);
    
    // Các thanh sẽ hiển thị trên Page 2 đến 5 (chiều cao 32 pixel giữa màn hình)
    wire in_y = (page_cnt >= 2 && page_cnt <= 5);

    reg draw_bar;
    always @(*) begin
        draw_bar = 0;
        if (in_y) begin
            if (in_bar1) draw_bar = 1;
            if (difficulty >= 1 && in_bar2) draw_bar = 1;
            if (difficulty >= 2 && in_bar3) draw_bar = 1;
            if (difficulty >= 3 && in_bar4) draw_bar = 1;
        end
    end

    // Dữ liệu pixel: Ghi 8'hFF nếu thuộc vùng thanh, ngược lại 8'h00
    wire [7:0] pixel_data = draw_bar ? 8'hFF : 8'h00;

    always @(posedge clk) begin
        if (tick) begin
            i2c_start <= 0;
            i2c_write <= 0;
            i2c_stop <= 0;

            if (boot_done && i2c_ready && !i2c_start && !i2c_write && !i2c_stop) begin
                case (main_state)
                    0: main_state <= init_done ? 5 : 1;
                    
                    // --- Khởi tạo OLED ---
                    1: begin 
                        i2c_data <= 8'h78; // Slave Addr
                        i2c_start <= 1;
                        main_state <= 2;
                    end
                    2: begin 
                        i2c_data <= 8'h00; // Command Register
                        i2c_write <= 1;
                        main_state <= 3;
                    end
                    3: begin 
                        i2c_data <= init_cmd[cmd_idx];
                        i2c_write <= 1;
                        if (cmd_idx == 24) main_state <= 4;
                        else cmd_idx <= cmd_idx + 1'b1;
                    end
                    4: begin 
                        i2c_stop <= 1;
                        init_done <= 1;
                        main_state <= 0;
                    end
                    
                    // --- Render Page Loop ---
                    5: begin // Gửi Slave addr
                        i2c_data <= 8'h78;
                        i2c_start <= 1;
                        main_state <= 6;
                    end
                    6: begin
                        i2c_data <= 8'h00; // Command mode
                        i2c_write <= 1;
                        main_state <= 7;
                    end
                    7: begin
                        i2c_data <= 8'hB0 + page_cnt; // Cài đặt Page hiện tại
                        i2c_write <= 1;
                        main_state <= 8;
                    end
                    8: begin
                        i2c_data <= 8'h00; // Set Lower Column = 0
                        i2c_write <= 1;
                        main_state <= 9;
                    end
                    9: begin
                        i2c_data <= 8'h10; // Set Higher Column = 0
                        i2c_write <= 1;
                        main_state <= 10;
                    end
                    10: begin
                        i2c_stop <= 1;
                        main_state <= 11;
                    end
                    
                    // --- Data Cột ---
                    11: begin 
                        i2c_data <= 8'h78;
                        i2c_start <= 1;
                        main_state <= 12;
                    end
                    12: begin
                        i2c_data <= 8'h40; // Data mode
                        i2c_write <= 1;
                        main_state <= 13;
                        pixel_cnt <= 0;
                    end
                    13: begin 
                        i2c_data <= pixel_data;
                        i2c_write <= 1;
                        if (pixel_cnt == 127) main_state <= 14;
                        else pixel_cnt <= pixel_cnt + 1'b1;
                    end
                    14: begin 
                        i2c_stop <= 1;
                        if (page_cnt == 7) page_cnt <= 0;
                        else page_cnt <= page_cnt + 1'b1;
                        
                        main_state <= 0; // Tiếp tục page tiếp theo
                    end
                endcase
            end
        end
    end
endmodule

