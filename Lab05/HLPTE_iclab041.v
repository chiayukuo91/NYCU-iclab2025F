module HLPTE(
    // input signals
    clk,
    rst_n,
    in_valid_data,
    in_valid_param,

    data,
	index,
	mode,
    QP,
	
    // output signals
    out_valid,
    out_value
);

input                     clk;
input                     rst_n;
input                     in_valid_data;
input                     in_valid_param;
input              [7:0]  data;
input              [3:0]  index;
input                     mode;
input              [4:0]  QP;
output reg                out_valid;
output reg signed [31:0]  out_value;

localparam IDLE       = 3'd0;
localparam READ_DATA  = 3'd1;
localparam READ_PARAM = 3'd2;
localparam SAD        = 3'd3;
localparam CAL        = 3'd4;
localparam DC         = 3'd5;

reg [1:0] cnt_grid_top;
reg [2:0] cnt_param, cnt_dc;
reg [3:0] cnt_grid, cnt_ok;
reg [6:0] cnt_sad, cnt_cal;
reg  signed [31:0] dc_num, sad_dc_num, sad_verti_num, sad_hori_num;
reg  signed [31:0] sad_dc [3:0], sad_verti [3:0], sad_hori [3:0];
wire signed [31:0] sad_dc_s1 [3:0], sad_verti_s1 [3:0], sad_hori_s1 [3:0];
wire signed [31:0] sad_dc_s2 [1:0], sad_verti_s2 [1:0], sad_hori_s2 [1:0];
wire signed [31:0] sad_dc_s3, sad_verti_s3, sad_hori_s3;
reg  signed [31:0] ref_topl[15:0], ref_topr[15:0], ref_left[15:0]; 
reg [2:0]  sumress_x, sumress_x_next;
reg [4:0]  sumress_y, sumress_y_next;
reg [3:0]  index_read, index_reg, mode_reg;
reg [4:0]  QP_reg;
reg [1:0]  input_data_cnt;
integer i, j;

reg enter_in_valid_param;
reg [2:0] state_d1, state_next;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enter_in_valid_param <= 1'd0;
    end else begin
        case (1'b1)
            (state_d1 == READ_PARAM && in_valid_param): enter_in_valid_param <= 1'd1;
            (state_d1 != READ_PARAM):                   enter_in_valid_param <= 1'd0;
            default:                                    enter_in_valid_param <= enter_in_valid_param;
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_d1 <= IDLE; 
    end else begin
        state_d1 <= state_next;
    end
end

always @(*) begin 
    case (state_d1)
        IDLE: begin
            case (1'b1)
                (in_valid_data): state_next = READ_DATA;
                default:         state_next = IDLE;
            endcase
        end
        READ_DATA: begin
            case (1'b1)
                (index_read == 15 && sumress_x == 7 && sumress_y == 31 && input_data_cnt == 3): 
                                state_next = READ_PARAM;
                default:        state_next = READ_DATA;
            endcase
        end
        READ_PARAM: begin
            case (1'b1)
                (cnt_param == 3): state_next = CAL;
                default:         state_next = READ_PARAM;
            endcase
        end
        SAD: begin
            case (1'b1)
                (!mode_reg[cnt_grid_top] && (cnt_sad == 71)): state_next = CAL;
                ( mode_reg[cnt_grid_top] && (cnt_sad == 11)): state_next = CAL;
                default:                                     state_next = SAD;
            endcase
        end
        CAL: begin
            case (1'b1)
                (cnt_cal == 23 && cnt_grid == 15 && cnt_grid_top == 3 && cnt_ok == 15):
                    state_next = IDLE;
                (cnt_cal == 23 && cnt_grid == 15 && cnt_grid_top == 3 && cnt_ok != 15):
                    state_next = READ_PARAM;
                (!mode_reg[cnt_grid_top] && cnt_cal == 23 && cnt_grid == 15):
                    state_next = DC;
                ( mode_reg[cnt_grid_top] && cnt_cal == 23):
                    state_next = DC;
                default:
                    state_next = CAL;
            endcase
        end
        DC: begin
            case (1'b1)
                (!mode_reg[cnt_grid_top] && cnt_grid_top == 3 && cnt_dc == 2):
                    state_next = SAD;
                (!mode_reg[cnt_grid_top] && (cnt_grid_top == 2 || cnt_grid_top == 1) && cnt_dc == 1):
                    state_next = SAD;
                (!mode_reg[cnt_grid_top]):
                    state_next = DC;
                default: begin
                    // 4x4 
                    case (1'b1)
                        (cnt_grid_top == 0 && (cnt_grid == 0 || cnt_grid == 1 || cnt_grid == 2 || cnt_grid == 3 || cnt_grid == 4 || cnt_grid == 8 || cnt_grid == 12)):
                            state_next = SAD;
                        (cnt_grid_top == 1 && (cnt_grid == 0 || cnt_grid == 1 || cnt_grid == 2 || cnt_grid == 3)):
                            state_next = SAD;
                        (cnt_grid_top == 2 && (cnt_grid == 0 || cnt_grid == 4 || cnt_grid == 8 || cnt_grid == 12)):
                            state_next = SAD;
                        (cnt_dc == 1):
                            state_next = SAD;
                        default:
                            state_next = DC;
                    endcase
                end
            endcase
        end
        default: begin
            state_next = IDLE;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_grid <= 0;
    end else begin
        if (state_next == READ_PARAM) begin
            cnt_grid <= 0;
        end else if (state_d1 == SAD && !mode_reg[cnt_grid_top] &&
                     cnt_sad[1:0] == 2'd3 && cnt_sad < 11'd64) begin
            cnt_grid <= cnt_grid + 1;
        end else if (state_d1 == CAL && cnt_cal == 11'd23) begin
            case (cnt_grid)
                4'd15:  cnt_grid <= 4'd0;
                default: cnt_grid <= cnt_grid + 1;
            endcase
        end else begin
            cnt_grid <= cnt_grid; // hold
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_grid_top <= 0;
    end else begin
        if (state_next == READ_PARAM) begin
            cnt_grid_top <= 0;
        end else if (state_d1 == CAL && cnt_cal == 11'd23 && cnt_grid == 4'd15 && cnt_grid_top == 2'd3) begin
            cnt_grid_top <= 0;
        end else if (state_d1 == CAL && cnt_cal == 11'd23 && cnt_grid == 4'd15) begin
            cnt_grid_top <= cnt_grid_top + 1;
        end else begin
            cnt_grid_top <= cnt_grid_top; // hold
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_ok <= 0;
    end else begin
        if (state_d1 == CAL && cnt_cal == 11'd23 && cnt_grid == 4'd15 && cnt_grid_top == 2'd3) begin
            cnt_ok <= cnt_ok + 1;
        end else begin
            cnt_ok <= cnt_ok; // hold
        end
    end
end

// input — QP_reg
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        QP_reg <= 5'd0;
    end else begin
        if (state_d1 == READ_PARAM && in_valid_param && !enter_in_valid_param) begin
            QP_reg <= QP;
        end else if (state_d1 != READ_PARAM && state_next == READ_PARAM) begin
            QP_reg <= 5'd0;
        end else begin
            QP_reg <= QP_reg; // hold
        end
    end
end

// input — mode_reg
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mode_reg <= 4'd0;
    end else begin
        if (state_d1 == READ_PARAM && in_valid_param) begin
            mode_reg[3] <= mode; mode_reg[2] <= mode_reg[3];
            mode_reg[1] <= mode_reg[2]; mode_reg[0] <= mode_reg[1];
        end else if (state_d1 != READ_PARAM && state_next == READ_PARAM) begin
            mode_reg <= 4'd0;
        end else begin
            mode_reg <= mode_reg; // hold
        end
    end
end

// input — in_buffer（4-byte shift buffer）
reg [7:0]  in_buffer [3:0];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (j = 0; j < 4; j = j + 1) begin
            in_buffer[j] <= 8'd0;
        end
    end else begin
        case (1'b1)
            in_valid_data: begin
                for (j = 0; j < 3; j = j + 1) begin
                    in_buffer[j] <= in_buffer[j+1];
                end
                in_buffer[3] <= data;
            end
            (state_d1 == CAL && state_next != CAL): begin
                for (j = 0; j < 4; j = j + 1) begin
                    in_buffer[j] <= 8'd0;
                end
            end
            default: begin
            end
        endcase
    end
end

// READ_DATA
reg signed [31:0] sram_din;
reg web, cs;
// input_data_cnt 
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		input_data_cnt <= 0;
	end else begin
		if (state_d1 == READ_DATA && input_data_cnt == 3)
			input_data_cnt <= 0;
		else if (state_d1 == READ_DATA)
			input_data_cnt <= input_data_cnt + 1;
		else if (state_d1 == CAL && state_next != CAL)
			input_data_cnt <= 0;
		else
			input_data_cnt <= input_data_cnt; // hold
	end
end
// cnt_param 
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cnt_param <= 0;
	end else begin
		if (state_d1 == READ_PARAM && (in_valid_param || enter_in_valid_param))
			cnt_param <= cnt_param + 1;
		else
			cnt_param <= 0; 
	end
end
// cnt_sad
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cnt_sad <= 0;
	end else begin
		if (state_d1 == SAD)
			cnt_sad <= cnt_sad + 1;
		else
			cnt_sad <= 0; 
	end
end
// cnt_cal
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cnt_cal <= 0;
	end else begin
		if (state_d1 == CAL && cnt_cal == 23)
			cnt_cal <= 0;
		else if (state_d1 == CAL)
			cnt_cal <= cnt_cal + 1;
		else
			cnt_cal <= 0;
	end
end
// index_read
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		index_read <= 0;
	end else begin
		if (state_d1 == READ_DATA && sumress_x == 7 && sumress_y == 31 && input_data_cnt == 3)
			index_read <= index_read + 1;
		else if (state_d1 == READ_PARAM && in_valid_param && !enter_in_valid_param)
			index_read <= index;
		else if (state_d1 == IDLE)
			index_read <= 0;
		else
			index_read <= index_read; // hold
	end
end

// x_y operate (next-state of sumress_x / sumress_y)
always @(*) begin
	// default hold
	sumress_x_next = sumress_x;
	sumress_y_next = sumress_y;
	case (state_d1)
		READ_DATA: begin
			case (1'b1)
				(input_data_cnt == 3 && sumress_x == 7): begin
					sumress_x_next = 0;
					sumress_y_next = sumress_y + 1;
				end
				(input_data_cnt == 3): begin
					sumress_x_next = sumress_x + 1;
				end
				default: /*hold*/ ;
			endcase
		end

		SAD: begin
			case (1'b1)
				// mode = 0（16x16）
				(!mode_reg[cnt_grid_top]): begin
					case (1'b1)
						(cnt_sad == 11'd71): begin
							case (cnt_grid_top)
								2'd1: begin sumress_x_next = 4; sumress_y_next = 0;  end
								2'd2: begin sumress_x_next = 0; sumress_y_next = 16; end
								2'd3: begin sumress_x_next = 4; sumress_y_next = 16; end
								default: begin sumress_x_next = 0; sumress_y_next = 0; end
							endcase
						end
						(cnt_sad[1:0] == 2'd3 && sumress_x == 3 && sumress_y == 15): begin
							// left grid: 0 -> 1
							sumress_x_next = 4; sumress_y_next = 0;
						end
						(cnt_sad[1:0] == 2'd3 && sumress_x == 3 && sumress_y == 31): begin
							// left grid: 2 -> 3
							sumress_x_next = 4; sumress_y_next = 16;
						end
						(cnt_sad[1:0] == 2'd3 && sumress_x == 3): begin
							// left grid: change row
							sumress_x_next = 0; sumress_y_next = sumress_y + 1;
						end
						(cnt_sad[1:0] == 2'd3 && sumress_x == 7 && sumress_y == 15): begin
							// right grid: 1 -> 2
							sumress_x_next = 0; sumress_y_next = 16;
						end
						(cnt_sad[1:0] == 2'd3 && sumress_x == 7 && sumress_y == 31): begin
							// right grid: end
							sumress_x_next = 0; sumress_y_next = 0;
						end
						(cnt_sad[1:0] == 2'd3 && sumress_x == 7): begin
							// right grid: change row
							sumress_x_next = 4; sumress_y_next = sumress_y + 1;
						end
						(cnt_sad[1:0] == 2'd3): begin
							// x+1, y-3
							sumress_x_next = sumress_x + 1;
							sumress_y_next = sumress_y - 3;
						end

						default: begin
							sumress_y_next = sumress_y + 1;
						end
					endcase
				end

				// mode = 1（4x4）
				(mode_reg[cnt_grid_top]): begin
					case (1'b1)
						(cnt_sad == 11): begin
							sumress_y_next = sumress_y - 3;
						end
						(cnt_sad <= 2): begin
							sumress_y_next = sumress_y + 1;
						end
						default: /*hold*/ ;
					endcase
				end

				default: /*hold*/ ;
			endcase
		end

		CAL: begin
			case (1'b1)
				// mode = 0（16x16）
				(!mode_reg[cnt_grid_top]): begin
					case (1'b1)
						(cnt_cal == 11'd23 && sumress_x == 3 && sumress_y == 15): begin sumress_x_next = 4; sumress_y_next = 0;  end
						(cnt_cal == 11'd23 && sumress_x == 3 && sumress_y == 31): begin sumress_x_next = 4; sumress_y_next = 16; end
						(cnt_cal == 11'd23 && sumress_x == 3):                begin sumress_x_next = 0; sumress_y_next = sumress_y + 1; end
						(cnt_cal == 11'd23 && sumress_x == 7 && sumress_y == 15): begin sumress_x_next = 0; sumress_y_next = 16; end
						(cnt_cal == 11'd23 && sumress_x == 7 && sumress_y == 31): begin sumress_x_next = 0; sumress_y_next = 0;  end
						(cnt_cal == 11'd23 && sumress_x == 7):                begin sumress_x_next = 4; sumress_y_next = sumress_y + 1; end
						(cnt_cal == 11'd23): begin
							sumress_x_next = sumress_x + 1;
							sumress_y_next = sumress_y - 3;
						end

						(cnt_cal <= 11'd2): begin
							sumress_y_next = sumress_y + 1;
						end

						default: /*hold*/ ;
					endcase
				end

				// mode = 1（4x4）
				(mode_reg[cnt_grid_top]): begin
					case (1'b1)
						(cnt_cal == 11'd3 && sumress_x == 3 && sumress_y == 15): begin sumress_x_next = 4; sumress_y_next = 0;  end
						(cnt_cal == 11'd3 && sumress_x == 3 && sumress_y == 31): begin sumress_x_next = 4; sumress_y_next = 16; end
						(cnt_cal == 11'd3 && sumress_x == 3):                begin sumress_x_next = 0; sumress_y_next = sumress_y + 1; end
						(cnt_cal == 11'd3 && sumress_x == 7 && sumress_y == 15): begin sumress_x_next = 0; sumress_y_next = 16; end
						(cnt_cal == 11'd3 && sumress_x == 7 && sumress_y == 31): begin sumress_x_next = 0; sumress_y_next = 0;  end
						(cnt_cal == 11'd3 && sumress_x == 7):                begin sumress_x_next = 4; sumress_y_next = sumress_y + 1; end
						(cnt_cal == 11'd3): begin
							sumress_x_next = sumress_x + 1;
							sumress_y_next = sumress_y - 3;
						end

						(cnt_cal <= 11'd2): begin
							sumress_y_next = sumress_y + 1;
						end

						default: /*hold*/ ;
					endcase
				end

				default: /*hold*/ ;
			endcase
		end

		default: /*hold*/ ;
	endcase
end

always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sumress_x <= 0;
		sumress_y <= 0;
	end else begin
		if (state_d1 == SAD || state_d1 == READ_DATA || state_d1 == READ_PARAM || state_d1 == CAL) begin
			sumress_x <= sumress_x_next;
			sumress_y <= sumress_y_next;
		end else if (state_d1 == IDLE) begin
			sumress_x <= 0;
			sumress_y <= 0;
		end else begin
			sumress_x <= sumress_x; // hold
			sumress_y <= sumress_y; // hold
		end
	end
end
reg [11:0] sram_sumr;
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sram_sumr <= 12'd0;
	end else begin
		sram_sumr <= {index_read, sumress_y, sumress_x};
	end
end

// sram_din
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sram_din <= 32'sd0;
	end else begin
		if (state_d1 == READ_DATA)
			sram_din <= {in_buffer[3], in_buffer[2], in_buffer[1], in_buffer[0]};
		else if (state_d1 == CAL && state_next != CAL)
			sram_din <= 32'sd0;
		else
			sram_din <= sram_din; // hold
	end
end

// sram WEB
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		web <= 1'b1;
	end else begin
		if (state_d1 == READ_DATA)
			web <= 1'b0;
		else if (state_d1 == READ_PARAM)
			web <= 1'b1;
		else
			web <= web; // hold
	end
end
wire signed [31:0] sram_dout;
reg  signed [31:0] sram_dout_d1;
sram_4096x32_bus u_sram(
	.CK(clk),
	.CS(1'b1),
	.WEB(web),
	.OE(1'b1),
	.A (sram_sumr),
	.D (sram_din),
	.Q (sram_dout)
);

always @(posedge clk) begin
	sram_dout_d1 <= sram_dout;
end

// SAD
reg [7:0] input_data [3:0];
always @(*) begin
	input_data[0] = sram_dout_d1[7:0]; input_data[1] = sram_dout_d1[15:8];
	input_data[2] = sram_dout_d1[23:16]; input_data[3] = sram_dout_d1[31:24];
end

subtract_share subtract_sad_dc_0(.a({24'd0, input_data[0]}), .b(dc_num), .c(sad_dc_s1[0]));
subtract_share subtract_sad_dc_1(.a({24'd0, input_data[1]}), .b(dc_num), .c(sad_dc_s1[1]));
subtract_share subtract_sad_dc_2(.a({24'd0, input_data[2]}), .b(dc_num), .c(sad_dc_s1[2]));
subtract_share subtract_sad_dc_3(.a({24'd0, input_data[3]}), .b(dc_num), .c(sad_dc_s1[3]));

sum_share sum_sad_dc_0(.a(sad_dc[0]), .b(sad_dc[1]), .c(sad_dc_s2[0]));
sum_share sum_sad_dc_1(.a(sad_dc[2]), .b(sad_dc[3]), .c(sad_dc_s2[1]));
sum_share sum_sad_dc_2(.a(sad_dc_s2[0]), .b(sad_dc_s2[1]), .c(sad_dc_s3));

// stage1
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sad_dc[0] <= 32'sd0;
		sad_dc[1] <= 32'sd0;
		sad_dc[2] <= 32'sd0;
		sad_dc[3] <= 32'sd0;
	end else begin
		// |sad_dc_s1[i]|
		sad_dc[0] <= (sad_dc_s1[0][31]) ? (~sad_dc_s1[0] + 32'sd1) : sad_dc_s1[0];
		sad_dc[1] <= (sad_dc_s1[1][31]) ? (~sad_dc_s1[1] + 32'sd1) : sad_dc_s1[1];
		sad_dc[2] <= (sad_dc_s1[2][31]) ? (~sad_dc_s1[2] + 32'sd1) : sad_dc_s1[2];
		sad_dc[3] <= (sad_dc_s1[3][31]) ? (~sad_dc_s1[3] + 32'sd1) : sad_dc_s1[3];
	end
end

reg signed [31:0] sad_dc_abs;

// s3
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sad_dc_abs <= 32'sd0;
	end else begin
		if (state_d1 == SAD)
			sad_dc_abs <= sad_dc_s3;
		else if (state_d1 == CAL && state_next != CAL) 
			sad_dc_abs <= 32'sd0;
		else
			sad_dc_abs <= sad_dc_abs; // hold
	end
end

always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sad_dc_num <= 32'sd0;
	end else begin
		if (state_d1 == SAD && cnt_sad >= 5)
			sad_dc_num <= sad_dc_num + sad_dc_abs;
		else if (state_d1 == CAL && state_next != CAL)
			sad_dc_num <= 32'sd0;
		else
			sad_dc_num <= sad_dc_num; // hold
	end
end

// verti — with 3-stage input buffers
reg  signed [31:0] compare_num_v      [3:0], compare_num_h[3:0];
reg  signed [31:0] compare_num_v_buf0 [3:0], compare_num_v_buf1 [3:0],
                   compare_num_v_buf2 [3:0], compare_num_v_buf3 [3:0];
reg  [3:0] v_base;

// verti compare values
always @(*) begin
    compare_num_v[0] = 32'sd0;
    compare_num_v[1] = 32'sd0;
    compare_num_v[2] = 32'sd0;
    compare_num_v[3] = 32'sd0;
    v_base = 4'd0;

    // choose base: {0,4,8,12} by cnt_grid[1:0]
    case (cnt_grid[1:0])
        2'd0: v_base = 4'd0;
        2'd1: v_base = 4'd4;
        2'd2: v_base = 4'd8;
        default: v_base = 4'd12;
    endcase

    // topl when top==0/2, topr when top==1/3 -> use LSB of cnt_grid_top
    case (cnt_grid_top[0])
        1'b0: begin
            compare_num_v[0] = ref_topl[v_base + 4'd0];
            compare_num_v[1] = ref_topl[v_base + 4'd1];
            compare_num_v[2] = ref_topl[v_base + 4'd2];
            compare_num_v[3] = ref_topl[v_base + 4'd3];
        end
        default: begin
            compare_num_v[0] = ref_topr[v_base + 4'd0];
            compare_num_v[1] = ref_topr[v_base + 4'd1];
            compare_num_v[2] = ref_topr[v_base + 4'd2];
            compare_num_v[3] = ref_topr[v_base + 4'd3];
        end
    endcase
end

// verti compare buffers
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= 3; i = i + 1) begin
            compare_num_v_buf0[i] <= 32'sd0;
            compare_num_v_buf1[i] <= 32'sd0;
            compare_num_v_buf2[i] <= 32'sd0;
            compare_num_v_buf3[i] <= 32'sd0;
        end
    end else begin
        for (i = 0; i <= 1; i = i + 1) begin
            compare_num_v_buf0[i] <= compare_num_v_buf0[i+1];
            compare_num_v_buf1[i] <= compare_num_v_buf1[i+1];
            compare_num_v_buf2[i] <= compare_num_v_buf2[i+1];
            compare_num_v_buf3[i] <= compare_num_v_buf3[i+1];
        end
        compare_num_v_buf0[2] <= compare_num_v[0];
        compare_num_v_buf1[2] <= compare_num_v[1];
        compare_num_v_buf2[2] <= compare_num_v[2];
        compare_num_v_buf3[2] <= compare_num_v[3];
    end
end

subtract_share subtract_sad_verti_0(.a({24'd0, input_data[0]}), .b(compare_num_v_buf0[0]), .c(sad_verti_s1[0]));
subtract_share subtract_sad_verti_1(.a({24'd0, input_data[1]}), .b(compare_num_v_buf1[0]), .c(sad_verti_s1[1]));
subtract_share subtract_sad_verti_2(.a({24'd0, input_data[2]}), .b(compare_num_v_buf2[0]), .c(sad_verti_s1[2]));
subtract_share subtract_sad_verti_3(.a({24'd0, input_data[3]}), .b(compare_num_v_buf3[0]), .c(sad_verti_s1[3]));

sum_share sum_sad_verti_0(.a(sad_verti[0]), .b(sad_verti[1]), .c(sad_verti_s2[0]));
sum_share sum_sad_verti_1(.a(sad_verti[2]), .b(sad_verti[3]), .c(sad_verti_s2[1]));
sum_share sum_sad_verti_2(.a(sad_verti_s2[0]), .b(sad_verti_s2[1]), .c(sad_verti_s3));

// stage1 abs writeback (verti)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sad_verti[0] <= 32'sd0; sad_verti[1] <= 32'sd0;
        sad_verti[2] <= 32'sd0; sad_verti[3] <= 32'sd0;
    end else begin
        sad_verti[0] <= sad_verti_s1[0][31] ? (~sad_verti_s1[0] + 32'sd1) : sad_verti_s1[0];
        sad_verti[1] <= sad_verti_s1[1][31] ? (~sad_verti_s1[1] + 32'sd1) : sad_verti_s1[1];
        sad_verti[2] <= sad_verti_s1[2][31] ? (~sad_verti_s1[2] + 32'sd1) : sad_verti_s1[2];
        sad_verti[3] <= sad_verti_s1[3][31] ? (~sad_verti_s1[3] + 32'sd1) : sad_verti_s1[3];
    end
end

reg signed [31:0] sad_verti_abs;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sad_verti_abs <= 32'sd0;
    end else begin
        if (state_d1 == SAD)
            sad_verti_abs <= sad_verti_s3;
        else if (state_d1 == CAL && state_next != CAL)
            sad_verti_abs <= 32'sd0;
        else
            sad_verti_abs <= sad_verti_abs; // hold
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sad_verti_num <= 32'sd0;
    end else begin
        if (state_d1 == SAD && cnt_sad >= 5)
            sad_verti_num <= sad_verti_num + sad_verti_abs;
        else if (state_d1 == CAL && state_next != CAL)
            sad_verti_num <= 32'sd0;
        else
            sad_verti_num <= sad_verti_num; // hold
    end
end

// hori — with 3-stage input buffers
reg  signed [31:0] compare_num_h_buf0 [3:0], compare_num_h_buf1 [3:0],
                   compare_num_h_buf2 [3:0], compare_num_h_buf3 [3:0];
reg  [3:0] h_idx_base, h_idx;
reg  signed [31:0] h_val;

function [3:0] base_left_idx;
        input [3:0] grid;
    begin
        case (grid[3:2]) // 0~3,4~7,8~11,12~15
            2'd0: base_left_idx = 4'd0;
            2'd1: base_left_idx = 4'd4;
            2'd2: base_left_idx = 4'd8;
            default: base_left_idx = 4'd12;
        endcase
    end
endfunction

function signed [31:0] pick_ref_left;
        input [3:0] sel;
    begin
        case (sel)
            4'd0 : pick_ref_left = ref_left[0 ];
            4'd1 : pick_ref_left = ref_left[1 ];
            4'd2 : pick_ref_left = ref_left[2 ];
            4'd3 : pick_ref_left = ref_left[3 ];
            4'd4 : pick_ref_left = ref_left[4 ];
            4'd5 : pick_ref_left = ref_left[5 ];
            4'd6 : pick_ref_left = ref_left[6 ];
            4'd7 : pick_ref_left = ref_left[7 ];
            4'd8 : pick_ref_left = ref_left[8 ];
            4'd9 : pick_ref_left = ref_left[9 ];
            4'd10: pick_ref_left = ref_left[10];
            4'd11: pick_ref_left = ref_left[11];
            4'd12: pick_ref_left = ref_left[12];
            4'd13: pick_ref_left = ref_left[13];
            4'd14: pick_ref_left = ref_left[14];
            default: pick_ref_left = ref_left[15];
        endcase
    end
endfunction
// hori compare values
always @(*) begin
    compare_num_h[0] = 32'sd0;
    compare_num_h[1] = 32'sd0;
    compare_num_h[2] = 32'sd0;
    compare_num_h[3] = 32'sd0;
    h_idx_base = 4'd0;
    h_idx      = 4'd0;
    h_val      = 32'sd0;

    h_idx_base = base_left_idx(cnt_grid);     // 0/4/8/12
    h_idx      = h_idx_base + cnt_sad[1:0];  // +0/1/2/3
    h_val      = pick_ref_left(h_idx);

    compare_num_h[0] = h_val;
    compare_num_h[1] = h_val;
    compare_num_h[2] = h_val;
    compare_num_h[3] = h_val;
end

// hori compare buffers
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= 3; i = i + 1) begin
            compare_num_h_buf0[i] <= 32'sd0;
            compare_num_h_buf1[i] <= 32'sd0;
            compare_num_h_buf2[i] <= 32'sd0;
            compare_num_h_buf3[i] <= 32'sd0;
        end
    end else begin
        for (i = 0; i <= 1; i = i + 1) begin
            compare_num_h_buf0[i] <= compare_num_h_buf0[i+1];
            compare_num_h_buf1[i] <= compare_num_h_buf1[i+1];
            compare_num_h_buf2[i] <= compare_num_h_buf2[i+1];
            compare_num_h_buf3[i] <= compare_num_h_buf3[i+1];
        end
        compare_num_h_buf0[2] <= compare_num_h[0];
        compare_num_h_buf1[2] <= compare_num_h[1];
        compare_num_h_buf2[2] <= compare_num_h[2];
        compare_num_h_buf3[2] <= compare_num_h[3];
    end
end

subtract_share subtract_sad_hori_0(.a({24'd0, input_data[0]}), .b(compare_num_h_buf0[0]), .c(sad_hori_s1[0]));
subtract_share subtract_sad_hori_1(.a({24'd0, input_data[1]}), .b(compare_num_h_buf1[0]), .c(sad_hori_s1[1]));
subtract_share subtract_sad_hori_2(.a({24'd0, input_data[2]}), .b(compare_num_h_buf2[0]), .c(sad_hori_s1[2]));
subtract_share subtract_sad_hori_3(.a({24'd0, input_data[3]}), .b(compare_num_h_buf3[0]), .c(sad_hori_s1[3]));

sum_share sum_sad_hori_0(.a(sad_hori[0]), .b(sad_hori[1]), .c(sad_hori_s2[0]));
sum_share sum_sad_hori_1(.a(sad_hori[2]), .b(sad_hori[3]), .c(sad_hori_s2[1]));
sum_share sum_sad_hori_2(.a(sad_hori_s2[0]), .b(sad_hori_s2[1]), .c(sad_hori_s3));

// stage1 abs writeback (hori)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sad_hori[0] <= 32'sd0; sad_hori[1] <= 32'sd0;
        sad_hori[2] <= 32'sd0; sad_hori[3] <= 32'sd0;
    end else begin
        sad_hori[0] <= sad_hori_s1[0][31] ? (~sad_hori_s1[0] + 32'sd1) : sad_hori_s1[0];
        sad_hori[1] <= sad_hori_s1[1][31] ? (~sad_hori_s1[1] + 32'sd1) : sad_hori_s1[1];
        sad_hori[2] <= sad_hori_s1[2][31] ? (~sad_hori_s1[2] + 32'sd1) : sad_hori_s1[2];
        sad_hori[3] <= sad_hori_s1[3][31] ? (~sad_hori_s1[3] + 32'sd1) : sad_hori_s1[3];
    end
end

reg signed [31:0] sad_hori_abs;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sad_hori_abs <= 32'sd0;
    end else begin
        if (state_d1 == SAD)
            sad_hori_abs <= sad_hori_s3;
        else if (state_d1 == CAL && state_next != CAL)
            sad_hori_abs <= 32'sd0;
        else
            sad_hori_abs <= sad_hori_abs; // hold
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sad_hori_num <= 32'sd0;
    end else begin
        if (state_d1 == SAD && cnt_sad >= 5)
            sad_hori_num <= sad_hori_num + sad_hori_abs;
        else if (state_d1 == CAL && state_next != CAL) 
            sad_hori_num <= 32'sd0;
        else
            sad_hori_num <= sad_hori_num; // hold
    end
end

// mode decision
reg [1:0] predict_d1, predict_next;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        predict_d1 <= 2'd0;
    end else begin
        if ( (state_d1 == SAD) &&
             ( (cnt_sad == 9  &&  mode_reg[cnt_grid_top]) ||
               (cnt_sad == 69 && !mode_reg[cnt_grid_top]) ) ) begin
            predict_d1 <= predict_next;
        end else if ( (state_next == SAD && state_d1 != SAD) || (state_d1 == READ_PARAM) ) begin
            predict_d1 <= 2'd0;
        end else begin
            predict_d1 <= predict_d1; // hold
        end
    end
end

// predict_next：0: DC, 1: hori, 2: verti, 3: unknown
always @(*) begin
    predict_next = 2'd3; // default unknown
    case (1'b1)
        // 16x16（mode=0）
        (!mode_reg[cnt_grid_top]):
        begin
            case (1'b1)
                (cnt_grid_top == 2'd0): predict_next = 2'd0; 
                (cnt_grid_top == 2'd1): begin
                    case (1'b1)
                        (sad_dc_num <= sad_hori_num): predict_next = 2'd0;
                        default                           : predict_next = 2'd1;
                    endcase
                end
                (cnt_grid_top == 2'd2): begin
                    case (1'b1)
                        (sad_dc_num <= sad_verti_num) : predict_next = 2'd0;
                        default                           : predict_next = 2'd2;
                    endcase
                end
                default: begin
                    case (1'b1)
                        (sad_dc_num <= sad_hori_num): begin
                            case (1'b1)
                                (sad_dc_num <= sad_verti_num): predict_next = 2'd0;
                                default                          : predict_next = 2'd2;
                            endcase
                        end
                        default: begin
                            case (1'b1)
                                (sad_hori_num <= sad_verti_num): predict_next = 2'd1;
                                default                                 : predict_next = 2'd2;
                            endcase
                        end
                    endcase
                end
            endcase
        end

        // 4x4（mode=1）
        (mode_reg[cnt_grid_top]):
        begin
            case (1'b1)
                ((cnt_grid_top == 2'd0) && (cnt_grid == 4'd0)) : predict_next = 2'd0;
                ((cnt_grid <= 4'd3) && ((cnt_grid_top == 2'd0) || (cnt_grid_top == 2'd1))): begin
                    case (1'b1)
                        (sad_dc_num <= sad_hori_num): predict_next = 2'd0;
                        default                           : predict_next = 2'd1;
                    endcase
                end
                (((cnt_grid == 4'd0) || (cnt_grid == 4'd4) || (cnt_grid == 4'd8) || (cnt_grid == 4'd12)) &&
                 ((cnt_grid_top == 2'd0) || (cnt_grid_top == 2'd2))): begin
                    case (1'b1)
                        (sad_dc_num <= sad_verti_num) : predict_next = 2'd0;
                        default                           : predict_next = 2'd2;
                    endcase
                end
                default: begin
                    case (1'b1)
                        (sad_dc_num <= sad_hori_num): begin
                            case (1'b1)
                                (sad_dc_num <= sad_verti_num): predict_next = 2'd0;
                                default                          : predict_next = 2'd2;
                            endcase
                        end
                        default: begin
                            case (1'b1)
                                (sad_hori_num <= sad_verti_num): predict_next = 2'd1;
                                default                                 : predict_next = 2'd2;
                            endcase
                        end
                    endcase
                end
            endcase
        end
        default: predict_next = 2'd3;
    endcase
end

// CAL — predict
function automatic [3:0] idx_h4; // ref_left[ 4*(grid>>2) + lane ]
    input [3:0] grid;   // cnt_grid
    input [1:0] lane;  // 0..3
begin
    idx_h4 = {grid[3:2], lane};  // 0..15
end
endfunction

function automatic [3:0] idx_v4; // ref_top{l/r}[ 4*(grid%4) + lane ]
    input [3:0] grid;   // cnt_grid
    input [1:0] lane;  // 0..3
begin
    idx_v4 = {grid[1:0], lane};  // 0..15
end
endfunction

// CAL：predict_num
reg  signed [31:0] residual_seq[3:0], predict_num[3:0];
wire signed [31:0] residual_comb[3:0];

reg  signed [31:0] change_s0_seq [3:0], change_s1_seq [3:0], change_s2_seq [3:0], change_s3_seq [3:0];
wire signed [31:0] change_s0_comb[3:0], change_s1_comb[3:0], change_s2_comb[3:0], change_s3_comb[3:0];
wire signed [31:0] change_s0_comb_m[3:0], change_s1_comb_m[3:0], change_s2_comb_m[3:0], change_s3_comb_m[3:0];

reg  signed [31:0] dequanti_seq[3:0], dequanti_comb[3:0];
reg  signed [31:0] ichange[3:0];

reg  [1:0]  h_lane; // for hori: cnt_cal == 3..6 -> lane 0..3
wire        use_left_col = (cnt_grid_top == 2'd0) || (cnt_grid_top == 2'd2); // verti: choose topl or topr

always @(*) begin
    integer k;
    // default zeros to avoid latches
    for (k = 0; k < 4; k = k + 1) begin
        predict_num[k] = 32'sd0;
    end
    // decode hori lane from cnt_cal (3..6)
    h_lane = 2'd0;
    case (cnt_cal[5:0])
        6'd3: h_lane = 2'd0;
        6'd4: h_lane = 2'd1;
        6'd5: h_lane = 2'd2;
        6'd6: h_lane = 2'd3;
        default: h_lane = 2'd0;
    endcase
    case (predict_d1)
        2'd0: begin
            // DC: broadcast dc_num
            for (k = 0; k < 4; k = k + 1) begin
                predict_num[k] = dc_num;
            end
        end

        2'd1: begin
            // hori: same value across the row
            // index = {cnt_grid[3:2], h_lane}
            // four outputs identical
            reg signed [31:0] h_src;
            h_src = ref_left[ idx_h4(cnt_grid, h_lane) ];
            predict_num[0] = h_src;
            predict_num[1] = h_src;
            predict_num[2] = h_src;
            predict_num[3] = h_src;
        end

        2'd2: begin
            // verti: lane = 0..3 per element, pick from topl/topr by cnt_grid_top
            predict_num[0] = use_left_col ? ref_topl[ idx_v4(cnt_grid, 2'd0) ] : ref_topr[ idx_v4(cnt_grid, 2'd0) ];
            predict_num[1] = use_left_col ? ref_topl[ idx_v4(cnt_grid, 2'd1) ] : ref_topr[ idx_v4(cnt_grid, 2'd1) ];
            predict_num[2] = use_left_col ? ref_topl[ idx_v4(cnt_grid, 2'd2) ] : ref_topr[ idx_v4(cnt_grid, 2'd2) ];
            predict_num[3] = use_left_col ? ref_topl[ idx_v4(cnt_grid, 2'd3) ] : ref_topr[ idx_v4(cnt_grid, 2'd3) ];
        end

        default: begin
            // 2'd3 unknown -> keep zeros
        end
    endcase
end

// residual = input - predict
subtract_share subtract_cal_residual_0(.a({24'd0, input_data[0]}), .b(predict_num[0]), .c(residual_comb[0]));
subtract_share subtract_cal_residual_1(.a({24'd0, input_data[1]}), .b(predict_num[1]), .c(residual_comb[1]));
subtract_share subtract_cal_residual_2(.a({24'd0, input_data[2]}), .b(predict_num[2]), .c(residual_comb[2]));
subtract_share subtract_cal_residual_3(.a({24'd0, input_data[3]}), .b(predict_num[3]), .c(residual_comb[3]));

// register residuals during CAL
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        residual_seq[0] <= 32'sd0; residual_seq[1] <= 32'sd0;
        residual_seq[2] <= 32'sd0; residual_seq[3] <= 32'sd0;
    end else if (state_d1 == CAL) begin
        residual_seq[0] <= residual_comb[0]; residual_seq[1] <= residual_comb[1];
        residual_seq[2] <= residual_comb[2]; residual_seq[3] <= residual_comb[3];
    end else begin
        // hold
        residual_seq[0] <= residual_seq[0]; residual_seq[1] <= residual_seq[1];
        residual_seq[2] <= residual_seq[2]; residual_seq[3] <= residual_seq[3];
    end
end

// s0
function automatic signed [31:0] sel_s0_val_v2;
    input [5:0]         cal;    // cnt_cal
    input signed [31:0] res_v;  // residual_seq[i]
    input signed [31:0] deq_v;  // dequanti_comb[i]
begin
    case (cal)
        6'd15, 6'd16, 6'd17, 6'd18: sel_s0_val_v2 = deq_v;
        default:                    sel_s0_val_v2 = res_v;
    endcase
end
endfunction

reg signed [31:0] pipe_s0 [3:0], sum_val0 [3:0];

integer si;
always @(*) begin
    for (si = 0; si < 4; si = si + 1) begin
        sum_val0[si] = sel_s0_val_v2(cnt_cal, residual_seq[si], dequanti_comb[si]);
    end
end

sum_share sum_cal_it_s00(.a(change_s0_seq[0]), .b(sum_val0[0]), .c(change_s0_comb[0]));
sum_share sum_cal_it_s01(.a(change_s0_seq[1]), .b(sum_val0[1]), .c(change_s0_comb[1]));
sum_share sum_cal_it_s02(.a(change_s0_seq[2]), .b(sum_val0[2]), .c(change_s0_comb[2]));
sum_share sum_cal_it_s03(.a(change_s0_seq[3]), .b(sum_val0[3]), .c(change_s0_comb[3]));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_s0[0] <= 32'sd0; pipe_s0[1] <= 32'sd0; pipe_s0[2] <= 32'sd0; pipe_s0[3] <= 32'sd0;
    end else begin
        pipe_s0[0] <= sum_val0[0];
        pipe_s0[1] <= sum_val0[1];
        pipe_s0[2] <= sum_val0[2];
        pipe_s0[3] <= sum_val0[3];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        change_s0_seq[0] <= 32'sd0; change_s0_seq[1] <= 32'sd0;
        change_s0_seq[2] <= 32'sd0; change_s0_seq[3] <= 32'sd0;
    end else begin
        if (cnt_cal == 6'd14 || cnt_cal == 6'd23) begin 
            change_s0_seq[0] <= 32'sd0; change_s0_seq[1] <= 32'sd0;
            change_s0_seq[2] <= 32'sd0; change_s0_seq[3] <= 32'sd0;
        end else if (cnt_cal >= 6'd4) begin
            change_s0_seq[0] <= change_s0_comb[0]; change_s0_seq[1] <= change_s0_comb[1];
            change_s0_seq[2] <= change_s0_comb[2]; change_s0_seq[3] <= change_s0_comb[3];
        end else begin
            // hold
            change_s0_seq[0] <= change_s0_seq[0]; change_s0_seq[1] <= change_s0_seq[1];
            change_s0_seq[2] <= change_s0_seq[2]; change_s0_seq[3] <= change_s0_seq[3];
        end
    end
end

// s1
reg  [31:0]           pipe_s1 [3:0];
reg  signed [31:0]    sum_val0_s1 [3:0], sum_val1_s1 [3:0];

// H：ref_left[ 4*(cnt_grid>>2) + (cnt_cal-20)[1:0] ]  -> {cnt_grid[3:2], cnt_cal[1:0]}
function automatic [3:0] idx_h_s1;
    input [3:0] grid;   // cnt_grid
    input [5:0] cal;   // cnt_cal
begin
    idx_h_s1 = {grid[3:2], cal[1:0]};
end
endfunction

// V：ref_topX[ 4*(cnt_grid%4) + lane ] -> {cnt_grid[1:0], lane}
function automatic [3:0] idx_v_s1;
    input [3:0] grid;   // cnt_grid
    input [1:0] lane;  // 0..3
begin
    idx_v_s1 = {grid[1:0], lane};
end
endfunction

function automatic signed [31:0] pick_ref_left_s1;
    input [3:0] sel;
begin
    case (sel)
        4'd0 : pick_ref_left_s1 = ref_left[0 ];
        4'd1 : pick_ref_left_s1 = ref_left[1 ];
        4'd2 : pick_ref_left_s1 = ref_left[2 ];
        4'd3 : pick_ref_left_s1 = ref_left[3 ];
        4'd4 : pick_ref_left_s1 = ref_left[4 ];
        4'd5 : pick_ref_left_s1 = ref_left[5 ];
        4'd6 : pick_ref_left_s1 = ref_left[6 ];
        4'd7 : pick_ref_left_s1 = ref_left[7 ];
        4'd8 : pick_ref_left_s1 = ref_left[8 ];
        4'd9 : pick_ref_left_s1 = ref_left[9 ];
        4'd10: pick_ref_left_s1 = ref_left[10];
        4'd11: pick_ref_left_s1 = ref_left[11];
        4'd12: pick_ref_left_s1 = ref_left[12];
        4'd13: pick_ref_left_s1 = ref_left[13];
        4'd14: pick_ref_left_s1 = ref_left[14];
        default: pick_ref_left_s1 = ref_left[15];
    endcase
end
endfunction

function automatic signed [31:0] pick_ref_topl_s1;
    input [3:0] sel;
begin
    case (sel)
        4'd0 : pick_ref_topl_s1 = ref_topl[0 ];
        4'd1 : pick_ref_topl_s1 = ref_topl[1 ];
        4'd2 : pick_ref_topl_s1 = ref_topl[2 ];
        4'd3 : pick_ref_topl_s1 = ref_topl[3 ];
        4'd4 : pick_ref_topl_s1 = ref_topl[4 ];
        4'd5 : pick_ref_topl_s1 = ref_topl[5 ];
        4'd6 : pick_ref_topl_s1 = ref_topl[6 ];
        4'd7 : pick_ref_topl_s1 = ref_topl[7 ];
        4'd8 : pick_ref_topl_s1 = ref_topl[8 ];
        4'd9 : pick_ref_topl_s1 = ref_topl[9 ];
        4'd10: pick_ref_topl_s1 = ref_topl[10];
        4'd11: pick_ref_topl_s1 = ref_topl[11];
        4'd12: pick_ref_topl_s1 = ref_topl[12];
        4'd13: pick_ref_topl_s1 = ref_topl[13];
        4'd14: pick_ref_topl_s1 = ref_topl[14];
        default: pick_ref_topl_s1 = ref_topl[15];
    endcase
end
endfunction

function automatic signed [31:0] pick_ref_topr_s1;
    input [3:0] sel;
begin
    case (sel)
        4'd0 : pick_ref_topr_s1 = ref_topr[0 ];
        4'd1 : pick_ref_topr_s1 = ref_topr[1 ];
        4'd2 : pick_ref_topr_s1 = ref_topr[2 ];
        4'd3 : pick_ref_topr_s1 = ref_topr[3 ];
        4'd4 : pick_ref_topr_s1 = ref_topr[4 ];
        4'd5 : pick_ref_topr_s1 = ref_topr[5 ];
        4'd6 : pick_ref_topr_s1 = ref_topr[6 ];
        4'd7 : pick_ref_topr_s1 = ref_topr[7 ];
        4'd8 : pick_ref_topr_s1 = ref_topr[8 ];
        4'd9 : pick_ref_topr_s1 = ref_topr[9 ];
        4'd10: pick_ref_topr_s1 = ref_topr[10];
        4'd11: pick_ref_topr_s1 = ref_topr[11];
        4'd12: pick_ref_topr_s1 = ref_topr[12];
        4'd13: pick_ref_topr_s1 = ref_topr[13];
        4'd14: pick_ref_topr_s1 = ref_topr[14];
        default: pick_ref_topr_s1 = ref_topr[15];
    endcase
end
endfunction

integer s1i;
always @(*) begin
    for (s1i = 0; s1i < 4; s1i = s1i + 1) begin
        case (1'b1)
            (cnt_cal >= 6'd20): sum_val0_s1[s1i] = ichange[s1i];
            default           : sum_val0_s1[s1i] = change_s1_seq[s1i];
        endcase
    end
end

reg  signed [31:0] h_src; 
wire use_topl = (cnt_grid_top[0] == 1'b0);
always @(*) begin
    sum_val1_s1[0] = pipe_s0[0]; sum_val1_s1[1] = pipe_s0[1];
    sum_val1_s1[2] = pipe_s0[2]; sum_val1_s1[3] = pipe_s0[3];
    // Reconstruction
    case (1'b1)
        (cnt_cal == 6'd20) | (cnt_cal == 6'd21) | (cnt_cal == 6'd22) | (cnt_cal == 6'd23): begin
            case (predict_d1)
                2'd0: begin
                    sum_val1_s1[0] = dc_num;
                    sum_val1_s1[1] = dc_num;
                    sum_val1_s1[2] = dc_num;
                    sum_val1_s1[3] = dc_num;
                end

                2'd1: begin
                    h_src = pick_ref_left_s1( idx_h_s1(cnt_grid, cnt_cal) );
                    sum_val1_s1[0] = h_src;
                    sum_val1_s1[1] = h_src;
                    sum_val1_s1[2] = h_src;
                    sum_val1_s1[3] = h_src;
                end

                2'd2: begin
                    if (use_topl) begin
                        sum_val1_s1[0] = pick_ref_topl_s1( idx_v_s1(cnt_grid, 2'd0) );
                        sum_val1_s1[1] = pick_ref_topl_s1( idx_v_s1(cnt_grid, 2'd1) );
                        sum_val1_s1[2] = pick_ref_topl_s1( idx_v_s1(cnt_grid, 2'd2) );
                        sum_val1_s1[3] = pick_ref_topl_s1( idx_v_s1(cnt_grid, 2'd3) );
                    end else begin
                        sum_val1_s1[0] = pick_ref_topr_s1( idx_v_s1(cnt_grid, 2'd0) );
                        sum_val1_s1[1] = pick_ref_topr_s1( idx_v_s1(cnt_grid, 2'd1) );
                        sum_val1_s1[2] = pick_ref_topr_s1( idx_v_s1(cnt_grid, 2'd2) );
                        sum_val1_s1[3] = pick_ref_topr_s1( idx_v_s1(cnt_grid, 2'd3) );
                    end
                end

                default: /* unknown -> pipe_s0 */ ;
            endcase
        end

        default: /* no -> pipe_s0 */ ;
    endcase
end

sum_share  sum_cal_it_s10(.a(sum_val0_s1[0]), .b(sum_val1_s1[0]), .c(change_s1_comb[0]));
sum_share  sum_cal_it_s11(.a(sum_val0_s1[1]), .b(sum_val1_s1[1]), .c(change_s1_comb[1]));
sum_share  sum_cal_it_s12(.a(sum_val0_s1[2]), .b(sum_val1_s1[2]), .c(change_s1_comb[2]));
sum_share  sum_cal_it_s13(.a(sum_val0_s1[3]), .b(sum_val1_s1[3]), .c(change_s1_comb[3]));

subtract_share subtract_cal_it_s10(.a(change_s1_seq[0]), .b(pipe_s0[0]), .c(change_s1_comb_m[0]));
subtract_share subtract_cal_it_s11(.a(change_s1_seq[1]), .b(pipe_s0[1]), .c(change_s1_comb_m[1]));
subtract_share subtract_cal_it_s12(.a(change_s1_seq[2]), .b(pipe_s0[2]), .c(change_s1_comb_m[2]));
subtract_share subtract_cal_it_s13(.a(change_s1_seq[3]), .b(pipe_s0[3]), .c(change_s1_comb_m[3]));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_s1[0] <= 32'd0; pipe_s1[1] <= 32'd0; pipe_s1[2] <= 32'd0; pipe_s1[3] <= 32'd0;
    end else begin
        pipe_s1[0] <= pipe_s0[0];
        pipe_s1[1] <= pipe_s0[1];
        pipe_s1[2] <= pipe_s0[2];
        pipe_s1[3] <= pipe_s0[3];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        change_s1_seq[0] <= 32'sd0; change_s1_seq[1] <= 32'sd0;
        change_s1_seq[2] <= 32'sd0; change_s1_seq[3] <= 32'sd0;
    end else begin
        if (cnt_cal == 6'd14 || cnt_cal == 6'd23) begin
            change_s1_seq[0] <= 32'sd0; change_s1_seq[1] <= 32'sd0;
            change_s1_seq[2] <= 32'sd0; change_s1_seq[3] <= 32'sd0;
        end else if ( (cnt_cal == 6'd5)  || (cnt_cal == 6'd6)  ||
                      (cnt_cal == 6'd16) || (cnt_cal == 6'd17) ) begin
            change_s1_seq[0] <= change_s1_comb[0]; change_s1_seq[1] <= change_s1_comb[1];
            change_s1_seq[2] <= change_s1_comb[2]; change_s1_seq[3] <= change_s1_comb[3];
        end else if ( (cnt_cal == 6'd7)  || (cnt_cal == 6'd8)  ||
                      (cnt_cal == 6'd18) || (cnt_cal == 6'd19) ) begin
            change_s1_seq[0] <= change_s1_comb_m[0]; change_s1_seq[1] <= change_s1_comb_m[1];
            change_s1_seq[2] <= change_s1_comb_m[2]; change_s1_seq[3] <= change_s1_comb_m[3];
        end else begin
            // hold
            change_s1_seq[0] <= change_s1_seq[0]; change_s1_seq[1] <= change_s1_seq[1];
            change_s1_seq[2] <= change_s1_seq[2]; change_s1_seq[3] <= change_s1_seq[3];
        end
    end
end
    
// s2
reg  [31:0] pipe_s2 [3:0];
function automatic [31:0] pick4_u32;
    input [31:0] a0, a1, a2, a3;
    input [1:0]  sel;
begin
    case (sel)
        2'd0: pick4_u32 = a0;
        2'd1: pick4_u32 = a1;
        2'd2: pick4_u32 = a2;
        default: pick4_u32 = a3;
    endcase
end
endfunction

function automatic signed [31:0] pick4_s32;
    input signed [31:0] a0, a1, a2, a3;
    input [1:0]         sel;
begin
    case (sel)
        2'd0: pick4_s32 = a0;
        2'd1: pick4_s32 = a1;
        2'd2: pick4_s32 = a2;
        default: pick4_s32 = a3;
    endcase
end
endfunction

wire [31:0]         s2_p1_0, s2_p1_1, s2_p1_2, s2_p1_3;         
wire signed [31:0]  s2_t2_0, s2_t2_1, s2_t2_2, s2_t2_3;

assign s2_p1_0 = pick4_u32(pipe_s1[0], pipe_s1[1], pipe_s1[2], pipe_s1[3], 2'd0);
assign s2_p1_1 = pick4_u32(pipe_s1[0], pipe_s1[1], pipe_s1[2], pipe_s1[3], 2'd1);
assign s2_p1_2 = pick4_u32(pipe_s1[0], pipe_s1[1], pipe_s1[2], pipe_s1[3], 2'd2);
assign s2_p1_3 = pick4_u32(pipe_s1[0], pipe_s1[1], pipe_s1[2], pipe_s1[3], 2'd3);

assign s2_t2_0 = pick4_s32(change_s2_seq[0], change_s2_seq[1], change_s2_seq[2], change_s2_seq[3], 2'd0);
assign s2_t2_1 = pick4_s32(change_s2_seq[0], change_s2_seq[1], change_s2_seq[2], change_s2_seq[3], 2'd1);
assign s2_t2_2 = pick4_s32(change_s2_seq[0], change_s2_seq[1], change_s2_seq[2], change_s2_seq[3], 2'd2);
assign s2_t2_3 = pick4_s32(change_s2_seq[0], change_s2_seq[1], change_s2_seq[2], change_s2_seq[3], 2'd3);

sum_share   sum_cal_it_s20(.a(s2_t2_0), .b(s2_p1_0), .c(change_s2_comb[0]));
sum_share   sum_cal_it_s21(.a(s2_t2_1), .b(s2_p1_1), .c(change_s2_comb[1]));
sum_share   sum_cal_it_s22(.a(s2_t2_2), .b(s2_p1_2), .c(change_s2_comb[2]));
sum_share   sum_cal_it_s23(.a(s2_t2_3), .b(s2_p1_3), .c(change_s2_comb[3]));

subtract_share subtract_cal_it_s20(.a(s2_t2_0), .b(s2_p1_0), .c(change_s2_comb_m[0]));
subtract_share subtract_cal_it_s21(.a(s2_t2_1), .b(s2_p1_1), .c(change_s2_comb_m[1]));
subtract_share subtract_cal_it_s22(.a(s2_t2_2), .b(s2_p1_2), .c(change_s2_comb_m[2]));
subtract_share subtract_cal_it_s23(.a(s2_t2_3), .b(s2_p1_3), .c(change_s2_comb_m[3]));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_s2[0] <= 32'd0; pipe_s2[1] <= 32'd0; pipe_s2[2] <= 32'd0; pipe_s2[3] <= 32'd0;
    end else begin
        pipe_s2[0] <= pipe_s1[0];
        pipe_s2[1] <= pipe_s1[1];
        pipe_s2[2] <= pipe_s1[2];
        pipe_s2[3] <= pipe_s1[3];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        change_s2_seq[0] <= 32'sd0; change_s2_seq[1] <= 32'sd0;
        change_s2_seq[2] <= 32'sd0; change_s2_seq[3] <= 32'sd0;
    end else begin
        case (1'b1)
            (cnt_cal == 6'd14) || (cnt_cal == 6'd23): begin
                change_s2_seq[0] <= 32'sd0; change_s2_seq[1] <= 32'sd0;
                change_s2_seq[2] <= 32'sd0; change_s2_seq[3] <= 32'sd0;
            end

            (cnt_cal == 6'd6) || (cnt_cal == 6'd9) || (cnt_cal == 6'd17) || (cnt_cal == 6'd20): begin
                change_s2_seq[0] <= change_s2_comb[0]; change_s2_seq[1] <= change_s2_comb[1];
                change_s2_seq[2] <= change_s2_comb[2]; change_s2_seq[3] <= change_s2_comb[3];
            end

            (cnt_cal == 6'd7) || (cnt_cal == 6'd8) || (cnt_cal == 6'd18) || (cnt_cal == 6'd19): begin
                change_s2_seq[0] <= change_s2_comb_m[0]; change_s2_seq[1] <= change_s2_comb_m[1];
                change_s2_seq[2] <= change_s2_comb_m[2]; change_s2_seq[3] <= change_s2_comb_m[3];
            end
            default: begin
                // hold
                change_s2_seq[0] <= change_s2_seq[0]; change_s2_seq[1] <= change_s2_seq[1];
                change_s2_seq[2] <= change_s2_seq[2]; change_s2_seq[3] <= change_s2_seq[3];
            end
        endcase
    end
end

// s3
reg  [31:0] pipe_s3 [3:0];
wire [31:0] s3_p2_0, s3_p2_1, s3_p2_2, s3_p2_3;
wire signed [31:0] s3_t3_0, s3_t3_1, s3_t3_2, s3_t3_3; 

assign s3_p2_0 = pick4_u32(pipe_s2[0], pipe_s2[1], pipe_s2[2], pipe_s2[3], 2'd0);
assign s3_p2_1 = pick4_u32(pipe_s2[0], pipe_s2[1], pipe_s2[2], pipe_s2[3], 2'd1);
assign s3_p2_2 = pick4_u32(pipe_s2[0], pipe_s2[1], pipe_s2[2], pipe_s2[3], 2'd2);
assign s3_p2_3 = pick4_u32(pipe_s2[0], pipe_s2[1], pipe_s2[2], pipe_s2[3], 2'd3);

assign s3_t3_0 = pick4_s32(change_s3_seq[0], change_s3_seq[1], change_s3_seq[2], change_s3_seq[3], 2'd0);
assign s3_t3_1 = pick4_s32(change_s3_seq[0], change_s3_seq[1], change_s3_seq[2], change_s3_seq[3], 2'd1);
assign s3_t3_2 = pick4_s32(change_s3_seq[0], change_s3_seq[1], change_s3_seq[2], change_s3_seq[3], 2'd2);
assign s3_t3_3 = pick4_s32(change_s3_seq[0], change_s3_seq[1], change_s3_seq[2], change_s3_seq[3], 2'd3);

sum_share   sum_cal_it_s30(.a(s3_t3_0), .b(s3_p2_0), .c(change_s3_comb[0]));
sum_share   sum_cal_it_s31(.a(s3_t3_1), .b(s3_p2_1), .c(change_s3_comb[1]));
sum_share   sum_cal_it_s32(.a(s3_t3_2), .b(s3_p2_2), .c(change_s3_comb[2]));
sum_share   sum_cal_it_s33(.a(s3_t3_3), .b(s3_p2_3), .c(change_s3_comb[3]));

subtract_share subtract_cal_it_s30(.a(s3_t3_0), .b(s3_p2_0), .c(change_s3_comb_m[0]));
subtract_share subtract_cal_it_s31(.a(s3_t3_1), .b(s3_p2_1), .c(change_s3_comb_m[1]));
subtract_share subtract_cal_it_s32(.a(s3_t3_2), .b(s3_p2_2), .c(change_s3_comb_m[2]));
subtract_share subtract_cal_it_s33(.a(s3_t3_3), .b(s3_p2_3), .c(change_s3_comb_m[3]));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_s3[0] <= 32'd0; pipe_s3[1] <= 32'd0; pipe_s3[2] <= 32'd0; pipe_s3[3] <= 32'd0;
    end else begin
        pipe_s3[0] <= pipe_s1[0];
        pipe_s3[1] <= pipe_s1[1];
        pipe_s3[2] <= pipe_s1[2];
        pipe_s3[3] <= pipe_s1[3];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        change_s3_seq[0] <= 32'sd0; change_s3_seq[1] <= 32'sd0;
        change_s3_seq[2] <= 32'sd0; change_s3_seq[3] <= 32'sd0;
    end else begin
        case (1'b1)
            (cnt_cal == 6'd14) || (cnt_cal == 6'd23): begin
                change_s3_seq[0] <= 32'sd0; change_s3_seq[1] <= 32'sd0;
                change_s3_seq[2] <= 32'sd0; change_s3_seq[3] <= 32'sd0;
            end

            (cnt_cal == 6'd7) || (cnt_cal == 6'd9) || (cnt_cal == 6'd18) || (cnt_cal == 6'd20): begin
                change_s3_seq[0] <= change_s3_comb[0]; change_s3_seq[1] <= change_s3_comb[1];
                change_s3_seq[2] <= change_s3_comb[2]; change_s3_seq[3] <= change_s3_comb[3];
            end

            (cnt_cal == 6'd8) || (cnt_cal == 6'd10) || (cnt_cal == 6'd19) || (cnt_cal == 6'd21): begin
                change_s3_seq[0] <= change_s3_comb_m[0]; change_s3_seq[1] <= change_s3_comb_m[1];
                change_s3_seq[2] <= change_s3_comb_m[2]; change_s3_seq[3] <= change_s3_comb_m[3];
            end

            default: begin
                // hold
                change_s3_seq[0] <= change_s3_seq[0]; change_s3_seq[1] <= change_s3_seq[1];
                change_s3_seq[2] <= change_s3_seq[2]; change_s3_seq[3] <= change_s3_seq[3];
            end
        endcase
    end
end
    
// s4
function automatic signed [31:0] sel_s4_num;
    input [5:0] cal; // cnt_cal
    input signed [31:0] v_s0, v_s1, v_s2, v_s3;
begin
    case (cal)
        6'd8,  6'd19: sel_s4_num = v_s0;   
        6'd9,  6'd20: sel_s4_num = v_s1;    
        6'd10, 6'd21: sel_s4_num = v_s2;    
        6'd11, 6'd22: sel_s4_num = v_s3; 
        default:       sel_s4_num = v_s3; 
    endcase
end
endfunction

reg  [3:0]  w_sign;
reg  signed [31:0] w_val [3:0], w_val_pre [3:0];
reg  signed [31:0] s4_num0 [3:0], s4_num1 [3:0];

integer s4i;
always @(*) begin : a_s4_pick_source
    for (s4i = 0; s4i < 4; s4i = s4i + 1) begin
        s4_num0[s4i] = sel_s4_num(
            cnt_cal,
            change_s0_seq[s4i],
            change_s1_seq[s4i],
            change_s2_seq[s4i],
            change_s3_seq[s4i]
        );
    end
end

wire signed [31:0] change_s4_s00 [1:0], change_s4_s01 [1:0], change_s4_s02 [1:0], change_s4_s03 [1:0];
wire signed [31:0] change_s4_s10, change_s4_s11, change_s4_s12, change_s4_s13;
sum_share sum_cal_it_s4_s000(.a(s4_num0[0]), .b(s4_num0[1]), .c(change_s4_s00[0]));
sum_share sum_cal_it_s4_s001(.a(s4_num0[2]), .b(s4_num0[3]), .c(change_s4_s00[1]));
sum_share sum_cal_it_s4_s002(.a(change_s4_s00[0]), .b(change_s4_s00[1]), .c(change_s4_s10));

subtract_share subtract_cal_it_s4_s010(.a(s4_num0[0]), .b(s4_num0[3]), .c(change_s4_s01[0]));
subtract_share subtract_cal_it_s4_s011(.a(s4_num0[1]), .b(s4_num0[2]), .c(change_s4_s01[1]));
sum_share   sum_cal_it_s4_s010  (.a(change_s4_s01[0]), .b(change_s4_s01[1]), .c(change_s4_s11));

subtract_share subtract_cal_it_s4_s020(.a(s4_num0[0]), .b(s4_num0[1]), .c(change_s4_s02[0]));
subtract_share subtract_cal_it_s4_s021(.a(s4_num0[3]), .b(s4_num0[2]), .c(change_s4_s02[1]));
sum_share   sum_cal_it_s4_s020  (.a(change_s4_s02[0]), .b(change_s4_s02[1]), .c(change_s4_s12));

subtract_share subtract_cal_it_s4_s030(.a(s4_num0[0]), .b(s4_num0[1]), .c(change_s4_s03[0]));
subtract_share subtract_cal_it_s4_s031(.a(s4_num0[2]), .b(s4_num0[3]), .c(change_s4_s03[1]));
sum_share   sum_cal_it_s4_s030  (.a(change_s4_s03[0]), .b(change_s4_s03[1]), .c(change_s4_s13));

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        w_val_pre[0] <= 32'sd0; w_val_pre[1] <= 32'sd0; w_val_pre[2] <= 32'sd0; w_val_pre[3] <= 32'sd0;
    end else begin
        w_val_pre[0] <= change_s4_s10;
        w_val_pre[1] <= change_s4_s11;
        w_val_pre[2] <= change_s4_s12;
        w_val_pre[3] <= change_s4_s13;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        w_val[0] <= 32'sd0; w_val[1] <= 32'sd0; w_val[2] <= 32'sd0; w_val[3] <= 32'sd0;
    end else begin
        w_val[0] <= (w_val_pre[0][31]) ? (~w_val_pre[0] + 32'sd1) : w_val_pre[0];
        w_val[1] <= (w_val_pre[1][31]) ? (~w_val_pre[1] + 32'sd1) : w_val_pre[1];
        w_val[2] <= (w_val_pre[2][31]) ? (~w_val_pre[2] + 32'sd1) : w_val_pre[2];
        w_val[3] <= (w_val_pre[3][31]) ? (~w_val_pre[3] + 32'sd1) : w_val_pre[3];
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        w_sign <= 4'd0;
    end else begin
        w_sign <= { w_val_pre[3][31], w_val_pre[2][31], w_val_pre[1][31], w_val_pre[0][31] };
    end
end

reg  signed [31:0] multi_val0_tr [3:0], multi_val1_tr [3:0];
reg  signed [31:0] a, b, c, f;
reg  signed [31:0] quanti_s0_seq  [3:0], quanti_s1_seq  [3:0];
reg  signed [31:0] quanti_s2_seq  [3:0], quanti_s2_wait [3:0], quanti_s11_comb [3:0];
wire signed [31:0] quanti_s0_comb [3:0], quanti_s1_comb  [3:0];
reg         [3:0]  w_sign_1, w_sign_2;

function automatic signed [31:0] sel_a;
    input [5:0] cal;
    input [5:0] qp;
begin
    sel_a = 32'sd0;
    if (cal==6'd10 || cal==6'd11 || cal==6'd12 || cal==6'd13) begin
        if (qp==0 || qp==6  || qp==12 || qp==18 || qp==24) sel_a = 32'sd13107;
        else if (qp==1 || qp==7  || qp==13 || qp==19 || qp==25) sel_a = 32'sd11916;
        else if (qp==2 || qp==8  || qp==14 || qp==20 || qp==26) sel_a = 32'sd10082;
        else if (qp==3 || qp==9  || qp==15 || qp==21 || qp==27) sel_a = 32'sd9362;
        else if (qp==4 || qp==10 || qp==16 || qp==22 || qp==28) sel_a = 32'sd8192;
        else if (qp==5 || qp==11 || qp==17 || qp==23 || qp==29) sel_a = 32'sd7282;
    end
    else if (cal==6'd14 || cal==6'd15 || cal==6'd16 || cal==6'd17) begin
        if (qp==0 || qp==6  || qp==12 || qp==18 || qp==24) sel_a = 32'sd10;
        else if (qp==1 || qp==7  || qp==13 || qp==19 || qp==25) sel_a = 32'sd11;
        else if (qp==2 || qp==8  || qp==14 || qp==20 || qp==26) sel_a = 32'sd13;
        else if (qp==3 || qp==9  || qp==15 || qp==21 || qp==27) sel_a = 32'sd14;
        else if (qp==4 || qp==10 || qp==16 || qp==22 || qp==28) sel_a = 32'sd16;
        else if (qp==5 || qp==11 || qp==17 || qp==23 || qp==29) sel_a = 32'sd18;
    end
end
endfunction

function automatic signed [31:0] sel_b;
    input [5:0] cal;
    input [5:0] qp;
begin
    sel_b = 32'sd0;
    if (cal==6'd10 || cal==6'd11 || cal==6'd12 || cal==6'd13) begin
        if (qp==0 || qp==6  || qp==12 || qp==18 || qp==24) sel_b = 32'sd5243;
        else if (qp==1 || qp==7  || qp==13 || qp==19 || qp==25) sel_b = 32'sd4660;
        else if (qp==2 || qp==8  || qp==14 || qp==20 || qp==26) sel_b = 32'sd4194;
        else if (qp==3 || qp==9  || qp==15 || qp==21 || qp==27) sel_b = 32'sd3647;
        else if (qp==4 || qp==10 || qp==16 || qp==22 || qp==28) sel_b = 32'sd3355;
        else if (qp==5 || qp==11 || qp==17 || qp==23 || qp==29) sel_b = 32'sd2893;
    end else if (cal==6'd14 || cal==6'd15 || cal==6'd16 || cal==6'd17) begin
        if (qp==0 || qp==6  || qp==12 || qp==18 || qp==24) sel_b = 32'sd16;
        else if (qp==1 || qp==7  || qp==13 || qp==19 || qp==25) sel_b = 32'sd18;
        else if (qp==2 || qp==8  || qp==14 || qp==20 || qp==26) sel_b = 32'sd20;
        else if (qp==3 || qp==9  || qp==15 || qp==21 || qp==27) sel_b = 32'sd23;
        else if (qp==4 || qp==10 || qp==16 || qp==22 || qp==28) sel_b = 32'sd25;
        else if (qp==5 || qp==11 || qp==17 || qp==23 || qp==29) sel_b = 32'sd29;
    end
end
endfunction

function automatic signed [31:0] sel_c;
    input [5:0] cal;
    input [5:0] qp;
begin
    sel_c = 32'sd0;
    if (cal==6'd10 || cal==6'd11 || cal==6'd12 || cal==6'd13) begin
        if (qp==0 || qp==6  || qp==12 || qp==18 || qp==24) sel_c = 32'sd8066;
        else if (qp==1 || qp==7  || qp==13 || qp==19 || qp==25) sel_c = 32'sd7490;
        else if (qp==2 || qp==8  || qp==14 || qp==20 || qp==26) sel_c = 32'sd6554;
        else if (qp==3 || qp==9  || qp==15 || qp==21 || qp==27) sel_c = 32'sd5825;
        else if (qp==4 || qp==10 || qp==16 || qp==22 || qp==28) sel_c = 32'sd5243;
        else if (qp==5 || qp==11 || qp==17 || qp==23 || qp==29) sel_c = 32'sd4559;
    end else if (cal==6'd14 || cal==6'd15 || cal==6'd16 || cal==6'd17) begin
        if (qp==0 || qp==6  || qp==12 || qp==18 || qp==24) sel_c = 32'sd13;
        else if (qp==1 || qp==7  || qp==13 || qp==19 || qp==25) sel_c = 32'sd14;
        else if (qp==2 || qp==8  || qp==14 || qp==20 || qp==26) sel_c = 32'sd16;
        else if (qp==3 || qp==9  || qp==15 || qp==21 || qp==27) sel_c = 32'sd18;
        else if (qp==4 || qp==10 || qp==16 || qp==22 || qp==28) sel_c = 32'sd20;
        else if (qp==5 || qp==11 || qp==17 || qp==23 || qp==29) sel_c = 32'sd23;
    end
end
endfunction

function automatic signed [31:0] sel_f;
    input [5:0] qp;
begin
    if      (qp <= 6'd5 ) sel_f = 32'sd10922;
    else if (qp <= 6'd11) sel_f = 32'sd21845;
    else if (qp <= 6'd17) sel_f = 32'sd43690;
    else if (qp <= 6'd23) sel_f = 32'sd87381;
    else                   sel_f = 32'sd174762; // qp<=29
end
endfunction

function automatic signed [31:0] sel_multi0;
    input [5:0]         cal;
    input signed [31:0] w_v;
    input signed [31:0] q_v;
begin
    case (cal)
        6'd14, 6'd15, 6'd16, 6'd17: sel_multi0 = q_v;
        default                   : sel_multi0 = w_v;
    endcase
end
endfunction

// cal==10/12/14/16 -> [a,c,a,c]
// cal==11/13/15/17 -> [c,b,c,b]
function automatic signed [31:0] sel_multi1;
    input [5:0]         cal;
    input [1:0]         lane; // 0..3
    input signed [31:0] a_v, b_v, c_v;
begin
    sel_multi1 = 32'sd0;
    case (cal)
        6'd10, 6'd12, 6'd14, 6'd16: begin
            case (lane)
                2'd0, 2'd2: sel_multi1 = a_v;
                default   : sel_multi1 = c_v; // 1,3
            endcase
        end
        6'd11, 6'd13, 6'd15, 6'd17: begin
            case (lane)
                2'd0, 2'd2: sel_multi1 = c_v;
                default   : sel_multi1 = b_v; // 1,3
            endcase
        end
        default: sel_multi1 = 32'sd0;
    endcase
end
endfunction

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        w_sign_1 <= 4'd0;
        w_sign_2 <= 4'd0;
    end else begin
        w_sign_1 <= w_sign;
        w_sign_2 <= w_sign_1;
    end
end

always @(*) begin
    a = sel_a(cnt_cal, QP_reg);
    b = sel_b(cnt_cal, QP_reg);
    c = sel_c(cnt_cal, QP_reg);
    f = sel_f(QP_reg);
end

integer s5i;
always @(*) begin
    for (s5i = 0; s5i < 4; s5i = s5i + 1) begin
        multi_val0_tr[s5i] = sel_multi0(cnt_cal, w_val[s5i], quanti_s2_wait[s5i]);
        multi_val1_tr[s5i] = sel_multi1(cnt_cal, s5i[1:0], a, b, c);
    end
end

multi_share multi_s50(.a(multi_val0_tr[0]), .b(multi_val1_tr[0]), .c(quanti_s0_comb[0]));
multi_share multi_s51(.a(multi_val0_tr[1]), .b(multi_val1_tr[1]), .c(quanti_s0_comb[1]));
multi_share multi_s52(.a(multi_val0_tr[2]), .b(multi_val1_tr[2]), .c(quanti_s0_comb[2]));
multi_share multi_s53(.a(multi_val0_tr[3]), .b(multi_val1_tr[3]), .c(quanti_s0_comb[3]));

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        quanti_s0_seq[0] <= 32'sd0; quanti_s0_seq[1] <= 32'sd0;
        quanti_s0_seq[2] <= 32'sd0; quanti_s0_seq[3] <= 32'sd0;
    end else begin
        quanti_s0_seq[0] <= quanti_s0_comb[0];
        quanti_s0_seq[1] <= quanti_s0_comb[1];
        quanti_s0_seq[2] <= quanti_s0_comb[2];
        quanti_s0_seq[3] <= quanti_s0_comb[3];
    end
end

sum_share sum_cal_quanti_s20(.a(quanti_s0_seq[0]), .b(f), .c(quanti_s1_comb[0]));
sum_share sum_cal_quanti_s21(.a(quanti_s0_seq[1]), .b(f), .c(quanti_s1_comb[1]));
sum_share sum_cal_quanti_s22(.a(quanti_s0_seq[2]), .b(f), .c(quanti_s1_comb[2]));
sum_share sum_cal_quanti_s23(.a(quanti_s0_seq[3]), .b(f), .c(quanti_s1_comb[3]));

always @(*) begin
    quanti_s11_comb[0] = 32'sd0;
    quanti_s11_comb[1] = 32'sd0;
    quanti_s11_comb[2] = 32'sd0;
    quanti_s11_comb[3] = 32'sd0;

    if (QP_reg <= 6'd5 ) begin
        quanti_s11_comb[0] = (quanti_s1_comb[0] >>> 15);
        quanti_s11_comb[1] = (quanti_s1_comb[1] >>> 15);
        quanti_s11_comb[2] = (quanti_s1_comb[2] >>> 15);
        quanti_s11_comb[3] = (quanti_s1_comb[3] >>> 15);
    end else if (QP_reg <= 6'd11) begin
        quanti_s11_comb[0] = (quanti_s1_comb[0] >>> 16);
        quanti_s11_comb[1] = (quanti_s1_comb[1] >>> 16);
        quanti_s11_comb[2] = (quanti_s1_comb[2] >>> 16);
        quanti_s11_comb[3] = (quanti_s1_comb[3] >>> 16);
    end else if (QP_reg <= 6'd17) begin
        quanti_s11_comb[0] = (quanti_s1_comb[0] >>> 17);
        quanti_s11_comb[1] = (quanti_s1_comb[1] >>> 17);
        quanti_s11_comb[2] = (quanti_s1_comb[2] >>> 17);
        quanti_s11_comb[3] = (quanti_s1_comb[3] >>> 17);
    end else if (QP_reg <= 6'd23) begin
        quanti_s11_comb[0] = (quanti_s1_comb[0] >>> 18);
        quanti_s11_comb[1] = (quanti_s1_comb[1] >>> 18);
        quanti_s11_comb[2] = (quanti_s1_comb[2] >>> 18);
        quanti_s11_comb[3] = (quanti_s1_comb[3] >>> 18);
    end else begin // <=29
        quanti_s11_comb[0] = (quanti_s1_comb[0] >>> 19);
        quanti_s11_comb[1] = (quanti_s1_comb[1] >>> 19);
        quanti_s11_comb[2] = (quanti_s1_comb[2] >>> 19);
        quanti_s11_comb[3] = (quanti_s1_comb[3] >>> 19);
    end
end

// |zij|
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        quanti_s1_seq[0] <= 32'sd0; quanti_s1_seq[1] <= 32'sd0;
        quanti_s1_seq[2] <= 32'sd0; quanti_s1_seq[3] <= 32'sd0;
    end else begin
        quanti_s1_seq[0] <= quanti_s11_comb[0];
        quanti_s1_seq[1] <= quanti_s11_comb[1];
        quanti_s1_seq[2] <= quanti_s11_comb[2];
        quanti_s1_seq[3] <= quanti_s11_comb[3];
    end
end

// zij
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        quanti_s2_seq[0] <= 32'sd0; quanti_s2_seq[1] <= 32'sd0;
        quanti_s2_seq[2] <= 32'sd0; quanti_s2_seq[3] <= 32'sd0;
    end else begin
        quanti_s2_seq[0] <= (w_sign_2[0]) ? (~quanti_s1_seq[0] + 32'sd1) : quanti_s1_seq[0];
        quanti_s2_seq[1] <= (w_sign_2[1]) ? (~quanti_s1_seq[1] + 32'sd1) : quanti_s1_seq[1];
        quanti_s2_seq[2] <= (w_sign_2[2]) ? (~quanti_s1_seq[2] + 32'sd1) : quanti_s1_seq[2];
        quanti_s2_seq[3] <= (w_sign_2[3]) ? (~quanti_s1_seq[3] + 32'sd1) : quanti_s1_seq[3];
    end
end

// wait one cycle to share multit
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        quanti_s2_wait[0] <= 32'sd0; quanti_s2_wait[1] <= 32'sd0;
        quanti_s2_wait[2] <= 32'sd0; quanti_s2_wait[3] <= 32'sd0;
    end else begin
        quanti_s2_wait[0] <= quanti_s2_seq[0];
        quanti_s2_wait[1] <= quanti_s2_seq[1];
        quanti_s2_wait[2] <= quanti_s2_seq[2];
        quanti_s2_wait[3] <= quanti_s2_seq[3];
    end
end

// s6（dequanti）
function automatic [2:0] deq_shamt;
    input [5:0] qp;
begin
    if      (qp <= 6'd5 ) deq_shamt = 3'd0;
    else if (qp <= 6'd11) deq_shamt = 3'd1;
    else if (qp <= 6'd17) deq_shamt = 3'd2;
    else if (qp <= 6'd23) deq_shamt = 3'd3;
    else                  deq_shamt = 3'd4; // qp<=29
end
endfunction

function automatic signed [31:0] deq_lshift;
    input signed [31:0] x;
    input [2:0]         sh;  // 0..4
begin
    case (sh)
        3'd0: deq_lshift = x;
        3'd1: deq_lshift = (x <<< 1);
        3'd2: deq_lshift = (x <<< 2);
        3'd3: deq_lshift = (x <<< 3);
        default: deq_lshift = (x <<< 4); // 3'd4
    endcase
end
endfunction

integer s6i;
always @(*) begin
    for (s6i = 0; s6i < 4; s6i = s6i + 1) begin
        dequanti_comb[s6i] = deq_lshift(quanti_s0_seq[s6i], deq_shamt(QP_reg));
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dequanti_seq[0] <= 32'sd0; dequanti_seq[1] <= 32'sd0;
        dequanti_seq[2] <= 32'sd0; dequanti_seq[3] <= 32'sd0;
    end else begin
        dequanti_seq[0] <= dequanti_comb[0];
        dequanti_seq[1] <= dequanti_comb[1];
        dequanti_seq[2] <= dequanti_comb[2];
        dequanti_seq[3] <= dequanti_comb[3];
    end
end

// s7
function automatic signed [31:0] pick_s4_sum;
    input [1:0]         lane;  // 0..3
    input signed [31:0] s10, s11, s12, s13;
begin
    case (lane)
        2'd0: pick_s4_sum = s10;
        2'd1: pick_s4_sum = s11;
        2'd2: pick_s4_sum = s12;
        default: pick_s4_sum = s13;
    endcase
end
endfunction

integer s7i;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        ichange[0] <= 32'sd0; ichange[1] <= 32'sd0;
        ichange[2] <= 32'sd0; ichange[3] <= 32'sd0;
    end else begin
        ichange[0] <= pick_s4_sum(2'd0, change_s4_s10, change_s4_s11, change_s4_s12, change_s4_s13) >>> 6;
        ichange[1] <= pick_s4_sum(2'd1, change_s4_s10, change_s4_s11, change_s4_s12, change_s4_s13) >>> 6;
        ichange[2] <= pick_s4_sum(2'd2, change_s4_s10, change_s4_s11, change_s4_s12, change_s4_s13) >>> 6;
        ichange[3] <= pick_s4_sum(2'd3, change_s4_s10, change_s4_s11, change_s4_s12, change_s4_s13) >>> 6;
    end
end
    
function automatic signed [31:0] fx_clamp_u8;
    input signed [31:0] x;
begin
    if (x[31])               fx_clamp_u8 = 32'sd0;
    else if (x > 32'sd255)   fx_clamp_u8 = 32'sd255;
    else                     fx_clamp_u8 = x;
end
endfunction

function automatic [3:0] fx_base_left_idx;
    input [3:0] grid; // cnt_grid
begin
    case (grid[3:2])     // 0~3, 4~7, 8~11, 12~15
        2'd0: fx_base_left_idx = 4'd0;
        2'd1: fx_base_left_idx = 4'd4;
        2'd2: fx_base_left_idx = 4'd8;
        default: fx_base_left_idx = 4'd12;
    endcase
end
endfunction

function automatic [1:0] fx_row_of_4_from_cal;
    input [5:0] cal; // cnt_cal
begin
    case (cal)
        6'd20: fx_row_of_4_from_cal = 2'd0;
        6'd21: fx_row_of_4_from_cal = 2'd1;
        6'd22: fx_row_of_4_from_cal = 2'd2;
        default: fx_row_of_4_from_cal = 2'd3; // 6'd23
    endcase
end
endfunction

function automatic [3:0] fx_base_top_idx;
    input [3:0] grid; // cnt_grid
begin
    case (grid[1:0])     // 0,1,2,3 -> 0,4,8,12
        2'd0: fx_base_top_idx = 4'd0;
        2'd1: fx_base_top_idx = 4'd4;
        2'd2: fx_base_top_idx = 4'd8;
        default: fx_base_top_idx = 4'd12;
    endcase
end
endfunction

// renew predicted
reg signed [31:0] ref_renew_val [3:0];
always @(*) begin
    if (cnt_cal >= 6'd20) begin
        ref_renew_val[0] = fx_clamp_u8(change_s1_comb[0]);
        ref_renew_val[1] = fx_clamp_u8(change_s1_comb[1]);
        ref_renew_val[2] = fx_clamp_u8(change_s1_comb[2]);
        ref_renew_val[3] = fx_clamp_u8(change_s1_comb[3]);
    end else begin
        ref_renew_val[0] = 32'sd0;
        ref_renew_val[1] = 32'sd0;
        ref_renew_val[2] = 32'sd0;
        ref_renew_val[3] = 32'sd0;
    end
end

// ref_left
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= 15; i = i + 1) ref_left[i] <= 32'sd0;
    end else begin
        if ( state_d1 == CAL
             && !(!mode_reg[1] && predict_d1 == 2'd1 && cnt_grid_top == 2'd1)
             && !(!mode_reg[3] && predict_d1 == 2'd1 && cnt_grid_top == 2'd3) ) begin

            if (cnt_cal >= 6'd20 && cnt_cal <= 6'd23) begin
                case (fx_base_left_idx(cnt_grid))
                    4'd0:  begin
                        case (fx_row_of_4_from_cal(cnt_cal))
                            2'd0: ref_left[0 ] <= ref_renew_val[3];
                            2'd1: ref_left[1 ] <= ref_renew_val[3];
                            2'd2: ref_left[2 ] <= ref_renew_val[3];
                            default: ref_left[3 ] <= ref_renew_val[3];
                        endcase
                    end
                    4'd4:  begin
                        case (fx_row_of_4_from_cal(cnt_cal))
                            2'd0: ref_left[4 ] <= ref_renew_val[3];
                            2'd1: ref_left[5 ] <= ref_renew_val[3];
                            2'd2: ref_left[6 ] <= ref_renew_val[3];
                            default: ref_left[7 ] <= ref_renew_val[3];
                        endcase
                    end
                    4'd8:  begin
                        case (fx_row_of_4_from_cal(cnt_cal))
                            2'd0: ref_left[8 ] <= ref_renew_val[3];
                            2'd1: ref_left[9 ] <= ref_renew_val[3];
                            2'd2: ref_left[10] <= ref_renew_val[3];
                            default: ref_left[11] <= ref_renew_val[3];
                        endcase
                    end
                    default: begin // 4'd12
                        case (fx_row_of_4_from_cal(cnt_cal))
                            2'd0: ref_left[12] <= ref_renew_val[3];
                            2'd1: ref_left[13] <= ref_renew_val[3];
                            2'd2: ref_left[14] <= ref_renew_val[3];
                            default: ref_left[15] <= ref_renew_val[3];
                        endcase
                    end
                endcase
            end
        end
    end
end

// ref_topl
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= 15; i = i + 1) ref_topl[i] <= 32'sd0;
    end else begin
        if ( state_d1 == CAL
             && (cnt_grid_top == 2'd0 || cnt_grid_top == 2'd2)
             && !(!mode_reg[2] && predict_d1 == 2'd2 && cnt_grid_top == 2'd2) ) begin

            if (cnt_cal == 6'd23) begin
                case (fx_base_top_idx(cnt_grid))
                    4'd0:  begin
                        ref_topl[0 ] <= ref_renew_val[0];
                        ref_topl[1 ] <= ref_renew_val[1];
                        ref_topl[2 ] <= ref_renew_val[2];
                        ref_topl[3 ] <= ref_renew_val[3];
                    end
                    4'd4:  begin
                        ref_topl[4 ] <= ref_renew_val[0];
                        ref_topl[5 ] <= ref_renew_val[1];
                        ref_topl[6 ] <= ref_renew_val[2];
                        ref_topl[7 ] <= ref_renew_val[3];
                    end
                    4'd8:  begin
                        ref_topl[8 ] <= ref_renew_val[0];
                        ref_topl[9 ] <= ref_renew_val[1];
                        ref_topl[10] <= ref_renew_val[2];
                        ref_topl[11] <= ref_renew_val[3];
                    end
                    default: begin // 4'd12
                        ref_topl[12] <= ref_renew_val[0];
                        ref_topl[13] <= ref_renew_val[1];
                        ref_topl[14] <= ref_renew_val[2];
                        ref_topl[15] <= ref_renew_val[3];
                    end
                endcase
            end
        end
    end
end

// ref_topr
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= 15; i = i + 1) ref_topr[i] <= 32'sd0;
    end else begin
        if ( state_d1 == CAL
             && (cnt_grid_top == 2'd1 || cnt_grid_top == 2'd3)
             && !(!mode_reg[3] && predict_d1 == 2'd2 && cnt_grid_top == 2'd3) ) begin

            if (cnt_cal == 6'd23) begin
                case (fx_base_top_idx(cnt_grid))
                    4'd0:  begin
                        ref_topr[0 ] <= ref_renew_val[0];
                        ref_topr[1 ] <= ref_renew_val[1];
                        ref_topr[2 ] <= ref_renew_val[2];
                        ref_topr[3 ] <= ref_renew_val[3];
                    end
                    4'd4:  begin
                        ref_topr[4 ] <= ref_renew_val[0];
                        ref_topr[5 ] <= ref_renew_val[1];
                        ref_topr[6 ] <= ref_renew_val[2];
                        ref_topr[7 ] <= ref_renew_val[3];
                    end
                    4'd8:  begin
                        ref_topr[8 ] <= ref_renew_val[0];
                        ref_topr[9 ] <= ref_renew_val[1];
                        ref_topr[10] <= ref_renew_val[2];
                        ref_topr[11] <= ref_renew_val[3];
                    end
                    default: begin // 4'd12
                        ref_topr[12] <= ref_renew_val[0];
                        ref_topr[13] <= ref_renew_val[1];
                        ref_topr[14] <= ref_renew_val[2];
                        ref_topr[15] <= ref_renew_val[3];
                    end
                endcase
            end
        end
    end
end

function automatic signed [31:0] fx_pick_top;
    input [0:0] use_right;
    input [3:0] idx4;
begin
    case (idx4)
        4'd0 : fx_pick_top = (use_right) ? ref_topr[0 ] : ref_topl[0 ];
        4'd1 : fx_pick_top = (use_right) ? ref_topr[1 ] : ref_topl[1 ];
        4'd2 : fx_pick_top = (use_right) ? ref_topr[2 ] : ref_topl[2 ];
        4'd3 : fx_pick_top = (use_right) ? ref_topr[3 ] : ref_topl[3 ];
        4'd4 : fx_pick_top = (use_right) ? ref_topr[4 ] : ref_topl[4 ];
        4'd5 : fx_pick_top = (use_right) ? ref_topr[5 ] : ref_topl[5 ];
        4'd6 : fx_pick_top = (use_right) ? ref_topr[6 ] : ref_topl[6 ];
        4'd7 : fx_pick_top = (use_right) ? ref_topr[7 ] : ref_topl[7 ];
        4'd8 : fx_pick_top = (use_right) ? ref_topr[8 ] : ref_topl[8 ];
        4'd9 : fx_pick_top = (use_right) ? ref_topr[9 ] : ref_topl[9 ];
        4'd10: fx_pick_top = (use_right) ? ref_topr[10] : ref_topl[10];
        4'd11: fx_pick_top = (use_right) ? ref_topr[11] : ref_topl[11];
        4'd12: fx_pick_top = (use_right) ? ref_topr[12] : ref_topl[12];
        4'd13: fx_pick_top = (use_right) ? ref_topr[13] : ref_topl[13];
        4'd14: fx_pick_top = (use_right) ? ref_topr[14] : ref_topl[14];
        default: fx_pick_top = (use_right) ? ref_topr[15] : ref_topl[15];
    endcase
end
endfunction

function automatic [1:0] fx_grid_row_group;
    input [3:0] grid;
begin
    fx_grid_row_group = grid[3:2];
end
endfunction

function automatic [1:0] fx_grid_col_index;
    input [3:0] grid;
begin
    fx_grid_col_index = grid[1:0];
end
endfunction

wire signed [31:0] dc_s0_comb [15:0], dc_s1_comb [7:0];
reg  signed [31:0] sum_val0_dc_s0 [7:0], sum_val1_dc_s0 [7:0];
reg  signed [31:0] sum_val0_dc_s1 [7:0], sum_val1_dc_s1 [7:0];

// counter
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_dc <= 0;
    end else begin
        if (state_d1 == DC) cnt_dc <= cnt_dc + 1; else cnt_dc <= 0;
    end
end

// dc_num
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dc_num <= 128;
    end else begin
        if(state_d1 == DC) begin
            if(!mode_reg[cnt_grid_top]) begin // 16x16
                if(cnt_grid_top == 1)      dc_num <= dc_s1_comb[4] >> 4;
                else if(cnt_grid_top == 2) dc_num <= dc_s1_comb[5] >> 4;
                else                      dc_num <= dc_s0_comb[8] >> 5;
            end else begin // 4x4
                if(cnt_grid_top == 0) begin
                    if     (cnt_grid == 1)  dc_num <= dc_s1_comb[0] >> 2;
                    else if(cnt_grid == 2)  dc_num <= dc_s1_comb[0] >> 2;
                    else if(cnt_grid == 3)  dc_num <= dc_s1_comb[0] >> 2;
                    else if(cnt_grid == 4)  dc_num <= dc_s1_comb[4] >> 2;
                    else if(cnt_grid == 8)  dc_num <= dc_s1_comb[4] >> 2;
                    else if(cnt_grid == 12) dc_num <= dc_s1_comb[4] >> 2;
                    else                   dc_num <= dc_s1_comb[0] >> 3;
                end else if(cnt_grid_top == 1) begin
                    if     (cnt_grid == 0)  dc_num <= dc_s1_comb[0] >> 2;
                    else if(cnt_grid == 1)  dc_num <= dc_s1_comb[0] >> 2;
                    else if(cnt_grid == 2)  dc_num <= dc_s1_comb[0] >> 2;
                    else if(cnt_grid == 3)  dc_num <= dc_s1_comb[0] >> 2;
                    else                   dc_num <= dc_s1_comb[0] >> 3;
                end else if(cnt_grid_top == 2) begin
                    if     (cnt_grid == 0)  dc_num <= dc_s1_comb[4] >> 2;
                    else if(cnt_grid == 4)  dc_num <= dc_s1_comb[4] >> 2;
                    else if(cnt_grid == 8)  dc_num <= dc_s1_comb[4] >> 2;
                    else if(cnt_grid == 12) dc_num <= dc_s1_comb[4] >> 2;
                    else                   dc_num <= dc_s1_comb[0] >> 3;
                end else begin
                    dc_num <= dc_s1_comb[0] >> 3;
                end
            end
        end else if (state_next == READ_PARAM) begin
            dc_num <= 128;
        end
    end
end

// s0 inputs
reg  signed [31:0] dc_s1_seq  [7:0];
always @(*) begin
    sum_val0_dc_s0[0] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd0 );
    sum_val0_dc_s0[1] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd2 );
    sum_val0_dc_s0[2] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd4 );
    sum_val0_dc_s0[3] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd6 );
    sum_val0_dc_s0[4] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd8 );
    sum_val0_dc_s0[5] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd10);
    sum_val0_dc_s0[6] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd12);
    sum_val0_dc_s0[7] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd14);

    if (cnt_dc == 1) begin
        sum_val0_dc_s0[0] = dc_s1_seq[0];
        sum_val0_dc_s0[1] = dc_s1_seq[2];
        sum_val0_dc_s0[2] = dc_s1_seq[4];
        sum_val0_dc_s0[3] = dc_s1_seq[6];
    end else if (cnt_dc == 2) begin
        sum_val0_dc_s0[0] = dc_s1_seq[4];
    end
end

always @(*) begin
    sum_val1_dc_s0[0] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd1 );
    sum_val1_dc_s0[1] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd3 );
    sum_val1_dc_s0[2] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd5 );
    sum_val1_dc_s0[3] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd7 );
    sum_val1_dc_s0[4] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd9 );
    sum_val1_dc_s0[5] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd11);
    sum_val1_dc_s0[6] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd13);
    sum_val1_dc_s0[7] = fx_pick_top( (cnt_grid_top[0] && (cnt_dc==0)), 4'd15);

    if (cnt_dc == 1) begin
        sum_val1_dc_s0[0] = dc_s1_seq[1];
        sum_val1_dc_s0[1] = dc_s1_seq[3];
        sum_val1_dc_s0[2] = dc_s1_seq[5];
        sum_val1_dc_s0[3] = dc_s1_seq[7];
    end else if (cnt_dc == 2) begin
        sum_val1_dc_s0[0] = dc_s1_seq[5];
    end
end

sum_share sum_dc_s00(.a(ref_left[0]),  .b(ref_left[1]),  .c(dc_s0_comb[0]));
sum_share sum_dc_s01(.a(ref_left[2]),  .b(ref_left[3]),  .c(dc_s0_comb[1]));
sum_share sum_dc_s02(.a(ref_left[4]),  .b(ref_left[5]),  .c(dc_s0_comb[2]));
sum_share sum_dc_s03(.a(ref_left[6]),  .b(ref_left[7]),  .c(dc_s0_comb[3]));
sum_share sum_dc_s04(.a(ref_left[8]),  .b(ref_left[9]),  .c(dc_s0_comb[4]));
sum_share sum_dc_s05(.a(ref_left[10]), .b(ref_left[11]), .c(dc_s0_comb[5]));
sum_share sum_dc_s06(.a(ref_left[12]), .b(ref_left[13]), .c(dc_s0_comb[6]));
sum_share sum_dc_s07(.a(ref_left[14]), .b(ref_left[15]), .c(dc_s0_comb[7]));

sum_share sum_dc_s08 (.a(sum_val0_dc_s0[0]), .b(sum_val1_dc_s0[0]), .c(dc_s0_comb[8]));
sum_share sum_dc_s09 (.a(sum_val0_dc_s0[1]), .b(sum_val1_dc_s0[1]), .c(dc_s0_comb[9]));
sum_share sum_dc_s010(.a(sum_val0_dc_s0[2]), .b(sum_val1_dc_s0[2]), .c(dc_s0_comb[10]));
sum_share sum_dc_s011(.a(sum_val0_dc_s0[3]), .b(sum_val1_dc_s0[3]), .c(dc_s0_comb[11]));
sum_share sum_dc_s012(.a(sum_val0_dc_s0[4]), .b(sum_val1_dc_s0[4]), .c(dc_s0_comb[12]));
sum_share sum_dc_s013(.a(sum_val0_dc_s0[5]), .b(sum_val1_dc_s0[5]), .c(dc_s0_comb[13]));
sum_share sum_dc_s014(.a(sum_val0_dc_s0[6]), .b(sum_val1_dc_s0[6]), .c(dc_s0_comb[14]));
sum_share sum_dc_s015(.a(sum_val0_dc_s0[7]), .b(sum_val1_dc_s0[7]), .c(dc_s0_comb[15]));

// s1 inputs
always @(*) begin
    sum_val0_dc_s1[0] = dc_s0_comb[0];
    sum_val1_dc_s1[1] = dc_s0_comb[1];

    if (mode_reg[cnt_grid_top] && (cnt_dc == 1)) begin
        case (fx_grid_row_group(cnt_grid))
            2'd0: sum_val0_dc_s1[0] = dc_s1_seq[0];
            2'd1: sum_val0_dc_s1[0] = dc_s1_seq[1];
            2'd2: sum_val0_dc_s1[0] = dc_s1_seq[2];
            default: sum_val0_dc_s1[0] = dc_s1_seq[3];
        endcase

        case (fx_grid_col_index(cnt_grid))
            2'd0: sum_val1_dc_s1[1] = dc_s1_seq[4];
            2'd1: sum_val1_dc_s1[1] = dc_s1_seq[5];
            2'd2: sum_val1_dc_s1[1] = dc_s1_seq[6];
            default: sum_val1_dc_s1[1] = dc_s1_seq[7];
        endcase
    end
end
sum_share sum_dc_s10(.a(sum_val0_dc_s1[0]), .b(sum_val1_dc_s1[1]), .c(dc_s1_comb[0]));
sum_share sum_dc_s11(.a(dc_s0_comb[2]), .b(dc_s0_comb[3]), .c(dc_s1_comb[1]));
sum_share sum_dc_s12(.a(dc_s0_comb[4]), .b(dc_s0_comb[5]), .c(dc_s1_comb[2]));
sum_share sum_dc_s13(.a(dc_s0_comb[6]), .b(dc_s0_comb[7]), .c(dc_s1_comb[3]));

sum_share sum_dc_s14(.a(dc_s0_comb[8]), .b(dc_s0_comb[9]), .c(dc_s1_comb[4]));
sum_share sum_dc_s15(.a(dc_s0_comb[10]), .b(dc_s0_comb[11]), .c(dc_s1_comb[5]));
sum_share sum_dc_s16(.a(dc_s0_comb[12]), .b(dc_s0_comb[13]), .c(dc_s1_comb[6]));
sum_share sum_dc_s17(.a(dc_s0_comb[14]), .b(dc_s0_comb[15]), .c(dc_s1_comb[7]));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= 7; i = i + 1) dc_s1_seq[i] <= 0;
    end else if (state_d1 == DC) begin
        for (i = 0; i <= 7; i = i + 1) dc_s1_seq[i] <= dc_s1_comb[i];
    end
end

//============================== OUTPUT ===============================
reg [31:0] reconstruct_map [15:0];
reg [3:0]  cnt_out;
reg        flag_out;

function automatic [3:0] fx_out_base_from_cntcal;
    input [5:0] cal; // cnt_cal
begin
    case (cal)
        6'd13: fx_out_base_from_cntcal = 4'd0;
        6'd14: fx_out_base_from_cntcal = 4'd4;
        6'd15: fx_out_base_from_cntcal = 4'd8;
        6'd16: fx_out_base_from_cntcal = 4'd12;
        default: fx_out_base_from_cntcal = 4'd0;
    endcase
end
endfunction

function automatic [31:0] fx_pick_recon_map;
    input [3:0] idx4;
begin
    case (idx4)
        4'd0 : fx_pick_recon_map = reconstruct_map[0 ];
        4'd1 : fx_pick_recon_map = reconstruct_map[1 ];
        4'd2 : fx_pick_recon_map = reconstruct_map[2 ];
        4'd3 : fx_pick_recon_map = reconstruct_map[3 ];
        4'd4 : fx_pick_recon_map = reconstruct_map[4 ];
        4'd5 : fx_pick_recon_map = reconstruct_map[5 ];
        4'd6 : fx_pick_recon_map = reconstruct_map[6 ];
        4'd7 : fx_pick_recon_map = reconstruct_map[7 ];
        4'd8 : fx_pick_recon_map = reconstruct_map[8 ];
        4'd9 : fx_pick_recon_map = reconstruct_map[9 ];
        4'd10: fx_pick_recon_map = reconstruct_map[10];
        4'd11: fx_pick_recon_map = reconstruct_map[11];
        4'd12: fx_pick_recon_map = reconstruct_map[12];
        4'd13: fx_pick_recon_map = reconstruct_map[13];
        4'd14: fx_pick_recon_map = reconstruct_map[14];
        default: fx_pick_recon_map = reconstruct_map[15];
    endcase
end
endfunction

// flag_out
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        flag_out <= 1'b0;
    end else begin
        if (cnt_out == 4'd15)
            flag_out <= 1'b0;
        else if (cnt_cal == 6'd16 && state_d1 == CAL)
            flag_out <= 1'b1;
    end
end

// cnt_out
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_out <= 4'd0;
    end else if (flag_out) begin
        if (cnt_out == 4'd15) cnt_out <= 4'd0;
        else                  cnt_out <= cnt_out + 4'd1;
    end
end

// reconstruct_map
always @(posedge clk or negedge rst_n) begin
    reg [3:0] base;
    if (!rst_n) begin
        for (i = 0; i <= 15; i = i + 1) reconstruct_map[i] <= 32'd0;
    end else begin
        if (state_d1 == CAL) begin
            base = fx_out_base_from_cntcal(cnt_cal);
            case (cnt_cal)
                6'd13, 6'd14, 6'd15, 6'd16: begin
                    case (base)
                        4'd0: begin
                            reconstruct_map[0]  <= quanti_s2_seq[0];
                            reconstruct_map[1]  <= quanti_s2_seq[1];
                            reconstruct_map[2]  <= quanti_s2_seq[2];
                            reconstruct_map[3]  <= quanti_s2_seq[3];
                        end
                        4'd4: begin
                            reconstruct_map[4]  <= quanti_s2_seq[0];
                            reconstruct_map[5]  <= quanti_s2_seq[1];
                            reconstruct_map[6]  <= quanti_s2_seq[2];
                            reconstruct_map[7]  <= quanti_s2_seq[3];
                        end
                        4'd8: begin
                            reconstruct_map[8]  <= quanti_s2_seq[0];
                            reconstruct_map[9]  <= quanti_s2_seq[1];
                            reconstruct_map[10] <= quanti_s2_seq[2];
                            reconstruct_map[11] <= quanti_s2_seq[3];
                        end
                        4'd12: begin
                            reconstruct_map[12] <= quanti_s2_seq[0];
                            reconstruct_map[13] <= quanti_s2_seq[1];
                            reconstruct_map[14] <= quanti_s2_seq[2];
                            reconstruct_map[15] <= quanti_s2_seq[3];
                        end
                        default: ;
                    endcase
                end
                default: ; 
            endcase
        end
    end
end

// out_valid
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_valid <= 1'b0;
    else        out_valid <= flag_out;
end

// out_value
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_value <= 32'd0;
    end else begin
        if (flag_out) out_value <= fx_pick_recon_map(cnt_out);
        else          out_value <= 32'd0;
    end
end
endmodule // HLPTE

module sum_share #(parameter W = 32) (
    input  signed [W-1:0] a,
    input  signed [W-1:0] b,
    output signed [W-1:0] c
);
    assign c = a + b;
endmodule

module subtract_share #(parameter W = 32) (
    input  signed [W-1:0] a,
    input  signed [W-1:0] b,
    output signed [W-1:0] c
);
    assign c = a - b;
endmodule

module multi_share #(parameter W = 32) (
    input  signed [W-1:0] a,
    input  signed [W-1:0] b,
    output signed [W-1:0] c
);
    assign c = a * b;  
endmodule

module sram_4096x32_bus (
  input  wire        CK,
  input  wire        CS,      // active-high
  input  wire        WEB,     // 0: write, 1: read
  input  wire        OE,      // active-high output enable
  input  wire [11:0] A,
  input  wire [31:0] D,
  output wire [31:0] Q
);
  MEM_4096X32 u_mem (
    // sumress
    .A0 (A[0]),  .A1 (A[1]),  .A2 (A[2]),  .A3 (A[3]),
    .A4 (A[4]),  .A5 (A[5]),  .A6 (A[6]),  .A7 (A[7]),
    .A8 (A[8]),  .A9 (A[9]),  .A10(A[10]), .A11(A[11]),
    // Data Out (Q)
    .DO0 (Q[0]),   .DO1 (Q[1]),   .DO2 (Q[2]),   .DO3 (Q[3]),
    .DO4 (Q[4]),   .DO5 (Q[5]),   .DO6 (Q[6]),   .DO7 (Q[7]),
    .DO8 (Q[8]),   .DO9 (Q[9]),   .DO10(Q[10]),  .DO11(Q[11]),
    .DO12(Q[12]),  .DO13(Q[13]),  .DO14(Q[14]),  .DO15(Q[15]),
    .DO16(Q[16]),  .DO17(Q[17]),  .DO18(Q[18]),  .DO19(Q[19]),
    .DO20(Q[20]),  .DO21(Q[21]),  .DO22(Q[22]),  .DO23(Q[23]),
    .DO24(Q[24]),  .DO25(Q[25]),  .DO26(Q[26]),  .DO27(Q[27]),
    .DO28(Q[28]),  .DO29(Q[29]),  .DO30(Q[30]),  .DO31(Q[31]),
    // Data In (D)
    .DI0 (D[0]),   .DI1 (D[1]),   .DI2 (D[2]),   .DI3 (D[3]),
    .DI4 (D[4]),   .DI5 (D[5]),   .DI6 (D[6]),   .DI7 (D[7]),
    .DI8 (D[8]),   .DI9 (D[9]),   .DI10(D[10]),  .DI11(D[11]),
    .DI12(D[12]),  .DI13(D[13]),  .DI14(D[14]),  .DI15(D[15]),
    .DI16(D[16]),  .DI17(D[17]),  .DI18(D[18]),  .DI19(D[19]),
    .DI20(D[20]),  .DI21(D[21]),  .DI22(D[22]),  .DI23(D[23]),
    .DI24(D[24]),  .DI25(D[25]),  .DI26(D[26]),  .DI27(D[27]),
    .DI28(D[28]),  .DI29(D[29]),  .DI30(D[30]),  .DI31(D[31]),
    // Control
    .CK (CK),
    .WEB(WEB),
    .OE (OE),
    .CS (CS)
  );
endmodule
