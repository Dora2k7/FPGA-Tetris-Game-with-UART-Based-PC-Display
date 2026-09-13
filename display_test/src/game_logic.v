// game_logic.v - Điều khiển khối vuông trên lưới 10x20
// KEY0 (B16) = Di chuyển lên
// KEY1 (A15) = Di chuyển xuống
// KEY2 (C15) = Reset về vị trí ban đầu
// Active-low buttons (nhấn = 0)

module game_logic (
    input  clk,
    input  key0,       // Active-low: move up
    input  key1,       // Active-low: move down
    input  key2,       // Active-low: reset

    // Grid output: grid[col][row] = color byte
    output reg [7:0] grid [0:9][0:19]
);
    localparam COLS = 10;
    localparam ROWS = 20;

    // Block position (khối 2x2)
    reg [3:0] block_col = 4;  // Bắt đầu ở giữa (cột 4-5)
    reg [4:0] block_row = 9;  // Bắt đầu ở giữa (hàng 9-10)

    // Debounce cho 3 nút
    reg [19:0] db0_cnt = 0, db1_cnt = 0, db2_cnt = 0;
    reg key0_prev = 1, key1_prev = 1, key2_prev = 1;
    wire key0_pressed, key1_pressed, key2_pressed;

    // Debounce ~20ms @ 50MHz = 1,000,000 cycles
    localparam DB_MAX = 1_000_000;

    reg key0_db = 1, key1_db = 1, key2_db = 1;

    always @(posedge clk) begin
        // Debounce KEY0
        if (key0 != key0_db) begin
            if (db0_cnt == DB_MAX - 1) begin
                key0_db <= key0;
                db0_cnt <= 0;
            end else db0_cnt <= db0_cnt + 1;
        end else db0_cnt <= 0;

        // Debounce KEY1
        if (key1 != key1_db) begin
            if (db1_cnt == DB_MAX - 1) begin
                key1_db <= key1;
                db1_cnt <= 0;
            end else db1_cnt <= db1_cnt + 1;
        end else db1_cnt <= 0;

        // Debounce KEY2
        if (key2 != key2_db) begin
            if (db2_cnt == DB_MAX - 1) begin
                key2_db <= key2;
                db2_cnt <= 0;
            end else db2_cnt <= db2_cnt + 1;
        end else db2_cnt <= 0;

        key0_prev <= key0_db;
        key1_prev <= key1_db;
        key2_prev <= key2_db;
    end

    // Edge detection (falling edge = button press)
    assign key0_pressed = (key0_prev == 1 && key0_db == 0);
    assign key1_pressed = (key1_prev == 1 && key1_db == 0);
    assign key2_pressed = (key2_prev == 1 && key2_db == 0);

    // Game logic
    integer c, r;
    always @(posedge clk) begin
        if (key2_pressed) begin
            // Reset: về vị trí giữa
            block_col <= 4;
            block_row <= 9;
        end else if (key0_pressed) begin
            // Move up
            if (block_row > 0) block_row <= block_row - 1;
        end else if (key1_pressed) begin
            // Move down
            if (block_row < ROWS - 2) block_row <= block_row + 1;
        end

        // Xây dựng grid: toàn bộ đen, khối 2x2 màu đỏ (0x01)
        for (c = 0; c < COLS; c = c + 1) begin
            for (r = 0; r < ROWS; r = r + 1) begin
                if ((c == block_col || c == block_col + 1) &&
                    (r == block_row || r == block_row + 1)) begin
                    grid[c][r] <= 8'h01; // Đỏ
                end else begin
                    grid[c][r] <= 8'h00; // Đen
                end
            end
        end
    end
endmodule
