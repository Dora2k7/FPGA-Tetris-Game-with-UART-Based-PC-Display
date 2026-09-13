// 7 types of brick, 7 brick colors and black = 8 colors => 4 bits index 

module game_logic (
    input  wire clk,
    input  wire key0, // Nút Trái (Active-Low)
    input  wire key1, // Nút Phải (Active-Low)
    input  wire key2, // Nút Xoay / Enter (Active-Low)
    output reg  [1599:0] grid,
    output wire [1:0] difficulty_out,
    output wire [31:0] score_out,
    output wire beep_pulse,
    output wire beep_cont
);

    // ─── Constants & Parameters ────────────────────────────────
    localparam S_GAME_MENU     = 3'd0;
    localparam S_RENDER_NEW    = 3'd1;
    localparam S_RENDER_CHECK  = 3'd2;
    localparam S_BRICK_FALL    = 3'd3;
    localparam S_BUTTON_HANDLE = 3'd4;
    localparam S_SAVE_MAP      = 3'd5;
    localparam S_CLEAN_ROW     = 3'd6;
    localparam S_GAME_OVER     = 3'd7;

    localparam ACT_LEFT  = 2'd0;
    localparam ACT_RIGHT = 2'd1;
    localparam ACT_ROT   = 2'd2;

    // ─── Registers ─────────────────────────────────────────────
    reg [3:0] board [0:9][0:19];
    reg [2:0] state = S_GAME_MENU;
    reg [1:0] difficulty = 0; // 0: Easy, 1: Medium, 2: Hard, 3: Expert
    reg [1:0] btn_action = 0;
    reg [31:0] score = 32'h0000_0000; // BCD score

    assign difficulty_out = difficulty;
    assign score_out = score;

    // Brick State
    reg signed [5:0] Px [0:3];
    reg signed [5:0] Py [0:3];
    reg signed [5:0] anchor_x;
    reg signed [5:0] anchor_y;
    reg [2:0] brick_type;
    reg [2:0] prev_brick_type; // ← Lưu khối trước để tránh trùng
    reg [1:0] brick_rot;
    reg [3:0] brick_color;

    // Khối preview ở game menu
    reg [2:0] menu_brick_type;
    reg [3:0] menu_brick_color;

    reg signed [5:0] scan_row;

    // ─── 1. LFSR (Randomizer) ──────────────────────────────────
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // Lấy giá trị 1-7, tránh trùng với prev_brick_type
    wire [2:0] raw_piece  = (lfsr[2:0] == 3'd7 || lfsr[2:0] == 3'd0) ? 3'd1 : lfsr[2:0];
    wire [2:0] next_piece = (raw_piece == prev_brick_type) ?
                            (raw_piece == 3'd7 ? 3'd1 : raw_piece + 1'b1) : raw_piece;

    // ─── 2. Button Processing (Sync, Debounce, DAS) ────────────
    wire [2:0] key_in = {key2, key1, key0};
    reg  [2:0] key_sync1 = 3'b111;
    reg  [2:0] key_sync2 = 3'b111;
    
    always @(posedge clk) begin
        key_sync1 <= key_in;
        key_sync2 <= key_sync1;
    end

    reg [19:0] db_cnt [0:2];
    reg [2:0]  key_state = 3'b111;
    reg [2:0]  key_prev  = 3'b111;

    integer b;
    always @(posedge clk) begin
        key_prev <= key_state;
        for (b = 0; b < 3; b = b + 1) begin
            if (key_sync2[b] == key_state[b]) begin
                db_cnt[b] <= 0;
            end else begin
                if (db_cnt[b] >= 20'd1_000_000) begin
                    key_state[b] <= key_sync2[b];
                    db_cnt[b] <= 0;
                end else begin
                    db_cnt[b] <= db_cnt[b] + 1'b1;
                end
            end
        end
    end

    wire [2:0] key_down = ~key_state & key_prev; // Pulse 1 cycle

    // DAS (Delayed Auto Shift) cho phím trái (0) và phải (1)
    reg [23:0] das_cnt [0:1];
    reg [1:0]  key_rep = 2'b00;

    always @(posedge clk) begin
        for (b = 0; b < 2; b = b + 1) begin
            if (key_state[b] == 1'b1) begin
                das_cnt[b] <= 0;
                key_rep[b] <= 0;
            end else begin
                if (das_cnt[b] >= 24'd10_000_000) begin
                    das_cnt[b] <= 24'd7_500_000; 
                    key_rep[b] <= 1'b1;
                end else begin
                    das_cnt[b] <= das_cnt[b] + 1'b1;
                    key_rep[b] <= 0;
                end
            end
        end
    end

    wire act_left  = key_down[0] | key_rep[0];
    wire act_right = key_down[1] | key_rep[1];
    wire act_rot   = key_down[2];

    // Nhấn cả trái + phải đồng thời -> Soft Drop (rơi nhanh)
    wire both_pressed = (~key_state[0]) & (~key_state[1]);

    assign beep_pulse = key_down[0] | key_down[1] | key_down[2];
    assign beep_cont  = key_rep[0] | key_rep[1];

    // ─── 3. Brick Shapes LUT ───────────────────────────────────
    function [15:0] get_shape(input [2:0] t, input [1:0] r);
        begin
            case (t)
                1: case (r) // S
                    0, 2: get_shape = 16'b0110_1100_0000_0000;
                    1, 3: get_shape = 16'b0100_0110_0010_0000;
                   endcase
                2: case (r) // Z
                    0, 2: get_shape = 16'b1100_0110_0000_0000;
                    1, 3: get_shape = 16'b0010_0110_0100_0000;
                   endcase
                3: case (r) // T
                    0: get_shape = 16'b0100_1110_0000_0000;
                    1: get_shape = 16'b0100_0110_0100_0000;
                    2: get_shape = 16'b0000_1110_0100_0000;
                    3: get_shape = 16'b0100_1100_0100_0000;
                   endcase
                4: get_shape = 16'b0110_0110_0000_0000; // O
                5: case (r) // I
                    0, 2: get_shape = 16'b0000_1111_0000_0000;
                    1, 3: get_shape = 16'b0100_0100_0100_0100;
                   endcase
                6: case (r) // L
                    0: get_shape = 16'b0010_1110_0000_0000;
                    1: get_shape = 16'b0100_0100_0110_0000;
                    2: get_shape = 16'b0000_1110_1000_0000;
                    3: get_shape = 16'b1100_0100_0100_0000;
                   endcase
                7: case (r) // J
                    0: get_shape = 16'b1000_1110_0000_0000;
                    1: get_shape = 16'b0110_0100_0100_0000;
                    2: get_shape = 16'b0000_1110_0010_0000;
                    3: get_shape = 16'b0100_0100_1100_0000;
                   endcase
                default: get_shape = 16'b0;
            endcase
        end
    endfunction

    function [3:0] get_color(input [2:0] t);
        begin
            case (t)
                1: get_color = 4'd2; // Green
                2: get_color = 4'd1; // Red
                3: get_color = 4'd6; // Purple
                4: get_color = 4'd4; // Yellow
                5: get_color = 4'd5; // Cyan
                6: get_color = 4'd7; // Orange
                7: get_color = 4'd3; // Blue
                default: get_color = 4'd0;
            endcase
        end
    endfunction

    // Phân tích hình dạng cho góc xoay hiện tại và tiếp theo
    wire [15:0] shape_cur = get_shape(brick_type, brick_rot);
    wire [15:0] shape_rot = get_shape(brick_type, brick_rot + 2'd1);

    // Hình dạng khối preview ở menu (xoay 0)
    wire [15:0] shape_menu = get_shape(menu_brick_type, 2'd0);

    reg signed [3:0] cur_dx [0:3];
    reg signed [3:0] cur_dy [0:3];
    reg signed [3:0] rot_dx [0:3];
    reg signed [3:0] rot_dy [0:3];
    // Tọa độ tương đối khối menu
    reg signed [3:0] menu_dx [0:3];
    reg signed [3:0] menu_dy [0:3];
    
    integer m, rr, cc, idx1, idx2, idx3;
    always @(*) begin
        for (m = 0; m < 4; m = m + 1) begin 
            cur_dx[m] = 0; cur_dy[m] = 0; 
            rot_dx[m] = 0; rot_dy[m] = 0;
            menu_dx[m] = 0; menu_dy[m] = 0;
        end
        
        idx1 = 0;
        for (rr = 0; rr < 4; rr = rr + 1) begin
            for (cc = 0; cc < 4; cc = cc + 1) begin
                if (shape_cur[(3-rr)*4 + (3-cc)]) begin
                    if (idx1 < 4) begin
                        cur_dx[idx1] = cc;
                        cur_dy[idx1] = rr;
                        idx1 = idx1 + 1;
                    end
                end
            end
        end

        idx2 = 0;
        for (rr = 0; rr < 4; rr = rr + 1) begin
            for (cc = 0; cc < 4; cc = cc + 1) begin
                if (shape_rot[(3-rr)*4 + (3-cc)]) begin
                    if (idx2 < 4) begin
                        rot_dx[idx2] = cc;
                        rot_dy[idx2] = rr;
                        idx2 = idx2 + 1;
                    end
                end
            end
        end

        idx3 = 0;
        for (rr = 0; rr < 4; rr = rr + 1) begin
            for (cc = 0; cc < 4; cc = cc + 1) begin
                if (shape_menu[(3-rr)*4 + (3-cc)]) begin
                    if (idx3 < 4) begin
                        menu_dx[idx3] = cc;
                        menu_dy[idx3] = rr;
                        idx3 = idx3 + 1;
                    end
                end
            end
        end
    end

    // ─── 4. Collision Detection ────────────────────────────────
    reg collision_down, collision_left, collision_right;
    reg collision_rotate, collision_spawn;
    integer i;

    always @(*) begin
        collision_down   = 0;
        collision_left   = 0;
        collision_right  = 0;
        collision_rotate = 0;
        collision_spawn  = 0;

        for (i = 0; i < 4; i = i + 1) begin
            // Down
            if (Py[i] + 1 >= 20) collision_down = 1;
            else if (Px[i] >= 0 && Px[i] < 10) begin
                if (board[Px[i][3:0]][Py[i][4:0] + 1] != 0) collision_down = 1;
            end

            // Left
            if (Px[i] - 1 < 0) collision_left = 1;
            else if (Py[i] >= 0 && Py[i] < 20) begin
                if (board[Px[i][3:0] - 1][Py[i][4:0]] != 0) collision_left = 1;
            end

            // Right
            if (Px[i] + 1 >= 10) collision_right = 1;
            else if (Py[i] >= 0 && Py[i] < 20) begin
                if (board[Px[i][3:0] + 1][Py[i][4:0]] != 0) collision_right = 1;
            end

            // Rotate
            begin : rot_check
                reg signed [5:0] rx;
                reg signed [5:0] ry;
                rx = anchor_x + rot_dx[i];
                ry = anchor_y + rot_dy[i];
                if (rx < 0 || rx >= 10 || ry < 0 || ry >= 20) collision_rotate = 1;
                else if (board[rx][ry] != 0) collision_rotate = 1;
            end

            // Spawn
            begin : spawn_check
                reg signed [5:0] sx;
                reg signed [5:0] sy;
                sx = anchor_x + cur_dx[i];
                sy = anchor_y + cur_dy[i];
                if (sx < 0 || sx >= 10 || sy < 0 || sy >= 20) collision_spawn = 1;
                else if (board[sx][sy] != 0) collision_spawn = 1;
            end
        end
    end

    // Kiểm tra hàng đầy
    reg row_full;
    integer chk_c;
    always @(*) begin
        row_full = 1;
        for (chk_c = 0; chk_c < 10; chk_c = chk_c + 1) begin
            if (scan_row >= 0 && scan_row < 20) begin
                if (board[chk_c][scan_row] == 0) row_full = 0;
            end else begin
                row_full = 0;
            end
        end
    end

    // ─── 5. Fall Tick Generator ────────────────────────────────
    reg [25:0] fall_tick_cnt = 0;
    reg [25:0] fall_tick_limit;

    always @(*) begin
        // Nếu đang nhấn cả 2 nút trái+phải -> Soft Drop (0.05s/bước)
        if (both_pressed) begin
            fall_tick_limit = 26'd2_500_000; // 0.05s
        end else begin
            case (difficulty)
                2'd0: fall_tick_limit = 26'd37_500_000; // 0.75s
                2'd1: fall_tick_limit = 26'd25_000_000; // 0.5s
                2'd2: fall_tick_limit = 26'd12_500_000; // 0.25s
                2'd3: fall_tick_limit = 26'd6_250_000;  // 0.125s (Expert)
                default: fall_tick_limit = 26'd25_000_000;
            endcase
        end
    end
    
    wire fall_tick = (fall_tick_cnt >= fall_tick_limit);

    // ─── 6. Main FSM ───────────────────────────────────────────
    integer j_c, j_r;
    always @(posedge clk) begin
        case (state)
            S_GAME_MENU: begin
                // Thay khối preview bất kỳ mỗi khi nhấn nút
                if (key_down[0] || key_down[1] || key_down[2]) begin
                    menu_brick_type  <= next_piece;
                    menu_brick_color <= get_color(next_piece);
                end

                if (act_left) begin
                    if (difficulty > 0) difficulty <= difficulty - 1'b1;
                end else if (act_right) begin
                    if (difficulty < 3) difficulty <= difficulty + 1'b1;
                end else if (act_rot) begin
                    score <= 32'h0000_0000;
                    prev_brick_type <= 3'd0; // Reset prev
                    // Khởi tạo/xóa bàn cờ
                    for (j_c = 0; j_c < 10; j_c = j_c + 1) begin
                        for (j_r = 0; j_r < 20; j_r = j_r + 1) begin
                            board[j_c][j_r] <= 4'd0;
                        end
                    end
                    state <= S_RENDER_NEW;
                end
            end

            S_RENDER_NEW: begin
                prev_brick_type <= next_piece; // Lưu lại để tránh lặp
                brick_type  <= next_piece;
                brick_color <= get_color(next_piece);
                brick_rot   <= 0;
                anchor_x    <= 3; 
                anchor_y    <= 0; 
                fall_tick_cnt <= 0;
                state <= S_RENDER_CHECK;
            end

            S_RENDER_CHECK: begin
                for (j_c = 0; j_c < 4; j_c = j_c + 1) begin
                    Px[j_c] <= anchor_x + cur_dx[j_c];
                    Py[j_c] <= anchor_y + cur_dy[j_c];
                end
                
                if (collision_spawn) begin
                    state <= S_GAME_OVER;
                end else begin
                    state <= S_BRICK_FALL;
                end
            end

            S_BRICK_FALL: begin
                if (act_left && !both_pressed) begin
                    btn_action <= ACT_LEFT;
                    state <= S_BUTTON_HANDLE;
                end else if (act_right && !both_pressed) begin
                    btn_action <= ACT_RIGHT;
                    state <= S_BUTTON_HANDLE;
                end else if (act_rot) begin
                    btn_action <= ACT_ROT;
                    state <= S_BUTTON_HANDLE;
                end else if (fall_tick) begin
                    fall_tick_cnt <= 0;
                    if (collision_down) begin
                        state <= S_SAVE_MAP;
                    end else begin
                        for (j_c = 0; j_c < 4; j_c = j_c + 1) Py[j_c] <= Py[j_c] + 1'b1;
                        anchor_y <= anchor_y + 1'b1;
                    end
                end else begin
                    fall_tick_cnt <= fall_tick_cnt + 1'b1;
                end
            end

            S_BUTTON_HANDLE: begin
                if (btn_action == ACT_LEFT) begin
                    if (!collision_left) begin
                        for (j_c = 0; j_c < 4; j_c = j_c + 1) Px[j_c] <= Px[j_c] - 1'b1;
                        anchor_x <= anchor_x - 1'b1;
                    end
                end else if (btn_action == ACT_RIGHT) begin
                    if (!collision_right) begin
                        for (j_c = 0; j_c < 4; j_c = j_c + 1) Px[j_c] <= Px[j_c] + 1'b1;
                        anchor_x <= anchor_x + 1'b1;
                    end
                end else if (btn_action == ACT_ROT) begin
                    if (!collision_rotate) begin
                        for (j_c = 0; j_c < 4; j_c = j_c + 1) begin
                            Px[j_c] <= anchor_x + rot_dx[j_c];
                            Py[j_c] <= anchor_y + rot_dy[j_c];
                        end
                        brick_rot <= brick_rot + 1'b1;
                    end
                end
                state <= S_BRICK_FALL;
            end

            S_SAVE_MAP: begin
                for (j_c = 0; j_c < 4; j_c = j_c + 1) begin
                    if (Px[j_c] >= 0 && Px[j_c] < 10 && Py[j_c] >= 0 && Py[j_c] < 20) begin
                        board[Px[j_c][3:0]][Py[j_c][4:0]] <= brick_color;
                    end
                end
                scan_row <= 19;
                fall_tick_cnt <= 0;
                state <= S_CLEAN_ROW;
            end

            S_CLEAN_ROW: begin
                if (scan_row >= 0 && scan_row < 20) begin
                    if (row_full) begin
                        // Tăng điểm BCD (8 chữ số)
                        if (score[3:0] == 4'd9) begin
                            score[3:0] <= 4'd0;
                            if (score[7:4] == 4'd9) begin
                                score[7:4] <= 4'd0;
                                if (score[11:8] == 4'd9) begin
                                    score[11:8] <= 4'd0;
                                    if (score[15:12] == 4'd9) begin
                                        score[15:12] <= 4'd0;
                                        if (score[19:16] == 4'd9) begin
                                            score[19:16] <= 4'd0;
                                            if (score[23:20] == 4'd9) begin
                                                score[23:20] <= 4'd0;
                                                if (score[27:24] == 4'd9) begin
                                                    score[27:24] <= 4'd0;
                                                    score[31:28] <= score[31:28] + 1'b1;
                                                end else score[27:24] <= score[27:24] + 1'b1;
                                            end else score[23:20] <= score[23:20] + 1'b1;
                                        end else score[19:16] <= score[19:16] + 1'b1;
                                    end else score[15:12] <= score[15:12] + 1'b1;
                                end else score[11:8] <= score[11:8] + 1'b1;
                            end else score[7:4] <= score[7:4] + 1'b1;
                        end else score[3:0] <= score[3:0] + 1'b1;
                        
                        // Dịch các hàng phía trên xuống
                        for (j_r = 19; j_r > 0; j_r = j_r - 1) begin
                            if (j_r <= scan_row) begin
                                for (j_c = 0; j_c < 10; j_c = j_c + 1) begin
                                    board[j_c][j_r] <= board[j_c][j_r - 1];
                                end
                            end
                        end
                        // Xóa hàng trên cùng
                        for (j_c = 0; j_c < 10; j_c = j_c + 1) board[j_c][0] <= 0;
                    end else begin
                        if (scan_row == 0) state <= S_RENDER_NEW;
                        else scan_row <= scan_row - 1'b1;
                    end
                end else begin
                    state <= S_RENDER_NEW;
                end
            end

            S_GAME_OVER: begin
                if (act_rot) begin
                    for (j_c = 0; j_c < 10; j_c = j_c + 1) begin
                        for (j_r = 0; j_r < 20; j_r = j_r + 1) begin
                            board[j_c][j_r] <= 4'd0;
                        end
                    end
                    state <= S_GAME_MENU;
                end
            end
            
            default: state <= S_GAME_MENU;
        endcase
    end

    // ─── 7. Output Mapping (Combinational) ─────────────────────
    // Tọa độ anchor giữa màn hình cho brick preview menu (col 3, row 8)
    localparam MENU_AX = 3;
    localparam MENU_AY = 8;

    integer gc, gr, gi;
    reg is_brick, is_menu_brick;
    always @(*) begin
        for (gc = 0; gc < 10; gc = gc + 1) begin
            for (gr = 0; gr < 20; gr = gr + 1) begin
                is_brick = 0;
                is_menu_brick = 0;
                
                // Hiển thị khối đang rơi khi đang trong quá trình điều khiển
                if (state >= S_RENDER_CHECK && state <= S_SAVE_MAP) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        if (Px[gi] == gc && Py[gi] == gr) is_brick = 1;
                    end
                end

                // Hiển thị brick preview ở game menu
                if (state == S_GAME_MENU) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        if ((MENU_AX + menu_dx[gi]) == gc && (MENU_AY + menu_dy[gi]) == gr)
                            is_menu_brick = 1;
                    end
                end
                
                if (is_brick) begin
                    grid[(gc*20 + gr)*8 +: 8] = {4'b0000, brick_color};
                end else if (is_menu_brick) begin
                    grid[(gc*20 + gr)*8 +: 8] = {4'b0000, menu_brick_color};
                end else begin
                    if (state == S_GAME_MENU) begin
                        // Màn hình menu: nền đen hoàn toàn (chỉ hiện brick preview)
                        grid[(gc*20 + gr)*8 +: 8] = 8'd0;
                    end else begin
                        // Hiển thị các khối đã đáp đất
                        grid[(gc*20 + gr)*8 +: 8] = {4'b0000, board[gc][gr]};
                    end
                end
            end
        end
    end

endmodule
