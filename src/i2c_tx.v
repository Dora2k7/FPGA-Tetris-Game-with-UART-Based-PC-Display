module i2c_tx (
    input clk,
    input tick,
    input start,
    input write,
    input stop,
    input [7:0] data_in,
    output reg ready = 1,
    output reg scl = 1,
    inout sda
);

    reg [3:0] state = 0;
    reg [2:0] bit_cnt = 0;
    reg [7:0] shift_reg = 0;
    reg sda_out = 1, sda_oe = 1;

    assign sda = sda_oe ? (sda_out ? 1'bz : 1'b0) : 1'bz; 

    always @(posedge clk) begin
        if (tick) begin
            if (ready) begin
                if (start) begin
                    ready <= 0;
                    shift_reg <= data_in;
                    sda_out <= 1; sda_oe <= 1; scl <= 1; 
                    state <= 1; 
                    bit_cnt <= 7;
                end else if (write) begin
                    ready <= 0;
                    shift_reg <= data_in;
                    state <= 3; 
                    bit_cnt <= 7;
                end else if (stop) begin
                    ready <= 0;
                    state <= 12; 
                end
            end else begin
                case (state)
                    1: begin sda_out <= 0; sda_oe <= 1; state <= 2; end 
                    2: begin scl <= 0; state <= 3; end

                    3: begin sda_out <= shift_reg[bit_cnt]; sda_oe <= 1; state <= 4; end 
                    4: begin scl <= 1; state <= 5; end 
                    5: begin scl <= 1; state <= 6; end 
                    6: begin 
                        scl <= 0; 
                        if (bit_cnt == 0) state <= 7; 
                        else begin bit_cnt <= bit_cnt - 1'b1; state <= 3; end 
                    end
                    
                    7: begin sda_oe <= 0; state <= 8; end 
                    8: begin scl <= 1; state <= 9; end
                    9: begin scl <= 1; state <= 10; end 
                    10: begin scl <= 0; state <= 11; end
                    11: begin ready <= 1; state <= 0; end 

                    12: begin sda_out <= 0; sda_oe <= 1; state <= 13; end
                    13: begin scl <= 1; state <= 14; end
                    14: begin sda_out <= 1; state <= 15; end 
                    15: begin ready <= 1; state <= 0; end
                endcase
            end
        end
    end
endmodule
