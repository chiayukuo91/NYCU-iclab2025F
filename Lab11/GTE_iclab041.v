module GTE(
    // input signals
    clk,
    rst_n,
	
    in_valid_data,
	data,
	
    in_valid_cmd,
    cmd,    
	
    // output signals
    busy
);

input              clk;
input              rst_n;

input              in_valid_data;
input       [7:0]  data;

input              in_valid_cmd;
input      [17:0]  cmd;

output reg         busy;

//============================================================
//  reg & wire
//============================================================
reg [3:0] st_cur;
reg [3:0] st_nxt;
// input stream 
reg  [15:0] cnt_in;
wire        cnt_in_en;
wire [15:0] cnt_in_plus;
wire [15:0] cnt_in_next;
// load/store 
reg  [8:0]  cnt_load;
reg  [8:0]  cnt_store;
wire        load_en;
wire        store_en;
wire [8:0]  cnt_load_plus;
wire [8:0]  cnt_store_plus;
wire [8:0]  cnt_load_next;
wire [8:0]  cnt_store_next;
wire [8:0]  load_idx;

//============================================================
//  input buffer 
//============================================================
reg  [7:0]  shift_buf [0:2];  
reg  [7:0]  data_d;
reg  [17:0] cmd_d;

wire [2:0] cmd_now_hi  = cmd[13:11];
wire [2:0] cmd_lat_hi  = cmd_d[13:11];
wire [2:0] cmd_lat_mid = cmd_d[6:4];

reg [7:0] blk_in  [0:15][0:15];
reg [7:0] blk_out [0:15][0:15];
reg [7:0] buf_img [0:255];

reg [9:0] offset_r;
reg [2:0] src_r, src_c;

wire [7:0] px_tr      [0:255];
wire [7:0] px_tr2     [0:255];
wire [7:0] px_mx      [0:255];
wire [7:0] px_my      [0:255];
wire [7:0] px_r90     [0:255];
wire [7:0] px_r180    [0:255];
wire [7:0] px_r270    [0:255];
wire [7:0] px_shift_r [0:255];
wire [7:0] px_shift_l [0:255];
wire [7:0] px_shift_u [0:255];
wire [7:0] px_shift_d [0:255];

integer i, j;
genvar  idx_g;

//============================================================
//  MEM 
//============================================================

// MEM_0, MEM_1, MEM_2, MEM_3: 8-bit width, 4096 depth
wire        mem0_web, mem1_web, mem2_web, mem3_web;
wire [11:0] mem0_addr, mem1_addr, mem2_addr, mem3_addr;
wire  [7:0] mem0_din,  mem1_din,  mem2_din,  mem3_din;
wire  [7:0] mem0_dout, mem1_dout, mem2_dout, mem3_dout;

// MEM_4, MEM_5: 16-bit width, 2048 depth
wire        mem4_web, mem5_web;
wire [10:0] mem4_addr, mem5_addr;
wire [15:0] mem4_din,  mem5_din;
wire [15:0] mem4_dout, mem5_dout;

// MEM_6, MEM_7: 32-bit width, 1024 depth
wire        mem6_web, mem7_web;
wire  [9:0] mem6_addr, mem7_addr;
wire [31:0] mem6_din,  mem7_din;
wire [31:0] mem6_dout, mem7_dout;

//============================================================
//  Pipeline after SRAM & cnt_load delay
//============================================================
reg [8:0]  cnt_load_r;

reg [7:0]  mem0_dout_r, mem1_dout_r, mem2_dout_r, mem3_dout_r;
reg [15:0] mem4_dout_r, mem5_dout_r;
reg [31:0] mem6_dout_r, mem7_dout_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_load_r   <= 9'd0;
        mem0_dout_r  <= 8'd0;
        mem1_dout_r  <= 8'd0;
        mem2_dout_r  <= 8'd0;
        mem3_dout_r  <= 8'd0;
        mem4_dout_r  <= 16'd0;
        mem5_dout_r  <= 16'd0;
        mem6_dout_r  <= 32'd0;
        mem7_dout_r  <= 32'd0;
    end
    else begin
        cnt_load_r   <= cnt_load;
        mem0_dout_r  <= mem0_dout;
        mem1_dout_r  <= mem1_dout;
        mem2_dout_r  <= mem2_dout;
        mem3_dout_r  <= mem3_dout;
        mem4_dout_r  <= mem4_dout;
        mem5_dout_r  <= mem5_dout;
        mem6_dout_r  <= mem6_dout;
        mem7_dout_r  <= mem7_dout;
    end
end

//==================================================================
// FSM 
//==================================================================
localparam [3:0]
    S_IDLE      = 4'd0,
    S_READ_MEM  = 4'd1,
    S_AL        = 4'd2,
    S_AS        = 4'd3,
    S_BL        = 4'd4,
    S_BS        = 4'd5,
    S_CL        = 4'd6,
    S_CS        = 4'd7,
    S_STORE     = 4'd8,
    S_OUTPUT    = 4'd9;

always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		st_cur <= S_IDLE;
	else
		st_cur <= st_nxt;
end

wire is_now_A;
wire is_now_B;
wire is_now_C;
wire is_lat_A;
wire is_lat_B;
wire is_lat_C;

assign is_now_A = (cmd_now_hi[2] == 1'b0);
assign is_now_B = (cmd_now_hi[2:1] == 2'b10);
assign is_now_C = (cmd_now_hi[2:1] == 2'b11);

assign is_lat_A = (cmd_lat_mid[2] == 1'b0);
assign is_lat_B = (cmd_lat_mid[2:1] == 2'b10);
assign is_lat_C = (cmd_lat_mid[2:1] == 2'b11);

// ------------------------------------------------------------
//  Next state logic
// ------------------------------------------------------------
always @* begin
    st_nxt = st_cur;  // default: stay
	
    case (st_cur)
        S_IDLE: begin
            if (in_valid_data)
                st_nxt = S_READ_MEM;
        end

        S_READ_MEM: begin
            if (in_valid_cmd) begin
                if (is_now_A)
                    st_nxt = S_AL;
                else if (is_now_B)
                    st_nxt = S_BL;
                else if (is_now_C)
                    st_nxt = S_CL;
            end
        end

        S_AL: begin
            if (cnt_load == 9'd258)
                st_nxt = S_STORE;
        end

        S_BL: begin
            if (cnt_load == 9'd130)
                st_nxt = S_STORE;
        end

        S_CL: begin
            if (cnt_load == 9'd66)
                st_nxt = S_STORE;
        end

        S_STORE: begin
            if (is_lat_A)
                st_nxt = S_AS;
            else if (is_lat_B)
                st_nxt = S_BS;
            else if (is_lat_C)
                st_nxt = S_CS;
        end

        S_AS: begin
            if (cnt_store == 9'd256)
                st_nxt = S_OUTPUT;
        end

        S_BS: begin
            if (cnt_store == 9'd128)
                st_nxt = S_OUTPUT;
        end

        S_CS: begin
            if (cnt_store == 9'd64)
                st_nxt = S_OUTPUT;
        end

        S_OUTPUT: begin
            if (in_valid_cmd) begin
                if (is_now_A)
                    st_nxt = S_AL;
                else if (is_now_B)
                    st_nxt = S_BL;
                else if (is_now_C)
                    st_nxt = S_CL;
            end
        end

        default: begin
            st_nxt = S_IDLE;
        end
    endcase
end

//==================================================================
// Counters
//==================================================================
assign cnt_in_en    = (st_nxt == S_READ_MEM);
assign cnt_in_plus  = cnt_in + 16'd1;
assign cnt_in_next  = cnt_in_en ? cnt_in_plus : 16'd0;

always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		cnt_in <= 16'd0;
	else
		cnt_in <= cnt_in_next;
end

assign load_en        = (st_cur == S_AL) || (st_cur == S_BL) || (st_cur == S_CL);
assign cnt_load_plus  = cnt_load + 9'd1;
assign cnt_load_next  = load_en ? cnt_load_plus : 9'd0;

always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		cnt_load <= 9'd0;
	else
		cnt_load <= cnt_load_next;
end

assign store_en       = (st_cur == S_AS) || (st_cur == S_BS) || (st_cur == S_CS);
assign cnt_store_plus = cnt_store + 9'd1;
assign cnt_store_next = store_en ? cnt_store_plus : 9'd0;

always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		cnt_store <= 9'd0;
	else
		cnt_store <= cnt_store_next;
end

wire [8:0] load_idx_tmp = cnt_load_r - 9'd2;
assign load_idx = load_idx_tmp;

//==================================================================
// input & CMD
//==================================================================
always @(posedge clk or negedge rst_n) begin
	integer i;
	if (!rst_n) begin
		for (i = 0; i < 3; i = i + 1) begin
			shift_buf[i] <= 8'd0;
		end
	end
	else begin
		shift_buf[2] <= shift_buf[1];
		shift_buf[1] <= shift_buf[0];
		shift_buf[0] <= data_d;
	end
end

always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		cmd_d <= 18'd0;
	else if (in_valid_cmd)
		cmd_d <= cmd;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
		data_d <= 8'd0;
    else
		data_d <= data;
end

//==================================================================
// blk_in[][] & buf_img[] 
//==================================================================
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (i = 0; i < 16; i = i + 1) begin
			for (j = 0; j < 16; j = j + 1) begin
				blk_in[i][j] <= 8'd0;
			end
		end
		for (i = 0; i < 256; i = i + 1) begin
			buf_img[i] <= 8'd0;
		end
	end
	else begin
		case (cmd_d[13:11])
			3'b000: begin
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd258)) begin
					blk_in[load_idx/16][load_idx%16] <= mem0_dout_r;
					buf_img[load_idx]               <= mem0_dout_r;
				end
			end
			3'b001: begin
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd258)) begin
					blk_in[load_idx/16][load_idx%16] <= mem1_dout_r;
					buf_img[load_idx]               <= mem1_dout_r;
				end
			end
			3'b010: begin
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd258)) begin
					blk_in[load_idx/16][load_idx%16] <= mem2_dout_r;
					buf_img[load_idx]               <= mem2_dout_r;
				end
			end
			3'b011: begin
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd258)) begin
					blk_in[load_idx/16][load_idx%16] <= mem3_dout_r;
					buf_img[load_idx]               <= mem3_dout_r;
				end
			end
			3'b100: begin
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd130)) begin
					blk_in[2*load_idx/16][2*load_idx%16]             <= mem4_dout_r[15:8];
					blk_in[(2*load_idx+1)/16][(2*load_idx+1)%16]     <= mem4_dout_r[7:0];

					buf_img[2*load_idx]                              <= mem4_dout_r[15:8];
					buf_img[2*load_idx+1]                            <= mem4_dout_r[7:0];
				end
			end
			3'b101: begin
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd130)) begin
					blk_in[2*load_idx/16][2*load_idx%16]             <= mem5_dout_r[15:8];
					blk_in[(2*load_idx+1)/16][(2*load_idx+1)%16]     <= mem5_dout_r[7:0];

					buf_img[2*load_idx]                              <= mem5_dout_r[15:8];
					buf_img[2*load_idx+1]                            <= mem5_dout_r[7:0];
				end
			end
			3'b110: begin 
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd66)) begin
					blk_in[4*load_idx/16][4*load_idx%16]             <= mem6_dout_r[31:24];
					blk_in[(4*load_idx+1)/16][(4*load_idx+1)%16]     <= mem6_dout_r[23:16];
					blk_in[(4*load_idx+2)/16][(4*load_idx+2)%16]     <= mem6_dout_r[15:8];
					blk_in[(4*load_idx+3)/16][(4*load_idx+3)%16]     <= mem6_dout_r[7:0];

					buf_img[4*load_idx]                              <= mem6_dout_r[31:24];
					buf_img[4*load_idx+1]                            <= mem6_dout_r[23:16];
					buf_img[4*load_idx+2]                            <= mem6_dout_r[15:8];
					buf_img[4*load_idx+3]                            <= mem6_dout_r[7:0];
				end
			end
			3'b111: begin 
				if ((cnt_load_r > 9'd1) && (cnt_load_r < 9'd66)) begin
					blk_in[4*load_idx/16][4*load_idx%16]             <= mem7_dout_r[31:24];
					blk_in[(4*load_idx+1)/16][(4*load_idx+1)%16]     <= mem7_dout_r[23:16];
					blk_in[(4*load_idx+2)/16][(4*load_idx+2)%16]     <= mem7_dout_r[15:8];
					blk_in[(4*load_idx+3)/16][(4*load_idx+3)%16]     <= mem7_dout_r[7:0];

					buf_img[4*load_idx]                              <= mem7_dout_r[31:24];
					buf_img[4*load_idx+1]                            <= mem7_dout_r[23:16];
					buf_img[4*load_idx+2]                            <= mem7_dout_r[15:8];
					buf_img[4*load_idx+3]                            <= mem7_dout_r[7:0];
				end
			end
		endcase
	end
end

//==================================================================
// MX/MY/TR/R90/R180/R270/Shift
//==================================================================
generate
    for (idx_g = 0; idx_g < 256; idx_g = idx_g + 1) begin : GEOM_OPT
        wire [3:0] y_idx = idx_g[7:4];
        wire [3:0] x_idx = idx_g[3:0];

        wire [4:0] pad_x_ls_tmp = 5'd26 - x_idx;
        wire [4:0] pad_y_us_tmp = 5'd26 - y_idx;
        wire [3:0] pad_x_ls = pad_x_ls_tmp[3:0];
        wire [3:0] pad_x_rs = 4'd4  - x_idx;
        wire [3:0] pad_y_us = pad_y_us_tmp[3:0];
        wire [3:0] pad_y_ds = 4'd4  - y_idx;

        wire [7:0] idx_mx   = {~y_idx, x_idx};
        wire [7:0] idx_my   = {y_idx, ~x_idx};

        wire [7:0] idx_tr   = {x_idx, y_idx};
        wire [7:0] idx_tr2  = {~x_idx[3:0], ~y_idx[3:0]};

        wire [7:0] idx_r90  = {~x_idx[3:0],  y_idx};
        wire [7:0] idx_r180 = {~y_idx[3:0], ~x_idx[3:0]};
        wire [7:0] idx_r270 = { x_idx,      ~y_idx[3:0]};

        wire        cond_sr   = (x_idx >= 4'd5);
        wire [3:0]  sxr       = x_idx - 4'd5;
        wire [7:0] idx_shift_r = cond_sr ? {y_idx, sxr} : {y_idx, pad_x_rs};

        wire        cond_sl   = (x_idx <= 4'd10);
        wire [3:0]  sxl       = x_idx + 4'd5;
        wire [7:0] idx_shift_l = cond_sl ? {y_idx, sxl} : {y_idx, pad_x_ls};

        wire        cond_su    = (y_idx <= 4'd10);
        wire [3:0]  syu        = y_idx + 4'd5;
        wire [7:0] idx_shift_u = cond_su ? {syu, x_idx} : {pad_y_us, x_idx};
            
        wire        cond_sd    = (y_idx >= 4'd5);
        wire [3:0]  syd        = y_idx - 4'd5;
        wire [7:0] idx_shift_d = cond_sd ? {syd, x_idx} : {pad_y_ds, x_idx};

        assign px_mx[idx_g]       = buf_img[idx_mx];
        assign px_my[idx_g]       = buf_img[idx_my];
        assign px_tr[idx_g]       = buf_img[idx_tr];
        assign px_tr2[idx_g]      = buf_img[idx_tr2];

        assign px_r90[idx_g]      = buf_img[idx_r90];
        assign px_r180[idx_g]     = buf_img[idx_r180];
        assign px_r270[idx_g]     = buf_img[idx_r270];

        assign px_shift_r[idx_g]  = buf_img[idx_shift_r];
        assign px_shift_l[idx_g]  = buf_img[idx_shift_l];
        assign px_shift_u[idx_g]  = buf_img[idx_shift_u];
        assign px_shift_d[idx_g]  = buf_img[idx_shift_d];
    end
endgenerate

//==================================================================
// ZigZag / Morton LUT
//==================================================================
localparam logic [5:0] ZZ8_LUT [0:63] = '{
    6'o00, 6'o01, 6'o10, 6'o20, 6'o11, 6'o02, 6'o03, 6'o12,
    6'o21, 6'o30, 6'o40, 6'o31, 6'o22, 6'o13, 6'o04, 6'o05,
    6'o14, 6'o23, 6'o32, 6'o41, 6'o50, 6'o60, 6'o51, 6'o42,
    6'o33, 6'o24, 6'o15, 6'o06, 6'o07, 6'o16, 6'o25, 6'o34,
    6'o43, 6'o52, 6'o61, 6'o70, 6'o71, 6'o62, 6'o53, 6'o44,
    6'o35, 6'o26, 6'o17, 6'o27, 6'o36, 6'o45, 6'o54, 6'o63,
    6'o72, 6'o73, 6'o64, 6'o55, 6'o46, 6'o37, 6'o47, 6'o56,
    6'o65, 6'o74, 6'o75, 6'o66, 6'o57, 6'o67, 6'o76, 6'o77
};

wire [2:0] zz8_row [0:63];
wire [2:0] zz8_col [0:63];

genvar g8;
generate
    for (g8 = 0; g8 < 64; g8 = g8 + 1) begin : GEN_ZZ8_TABLE
        assign {zz8_row[g8], zz8_col[g8]} = ZZ8_LUT[g8];
    end
endgenerate

localparam logic [3:0] ZZ4_LUT [0:15] = '{
    4'b00_00, 4'b00_01, 4'b01_00, 4'b10_00,
    4'b01_01, 4'b00_10, 4'b00_11, 4'b01_10,
    4'b10_01, 4'b11_00, 4'b11_01, 4'b10_10,
    4'b01_11, 4'b10_11, 4'b11_10, 4'b11_11
};

wire [1:0] zz4_row [0:15];
wire [1:0] zz4_col [0:15];

genvar g4;
generate
    for (g4 = 0; g4 < 16; g4 = g4 + 1) begin : GEN_ZZ4_TABLE
        assign {zz4_row[g4], zz4_col[g4]} = ZZ4_LUT[g4];
    end
endgenerate

//==================================================================
// block-based transform px_zz4 / px_zz8 / px_mo4 / px_mo8
//==================================================================
wire [7:0] px_zz4 [0:255];
wire [7:0] px_zz8 [0:255];
wire [7:0] px_mo4 [0:255];
wire [7:0] px_mo8 [0:255];

genvar p;
generate
    for (p = 0; p < 256; p = p + 1) begin : GEN_BLOCK_XFORM
        wire [3:0] out_r = p[7:4];
        wire [3:0] out_c = p[3:0];

        wire [3:0] blk4_r_base = {out_r[3:2], 2'b00};
        wire [3:0] blk4_c_base = {out_c[3:2], 2'b00};
        wire [1:0] in4_r       = out_r[1:0];
        wire [1:0] in4_c       = out_c[1:0];
        wire [3:0] k4          = {in4_r, in4_c};

        wire [1:0] zz4_r_off   = zz4_row[k4];
        wire [1:0] zz4_c_off   = zz4_col[k4];
        wire [3:0] src4_r_zz   = blk4_r_base + zz4_r_off;
        wire [3:0] src4_c_zz   = blk4_c_base + zz4_c_off;

        wire [1:0] mo4_r_off   = {k4[3], k4[1]};
        wire [1:0] mo4_c_off   = {k4[2], k4[0]};
        wire [3:0] src4_r_mo   = blk4_r_base + mo4_r_off;
        wire [3:0] src4_c_mo   = blk4_c_base + mo4_c_off;

        wire [3:0] blk8_r_base = {out_r[3], 3'b000};
        wire [3:0] blk8_c_base = {out_c[3], 3'b000};
        wire [2:0] in8_r       = out_r[2:0];
        wire [2:0] in8_c       = out_c[2:0];
        wire [5:0] k8          = {in8_r, in8_c};

        wire [2:0] zz8_r_off   = zz8_row[k8];
        wire [2:0] zz8_c_off   = zz8_col[k8];
        wire [3:0] src8_r_zz   = blk8_r_base + zz8_r_off;
        wire [3:0] src8_c_zz   = blk8_c_base + zz8_c_off;

        wire [2:0] mo8_r_off   = {k8[5], k8[3], k8[1]};
        wire [2:0] mo8_c_off   = {k8[4], k8[2], k8[0]};
        wire [3:0] src8_r_mo   = blk8_r_base + mo8_r_off;
        wire [3:0] src8_c_mo   = blk8_c_base + mo8_c_off;

        assign px_zz4[p] = blk_in[src4_r_zz][src4_c_zz];
        assign px_mo4[p] = blk_in[src4_r_mo][src4_c_mo];
        assign px_zz8[p] = blk_in[src8_r_zz][src8_c_zz];
        assign px_mo8[p] = blk_in[src8_r_mo][src8_c_mo];
    end
endgenerate

//==================================================================
// blk_out[][]
//==================================================================
always @* begin
	integer r, c;
	integer flat_idx;

	for (r = 0; r < 16; r = r + 1) begin
		for (c = 0; c < 16; c = c + 1) begin
			flat_idx = (r << 4) + c;

			case (cmd_d[17:14])
				4'b0000: blk_out[r][c] = px_mx      [flat_idx];
				4'b0001: blk_out[r][c] = px_my      [flat_idx];
				4'b0010: blk_out[r][c] = px_tr      [flat_idx];
				4'b0011: blk_out[r][c] = px_tr2     [flat_idx];
				4'b0100: blk_out[r][c] = px_r90     [flat_idx];
				4'b0101: blk_out[r][c] = px_r180    [flat_idx];
				4'b0110: blk_out[r][c] = px_r270    [flat_idx];
				4'b1000: blk_out[r][c] = px_shift_r [flat_idx];
				4'b1001: blk_out[r][c] = px_shift_l [flat_idx];
				4'b1010: blk_out[r][c] = px_shift_u [flat_idx];
				4'b1011: blk_out[r][c] = px_shift_d [flat_idx];

				4'b1100: blk_out[r][c] = px_zz4 [flat_idx];
				4'b1101: blk_out[r][c] = px_zz8 [flat_idx];
				4'b1110: blk_out[r][c] = px_mo4 [flat_idx];
				4'b1111: blk_out[r][c] = px_mo8 [flat_idx];

				default: blk_out[r][c] = blk_in[r][c];
			endcase
		end
	end
end

//============================================================
// MEM0
//============================================================
reg  [11:0] mem0_addr_in;
reg         mem0_web_in;
reg  [7:0]  mem0_wb;

wire mem0_do_read  = (st_cur == S_READ_MEM) || (st_nxt == S_READ_MEM);
wire mem0_do_load  = (st_cur == S_AL)       || (st_nxt == S_OUTPUT);
wire mem0_do_store = (st_cur == S_AS)       && (cmd_d[5:4] == 2'd0);

wire [11:0] mem0_addr_read  = (cnt_in < 16'd4096) ? cnt_in[11:0] : 12'd0;
wire        mem0_web_read   = (cnt_in < 16'd4096) ? 1'b0         : 1'b1;

wire [11:0] mem0_addr_load  = cnt_load + cmd_d[10:7] * 12'd256;
wire [11:0] mem0_addr_store = cnt_store + 12'd256 * cmd_d[3:0];
wire [7:0]  mem0_wb_store   = blk_out[cnt_store/16][cnt_store%16];

reg [11:0] mem0_addr_n;
reg        mem0_web_n;
reg [7:0]  mem0_wb_n;

always @* begin
    mem0_addr_n = mem0_addr_in;
    mem0_web_n  = mem0_web_in;
    mem0_wb_n   = mem0_wb;

    casez ({mem0_do_read, mem0_do_load, mem0_do_store})
        3'b1??: begin
            mem0_addr_n = mem0_addr_read;
            mem0_web_n  = mem0_web_read;
        end
        3'b01?: begin
            mem0_addr_n = mem0_addr_load;
            mem0_web_n  = 1'b1;
        end
        3'b001: begin
            mem0_addr_n = mem0_addr_store;
            mem0_web_n  = 1'b0;
            mem0_wb_n   = mem0_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem0_addr_in <= 12'd0;
        mem0_web_in  <= 1'b1;
        mem0_wb      <= 8'd0;
    end
    else begin
        mem0_addr_in <= mem0_addr_n;
        mem0_web_in  <= mem0_web_n;
        mem0_wb      <= mem0_wb_n;
    end
end

assign mem0_addr = mem0_addr_in;
assign mem0_web  = mem0_web_in;
assign mem0_din  = (st_cur == S_READ_MEM) ? data_d : mem0_wb;

//============================================================
// MEM1
//============================================================
reg  [11:0] mem1_addr_in;
reg         mem1_web_in;
reg  [7:0]  mem1_wb;

wire mem1_do_read  = (st_cur == S_READ_MEM);
wire mem1_do_load  = (st_cur == S_AL) || (st_nxt == S_OUTPUT);
wire mem1_do_store = (st_cur == S_AS) && (cmd_d[5:4] == 2'd1);

wire [11:0] mem1_addr_read = (cnt_in < 16'd8192) ? (cnt_in - 16'd4096) : 12'd0;
wire        mem1_web_read  = ((cnt_in >= 16'd4096) && (cnt_in < 16'd8192)) ? 1'b0 : 1'b1;

wire [11:0] mem1_addr_load  = cnt_load + cmd_d[10:7] * 12'd256;
wire [11:0] mem1_addr_store = cnt_store + 12'd256 * cmd_d[3:0];
wire [7:0]  mem1_wb_store   = blk_out[cnt_store/16][cnt_store%16];

reg [11:0] mem1_addr_n;
reg        mem1_web_n;
reg [7:0]  mem1_wb_n;

always @* begin
    mem1_addr_n = mem1_addr_in;
    mem1_web_n  = mem1_web_in;
    mem1_wb_n   = mem1_wb;

    casez ({mem1_do_read, mem1_do_load, mem1_do_store})
        3'b1??: begin
            mem1_addr_n = mem1_addr_read;
            mem1_web_n  = mem1_web_read;
        end
        3'b01?: begin
            mem1_addr_n = mem1_addr_load;
            mem1_web_n  = 1'b1;
        end
        3'b001: begin
            mem1_addr_n = mem1_addr_store;
            mem1_web_n  = 1'b0;
            mem1_wb_n   = mem1_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem1_addr_in <= 12'd0;
        mem1_web_in  <= 1'b1;
        mem1_wb      <= 8'd0;
    end
    else begin
        mem1_addr_in <= mem1_addr_n;
        mem1_web_in  <= mem1_web_n;
        mem1_wb      <= mem1_wb_n;
    end
end

assign mem1_addr = mem1_addr_in;
assign mem1_web  = mem1_web_in;
assign mem1_din  = (st_cur == S_READ_MEM) ? data_d : mem1_wb;

//============================================================
// MEM2
//============================================================
reg  [11:0] mem2_addr_in;
reg         mem2_web_in;
reg  [7:0]  mem2_wb;

wire mem2_do_read  = (st_cur == S_READ_MEM);
wire mem2_do_load  = (st_cur == S_AL) || (st_nxt == S_OUTPUT);
wire mem2_do_store = (st_cur == S_AS) && (cmd_d[5:4] == 2'd2);

wire [11:0] mem2_addr_read = (cnt_in < 16'd12288) ? (cnt_in - 16'd8192) : 12'd0;
wire        mem2_web_read  = ((cnt_in >= 16'd8192) && (cnt_in < 16'd12288)) ? 1'b0 : 1'b1;

wire [11:0] mem2_addr_load  = cnt_load + cmd_d[10:7] * 12'd256;
wire [11:0] mem2_addr_store = cnt_store + 12'd256 * cmd_d[3:0];
wire [7:0]  mem2_wb_store   = blk_out[cnt_store/16][cnt_store%16];

reg [11:0] mem2_addr_n;
reg        mem2_web_n;
reg [7:0]  mem2_wb_n;

always @* begin
    mem2_addr_n = mem2_addr_in;
    mem2_web_n  = mem2_web_in;
    mem2_wb_n   = mem2_wb;

    casez ({mem2_do_read, mem2_do_load, mem2_do_store})
        3'b1??: begin
            mem2_addr_n = mem2_addr_read;
            mem2_web_n  = mem2_web_read;
        end
        3'b01?: begin
            mem2_addr_n = mem2_addr_load;
            mem2_web_n  = 1'b1;
        end
        3'b001: begin
            mem2_addr_n = mem2_addr_store;
            mem2_web_n  = 1'b0;
            mem2_wb_n   = mem2_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem2_addr_in <= 12'd0;
        mem2_web_in  <= 1'b1;
        mem2_wb      <= 8'd0;
    end
    else begin
        mem2_addr_in <= mem2_addr_n;
        mem2_web_in  <= mem2_web_n;
        mem2_wb      <= mem2_wb_n;
    end
end

assign mem2_addr = mem2_addr_in;
assign mem2_web  = mem2_web_in;
assign mem2_din  = (st_cur == S_READ_MEM) ? data_d : mem2_wb;

//============================================================
// MEM3
//============================================================
reg  [11:0] mem3_addr_in;
reg         mem3_web_in;
reg  [7:0]  mem3_wb;

wire mem3_do_read  = (st_cur == S_READ_MEM);
wire mem3_do_load  = (st_cur == S_AL) || (st_nxt == S_OUTPUT);
wire mem3_do_store = (st_cur == S_AS) && (cmd_d[5:4] == 2'd3);

wire [11:0] mem3_addr_read = (cnt_in < 16'd16384) ? (cnt_in - 16'd12288) : 12'd0;
wire        mem3_web_read  = ((cnt_in >= 16'd12288) && (cnt_in < 16'd16384)) ? 1'b0 : 1'b1;

wire [11:0] mem3_addr_load  = cnt_load + cmd_d[10:7] * 12'd256;
wire [11:0] mem3_addr_store = cnt_store + 12'd256 * cmd_d[3:0];
wire [7:0]  mem3_wb_store   = blk_out[cnt_store/16][cnt_store%16];

reg [11:0] mem3_addr_n;
reg        mem3_web_n;
reg [7:0]  mem3_wb_n;

always @* begin
    mem3_addr_n = mem3_addr_in;
    mem3_web_n  = mem3_web_in;
    mem3_wb_n   = mem3_wb;

    casez ({mem3_do_read, mem3_do_load, mem3_do_store})
        3'b1??: begin
            mem3_addr_n = mem3_addr_read;
            mem3_web_n  = mem3_web_read;
        end
        3'b01?: begin
            mem3_addr_n = mem3_addr_load;
            mem3_web_n  = 1'b1;
        end
        3'b001: begin
            mem3_addr_n = mem3_addr_store;
            mem3_web_n  = 1'b0;
            mem3_wb_n   = mem3_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem3_addr_in <= 12'd0;
        mem3_web_in  <= 1'b1;
        mem3_wb      <= 8'd0;
    end
    else begin
        mem3_addr_in <= mem3_addr_n;
        mem3_web_in  <= mem3_web_n;
        mem3_wb      <= mem3_wb_n;
    end
end

assign mem3_addr = mem3_addr_in;
assign mem3_web  = mem3_web_in;
assign mem3_din  = (st_cur == S_READ_MEM) ? data_d : mem3_wb;

//============================================================
// MEM4
//============================================================
reg  [10:0] mem4_addr_in;
reg         mem4_web_in;
reg  [15:0] mem4_din_reg;
reg  [15:0] mem4_wb;

wire mem4_do_read  = (st_cur == S_READ_MEM);
wire mem4_do_load  = (st_cur == S_BL) || (st_nxt == S_OUTPUT);
wire mem4_do_store = (st_cur == S_BS) && (cmd_d[5:4] == 2'd0);

wire [10:0] mem4_addr_read =
    (cnt_in < 16'd20481) ? ((cnt_in - 16'd16385) >> 1) : 11'd0;
wire        mem4_web_read  =
    ((cnt_in >= 16'd16385) && (cnt_in < 16'd20481) && (cnt_in[0] == 1'b0)) ? 1'b0 : 1'b1;

wire [10:0] mem4_addr_load  = cnt_load + cmd_d[10:7] * 11'd128;
wire [10:0] mem4_addr_store = cnt_store + 11'd128 * cmd_d[3:0];
wire [15:0] mem4_wb_store   = {
    blk_out[(2*cnt_store)   /16][(2*cnt_store)   %16],
    blk_out[(2*cnt_store+1) /16][(2*cnt_store+1) %16]
};

reg [10:0] mem4_addr_n;
reg        mem4_web_n;
reg [15:0] mem4_wb_n;

always @* begin
    mem4_addr_n = mem4_addr_in;
    mem4_web_n  = mem4_web_in;
    mem4_wb_n   = mem4_wb;

    casez ({mem4_do_read, mem4_do_load, mem4_do_store})
        3'b1??: begin
            mem4_addr_n = mem4_addr_read;
            mem4_web_n  = mem4_web_read;
        end
        3'b01?: begin
            mem4_addr_n = mem4_addr_load;
            mem4_web_n  = 1'b1;
        end
        3'b001: begin
            mem4_addr_n = mem4_addr_store;
            mem4_web_n  = 1'b0;
            mem4_wb_n   = mem4_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem4_addr_in <= 11'd0;
        mem4_web_in  <= 1'b1;
        mem4_din_reg <= 16'd0;
        mem4_wb      <= 16'd0;
    end
    else begin
        mem4_addr_in <= mem4_addr_n;
        mem4_web_in  <= mem4_web_n;
        mem4_wb      <= mem4_wb_n;

        if (st_cur == S_READ_MEM) begin
            mem4_din_reg <= {shift_buf[0], data_d};
        end
    end
end

assign mem4_addr = mem4_addr_in;
assign mem4_web  = mem4_web_in;
assign mem4_din  = (st_cur == S_READ_MEM) ? mem4_din_reg : mem4_wb;

//============================================================
// MEM5
//============================================================
reg  [10:0] mem5_addr_in;
reg         mem5_web_in;
reg  [15:0] mem5_din_reg;
reg  [15:0] mem5_wb;

wire mem5_do_read  = (st_cur == S_READ_MEM);
wire mem5_do_load  = (st_cur == S_BL) || (st_nxt == S_OUTPUT);
wire mem5_do_store = (st_cur == S_BS) && (cmd_d[5:4] == 2'd1);

wire [10:0] mem5_addr_read =
    (cnt_in < 16'd24577) ? ((cnt_in - 16'd20481) >> 1) : 11'd0;
wire        mem5_web_read  =
    ((cnt_in >= 16'd20481) && (cnt_in < 16'd24577) && (cnt_in[0] == 1'b0)) ? 1'b0 : 1'b1;

wire [10:0] mem5_addr_load  = cnt_load + cmd_d[10:7] * 11'd128;
wire [10:0] mem5_addr_store = cnt_store + 11'd128 * cmd_d[3:0];
wire [15:0] mem5_wb_store   = {
    blk_out[(2*cnt_store)   /16][(2*cnt_store)   %16],
    blk_out[(2*cnt_store+1) /16][(2*cnt_store+1) %16]
};

reg [10:0] mem5_addr_n;
reg        mem5_web_n;
reg [15:0] mem5_wb_n;

always @* begin
    mem5_addr_n = mem5_addr_in;
    mem5_web_n  = mem5_web_in;
    mem5_wb_n   = mem5_wb;

    casez ({mem5_do_read, mem5_do_load, mem5_do_store})
        3'b1??: begin
            mem5_addr_n = mem5_addr_read;
            mem5_web_n  = mem5_web_read;
        end
        3'b01?: begin
            mem5_addr_n = mem5_addr_load;
            mem5_web_n  = 1'b1;
        end
        3'b001: begin
            mem5_addr_n = mem5_addr_store;
            mem5_web_n  = 1'b0;
            mem5_wb_n   = mem5_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem5_addr_in <= 11'd0;
        mem5_web_in  <= 1'b1;
        mem5_din_reg <= 16'd0;
        mem5_wb      <= 16'd0;
    end
    else begin
        mem5_addr_in <= mem5_addr_n;
        mem5_web_in  <= mem5_web_n;
        mem5_wb      <= mem5_wb_n;

        if (st_cur == S_READ_MEM) begin
            mem5_din_reg <= {shift_buf[0], data_d};
        end
    end
end

assign mem5_addr = mem5_addr_in;
assign mem5_web  = mem5_web_in;
assign mem5_din  = (st_cur == S_READ_MEM) ? mem5_din_reg : mem5_wb;

//============================================================
// MEM6
//============================================================
reg  [9:0]  mem6_addr_in;
reg         mem6_web_in;
reg  [31:0] mem6_din_reg;
reg  [31:0] mem6_wb;

wire mem6_do_read  = (st_cur == S_READ_MEM);
wire mem6_do_load  = (st_cur == S_CL) || (st_nxt == S_OUTPUT);
wire mem6_do_store = (st_cur == S_CS) && (cmd_d[5:4] == 2'd2);

wire [9:0] mem6_addr_read =
    (cnt_in < 16'd28673) ? ((cnt_in - 16'd24577) >> 2) : 10'd0;
wire       mem6_web_read  =
    ((cnt_in >= 16'd24577) && (cnt_in < 16'd28673) && (cnt_in[1:0] == 2'b00)) ? 1'b0 : 1'b1;

wire [9:0]  mem6_addr_load  = cnt_load + cmd_d[10:7] * 10'd64;
wire [9:0]  mem6_addr_store = cnt_store + 10'd64 * cmd_d[3:0];
wire [31:0] mem6_wb_store   = {
    blk_out[(4*cnt_store)   /16][(4*cnt_store)   %16],
    blk_out[(4*cnt_store+1) /16][(4*cnt_store+1) %16],
    blk_out[(4*cnt_store+2) /16][(4*cnt_store+2) %16],
    blk_out[(4*cnt_store+3) /16][(4*cnt_store+3) %16]
};

reg [9:0]  mem6_addr_n;
reg        mem6_web_n;
reg [31:0] mem6_wb_n;

always @* begin
    mem6_addr_n = mem6_addr_in;
    mem6_web_n  = mem6_web_in;
    mem6_wb_n   = mem6_wb;

    casez ({mem6_do_read, mem6_do_load, mem6_do_store})
        3'b1??: begin
            mem6_addr_n = mem6_addr_read;
            mem6_web_n  = mem6_web_read;
        end
        3'b01?: begin
            mem6_addr_n = mem6_addr_load;
            mem6_web_n  = 1'b1;
        end
        3'b001: begin
            mem6_addr_n = mem6_addr_store;
            mem6_web_n  = 1'b0;
            mem6_wb_n   = mem6_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem6_addr_in <= 10'd0;
        mem6_web_in  <= 1'b1;
        mem6_din_reg <= 32'd0;
        mem6_wb      <= 32'd0;
    end
    else begin
        mem6_addr_in <= mem6_addr_n;
        mem6_web_in  <= mem6_web_n;
        mem6_wb      <= mem6_wb_n;

        if (st_cur == S_READ_MEM) begin
            mem6_din_reg <= {shift_buf[2], shift_buf[1], shift_buf[0], data_d};
        end
    end
end

assign mem6_addr = mem6_addr_in;
assign mem6_web  = mem6_web_in;
assign mem6_din  = (st_cur == S_READ_MEM) ? mem6_din_reg : mem6_wb;

//============================================================
// MEM7
//============================================================
reg  [9:0]  mem7_addr_in;
reg         mem7_web_in;
reg  [31:0] mem7_din_reg;
reg  [31:0] mem7_wb;

wire mem7_do_read  = (st_cur == S_READ_MEM);
wire mem7_do_load  = (st_cur == S_CL) || (st_nxt == S_OUTPUT);
wire mem7_do_store = (st_cur == S_CS) && (cmd_d[5:4] == 2'd3);

wire [9:0] mem7_addr_read =
    (cnt_in < 16'd32769) ? ((cnt_in - 16'd28673) >> 2) : 10'd0;
wire       mem7_web_read  =
    ((cnt_in >= 16'd28673) && (cnt_in < 16'd32769) && (cnt_in[1:0] == 2'b00)) ? 1'b0 : 1'b1;

wire [9:0]  mem7_addr_load  = cnt_load + cmd_d[10:7] * 10'd64;
wire [9:0]  mem7_addr_store = cnt_store + 10'd64 * cmd_d[3:0];
wire [31:0] mem7_wb_store   = {
    blk_out[(4*cnt_store)   /16][(4*cnt_store)   %16],
    blk_out[(4*cnt_store+1) /16][(4*cnt_store+1) %16],
    blk_out[(4*cnt_store+2) /16][(4*cnt_store+2) %16],
    blk_out[(4*cnt_store+3) /16][(4*cnt_store+3) %16]
};

reg [9:0]  mem7_addr_n;
reg        mem7_web_n;
reg [31:0] mem7_wb_n;

always @* begin
    mem7_addr_n = mem7_addr_in;
    mem7_web_n  = mem7_web_in;
    mem7_wb_n   = mem7_wb;

    casez ({mem7_do_read, mem7_do_load, mem7_do_store})
        3'b1??: begin
            mem7_addr_n = mem7_addr_read;
            mem7_web_n  = mem7_web_read;
        end
        3'b01?: begin
            mem7_addr_n = mem7_addr_load;
            mem7_web_n  = 1'b1;
        end
        3'b001: begin
            mem7_addr_n = mem7_addr_store;
            mem7_web_n  = 1'b0;
            mem7_wb_n   = mem7_wb_store;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem7_addr_in <= 10'd0;
        mem7_web_in  <= 1'b1;
        mem7_din_reg <= 32'd0;
        mem7_wb      <= 32'd0;
    end
    else begin
        mem7_addr_in <= mem7_addr_n;
        mem7_web_in  <= mem7_web_n;
        mem7_wb      <= mem7_wb_n;

        if (st_cur == S_READ_MEM) begin
            mem7_din_reg <= {shift_buf[2], shift_buf[1], shift_buf[0], data_d};
        end
    end
end

assign mem7_addr = mem7_addr_in;
assign mem7_web  = mem7_web_in;
assign mem7_din  = (st_cur == S_READ_MEM) ? mem7_din_reg : mem7_wb;

//==================================================================
// busy 
//==================================================================
wire to_S_OUTPUT = (st_cur != S_OUTPUT) && (st_nxt == S_OUTPUT);
wire busy_next   = to_S_OUTPUT ? 1'b0 : 1'b1;

always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		busy <= 1'b1;
	else
		busy <= busy_next;
end

//==================================================================
// SRAM Instantiation
//==================================================================
SUMA180_4096X8X1BM4 MEM0(
    .A0(mem0_addr[0]), .A1(mem0_addr[1]), .A2(mem0_addr[2]), .A3(mem0_addr[3]), .A4(mem0_addr[4]), .A5(mem0_addr[5]), .A6(mem0_addr[6]), .A7(mem0_addr[7]), 
    .A8(mem0_addr[8]), .A9(mem0_addr[9]), .A10(mem0_addr[10]), .A11(mem0_addr[11]),
    .DO0(mem0_dout[0]), .DO1(mem0_dout[1]), .DO2(mem0_dout[2]), .DO3(mem0_dout[3]), .DO4(mem0_dout[4]), .DO5(mem0_dout[5]), .DO6(mem0_dout[6]), .DO7(mem0_dout[7]),
    .DI0(mem0_din[0]), .DI1(mem0_din[1]), .DI2(mem0_din[2]), .DI3(mem0_din[3]), .DI4(mem0_din[4]), .DI5(mem0_din[5]), .DI6(mem0_din[6]), .DI7(mem0_din[7]),
    .CK(clk), .WEB(mem0_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_4096X8X1BM4 MEM1(
    .A0(mem1_addr[0]), .A1(mem1_addr[1]), .A2(mem1_addr[2]), .A3(mem1_addr[3]), .A4(mem1_addr[4]), .A5(mem1_addr[5]), .A6(mem1_addr[6]), .A7(mem1_addr[7]), 
    .A8(mem1_addr[8]), .A9(mem1_addr[9]), .A10(mem1_addr[10]), .A11(mem1_addr[11]),
    .DO0(mem1_dout[0]), .DO1(mem1_dout[1]), .DO2(mem1_dout[2]), .DO3(mem1_dout[3]), .DO4(mem1_dout[4]), .DO5(mem1_dout[5]), .DO6(mem1_dout[6]), .DO7(mem1_dout[7]),
    .DI0(mem1_din[0]), .DI1(mem1_din[1]), .DI2(mem1_din[2]), .DI3(mem1_din[3]), .DI4(mem1_din[4]), .DI5(mem1_din[5]), .DI6(mem1_din[6]), .DI7(mem1_din[7]),
    .CK(clk), .WEB(mem1_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_4096X8X1BM4 MEM2 (
    .A0(mem2_addr[0]), .A1(mem2_addr[1]), .A2(mem2_addr[2]), .A3(mem2_addr[3]), .A4(mem2_addr[4]), .A5(mem2_addr[5]), .A6(mem2_addr[6]), .A7(mem2_addr[7]),
    .A8(mem2_addr[8]), .A9(mem2_addr[9]), .A10(mem2_addr[10]), .A11(mem2_addr[11]),
    .DO0(mem2_dout[0]), .DO1(mem2_dout[1]), .DO2(mem2_dout[2]), .DO3(mem2_dout[3]), .DO4(mem2_dout[4]), .DO5(mem2_dout[5]), .DO6(mem2_dout[6]), .DO7(mem2_dout[7]),
    .DI0(mem2_din[0]), .DI1(mem2_din[1]), .DI2(mem2_din[2]), .DI3(mem2_din[3]), .DI4(mem2_din[4]), .DI5(mem2_din[5]), .DI6(mem2_din[6]), .DI7(mem2_din[7]),
    .CK(clk), .WEB(mem2_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_4096X8X1BM4 MEM3(
    .A0(mem3_addr[0]), .A1(mem3_addr[1]), .A2(mem3_addr[2]), .A3(mem3_addr[3]), .A4(mem3_addr[4]), .A5(mem3_addr[5]), .A6(mem3_addr[6]), .A7(mem3_addr[7]), 
    .A8(mem3_addr[8]), .A9(mem3_addr[9]), .A10(mem3_addr[10]), .A11(mem3_addr[11]),
    .DO0(mem3_dout[0]), .DO1(mem3_dout[1]), .DO2(mem3_dout[2]), .DO3(mem3_dout[3]), .DO4(mem3_dout[4]), .DO5(mem3_dout[5]), .DO6(mem3_dout[6]), .DO7(mem3_dout[7]),
    .DI0(mem3_din[0]), .DI1(mem3_din[1]), .DI2(mem3_din[2]), .DI3(mem3_din[3]), .DI4(mem3_din[4]), .DI5(mem3_din[5]), .DI6(mem3_din[6]), .DI7(mem3_din[7]),
    .CK(clk), .WEB(mem3_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_2048X16X1BM1 MEM4(
	.A0(mem4_addr[0]), .A1(mem4_addr[1]), .A2(mem4_addr[2]), .A3(mem4_addr[3]), .A4(mem4_addr[4]), .A5(mem4_addr[5]), .A6(mem4_addr[6]), .A7(mem4_addr[7]), 
	.A8(mem4_addr[8]), .A9(mem4_addr[9]), .A10(mem4_addr[10]),
	.DO0(mem4_dout[0]), .DO1(mem4_dout[1]), .DO2(mem4_dout[2]), .DO3(mem4_dout[3]), .DO4(mem4_dout[4]), .DO5(mem4_dout[5]), .DO6(mem4_dout[6]), .DO7(mem4_dout[7]), 
	.DO8(mem4_dout[8]), .DO9(mem4_dout[9]), .DO10(mem4_dout[10]), .DO11(mem4_dout[11]), .DO12(mem4_dout[12]), .DO13(mem4_dout[13]), .DO14(mem4_dout[14]), .DO15(mem4_dout[15]),
	.DI0(mem4_din[0]), .DI1(mem4_din[1]), .DI2(mem4_din[2]), .DI3(mem4_din[3]), .DI4(mem4_din[4]), .DI5(mem4_din[5]), .DI6(mem4_din[6]), .DI7(mem4_din[7]), 
	.DI8(mem4_din[8]), .DI9(mem4_din[9]), .DI10(mem4_din[10]), .DI11(mem4_din[11]), .DI12(mem4_din[12]), .DI13(mem4_din[13]), .DI14(mem4_din[14]), .DI15(mem4_din[15]),
	.CK(clk), .WEB(mem4_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_2048X16X1BM1 MEM5(
	.A0(mem5_addr[0]), .A1(mem5_addr[1]), .A2(mem5_addr[2]), .A3(mem5_addr[3]), .A4(mem5_addr[4]), .A5(mem5_addr[5]), .A6(mem5_addr[6]), .A7(mem5_addr[7]), 
	.A8(mem5_addr[8]), .A9(mem5_addr[9]), .A10(mem5_addr[10]),
	.DO0(mem5_dout[0]), .DO1(mem5_dout[1]), .DO2(mem5_dout[2]), .DO3(mem5_dout[3]), .DO4(mem5_dout[4]), .DO5(mem5_dout[5]), .DO6(mem5_dout[6]), .DO7(mem5_dout[7]), 
	.DO8(mem5_dout[8]), .DO9(mem5_dout[9]), .DO10(mem5_dout[10]), .DO11(mem5_dout[11]), .DO12(mem5_dout[12]), .DO13(mem5_dout[13]), .DO14(mem5_dout[14]), .DO15(mem5_dout[15]),
	.DI0(mem5_din[0]), .DI1(mem5_din[1]), .DI2(mem5_din[2]), .DI3(mem5_din[3]), .DI4(mem5_din[4]), .DI5(mem5_din[5]), .DI6(mem5_din[6]), .DI7(mem5_din[7]), 
	.DI8(mem5_din[8]), .DI9(mem5_din[9]), .DI10(mem5_din[10]), .DI11(mem5_din[11]), .DI12(mem5_din[12]), .DI13(mem5_din[13]), .DI14(mem5_din[14]), .DI15(mem5_din[15]),
	.CK(clk), .WEB(mem5_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_1024X32X1BM2 MEM6(
	.A0(mem6_addr[0]), .A1(mem6_addr[1]), .A2(mem6_addr[2]), .A3(mem6_addr[3]), .A4(mem6_addr[4]), .A5(mem6_addr[5]), .A6(mem6_addr[6]), .A7(mem6_addr[7]), 
	.A8(mem6_addr[8]), .A9(mem6_addr[9]),
	.DO0(mem6_dout[0]), .DO1(mem6_dout[1]), .DO2(mem6_dout[2]), .DO3(mem6_dout[3]), .DO4(mem6_dout[4]), .DO5(mem6_dout[5]), .DO6(mem6_dout[6]), .DO7(mem6_dout[7]), 
	.DO8(mem6_dout[8]), .DO9(mem6_dout[9]), .DO10(mem6_dout[10]), .DO11(mem6_dout[11]), .DO12(mem6_dout[12]), .DO13(mem6_dout[13]), .DO14(mem6_dout[14]), .DO15(mem6_dout[15]), 
	.DO16(mem6_dout[16]), .DO17(mem6_dout[17]), .DO18(mem6_dout[18]), .DO19(mem6_dout[19]), .DO20(mem6_dout[20]), .DO21(mem6_dout[21]), .DO22(mem6_dout[22]), .DO23(mem6_dout[23]), 
	.DO24(mem6_dout[24]), .DO25(mem6_dout[25]), .DO26(mem6_dout[26]), .DO27(mem6_dout[27]), .DO28(mem6_dout[28]), .DO29(mem6_dout[29]), .DO30(mem6_dout[30]), .DO31(mem6_dout[31]),
	.DI0(mem6_din[0]), .DI1(mem6_din[1]), .DI2(mem6_din[2]), .DI3(mem6_din[3]), .DI4(mem6_din[4]), .DI5(mem6_din[5]), .DI6(mem6_din[6]), .DI7(mem6_din[7]), 
	.DI8(mem6_din[8]), .DI9(mem6_din[9]), .DI10(mem6_din[10]), .DI11(mem6_din[11]), .DI12(mem6_din[12]), .DI13(mem6_din[13]), .DI14(mem6_din[14]), .DI15(mem6_din[15]), 
	.DI16(mem6_din[16]), .DI17(mem6_din[17]), .DI18(mem6_din[18]), .DI19(mem6_din[19]), .DI20(mem6_din[20]), .DI21(mem6_din[21]), .DI22(mem6_din[22]), .DI23(mem6_din[23]), 
	.DI24(mem6_din[24]), .DI25(mem6_din[25]), .DI26(mem6_din[26]), .DI27(mem6_din[27]), .DI28(mem6_din[28]), .DI29(mem6_din[29]), .DI30(mem6_din[30]), .DI31(mem6_din[31]),
	.CK(clk), .WEB(mem6_web), .OE(1'b1), .CS(1'b1)
);

SUMA180_1024X32X1BM2 MEM7(
	.A0(mem7_addr[0]), .A1(mem7_addr[1]), .A2(mem7_addr[2]), .A3(mem7_addr[3]), .A4(mem7_addr[4]), .A5(mem7_addr[5]), .A6(mem7_addr[6]), .A7(mem7_addr[7]), 
	.A8(mem7_addr[8]), .A9(mem7_addr[9]),
	.DO0(mem7_dout[0]), .DO1(mem7_dout[1]), .DO2(mem7_dout[2]), .DO3(mem7_dout[3]), .DO4(mem7_dout[4]), .DO5(mem7_dout[5]), .DO6(mem7_dout[6]), .DO7(mem7_dout[7]), 
	.DO8(mem7_dout[8]), .DO9(mem7_dout[9]), .DO10(mem7_dout[10]), .DO11(mem7_dout[11]), .DO12(mem7_dout[12]), .DO13(mem7_dout[13]), .DO14(mem7_dout[14]), .DO15(mem7_dout[15]), 
	.DO16(mem7_dout[16]), .DO17(mem7_dout[17]), .DO18(mem7_dout[18]), .DO19(mem7_dout[19]), .DO20(mem7_dout[20]), .DO21(mem7_dout[21]), .DO22(mem7_dout[22]), .DO23(mem7_dout[23]), 
	.DO24(mem7_dout[24]), .DO25(mem7_dout[25]), .DO26(mem7_dout[26]), .DO27(mem7_dout[27]), .DO28(mem7_dout[28]), .DO29(mem7_dout[29]), .DO30(mem7_dout[30]), .DO31(mem7_dout[31]),
	.DI0(mem7_din[0]), .DI1(mem7_din[1]), .DI2(mem7_din[2]), .DI3(mem7_din[3]), .DI4(mem7_din[4]), .DI5(mem7_din[5]), .DI6(mem7_din[6]), .DI7(mem7_din[7]), 
	.DI8(mem7_din[8]), .DI9(mem7_din[9]), .DI10(mem7_din[10]), .DI11(mem7_din[11]), .DI12(mem7_din[12]), .DI13(mem7_din[13]), .DI14(mem7_din[14]), .DI15(mem7_din[15]), 
	.DI16(mem7_din[16]), .DI17(mem7_din[17]), .DI18(mem7_din[18]), .DI19(mem7_din[19]), .DI20(mem7_din[20]), .DI21(mem7_din[21]), .DI22(mem7_din[22]), .DI23(mem7_din[23]), 
	.DI24(mem7_din[24]), .DI25(mem7_din[25]), .DI26(mem7_din[26]), .DI27(mem7_din[27]), .DI28(mem7_din[28]), .DI29(mem7_din[29]), .DI30(mem7_din[30]), .DI31(mem7_din[31]),
	.CK(clk), .WEB(mem7_web), .OE(1'b1), .CS(1'b1)
);

endmodule
