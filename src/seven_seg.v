// Module seven_seg: điều khiển 8 chữ số LED 7 đoạn qua 2 chip 74HC595 nối tiếp
//
// Sơ đồ kết nối ACG525:
//   SEG7_DIO  (F4)  -> ds    (Data Serial vào IC1)
//   SEG7_SCLK (H4)  -> sh_cp (Shift Clock)
//   SEG7_RCLK (F3)  -> st_cp (Latch/Storage Clock)
//
// Chuỗi 2 chip: DS -> [IC1 SER] -> Q7' -> [IC2 SER]
//   IC1 (gần DIO hơn): nhận 8 bit CUỐI cùng được shift vào  -> điều khiển Digit Select
//   IC2 (xa DIO hơn) : nhận 8 bit ĐẦU TIÊN được shift vào   -> điều khiển Segment Data
//
// Do đó, thứ tự gửi 16 bit: {seg_data, seg_sel} (MSB trước)
//   seg_data (15:8) -> vào trước -> tràn sang IC2 -> điều khiển segments
//   seg_sel  (7:0)  -> vào sau  -> nằm lại IC1   -> điều khiển chọn digit
//
// Digit Select: Active HIGH (qua transistor PNP/NPN bên ngoài)
//   bit=1 -> transistor ON -> anode được cấp điện -> digit sáng
// Segment Data: Active LOW (common anode)
//   bit=0 -> cathode kéo xuống GND -> segment sáng

module seven_seg (
    input  wire clk,
    input  wire [31:0] bcd_in, // BCD 8 chữ số [31:28]=cao nhất, [3:0]=thấp nhất
    output reg  ds,            // SEG7_DIO  - Data Serial
    output reg  st_cp,         // SEG7_RCLK - Latch (Storage Clock)
    output reg  sh_cp          // SEG7_SCLK - Shift Clock
);

    // ─── Tạo tick 500kHz để shift data ───────────────────────
    // 50MHz / 100 = 500kHz (chu kỳ 2us, đủ ổn định)
    reg [6:0] div_cnt = 0;
    wire tick = (div_cnt == 0);
    always @(posedge clk) begin
        if (div_cnt == 99) div_cnt <= 0;
        else               div_cnt <= div_cnt + 1'b1;
    end

    // ─── Xung quét digit: 1ms/digit -> 8 digit = 8ms chu kỳ (~125Hz) ───
    reg [15:0] refresh_cnt = 0;
    reg [2:0]  digit_idx   = 0;
    reg        do_shift     = 0;

    always @(posedge clk) begin
        do_shift <= 0;
        if (refresh_cnt >= 16'd49_999) begin
            refresh_cnt <= 0;
            digit_idx   <= digit_idx + 1'b1;
            do_shift    <= 1;
        end else begin
            refresh_cnt <= refresh_cnt + 1'b1;
        end
    end

    // ─── Lấy giá trị BCD digit hiện tại ─────────────────────
    reg [3:0] cur_bcd;
    always @(*) begin
        case (digit_idx)
            3'd0: cur_bcd = bcd_in[3:0];    // Hàng đơn vị
            3'd1: cur_bcd = bcd_in[7:4];    // Hàng chục
            3'd2: cur_bcd = bcd_in[11:8];   // Hàng trăm
            3'd3: cur_bcd = bcd_in[15:12];  // Hàng nghìn
            3'd4: cur_bcd = bcd_in[19:16];
            3'd5: cur_bcd = bcd_in[23:20];
            3'd6: cur_bcd = bcd_in[27:24];
            3'd7: cur_bcd = bcd_in[31:28];  // Hàng chục triệu
            default: cur_bcd = 4'hF;
        endcase
    end

    // ─── Giải mã 7 đoạn (Common Anode - Active LOW) ──────────
    // Bit map: [7]=DP [6]=G [5]=F [4]=E [3]=D [2]=C [1]=B [0]=A
    reg [7:0] seg_data;
    always @(*) begin
        case (cur_bcd)
            4'd0: seg_data = 8'b1100_0000; // 0
            4'd1: seg_data = 8'b1111_1001; // 1
            4'd2: seg_data = 8'b1010_0100; // 2
            4'd3: seg_data = 8'b1011_0000; // 3
            4'd4: seg_data = 8'b1001_1001; // 4
            4'd5: seg_data = 8'b1001_0010; // 5
            4'd6: seg_data = 8'b1000_0010; // 6
            4'd7: seg_data = 8'b1111_1000; // 7
            4'd8: seg_data = 8'b1000_0000; // 8
            4'd9: seg_data = 8'b1001_0000; // 9
            default: seg_data = 8'b1111_1111; // Tắt
        endcase
    end

    // ─── Chọn digit (Active HIGH) ────────────────────────────
    // Bit tương ứng = 1 -> transistor ON -> digit đó sáng
    wire [7:0] seg_sel = (8'b0000_0001 << digit_idx);

    // ─── Ghép 16 bit: seg_data vào TRƯỚC, seg_sel vào SAU ────
    // MSB first khi shift: seg_data[7] ra trước -> đi đến IC2
    //                      seg_sel[0] ra cuối   -> nằm ở IC1
    wire [15:0] shift_data = {seg_data, seg_sel};

    // ─── FSM shift 16 bit vào 74HC595 ────────────────────────
    reg [15:0] shift_reg  = 16'hFFFF;
    reg [4:0]  shift_bits = 0;
    reg [2:0]  sr_state   = 0;

    always @(posedge clk) begin
        // Chốt dữ liệu vào shift_reg khi có tín hiệu do_shift
        if (do_shift && sr_state == 0) begin
            shift_reg  <= shift_data; // Snapshot tại đúng thời điểm
            shift_bits <= 5'd16;
            st_cp      <= 0;
            sh_cp      <= 0;
            sr_state   <= 1;
        end else if (tick) begin
            case (sr_state)
                // State 1: Đặt bit data lên đường DS, giữ SCLK=0
                1: begin
                    if (shift_bits > 0) begin
                        ds        <= shift_reg[15]; // MSB first
                        shift_reg <= {shift_reg[14:0], 1'b0};
                        sr_state  <= 2;
                    end else begin
                        sr_state  <= 4; // Xong 16 bit, chuyển sang latch
                    end
                end
                // State 2: SCLK rising edge -> IC595 chốt bit vào shift register
                2: begin
                    sh_cp    <= 1;
                    sr_state <= 3;
                end
                // State 3: SCLK falling edge, đếm bit
                3: begin
                    sh_cp      <= 0;
                    shift_bits <= shift_bits - 1'b1;
                    sr_state   <= 1;
                end
                // State 4: RCLK rising edge -> chuyển shift register ra output latch
                4: begin
                    st_cp    <= 1;
                    sr_state <= 5;
                end
                // State 5: RCLK falling edge, hoàn tất
                5: begin
                    st_cp    <= 0;
                    sr_state <= 0;
                end
                default: sr_state <= 0;
            endcase
        end
    end

endmodule
