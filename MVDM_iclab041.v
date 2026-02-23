module MVDM(
    // input signals
    clk,
    rst_n,
    in_valid, 
    in_valid2,
    in_data,
    // output signals
    out_valid,
    out_sad
);

input clk;
input rst_n;
input in_valid;
input in_valid2;
input [8:0] in_data;

output reg out_valid;
output reg out_sad;

//=======================================================
//                   Reg/Wire
//=======================================================
wire [127:0] mem_dout00, mem_dout01, mem_dout10, mem_dout11;
reg  [8:0]   mem_addr00, mem_addr01, mem_addr10, mem_addr11;
reg          mem_web00, mem_web01, mem_web10, mem_web11; 
reg  [5:0] st_q;
reg  [5:0] st_d;
reg [3:0] gotload_cnt, SATD_cnt;
reg [3:0] pointer_out;
reg [5:0] got_cnt,out_cnt;
reg [6:0] math_cnt;
reg [7:0] pointer1_end, pointer2_end; 
reg [7:0] win_l0 [0:14], win_l1 [0:14];
reg [7:0] L0P1_end, L0P2_end, L1P1_end, L1P2_end;
reg [16:0] in_cnt;
reg [23:0] SATD_out;
reg [27:0] OUT_REG;
reg [127:0] img_shift_reg;

reg [8:0] L0P1_MVx;
reg [8:0] L0P1_MVy;
reg [8:0] L1P1_MVx;
reg [8:0] L1P1_MVy;
reg [8:0] L0P2_MVx;
reg [8:0] L0P2_MVy;
reg [8:0] L1P2_MVx;
reg [8:0] L1P2_MVy;
wire finishing_flag;
reg busy_flag_L0, busy_flag_L1;
reg busy_flag;
reg [1:0] swap_sel;
reg [255:0] mem_concat_l0, mem_concat_l1;
wire [20:0] val_out_l0 [0:9], val_out_l1 [0:9];
reg signed [14:0] filtbuf_l0 [0:99], filtbuf_l1 [0:99];
reg signed [9:0] diff0 [0:31], diff1 [0:31], diff2 [0:31], diff3 [0:31], diff4 [0:31], diff5 [0:31], diff6 [0:31], diff7 [0:31], diff8 [0:31];

reg [23:0] satd_acc [0:8];
wire [23:0] satd_sum [0:8];
reg  signed [9:0] diff_in [0:8][0:31];
integer kk, i, j;
always @(*) begin
    for (kk=0; kk<32; kk=kk+1) begin
        diff_in[0][kk] = diff0[kk];
        diff_in[1][kk] = diff1[kk];
        diff_in[2][kk] = diff2[kk];
        diff_in[3][kk] = diff3[kk];
        diff_in[4][kk] = diff4[kk];
        diff_in[5][kk] = diff5[kk];
        diff_in[6][kk] = diff6[kk];
        diff_in[7][kk] = diff7[kk];
        diff_in[8][kk] = diff8[kk];
    end
end

reg [55:0] out_reg;
reg [5:0] L0L1_skew, L1L0_skew;
reg OUTPUT_finish_flg;

parameter [5:0] ST_IDLE      = 6'h01;
parameter [5:0] ST_LOAD_IMG  = 6'h02;
parameter [5:0] ST_WAIT      = 6'h04;
parameter [5:0] ST_LOAD_INS  = 6'h08;
parameter [5:0] ST_EXE       = 6'h10;
parameter [5:0] ST_OUT       = 6'h20;

genvar gi;

parameter [7:0] op_end_no        = 8'h10;
parameter [7:0] op_end_hori      = 8'h10;
parameter [7:0] op_end_verti     = 8'h15;
parameter [7:0] op_end_horiverti = 8'h20;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        st_q <= ST_IDLE;
    else
        st_q <= st_d;
end

always @(*) begin
    st_d = st_q;

    if (st_q[0]) begin 
        if (in_valid) st_d = ST_LOAD_IMG;
        else          st_d = ST_IDLE;
    end
    else if (st_q[1]) begin
        if (in_valid) st_d = ST_LOAD_IMG;
        else          st_d = ST_WAIT;
    end
    else if (st_q[2]) begin
        if (in_valid2) st_d = ST_LOAD_INS;
        else           st_d = ST_WAIT;
    end
    else if (st_q[3]) begin 
        if (gotload_cnt == 3) st_d = ST_EXE;
        else                        st_d = ST_LOAD_INS;
    end
    else if (st_q[4]) begin
        if (finishing_flag) st_d = ST_OUT;
        else                st_d = ST_EXE;
    end
    else if (st_q[5]) begin 
        if (OUTPUT_finish_flg) begin
            if (got_cnt == 6'h3F) st_d = ST_IDLE;
            else                    st_d = ST_WAIT;
        end else begin
            st_d = ST_OUT;
        end
    end
    else begin
        st_d = ST_IDLE;
    end
end

// finish flags 
wire output_is_last;
assign output_is_last = (out_cnt == 6'h37);

always @(*) begin
    OUTPUT_finish_flg = output_is_last;
end

wire p1_done;
assign p1_done = (math_cnt > (pointer1_end - 1));

always @(*) begin
    busy_flag = p1_done;
end

wire exe_done_cond;
assign exe_done_cond = (math_cnt > (pointer1_end + pointer2_end - 26));

assign finishing_flag = (exe_done_cond & busy_flag);


// finish time max selection
wire p1_sel_l0;
assign p1_sel_l0 = (L0P1_end >= L1P1_end);

always @(*) begin
    pointer1_end = p1_sel_l0 ? L0P1_end : L1P1_end;
end

wire p2_sel_l0;
assign p2_sel_l0 = (L0P2_end >= L1P2_end);

always @(*) begin
    pointer2_end = p2_sel_l0 ? L0P2_end : L1P2_end;
end

// per-layer finish time decode
always @(*) begin
    case ({L0P1_MVx[0], L0P1_MVy[0]})
        2'b11: L0P1_end = op_end_horiverti;
        2'b10: L0P1_end = op_end_hori;
        2'b01: L0P1_end = op_end_verti;
        default: L0P1_end = op_end_no;
    endcase
end

always @(*) begin
    case ({L1P1_MVx[0], L1P1_MVy[0]})
        2'b11: L1P1_end = op_end_horiverti;
        2'b10: L1P1_end = op_end_hori;
        2'b01: L1P1_end = op_end_verti;
        default: L1P1_end = op_end_no;
    endcase
end

always @(*) begin
    case ({L0P2_MVx[0], L0P2_MVy[0]})
        2'b11: L0P2_end = op_end_horiverti;
        2'b10: L0P2_end = op_end_hori;
        2'b01: L0P2_end = op_end_verti;
        default: L0P2_end = op_end_no;
    endcase
end

always @(*) begin
    case ({L1P2_MVx[0], L1P2_MVy[0]})
        2'b11: L1P2_end = op_end_horiverti;
        2'b10: L1P2_end = op_end_hori;
        2'b01: L1P2_end = op_end_verti;
        default: L1P2_end = op_end_no;
    endcase
end

reg  [15:0] in_cnt_n;   
wire        load_cnt_clr;
wire        load_cnt_inc;

assign load_cnt_inc = in_valid;
assign load_cnt_clr = st_q[5]; 

always @(*) begin
    in_cnt_n = in_cnt;
    if (load_cnt_inc)      in_cnt_n = in_cnt + 1'b1;
    else if (load_cnt_clr) in_cnt_n = {16{1'b0}};
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) in_cnt <= {16{1'b0}};
    else        in_cnt <= in_cnt_n;
end
wire inst_cnt_fire;
assign inst_cnt_fire = st_q[5] & OUTPUT_finish_flg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) got_cnt <= {16{1'b0}};   
    else if (inst_cnt_fire) got_cnt <= got_cnt + 1'b1;
end
wire inst_ld_en;
assign inst_ld_en = in_valid2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) gotload_cnt <= {16{1'b0}}; 
    else if (inst_ld_en) gotload_cnt <= gotload_cnt + 1'b1;
    else gotload_cnt <= {16{1'b0}};
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        L0P1_MVx <= {9{1'b0}};  L0P1_MVy <= {9{1'b0}};
        L1P1_MVx <= {9{1'b0}};  L1P1_MVy <= {9{1'b0}};
        L0P2_MVx <= {9{1'b0}};  L0P2_MVy <= {9{1'b0}};
        L1P2_MVx <= {9{1'b0}};  L1P2_MVy <= {9{1'b0}};
    end else if (in_valid2) begin
        case (gotload_cnt[2:0])
            3'd0: L0P1_MVx <= in_data;
            3'd1: L0P1_MVy <= in_data;
            3'd2: L1P1_MVx <= in_data;
            3'd3: L1P1_MVy <= in_data;
            3'd4: L0P2_MVx <= in_data;
            3'd5: L0P2_MVy <= in_data;
            3'd6: L1P2_MVx <= in_data;
            3'd7: L1P2_MVy <= in_data;
            // default: do nothing (hold value)
        endcase
    end
end
wire cal_cnt_run;
assign cal_cnt_run = (st_q[4] | st_q[5]);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) math_cnt <= {16{1'b0}};      
    else if (cal_cnt_run) math_cnt <= math_cnt + 1'b1;
    else math_cnt <= {16{1'b0}};
end
wire satd_win_p1;
wire satd_win_p2;
wire satd_cnt_en;

assign satd_win_p1 = (math_cnt > (pointer1_end - 9)) & (~busy_flag);
assign satd_win_p2 = (math_cnt > (pointer1_end + pointer2_end - 9)) & ( busy_flag);
assign satd_cnt_en = satd_win_p1 | satd_win_p2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) SATD_cnt <= {16{1'b0}};      
    else if (satd_cnt_en) SATD_cnt <= SATD_cnt + 1'b1;
    else SATD_cnt <= {16{1'b0}};
end
wire img_sh_en;
wire img_sh_clr;

assign img_sh_en  = in_valid;
assign img_sh_clr = (st_q[2] | st_q[0]);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) img_shift_reg <= {128{1'b0}};
    else if (img_sh_en) img_shift_reg <= {img_shift_reg[119:0], in_data[8:1]};
    else if (img_sh_clr) img_shift_reg <= {128{1'b0}};
end

// MVx select (P1/P2) : one place only
wire [7:0] mvx_l0_i = busy_flag ? L0P2_MVx[8:1] : L0P1_MVx[8:1];
wire [3:0] mvx_l0_s = busy_flag ? L0P2_MVx[4:1] : L0P1_MVx[4:1];

wire [7:0] mvx_l1_i = busy_flag ? L1P2_MVx[8:1] : L1P1_MVx[8:1];
wire [3:0] mvx_l1_s = busy_flag ? L1P2_MVx[4:1] : L1P1_MVx[4:1];

reg  [7:0] base_byte_l0;
reg  [7:0] base_byte_l1;
reg  [3:0] idx_l0;
reg  [3:0] idx_l1;
reg [119:0] pad_l0, pad_l1;

always @(*) begin
    // default
    pad_l0 = mem_concat_l0[255 - 14*8 -: 120]; 
    idx_l0 = mvx_l0_s;

    // edge cases on integer MVx
    case (mvx_l0_i)
        8'd0:   pad_l0 = {mem_concat_l0[127:120], mem_concat_l0[127:120], mem_concat_l0[127:24]};
        8'd1:   pad_l0 = {mem_concat_l0[127:120], mem_concat_l0[127:16]};
        8'd116: pad_l0 = {mem_concat_l0[239:128], mem_concat_l0[135:128]};
        8'd117: pad_l0 = {mem_concat_l0[239:128], mem_concat_l0[135:128], mem_concat_l0[135:128]};
        default: begin
            // middle area uses mvx_l0_s mapping 
            if (idx_l0 == 4'd0)      pad_l0 = mem_concat_l0[255 - 14*8 -: 120];
            else if (idx_l0 == 4'd1) pad_l0 = mem_concat_l0[255 - 15*8 -: 120];
            else                     pad_l0 = mem_concat_l0[255 - (idx_l0 - 4'd2)*8 -: 120];
        end
    endcase
end

always @(*) begin
    pad_l1 = mem_concat_l1[255 - 14*8 -: 120];
    idx_l1 = mvx_l1_s;

    case (mvx_l1_i)
        8'd0:   pad_l1 = {mem_concat_l1[127:120], mem_concat_l1[127:120], mem_concat_l1[127:24]};
        8'd1:   pad_l1 = {mem_concat_l1[127:120], mem_concat_l1[127:16]};
        8'd116: pad_l1 = {mem_concat_l1[239:128], mem_concat_l1[135:128]};
        8'd117: pad_l1 = {mem_concat_l1[231:128], mem_concat_l1[135:128], mem_concat_l1[135:128]};
        default: begin
            if (idx_l1 == 4'd0)      pad_l1 = mem_concat_l1[255 - 14*8 -: 120];
            else if (idx_l1 == 4'd1) pad_l1 = mem_concat_l1[255 - 15*8 -: 120];
            else                     pad_l1 = mem_concat_l1[255 - (idx_l1 - 4'd2)*8 -: 120];
        end
    endcase
end

//  win_l0 / win_l1
integer k;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (k = 0; k < 15; k = k + 1)
            win_l0[k] <= 8'd0;
    end else if (st_q[4] | st_q[5]) begin
        for (k = 0; k < 15; k = k + 1)
            win_l0[k] <= pad_l0[(14-k)*8 +: 8];   // win[14]=pad[7:0] ... win[0]=pad[119:112]
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (k = 0; k < 15; k = k + 1)
            win_l1[k] <= 8'd0;
    end else if (st_q[4] | st_q[5]) begin
        for (k = 0; k < 15; k = k + 1)
            win_l1[k] <= pad_l1[(14-k)*8 +: 8];
    end
end

// shift10_l0 / shift10_l1
wire use_filt_l0 = ( (~busy_flag &  L0P1_MVx[0] & L0P1_MVy[0]) |
                     ( busy_flag &  L0P2_MVx[0] & L0P2_MVy[0]) );

wire use_filt_l1 = ( (~busy_flag &  L1P1_MVx[0] & L1P1_MVy[0]) |
                     ( busy_flag &  L1P2_MVx[0] & L1P2_MVy[0]) );

// 10x 15-bit seeds (NOT packed 80-bit)
reg signed [14:0] seed_l0 [0:9];
reg signed [14:0] seed_l1 [0:9];
reg signed [14:0] shift10_l0 [0:59], shift10_l1 [0:59];

integer s;

// build seed from filtbuf (15b) or pad (8b -> zero-extend to 15b)
always @(*) begin
    for (s = 0; s < 10; s = s + 1) begin
        seed_l0[s] = 15'sd0;
        seed_l1[s] = 15'sd0;
    end

    if (use_filt_l0) begin
        for (s = 0; s < 10; s = s + 1)
            seed_l0[s] = filtbuf_l0[s];          // keep signed [14:0]
    end else begin
        // shift10[9..0] <= pad[31:24]..pad[103:96]
        seed_l0[9] = {7'd0, pad_l0[31:24]};
        seed_l0[8] = {7'd0, pad_l0[39:32]};
        seed_l0[7] = {7'd0, pad_l0[47:40]};
        seed_l0[6] = {7'd0, pad_l0[55:48]};
        seed_l0[5] = {7'd0, pad_l0[63:56]};
        seed_l0[4] = {7'd0, pad_l0[71:64]};
        seed_l0[3] = {7'd0, pad_l0[79:72]};
        seed_l0[2] = {7'd0, pad_l0[87:80]};
        seed_l0[1] = {7'd0, pad_l0[95:88]};
        seed_l0[0] = {7'd0, pad_l0[103:96]};
    end

    if (use_filt_l1) begin
        for (s = 0; s < 10; s = s + 1)
            seed_l1[s] = filtbuf_l1[s];
    end else begin
        seed_l1[9] = {7'd0, pad_l1[31:24]};
        seed_l1[8] = {7'd0, pad_l1[39:32]};
        seed_l1[7] = {7'd0, pad_l1[47:40]};
        seed_l1[6] = {7'd0, pad_l1[55:48]};
        seed_l1[5] = {7'd0, pad_l1[63:56]};
        seed_l1[4] = {7'd0, pad_l1[71:64]};
        seed_l1[3] = {7'd0, pad_l1[79:72]};
        seed_l1[2] = {7'd0, pad_l1[87:80]};
        seed_l1[1] = {7'd0, pad_l1[95:88]};
        seed_l1[0] = {7'd0, pad_l1[103:96]};
    end
end

integer t0, t1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (t0 = 0; t0 < 60; t0 = t0 + 1)
            shift10_l0[t0] <= 15'sd0;
    end else begin
        for (t0 = 0; t0 < 10; t0 = t0 + 1)
            shift10_l0[t0] <= seed_l0[t0];

        for (t0 = 10; t0 < 60; t0 = t0 + 1)
            shift10_l0[t0] <= shift10_l0[t0 - 10];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (t1 = 0; t1 < 60; t1 = t1 + 1)
            shift10_l1[t1] <= 15'sd0;
    end else begin
        for (t1 = 0; t1 < 10; t1 = t1 + 1)
            shift10_l1[t1] <= seed_l1[t1];

        for (t1 = 10; t1 < 60; t1 = t1 + 1)
            shift10_l1[t1] <= shift10_l1[t1 - 10];
    end
end

//  Val generation
function automatic signed [20:0] Val(
    input signed [14:0] P0,P1,P2,P3,P4,P5
);
begin
    // keep constant-mul form for synthesis optimization
    Val = (P0 + P5) + (20*P2) + (20*P3) - (5*P1) - (5*P4);
end
endfunction
wire mvx0_L0 = busy_flag ? L0P2_MVx[0] : L0P1_MVx[0];
wire mvy0_L0 = busy_flag ? L0P2_MVy[0] : L0P1_MVy[0];
wire mvx0_L1 = busy_flag ? L1P2_MVx[0] : L1P1_MVx[0];
wire mvy0_L1 = busy_flag ? L1P2_MVy[0] : L1P1_MVy[0];

wire th_ok_L0 = busy_flag ? (math_cnt > (pointer1_end + 18)) : (math_cnt > 18);
wire th_ok_L1 = busy_flag ? (math_cnt > (pointer1_end + 19)) : (math_cnt > 19);

wire en_shift_L0 = ((~mvx0_L0) & (mvy0_L0)) | (mvx0_L0 & mvy0_L0 & th_ok_L0);
wire en_win_L0   = (mvx0_L0 & ~mvy0_L0) | (mvx0_L0 & mvy0_L0 & ~th_ok_L0); 

wire en_shift_L1 = ((~mvx0_L1) & (mvy0_L1)) | (mvx0_L1 & mvy0_L1 & th_ok_L1);
wire en_win_L1   = (mvx0_L1 & ~mvy0_L1) | (mvx0_L1 & mvy0_L1 & ~th_ok_L1);

wire [14:0] mS_L0 = {15{en_shift_L0}};
wire [14:0] mW_L0 = {15{en_win_L0}};
wire [14:0] mS_L1 = {15{en_shift_L1}};
wire [14:0] mW_L1 = {15{en_win_L1}};

genvar gi;
generate
  for (gi = 0; gi < 10; gi = gi + 1) begin : GEN_VAL

    wire [14:0] t0_l0 = (mS_L0 & shift10_l0[gi    ]) | (mW_L0 & win_l0[gi    ]);
    wire [14:0] t1_l0 = (mS_L0 & shift10_l0[gi+10 ]) | (mW_L0 & win_l0[gi+1  ]);
    wire [14:0] t2_l0 = (mS_L0 & shift10_l0[gi+20 ]) | (mW_L0 & win_l0[gi+2  ]);
    wire [14:0] t3_l0 = (mS_L0 & shift10_l0[gi+30 ]) | (mW_L0 & win_l0[gi+3  ]);
    wire [14:0] t4_l0 = (mS_L0 & shift10_l0[gi+40 ]) | (mW_L0 & win_l0[gi+4  ]);
    wire [14:0] t5_l0 = (mS_L0 & shift10_l0[gi+50 ]) | (mW_L0 & win_l0[gi+5  ]);

    assign val_out_l0[gi] = Val($signed(t0_l0),$signed(t1_l0),$signed(t2_l0),
                                $signed(t3_l0),$signed(t4_l0),$signed(t5_l0));

    // L1 taps
    wire [14:0] t0_l1 = (mS_L1 & shift10_l1[gi    ]) | (mW_L1 & win_l1[gi    ]);
    wire [14:0] t1_l1 = (mS_L1 & shift10_l1[gi+10 ]) | (mW_L1 & win_l1[gi+1  ]);
    wire [14:0] t2_l1 = (mS_L1 & shift10_l1[gi+20 ]) | (mW_L1 & win_l1[gi+2  ]);
    wire [14:0] t3_l1 = (mS_L1 & shift10_l1[gi+30 ]) | (mW_L1 & win_l1[gi+3  ]);
    wire [14:0] t4_l1 = (mS_L1 & shift10_l1[gi+40 ]) | (mW_L1 & win_l1[gi+4  ]);
    wire [14:0] t5_l1 = (mS_L1 & shift10_l1[gi+50 ]) | (mW_L1 & win_l1[gi+5  ]);

    assign val_out_l1[gi] = Val($signed(t0_l1),$signed(t1_l1),$signed(t2_l1),
                                $signed(t3_l1),$signed(t4_l1),$signed(t5_l1));
  end
endgenerate

//  filtbuf_l0 / filtbuf_l1
wire exe_go = (st_q[4] | st_q[5]);

wire mvx0_l0 = busy_flag ? L0P2_MVx[0] : L0P1_MVx[0];
wire mvy0_l0 = busy_flag ? L0P2_MVy[0] : L0P1_MVy[0];
wire mvx0_l1 = busy_flag ? L1P2_MVx[0] : L1P1_MVx[0];
wire mvy0_l1 = busy_flag ? L1P2_MVy[0] : L1P1_MVy[0];

wire th_ok_f = busy_flag ? (math_cnt > (pointer1_end + 19)) : (math_cnt > 19);
wire hv_l0   = mvx0_l0 & mvy0_l0;
wire noop_l0 = (~mvx0_l0) & (~mvy0_l0);
wire hv_l1   = mvx0_l1 & mvy0_l1;
wire noop_l1 = (~mvx0_l1) & (~mvy0_l1);


integer kb;

// L0
function automatic [7:0] Layer1_clip(
    input signed [14:0] in_number
);
    reg signed [14:0] q;
begin
    q = (in_number + 15'sd16) >>> 5;
    if (q[14])              Layer1_clip = 8'd0;       // negative
    else if (q > 15'sd255)  Layer1_clip = 8'd255;     // overflow
    else                    Layer1_clip = q[7:0];
end
endfunction
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (kb=0; kb<100; kb=kb+1) filtbuf_l0[kb] <= 15'sd0;
  end else if (!exe_go) begin
    for (kb=0; kb<100; kb=kb+1) filtbuf_l0[kb] <= 15'sd0;
  end else begin
    // shift
    for (kb=0; kb<90; kb=kb+1) filtbuf_l0[kb] <= filtbuf_l0[kb+10];

    // tail [90..99]  (mode is constant across kb, hoist condition out of the loop)
    if (hv_l0) begin
      for (kb=0; kb<10; kb=kb+1) begin
        if (th_ok_f)  filtbuf_l0[kb+90] <= Layer2_clip(val_out_l0[kb]);
        else          filtbuf_l0[kb+90] <= val_out_l0[kb];
      end
    end else if (noop_l0) begin
      for (kb=0; kb<10; kb=kb+1) begin
        filtbuf_l0[kb+90] <= win_l0[kb+2];
      end
    end else begin
      for (kb=0; kb<10; kb=kb+1) begin
        filtbuf_l0[kb+90] <= Layer1_clip(val_out_l0[kb][14:0]);
      end
    end
  end
end

// L1
function automatic [7:0] Layer2_clip(
    input signed [20:0] in_number
);
    reg signed [20:0] q;
begin
    q = (in_number + 21'sd512) >>> 10;
    if (q[20])              Layer2_clip = 8'd0;
    else if (q > 21'sd255)  Layer2_clip = 8'd255;
    else                    Layer2_clip = q[7:0];
end
endfunction
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (kb=0; kb<100; kb=kb+1) filtbuf_l1[kb] <= 15'sd0;
  end else if (!exe_go) begin
    for (kb=0; kb<100; kb=kb+1) filtbuf_l1[kb] <= 15'sd0;
  end else begin
    // shift
    for (kb=0; kb<90; kb=kb+1) filtbuf_l1[kb] <= filtbuf_l1[kb+10];

    // tail [90..99]
    if (hv_l1) begin
      for (kb=0; kb<10; kb=kb+1) begin
        if (th_ok_f)  filtbuf_l1[kb+90] <= Layer2_clip(val_out_l1[kb]);
        else          filtbuf_l1[kb+90] <= val_out_l1[kb];
      end
    end else if (noop_l1) begin
      for (kb=0; kb<10; kb=kb+1) begin
        filtbuf_l1[kb+90] <= win_l1[kb+2];
      end
    end else begin
      for (kb=0; kb<10; kb=kb+1) begin
        filtbuf_l1[kb+90] <= Layer1_clip(val_out_l1[kb][14:0]);
      end
    end
  end
end


//  diff & SATD 
// bank base index helper
function automatic [5:0] base_l0;
    input [3:0] b;
    begin
        case (b)
            4'd0: base_l0 = 6'd0;
            4'd1: base_l0 = 6'd10;
            4'd2: base_l0 = 6'd20;
            4'd3: base_l0 = 6'd1;
            4'd4: base_l0 = 6'd11;
            4'd5: base_l0 = 6'd21;
            4'd6: base_l0 = 6'd2;
            4'd7: base_l0 = 6'd12;
            default: base_l0 = 6'd22; // b=8
        endcase
    end
endfunction

function automatic [5:0] base_l1;
    input [3:0] b;
    begin
        case (b)
            4'd0: base_l1 = 6'd22;
            4'd1: base_l1 = 6'd12;
            4'd2: base_l1 = 6'd2;
            4'd3: base_l1 = 6'd21;
            4'd4: base_l1 = 6'd11;
            4'd5: base_l1 = 6'd1;
            4'd6: base_l1 = 6'd20;
            4'd7: base_l1 = 6'd10;
            default: base_l1 = 6'd0;  // b=8
        endcase
    end
endfunction

integer bi, bj;

// shift-register style update for all 9 banks at once
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (bi = 0; bi < 9; bi = bi + 1)
            for (bj = 0; bj < 32; bj = bj + 1)
                diff_in[bi][bj] <= 10'sd0;
    end else begin
        for (bi = 0; bi < 9; bi = bi + 1) begin
            // shift older 24 entries
            for (bj = 0; bj < 24; bj = bj + 1)
                diff_in[bi][bj] <= diff_in[bi][bj + 8];

            // push 8 new diffs into tail
            for (bj = 0; bj < 8; bj = bj + 1)
                diff_in[bi][bj + 24] <=
                    filtbuf_l0[70 + base_l0(bi[3:0]) + bj] -
                    filtbuf_l1[70 + base_l1(bi[3:0]) + bj];
        end
    end
end

SATD_BANK9 u_satd_bank (
    .diff_in(diff_in),
    .satd_out(satd_sum)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 9; i = i + 1)
            satd_acc[i] <= 24'd0;
    end else begin
        if (SATD_cnt == 0) begin
            for (i = 0; i < 9; i = i + 1)
                satd_acc[i] <= 24'd0;
        end
        else if ((SATD_cnt == 3) || (SATD_cnt == 7)) begin
            for (i = 0; i < 9; i = i + 1)
                satd_acc[i] <= satd_acc[i] + satd_sum[i];
        end
    end
end

integer mi;
always @(*) begin
    pointer_out = 4'd0;
    SATD_out  = satd_acc[0];
    for (mi = 1; mi < 9; mi = mi + 1) begin
        if (satd_acc[mi] < SATD_out) begin
            SATD_out  = satd_acc[mi];
            pointer_out = mi[3:0];
        end
    end
end

//  output pack + serialize 
reg st5_d;  // st_q[5] delayed for edge detect

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st5_d          <= 1'b0;
        out_cnt <= 6'd0;       // 56 bits needs 6 bits (0~55)
        out_reg        <= 56'd0;
        out_valid      <= 1'b0;
        out_sad        <= 1'b0;
    end else begin
        // default outputs
        out_valid <= 1'b0;
        out_sad   <= 1'b0;
        // record previous st_q[5]
        st5_d <= st_q[5];

        // out_reg update points
        if (st_q[0] || st_q[2]) begin
            out_reg <= 56'd0;
        end else if (math_cnt == pointer1_end) begin
            out_reg <= {28'b0, pointer_out, SATD_out};
        end else if (math_cnt == (pointer1_end + pointer2_end)) begin
            out_reg <= {pointer_out, SATD_out, out_reg[27:0]};
        end

        // serialize when st_q[5] is high
        if (st_q[5]) begin
            out_valid <= 1'b1;
            out_sad   <= out_reg[out_cnt];

            // if just entered OUTPUT -> start from 0
            if (!st5_d) begin
                out_cnt <= 6'd1;  
            end else begin
                out_cnt <= out_cnt + 6'd1;
            end
        end else begin
            out_cnt <= 6'd0;
        end
    end
end


MEM128_512 L0P1 (
    .A   (mem_addr00),
    .DI  (img_shift_reg),
    .DO  (mem_dout00),
    .CK  (clk),
    .WEB (mem_web00),
    .OE  (1'b1),
    .CS  (1'b1)
);

MEM128_512 L0P2 (
    .A   (mem_addr01),
    .DI  (img_shift_reg),
    .DO  (mem_dout01),
    .CK  (clk),
    .WEB (mem_web01),
    .OE  (1'b1),
    .CS  (1'b1)
);

MEM128_512 L1P1 (
    .A   (mem_addr10),
    .DI  (img_shift_reg),
    .DO  (mem_dout10),
    .CK  (clk),
    .WEB (mem_web10),
    .OE  (1'b1),
    .CS  (1'b1)
);

MEM128_512 L1P2 (
    .A   (mem_addr11),
    .DI  (img_shift_reg),
    .DO  (mem_dout11),
    .CK  (clk),
    .WEB (mem_web11),
    .OE  (1'b1),
    .CS  (1'b1)
);

wire write_req = st_q[1] && (in_cnt[15] == 1'b0);
wire [1:0] bank_sel = {in_cnt[14], in_cnt[4]};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_web00 <= 1'b1;
        mem_web01 <= 1'b1;
        mem_web10 <= 1'b1;
        mem_web11 <= 1'b1;
    end else begin
        mem_web00 <= ~(write_req & (bank_sel == 2'b00));
        mem_web01 <= ~(write_req & (bank_sel == 2'b01));
        mem_web10 <= ~(write_req & (bank_sel == 2'b10));
        mem_web11 <= ~(write_req & (bank_sel == 2'b11));
    end
end

reg [7:0] val_A, val_B;
reg [7:0] abs_diff;

always @(*) begin
    val_A = (!busy_flag) ? L0P1_end : L0P2_end;
    val_B = (!busy_flag) ? L1P1_end : L1P2_end;
    
    abs_diff = (val_A > val_B) ? (val_A - val_B) : (val_B - val_A);

    L0L1_skew = (val_A > val_B) ? abs_diff[5:0] : 6'd0;
    L1L0_skew = (val_A > val_B) ? 6'd0 : abs_diff[5:0];
end

//  L0 mem_addr00/01 (rewrite: event flags + base calc)
wire do_load_img = st_q[1];
wire do_stream   = (st_q[4] | st_q[5]);

wire hit_p1_l0    = (math_cnt == (32'd0 + L1L0_skew));
wire hit_p2_l0    = (math_cnt == (pointer1_end + L1L0_skew));
wire hit_p1_inc1  = (math_cnt == (32'd1 + L1L0_skew));
wire hit_p1_inc2  = (math_cnt == (32'd2 + L1L0_skew));
wire hit_p2_inc1  = (math_cnt == (pointer1_end + 32'd1 + L1L0_skew));
wire hit_p2_inc2  = (math_cnt == (pointer1_end + 32'd2 + L1L0_skew));

wire p1_l0_y_block1 = (L0P1_MVy[8:1] < 2) & (L0P1_MVy[0] == 1'b1);
wire p1_l0_y_block2 = (L0P1_MVy[8:1] < 1) & (L0P1_MVy[0] == 1'b1);
wire p2_l0_y_block1 = (L0P2_MVy[8:1] < 2) & (L0P2_MVy[0] == 1'b1);
wire p2_l0_y_block2 = (L0P2_MVy[8:1] < 1) & (L0P2_MVy[0] == 1'b1);

function automatic [8:0] Clip_clamp(
    input [6:0] Y_addr,
    input [1:0] X_addr
);
    reg [6:0] y_base;
begin
    // clamp top border: y=0/1 -> 0, else y-2
    case (Y_addr)
        7'd0, 7'd1: y_base = 7'd0;
        default   : y_base = Y_addr - 7'd2;
    endcase
    Clip_clamp = {y_base, X_addr};
end
endfunction
wire [8:0] base_p1_l0 = (L0P1_MVy[0]) ? Clip_clamp(L0P1_MVy[7:1], L0P1_MVx[7:6])
                                      : {L0P1_MVy[7:1], L0P1_MVx[7:6]};
wire [8:0] base_p2_l0 = (L0P2_MVy[0]) ? Clip_clamp(L0P2_MVy[7:1], L0P2_MVx[7:6])
                                      : {L0P2_MVy[7:1], L0P2_MVx[7:6]};

wire p1_l0_right = (L0P1_MVx[5:1] >= 18);
wire p2_l0_right = (L0P2_MVx[5:1] >= 18);

wire p1_l0_left_ok = (L0P1_MVx[5:1] > 1);
wire p2_l0_left_ok = (L0P2_MVx[5:1] > 1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_addr00 <= 9'd0;
        mem_addr01 <= 9'd0;
    end else begin
        if (do_load_img) begin
            mem_addr00 <= in_cnt[13:5];
            mem_addr01 <= in_cnt[13:5];
        end else if (hit_p1_l0) begin
            // addr00: base (+1 if right boundary)
            mem_addr00 <= base_p1_l0 + (p1_l0_right ? 9'd1 : 9'd0);
            // addr01: base (-1 if left boundary)
            mem_addr01 <= base_p1_l0 + (p1_l0_left_ok ? 9'd0 : -9'd1);
        end else if (hit_p2_l0) begin
            mem_addr00 <= base_p2_l0 + (p2_l0_right ? 9'd1 : 9'd0);
            mem_addr01 <= base_p2_l0 + (p2_l0_left_ok ? 9'd0 : -9'd1);
        end else if (hit_p1_inc1) begin
            if (!p1_l0_y_block1) begin
                mem_addr00 <= mem_addr00 + 9'd4;
                mem_addr01 <= mem_addr01 + 9'd4;
            end
        end else if (hit_p1_inc2) begin
            if (!p1_l0_y_block2) begin
                mem_addr00 <= mem_addr00 + 9'd4;
                mem_addr01 <= mem_addr01 + 9'd4;
            end
        end else if (hit_p2_inc1) begin
            if (!p2_l0_y_block1) begin
                mem_addr00 <= mem_addr00 + 9'd4;
                mem_addr01 <= mem_addr01 + 9'd4;
            end
        end else if (hit_p2_inc2) begin
            if (!p2_l0_y_block2) begin
                mem_addr00 <= mem_addr00 + 9'd4;
                mem_addr01 <= mem_addr01 + 9'd4;
            end
        end else if (do_stream) begin
            if (mem_addr00[8:2] != 7'd127) mem_addr00 <= mem_addr00 + 9'd4;
            if (mem_addr01[8:2] != 7'd127) mem_addr01 <= mem_addr01 + 9'd4;
        end
    end
end

//  L1 mem_addr10/11
wire hit_p1_l1    = (math_cnt == (32'd0 + L0L1_skew));
wire hit_p2_l1    = (math_cnt == (pointer1_end + L0L1_skew));
wire hit_p1_l1i1  = (math_cnt == (32'd1 + L0L1_skew));
wire hit_p1_l1i2  = (math_cnt == (32'd2 + L0L1_skew));
wire hit_p2_l1i1  = (math_cnt == (pointer1_end + 32'd1 + L0L1_skew));
wire hit_p2_l1i2  = (math_cnt == (pointer1_end + 32'd2 + L0L1_skew));

wire p1_l1_y_block1 = (L1P1_MVy[8:1] < 2) & (L1P1_MVy[0] == 1'b1);
wire p1_l1_y_block2 = (L1P1_MVy[8:1] < 1) & (L1P1_MVy[0] == 1'b1);
wire p2_l1_y_block1 = (L1P2_MVy[8:1] < 2) & (L1P2_MVy[0] == 1'b1);
wire p2_l1_y_block2 = (L1P2_MVy[8:1] < 1) & (L1P2_MVy[0] == 1'b1);

wire [8:0] base_p1_l1 = (L1P1_MVy[0]) ? Clip_clamp(L1P1_MVy[7:1], L1P1_MVx[7:6])
                                      : {L1P1_MVy[7:1], L1P1_MVx[7:6]};
wire [8:0] base_p2_l1 = (L1P2_MVy[0]) ? Clip_clamp(L1P2_MVy[7:1], L1P2_MVx[7:6])
                                      : {L1P2_MVy[7:1], L1P2_MVx[7:6]};

wire p1_l1_right = (L1P1_MVx[5:1] >= 18);
wire p2_l1_right = (L1P2_MVx[5:1] >= 18);

wire p1_l1_left_ok = (L1P1_MVx[5:1] > 1);
wire p2_l1_left_ok = (L1P2_MVx[5:1] > 1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_addr10 <= 9'd0;
        mem_addr11 <= 9'd0;
    end else begin
        if (do_load_img) begin
            mem_addr10 <= in_cnt[13:5];
            mem_addr11 <= in_cnt[13:5];
        end else if (hit_p1_l1) begin
            mem_addr10 <= base_p1_l1 + (p1_l1_right ? 9'd1 : 9'd0);
            mem_addr11 <= base_p1_l1 + (p1_l1_left_ok ? 9'd0 : -9'd1);
        end else if (hit_p2_l1) begin
            mem_addr10 <= base_p2_l1 + (p2_l1_right ? 9'd1 : 9'd0);
            mem_addr11 <= base_p2_l1 + (p2_l1_left_ok ? 9'd0 : -9'd1);
        end else if (hit_p1_l1i1) begin
            if (!p1_l1_y_block1) begin
                mem_addr10 <= mem_addr10 + 9'd4;
                mem_addr11 <= mem_addr11 + 9'd4;
            end
        end else if (hit_p1_l1i2) begin
            if (!p1_l1_y_block2) begin
                mem_addr10 <= mem_addr10 + 9'd4;
                mem_addr11 <= mem_addr11 + 9'd4;
            end
        end else if (hit_p2_l1i1) begin
            if (!p2_l1_y_block1) begin
                mem_addr10 <= mem_addr10 + 9'd4;
                mem_addr11 <= mem_addr11 + 9'd4;
            end
        end else if (hit_p2_l1i2) begin
            if (!p2_l1_y_block2) begin
                mem_addr10 <= mem_addr10 + 9'd4;
                mem_addr11 <= mem_addr11 + 9'd4;
            end
        end else if (do_stream) begin
            if (mem_addr10[8:2] != 7'd127) mem_addr10 <= mem_addr10 + 9'd4;
            if (mem_addr11[8:2] != 7'd127) mem_addr11 <= mem_addr11 + 9'd4;
        end
    end
end

reg [4:0] x_check_l0;
reg [4:0] x_check_l1;

always @(*) begin
    x_check_l0 = L0P2_MVx[5:1];
    x_check_l1 = L1P2_MVx[5:1];
    
    if (gotload_cnt == 4) begin
        x_check_l0 = L0P1_MVx[5:1];
        x_check_l1 = L1P1_MVx[5:1];
    end
end

wire normal_cond_l0 = (x_check_l0 > 5'd1 && x_check_l0 < 5'd18);
wire normal_cond_l1 = (x_check_l1 > 5'd1 && x_check_l1 < 5'd18);

reg is_normal_l0;
reg is_normal_l1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        is_normal_l0 <= 0;
        is_normal_l1 <= 0;
    end else begin
        if ((gotload_cnt == 4) || (math_cnt == pointer1_end - 1)) begin
            is_normal_l0 <= normal_cond_l0;
            is_normal_l1 <= normal_cond_l1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_concat_l0 <= 0;
        mem_concat_l1 <= 0;
    end else begin
        if (is_normal_l0)
            mem_concat_l0 <= {mem_dout00, mem_dout01};
        else
            mem_concat_l0 <= {mem_dout01, mem_dout00};
        // L1 
        if (is_normal_l1)
            mem_concat_l1 <= {mem_dout10, mem_dout11};
        else
            mem_concat_l1 <= {mem_dout11, mem_dout10};
    end
end

endmodule

module SATD_BANK9 (
    input  signed [9:0] diff_in [0:8][0:31],
    output [23:0]        satd_out [0:8]
);
    genvar gi;
    generate
        for (gi=0; gi<9; gi=gi+1) begin : G_SATD
            SATD4x4 u_satd (.data_in(diff_in[gi]), .SATD_sum(satd_out[gi]));
        end
    endgenerate
endmodule

module SATD4x4 (
    input  signed [9:0] data_in [0:31],
    output [23:0]        SATD_sum
);
    // helper: absolute value
    function automatic [15:0] abs16;
        input signed [15:0] x;
        begin
            abs16 = x[15] ? (~x + 16'sd1) : x;
        end
    endfunction

    wire signed [11:0] d [0:1][0:3][0:3]; // [blk][r][c]
    genvar br, bc;
    generate
        for (br=0; br<4; br=br+1) begin: GEN_R
            for (bc=0; bc<4; bc=bc+1) begin: GEN_C
                assign d[0][br][bc] = data_in[br*8 + bc];
                assign d[1][br][bc] = data_in[br*8 + (bc+4)];
            end
        end
    endgenerate

    wire signed [13:0] rH [0:1][0:3][0:3]; // [blk][r][k]
    genvar r;
    generate
        for (r=0; r<4; r=r+1) begin: GEN_ROW
            // blk0 row butterflies
            wire signed [13:0] a00, a01, a02, a03;
            assign a00 = d[0][r][0] + d[0][r][3];
            assign a01 = d[0][r][1] + d[0][r][2];
            assign a02 = d[0][r][1] - d[0][r][2];
            assign a03 = d[0][r][0] - d[0][r][3];
            assign rH[0][r][0] = a00 + a01;
            assign rH[0][r][1] = a03 + a02;
            assign rH[0][r][2] = a00 - a01;
            assign rH[0][r][3] = a03 - a02;

            // blk1 row butterflies
            wire signed [13:0] b00, b01, b02, b03;
            assign b00 = d[1][r][0] + d[1][r][3];
            assign b01 = d[1][r][1] + d[1][r][2];
            assign b02 = d[1][r][1] - d[1][r][2];
            assign b03 = d[1][r][0] - d[1][r][3];
            assign rH[1][r][0] = b00 + b01;
            assign rH[1][r][1] = b03 + b02;
            assign rH[1][r][2] = b00 - b01;
            assign rH[1][r][3] = b03 - b02;
        end
    endgenerate

    wire [23:0] satd_blk0, satd_blk1;

    function automatic [23:0] satd4x4_from_rH;
        input signed [13:0] x00, x10, x20, x30;
        input signed [13:0] x01, x11, x21, x31;
        input signed [13:0] x02, x12, x22, x32;
        input signed [13:0] x03, x13, x23, x33;
        reg   signed [15:0] s0,s1,s2,s3;
        reg   signed [15:0] y00,y10,y20,y30;
        reg   signed [15:0] y01,y11,y21,y31;
        reg   signed [15:0] y02,y12,y22,y32;
        reg   signed [15:0] y03,y13,y23,y33;
        reg   [23:0] sum;
        begin
            // col 0
            s0  = x00 + x30;  s1 = x10 + x20;  s2 = x10 - x20;  s3 = x00 - x30;
            y00 = s0 + s1;    y10 = s3 + s2;   y20 = s0 - s1;   y30 = s3 - s2;
            // col 1
            s0  = x01 + x31;  s1 = x11 + x21;  s2 = x11 - x21;  s3 = x01 - x31;
            y01 = s0 + s1;    y11 = s3 + s2;   y21 = s0 - s1;   y31 = s3 - s2;
            // col 2
            s0  = x02 + x32;  s1 = x12 + x22;  s2 = x12 - x22;  s3 = x02 - x32;
            y02 = s0 + s1;    y12 = s3 + s2;   y22 = s0 - s1;   y32 = s3 - s2;
            // col 3
            s0  = x03 + x33;  s1 = x13 + x23;  s2 = x13 - x23;  s3 = x03 - x33;
            y03 = s0 + s1;    y13 = s3 + s2;   y23 = s0 - s1;   y33 = s3 - s2;

            sum =
                abs16(y00) + abs16(y01) + abs16(y02) + abs16(y03) +
                abs16(y10) + abs16(y11) + abs16(y12) + abs16(y13) +
                abs16(y20) + abs16(y21) + abs16(y22) + abs16(y23) +
                abs16(y30) + abs16(y31) + abs16(y32) + abs16(y33);

            satd4x4_from_rH = sum;
        end
    endfunction

    assign satd_blk0 = satd4x4_from_rH(
        rH[0][0][0], rH[0][1][0], rH[0][2][0], rH[0][3][0],
        rH[0][0][1], rH[0][1][1], rH[0][2][1], rH[0][3][1],
        rH[0][0][2], rH[0][1][2], rH[0][2][2], rH[0][3][2],
        rH[0][0][3], rH[0][1][3], rH[0][2][3], rH[0][3][3]
    );

    assign satd_blk1 = satd4x4_from_rH(
        rH[1][0][0], rH[1][1][0], rH[1][2][0], rH[1][3][0],
        rH[1][0][1], rH[1][1][1], rH[1][2][1], rH[1][3][1],
        rH[1][0][2], rH[1][1][2], rH[1][2][2], rH[1][3][2],
        rH[1][0][3], rH[1][1][3], rH[1][2][3], rH[1][3][3]
    );

    assign SATD_sum = satd_blk0 + satd_blk1;

endmodule

module MEM128_512(A, DO, DI, CK, WEB, OE, CS);
	input [8:0] A;
	input [127:0] DI;
	input CK, CS, OE, WEB;
	output [127:0] DO;

L0P1 mem(
        .A0(A[0]), .A1(A[1]), .A2(A[2]), .A3(A[3]), .A4(A[4]), .A5(A[5]), .A6(A[6]), .A7(A[7]), .A8(A[8]),

        .DO0(DO[0]),     .DO1(DO[1]),     .DO2(DO[2]),     .DO3(DO[3]),     .DO4(DO[4]),     .DO5(DO[5]),     .DO6(DO[6]),     .DO7(DO[7]),
        .DO8(DO[8]),     .DO9(DO[9]),     .DO10(DO[10]),   .DO11(DO[11]),   .DO12(DO[12]),   .DO13(DO[13]),   .DO14(DO[14]),   .DO15(DO[15]),
        .DO16(DO[16]),   .DO17(DO[17]),   .DO18(DO[18]),   .DO19(DO[19]),   .DO20(DO[20]),   .DO21(DO[21]),   .DO22(DO[22]),   .DO23(DO[23]),
        .DO24(DO[24]),   .DO25(DO[25]),   .DO26(DO[26]),   .DO27(DO[27]),   .DO28(DO[28]),   .DO29(DO[29]),   .DO30(DO[30]),   .DO31(DO[31]),
        .DO32(DO[32]),   .DO33(DO[33]),   .DO34(DO[34]),   .DO35(DO[35]),   .DO36(DO[36]),   .DO37(DO[37]),   .DO38(DO[38]),   .DO39(DO[39]),
        .DO40(DO[40]),   .DO41(DO[41]),   .DO42(DO[42]),   .DO43(DO[43]),   .DO44(DO[44]),   .DO45(DO[45]),   .DO46(DO[46]),   .DO47(DO[47]),
        .DO48(DO[48]),   .DO49(DO[49]),   .DO50(DO[50]),   .DO51(DO[51]),   .DO52(DO[52]),   .DO53(DO[53]),   .DO54(DO[54]),   .DO55(DO[55]),
        .DO56(DO[56]),   .DO57(DO[57]),   .DO58(DO[58]),   .DO59(DO[59]),   .DO60(DO[60]),   .DO61(DO[61]),   .DO62(DO[62]),   .DO63(DO[63]),
        .DO64(DO[64]),   .DO65(DO[65]),   .DO66(DO[66]),   .DO67(DO[67]),   .DO68(DO[68]),   .DO69(DO[69]),   .DO70(DO[70]),   .DO71(DO[71]),
        .DO72(DO[72]),   .DO73(DO[73]),   .DO74(DO[74]),   .DO75(DO[75]),   .DO76(DO[76]),   .DO77(DO[77]),   .DO78(DO[78]),   .DO79(DO[79]),
        .DO80(DO[80]),   .DO81(DO[81]),   .DO82(DO[82]),   .DO83(DO[83]),   .DO84(DO[84]),   .DO85(DO[85]),   .DO86(DO[86]),   .DO87(DO[87]),
        .DO88(DO[88]),   .DO89(DO[89]),   .DO90(DO[90]),   .DO91(DO[91]),   .DO92(DO[92]),   .DO93(DO[93]),   .DO94(DO[94]),   .DO95(DO[95]),
        .DO96(DO[96]),   .DO97(DO[97]),   .DO98(DO[98]),   .DO99(DO[99]),   .DO100(DO[100]), .DO101(DO[101]), .DO102(DO[102]), .DO103(DO[103]),
        .DO104(DO[104]), .DO105(DO[105]), .DO106(DO[106]), .DO107(DO[107]), .DO108(DO[108]), .DO109(DO[109]), .DO110(DO[110]), .DO111(DO[111]),
        .DO112(DO[112]), .DO113(DO[113]), .DO114(DO[114]), .DO115(DO[115]), .DO116(DO[116]), .DO117(DO[117]), .DO118(DO[118]), .DO119(DO[119]),
        .DO120(DO[120]), .DO121(DO[121]), .DO122(DO[122]), .DO123(DO[123]), .DO124(DO[124]), .DO125(DO[125]), .DO126(DO[126]), .DO127(DO[127]),

        .DI0(DI[0]),     .DI1(DI[1]),     .DI2(DI[2]),     .DI3(DI[3]),     .DI4(DI[4]),     .DI5(DI[5]),     .DI6(DI[6]),     .DI7(DI[7]),
        .DI8(DI[8]),     .DI9(DI[9]),     .DI10(DI[10]),   .DI11(DI[11]),   .DI12(DI[12]),   .DI13(DI[13]),   .DI14(DI[14]),   .DI15(DI[15]),
        .DI16(DI[16]),   .DI17(DI[17]),   .DI18(DI[18]),   .DI19(DI[19]),   .DI20(DI[20]),   .DI21(DI[21]),   .DI22(DI[22]),   .DI23(DI[23]),
        .DI24(DI[24]),   .DI25(DI[25]),   .DI26(DI[26]),   .DI27(DI[27]),   .DI28(DI[28]),   .DI29(DI[29]),   .DI30(DI[30]),   .DI31(DI[31]),
        .DI32(DI[32]),   .DI33(DI[33]),   .DI34(DI[34]),   .DI35(DI[35]),   .DI36(DI[36]),   .DI37(DI[37]),   .DI38(DI[38]),   .DI39(DI[39]),
        .DI40(DI[40]),   .DI41(DI[41]),   .DI42(DI[42]),   .DI43(DI[43]),   .DI44(DI[44]),   .DI45(DI[45]),   .DI46(DI[46]),   .DI47(DI[47]),
        .DI48(DI[48]),   .DI49(DI[49]),   .DI50(DI[50]),   .DI51(DI[51]),   .DI52(DI[52]),   .DI53(DI[53]),   .DI54(DI[54]),   .DI55(DI[55]),
        .DI56(DI[56]),   .DI57(DI[57]),   .DI58(DI[58]),   .DI59(DI[59]),   .DI60(DI[60]),   .DI61(DI[61]),   .DI62(DI[62]),   .DI63(DI[63]),
        .DI64(DI[64]),   .DI65(DI[65]),   .DI66(DI[66]),   .DI67(DI[67]),   .DI68(DI[68]),   .DI69(DI[69]),   .DI70(DI[70]),   .DI71(DI[71]),
        .DI72(DI[72]),   .DI73(DI[73]),   .DI74(DI[74]),   .DI75(DI[75]),   .DI76(DI[76]),   .DI77(DI[77]),   .DI78(DI[78]),   .DI79(DI[79]),
        .DI80(DI[80]),   .DI81(DI[81]),   .DI82(DI[82]),   .DI83(DI[83]),   .DI84(DI[84]),   .DI85(DI[85]),   .DI86(DI[86]),   .DI87(DI[87]),
        .DI88(DI[88]),   .DI89(DI[89]),   .DI90(DI[90]),   .DI91(DI[91]),   .DI92(DI[92]),   .DI93(DI[93]),   .DI94(DI[94]),   .DI95(DI[95]),
        .DI96(DI[96]),   .DI97(DI[97]),   .DI98(DI[98]),   .DI99(DI[99]),   .DI100(DI[100]), .DI101(DI[101]), .DI102(DI[102]), .DI103(DI[103]),
        .DI104(DI[104]), .DI105(DI[105]), .DI106(DI[106]), .DI107(DI[107]), .DI108(DI[108]), .DI109(DI[109]), .DI110(DI[110]), .DI111(DI[111]),
        .DI112(DI[112]), .DI113(DI[113]), .DI114(DI[114]), .DI115(DI[115]), .DI116(DI[116]), .DI117(DI[117]), .DI118(DI[118]), .DI119(DI[119]),
        .DI120(DI[120]), .DI121(DI[121]), .DI122(DI[122]), .DI123(DI[123]), .DI124(DI[124]), .DI125(DI[125]), .DI126(DI[126]), .DI127(DI[127]),

        .CK(CK), .WEB(WEB), .OE(OE), .CS(CS)
    );
endmodule
