module buzzer (
    input wire clk,
    input wire beep_pulse, // Xung 1 chu kỳ khi nhấn nút
    input wire beep_cont,  // Xung 1 chu kỳ lặp lại khi giữ nút (DAS)
    output wire buzzer_out
);
    // Hẹn giờ thời lượng phát tiếng kêu (ví dụ: 20ms mỗi lần tít)
    // 20ms * 50MHz = 1,000,000 xung nhịp
    reg [19:0] timer = 0;
    
    always @(posedge clk) begin
        if (beep_pulse || beep_cont) begin
            timer <= 20'd1_000_000; 
        end else if (timer > 0) begin
            timer <= timer - 1'b1;
        end
    end

    // Tạo xung PWM tần số âm thanh cho Passive Buzzer
    // Tần số 2kHz -> chu kỳ 500us -> 25000 xung clk (12500 mức cao, 12500 mức thấp)
    reg [14:0] tone_cnt = 0;
    reg tone_out = 0;

    always @(posedge clk) begin
        if (timer > 0) begin
            if (tone_cnt >= 15'd12_500) begin
                tone_cnt <= 0;
                tone_out <= ~tone_out;
            end else begin
                tone_cnt <= tone_cnt + 1'b1;
            end
        end else begin
            tone_cnt <= 0;
            tone_out <= 0;
        end
    end

    assign buzzer_out = tone_out;
endmodule
