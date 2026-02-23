// synopsys translate_off
`ifdef RTL
  `include "GATED_OR.v"
`else
  `include "Netlist/GATED_OR_SYN.v"
`endif
// synopsys translate_on

`timescale 1ns/10ps
module SAD(
    // Input signals
    clk,
    rst_n,
    cg_en,
    in_valid,
    in_data1,
    T,
    in_data2,
    w_Q,
    w_K,
    w_V,
    // Output signals
    out_valid,
    out_data
);
input clk;
input rst_n;
input cg_en;
input in_valid;
input signed [5:0] in_data1;
input [3:0] T;
input signed [7:0] in_data2;
input signed [7:0] w_Q;
input signed [7:0] w_K;
input signed [7:0] w_V;
output reg out_valid;
output reg signed [91:0] out_data;
parameter d_model = 'd8;

parameter S_IDLE  = 2'd0;
parameter S_LOAD  = 2'd1; // cnt<57
parameter S_RUN   = 2'd2; // 57..191 
parameter S_DRAIN = 2'd3; // 192..end 

reg [1:0] state, next_state;
reg [9:0] cnt;
reg [3:0] t_buf;

reg signed [5:0] in_data1_buf [0:15];
reg signed [7:0] in_data2_buf [0:63];
reg signed [7:0] wq_buf [0:63], wk_buf [0:63];

reg signed [18:0] Q [0:7][0:7], K [0:7][0:7], V [0:7][0:7];

reg signed [40:0] Scale;
reg signed [40:0] Relu [0:63];

reg signed [60:0] P;
reg signed [31:0] Det [0:4];

reg signed [91:0] outans, outans_d1, outans_d2, outans_d3;

reg signed [7:0] mac0_a [0:7][0:7];
reg signed [7:0] mac0_b [0:7];
wire signed [18:0] mac0_c [0:7];

reg signed [18:0] mac1_a [0:7], mac1_b [0:7];
wire signed [40:0] mac1_c;

localparam DETW = 6;
reg signed [DETW-1:0] det_coef [0:4];  // det_coef[0]=a, [1]=b, [2]=c, [3]=d, [4]=e

`define det_a det_coef[0]
`define det_b det_coef[1]
`define det_c det_coef[2]
`define det_d det_coef[3]
`define det_e det_coef[4]

reg signed [20:1] det_f_unused_pad; 
reg signed [20:0] det_f;

integer i, j;
genvar ii, jj;
// FSM 
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) state <= S_IDLE;
    else        state <= next_state;
end

wire [9:0] end_cnt = (t_buf==4'd1) ? 10'd200 :
                     (t_buf==4'd4) ? 10'd225 : 10'd256;

always @(*) begin
    case (state)
      S_IDLE : next_state = (in_valid) ? S_LOAD : S_IDLE;
      S_LOAD : next_state = (cnt < 10'd57) ? S_LOAD : S_RUN;      // 0..56
      S_RUN  : next_state = (cnt < 10'd192)? S_RUN  : S_DRAIN;    // 57..191
      S_DRAIN: next_state = (cnt == end_cnt) ? S_IDLE : S_DRAIN;  // 192..end
      default: next_state = S_IDLE;
    endcase
end

// INPUT
wire done_tick  = (state == S_DRAIN) && (cnt == end_cnt);
wire cnt_en     =  in_valid || (state != S_IDLE);

always @(posedge clk or negedge rst_n) begin
  if (!rst_n)                     cnt <= 10'd0;
  else if (done_tick)             cnt <= 10'd0;
  else if (cnt_en)                cnt <= cnt + 10'd1;
end

//wire clk_t_buf;
//GATED_OR GATED_t_buf (.CLOCK(clk), .SLEEP_CTRL(cg_en & counter != 0), .RST_N(rst_n), .CLOCK_GATED(clk_t_buf));
always @(posedge clk or negedge rst_n) begin
  if (!rst_n)                     t_buf <= 4'd0;
  else if (in_valid && (cnt==10'd0))
                                  t_buf <= T;
end

//wire clk_in_data1_buf;
//GATED_OR GATED_in_data1_buf (.CLOCK(clk), .SLEEP_CTRL(cg_en & counter != 15), .RST_N(rst_n), .CLOCK_GATED(clk_in_data1_buf));
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (i = 0; i < 16; i = i + 1) in_data1_buf[i] <= 6'sd0;
  end else if (in_valid && (cnt <= 10'd15)) begin
    in_data1_buf[cnt] <= in_data1;
  end
end

wire [9:0] t_last = (t_buf * d_model) - 10'd1;
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (i = 0; i < 64; i = i + 1) in_data2_buf[i] <= 8'sd0;
  end else if (in_valid) begin
    in_data2_buf[cnt] <= (cnt <= t_last) ? in_data2 : 8'sd0;
  end
end

wire in_wq_phase0 = (cnt <= 10'd63);
wire in_wk_phase  = (cnt >= 10'd64)  && (cnt <= 10'd127);
wire in_wq_phase1 = (cnt >= 10'd128) && (cnt <= 10'd191);

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (i = 0; i < 64; i = i + 1) begin
      wq_buf[i] <= 8'sd0;
      wk_buf[i] <= 8'sd0;
    end
  end else if (in_valid) begin
    if (in_wq_phase0)         wq_buf[cnt]            <= w_Q;
    else if (in_wk_phase)     wk_buf[cnt - 10'd64]   <= w_K;
    else if (in_wq_phase1)    wq_buf[cnt - 10'd128]  <= w_V; // keep original behavior
  end
end

// K, Q, V MAC
wire a_load_en = (cnt >= 10'd57) && (cnt <= 10'd64);
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_A_LOAD
    for (jj = 0; jj < 8; jj = jj + 1) begin: G_A_LOAD_IN
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            mac0_a[ii][jj] <= '0;
        else if (a_load_en)    mac0_a[ii][jj] <= in_data2_buf[ii*8 + jj];
      end
    end
  end
endgenerate

wire b_wq0_en = (cnt >= 10'd65)  && (cnt <= 10'd72);
wire b_wk_en  = (cnt >= 10'd121) && (cnt <= 10'd128);
wire b_wq1_en = (cnt >= 10'd185) && (cnt <= 10'd192);

always @(posedge clk or negedge rst_n) begin : G_B_LOAD_ALL
  integer k;
  if (!rst_n) begin
    for (k = 0; k < 8; k = k + 1) mac0_b[k] <= '0;
  end else begin
    for (k = 0; k < 8; k = k + 1) begin
      if (b_wq0_en)      mac0_b[k] <= wq_buf[k*8 + (cnt-10'd65)];
      else if (b_wk_en)  mac0_b[k] <= wk_buf[k*8 + (cnt-10'd121)];
      else if (b_wq1_en) mac0_b[k] <= wq_buf[k*8 + (cnt-10'd185)];
      // else: hold
    end
  end
end

generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_MAC0
    MAC_8 u_mac0_row (
      .in_1_a(mac0_a[ii][0]), .in_2_a(mac0_a[ii][1]), .in_3_a(mac0_a[ii][2]), .in_4_a(mac0_a[ii][3]),
      .in_5_a(mac0_a[ii][4]), .in_6_a(mac0_a[ii][5]), .in_7_a(mac0_a[ii][6]), .in_8_a(mac0_a[ii][7]),
      .in_1_b(mac0_b[0]),     .in_2_b(mac0_b[1]),     .in_3_b(mac0_b[2]),     .in_4_b(mac0_b[3]),
      .in_5_b(mac0_b[4]),     .in_6_b(mac0_b[5]),     .in_7_b(mac0_b[6]),     .in_8_b(mac0_b[7]),
      .result(mac0_c[ii])
    );
  end
endgenerate

wire q_shift_en = (cnt >= 10'd66) && (cnt <= 10'd73);
wire clk_Q [0:7][0:7];
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_Q_SHIFT
    for (jj = 0; jj < 8; jj = jj + 1) begin: G_Q_SHIFT_IN
	GATED_OR GATED_Q (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 66 || cnt > 73)), .RST_N(rst_n), .CLOCK_GATED(clk_Q[ii][jj]));
      always @(posedge clk_Q[ii][jj] or negedge rst_n) begin
        if (!rst_n)            Q[ii][jj] <= '0;
        else if (q_shift_en)   Q[ii][jj] <= (jj==7) ? mac0_c[ii] : Q[ii][jj+1];
      end
    end
  end
endgenerate

wire k_shift_en = (cnt >= 10'd122) && (cnt <= 10'd129);
wire clk_K [0:7][0:7];
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_K_SHIFT
    for (jj = 0; jj < 8; jj = jj + 1) begin: G_K_SHIFT_IN
	  GATED_OR GATED_K (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 122 || cnt > 129)), .RST_N(rst_n), .CLOCK_GATED(clk_K[ii][jj]));
      always @(posedge clk_K[ii][jj] or negedge rst_n) begin
        if (!rst_n)            K[ii][jj] <= '0;
        else if (k_shift_en)   K[ii][jj] <= (jj==7) ? mac0_c[ii] : K[ii][jj+1];
      end
    end
  end
endgenerate

wire v_load_en = (cnt >= 10'd186) && (cnt <= 10'd193);
wire v_rot_en  = (cnt >= 10'd194) && (cnt <= 10'd249);
wire clk_V [0:7][0:7];
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_V_SHIFT
    for (jj = 0; jj < 8; jj = jj + 1) begin: G_V_SHIFT_IN
	GATED_OR GATED_V (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 186 || cnt > 249)), .RST_N(rst_n), .CLOCK_GATED(clk_V[ii][jj]));
      always @(posedge clk_V[ii][jj] or negedge rst_n) begin
        if (!rst_n)               V[ii][jj] <= '0;
        else if (v_load_en)       V[ii][jj] <= (jj==7) ? mac0_c[ii] : V[ii][jj+1];
        else if (v_rot_en)        V[ii][jj] <= (jj==7) ? V[ii][0]   : V[ii][jj+1];
      end
    end
  end
endgenerate

// A = QK
wire clk_mac1_a[0:7];
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_MAC1_A
  GATED_OR GATED_mac1_a (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 131 || cnt > 187)), .RST_N(rst_n), .CLOCK_GATED(clk_mac1_a[ii]));
    wire [9:0] cnt_offA = cnt - 10'd131;     // valid when cnt>=131
    wire       a_hit    = (cnt >= 10'd131) && (cnt <= 10'd187) && (cnt_offA[2:0]==3'b000);
    always @(posedge clk_mac1_a[ii] or negedge rst_n) begin
      if (!rst_n)          mac1_a[ii] <= 19'sd0;
      else if (a_hit)      mac1_a[ii] <= Q[cnt_offA[9:3]][ii]; // row = (cnt-131)/8
    end
  end
endgenerate

wire        mac1b_en  = (cnt >= 10'd131) && (cnt <= 10'd194);
wire [9:0]  cnt_offB  = cnt - 10'd131;
wire [2:0]  k_row_sel = cnt_offB[2:0];
wire clk_mac1_b[0:7];
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_MAC1_B
  GATED_OR GATED_mac1_b (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 131 || cnt > 194)), .RST_N(rst_n), .CLOCK_GATED(clk_mac1_b[ii]));
    always @(posedge clk_mac1_b[ii] or negedge rst_n) begin
      if (!rst_n)        mac1_b[ii] <= 19'sd0;
      else if (mac1b_en) mac1_b[ii] <= K[k_row_sel][ii];
    end
  end
endgenerate

wire signed [40:0] mac1_s [0:8];
assign mac1_s[0] = 41'sd0;
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_MAC1_CHAIN
    MAC_19 u_mac1_chain (
      .in_1    (mac1_a[ii]),
      .in_2    (mac1_b[ii]),
      .psum_in (mac1_s[ii]),
      .psum_out(mac1_s[ii+1])
    );
  end
endgenerate
assign mac1_c = mac1_s[8];

// Scale & Relu
wire signed [40:0] scale_relu_w;
ReLU_div_3 u_relu_div3(.in(mac1_c), .out(scale_relu_w));
wire clk_scale;
GATED_OR GATED_scale (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 132 || cnt > 195)), .RST_N(rst_n), .CLOCK_GATED(clk_scale));
always @(posedge clk_scale or negedge rst_n) begin
    if (~rst_n) begin
        Scale <= 0;
    end else if ((cnt >= 132) && (cnt <= 195)) begin
        Scale <= scale_relu_w;
    end
end
wire clk_RELU_0[0:7];
generate
    for (ii = 0; ii < 8; ii = ii + 1) begin: G_RELU_0
    GATED_OR GATED_RELU_0 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 133 || cnt > 140)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_0[ii]));
        always @(posedge clk_RELU_0[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 133) && (cnt <= 140)) begin
                if (ii == 7) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_1[8:15];
generate
    for (ii = 8; ii < 16; ii = ii + 1) begin: G_RELU_1
	GATED_OR GATED_RELU_1 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 141 || cnt > 148)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_1[ii]));
        always @(posedge clk_RELU_1[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 141) && (cnt <= 148)) begin
                if (ii == 15) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_2[16:23];
generate
    for (ii = 16; ii < 24; ii = ii + 1) begin: G_RELU_2
	GATED_OR GATED_RELU_2 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 149 || cnt > 156)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_2[ii]));
        always @(posedge clk_RELU_2[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 149) && (cnt <= 156)) begin
                if (ii == 23) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_3[24:31];
generate
    for (ii = 24; ii < 32; ii = ii + 1) begin: G_RELU_3
	GATED_OR GATED_RELU_3 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 157 || cnt > 164)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_3[ii]));
        always @(posedge clk_RELU_3[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 157) && (cnt <= 164)) begin
                if (ii == 31) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_4[32:39];
generate
    for (ii = 32; ii < 40; ii = ii + 1) begin: G_RELU_4
	GATED_OR GATED_RELU_4 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 165 || cnt > 172)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_4[ii]));
        always @(posedge clk_RELU_4[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 165) && (cnt <= 172)) begin
                if (ii == 39) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_5[40:47];
generate
    for (ii = 40; ii < 48; ii = ii + 1) begin: G_RELU_5
	GATED_OR GATED_RELU_5 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 173 || cnt > 180)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_5[ii]));
        always @(posedge clk_RELU_5[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 173) && (cnt <= 180)) begin
                if (ii == 47) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_6[48:55];
generate
    for (ii = 48; ii < 56; ii = ii + 1) begin: G_RELU_6
	GATED_OR GATED_RELU_6 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 181 || cnt > 188)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_6[ii]));
        always @(posedge clk_RELU_6[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 181) && (cnt <= 188)) begin
                if (ii == 55) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate
wire clk_RELU_7[56:63];
generate
    for (ii = 56; ii < 64; ii = ii + 1) begin: G_RELU_7
	GATED_OR GATED_RELU_7 (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 189 || cnt > 196)), .RST_N(rst_n), .CLOCK_GATED(clk_RELU_7[ii]));
        always @(posedge clk_RELU_7[ii] or negedge rst_n) begin
            if (~rst_n) begin
                Relu[ii] <= 0;
            end else if ((cnt >= 189) && (cnt <= 196)) begin
                if (ii == 63) Relu[ii] <= (Scale > 0) ? Scale : 0;
                else Relu[ii] <= Relu[ii + 1];
            end
        end
    end
endgenerate

// P = S * V 
wire [5:0] pidx = cnt - 10'd187;
wire [2:0] row  = pidx[5:3];

wire signed [59:0] vprod [0:7];
generate
  for (ii = 0; ii < 8; ii = ii + 1) begin: G_P_MUL
    mult_41x19 u_mul_sv (
      .in_1   (Relu[{row, 3'b000} + ii]),   // Relu[row*8 + ii]
      .in_2   (V[ii][7]),
      .product(vprod[ii])
    );
  end
endgenerate

wire signed [60:0] p_sum_w;
add_60 u_add60(
  .in_0(vprod[0]), .in_1(vprod[1]), .in_2(vprod[2]), .in_3(vprod[3]),
  .in_4(vprod[4]), .in_5(vprod[5]), .in_6(vprod[6]), .in_7(vprod[7]),
  .out(p_sum_w)
);
wire clk_P;
GATED_OR GATED_P (.CLOCK(clk), .SLEEP_CTRL(cg_en & (cnt < 187 || cnt > 250)), .RST_N(rst_n), .CLOCK_GATED(clk_P));
always @(posedge clk_P or negedge rst_n) begin
  if (!rst_n) begin
    P <= 0;
  end else if (cnt >= 187 && cnt <= 250) begin
    P <= p_sum_w[60:0];
  end
end

// Determinant
wire c17 = (cnt==10'd17);
wire c18 = (cnt==10'd18);
wire c19 = (cnt==10'd19);
wire c21 = (cnt==10'd21);
wire c22 = (cnt==10'd22);
wire c23 = (cnt==10'd23);
wire c25 = (cnt==10'd25);
wire c26 = (cnt==10'd26);
wire c27 = (cnt==10'd27);
wire c29 = (cnt==10'd29);
wire c30 = (cnt==10'd30);
wire c31 = (cnt==10'd31);
//wire clk_detcoef;
//GATED_OR GATED_detcoef (.CLOCK(clk), .SLEEP_CTRL( cg_en & ~(cnt>=10'd17 && cnt<=10'd31) ), .RST_N(rst_n), .CLOCK_GATED(clk_detcoef));
always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    `det_a <= 6'sd0;
    `det_b <= 6'sd0;
    `det_c <= 6'sd0;
    `det_d <= 6'sd0;
    `det_e <= 6'sd0;
  end else begin
    if (c17) begin
      `det_a <= in_data1_buf[10]; `det_b <= in_data1_buf[15];
      `det_c <= in_data1_buf[11]; `det_d <= in_data1_buf[14]; `det_e <= in_data1_buf[5];
    end else if (c18) begin
      `det_a <= in_data1_buf[9];  `det_b <= in_data1_buf[15];
      `det_c <= in_data1_buf[11]; `det_d <= in_data1_buf[13]; `det_e <= in_data1_buf[6];
    end else if (c19) begin
      `det_a <= in_data1_buf[9];  `det_b <= in_data1_buf[14];
      `det_c <= in_data1_buf[10]; `det_d <= in_data1_buf[13]; `det_e <= in_data1_buf[7];
    end else if (c21) begin
      `det_a <= in_data1_buf[10]; `det_b <= in_data1_buf[15];
      `det_c <= in_data1_buf[11]; `det_d <= in_data1_buf[14]; `det_e <= in_data1_buf[4];
    end else if (c22) begin
      `det_a <= in_data1_buf[8];  `det_b <= in_data1_buf[15];
      `det_c <= in_data1_buf[11]; `det_d <= in_data1_buf[12]; `det_e <= in_data1_buf[6];
    end else if (c23) begin
      `det_a <= in_data1_buf[8];  `det_b <= in_data1_buf[14];
      `det_c <= in_data1_buf[10]; `det_d <= in_data1_buf[12]; `det_e <= in_data1_buf[7];
    end else if (c25) begin
      `det_a <= in_data1_buf[9];  `det_b <= in_data1_buf[15];
      `det_c <= in_data1_buf[11]; `det_d <= in_data1_buf[13]; `det_e <= in_data1_buf[4];
    end else if (c26) begin
      `det_a <= in_data1_buf[8];  `det_b <= in_data1_buf[15];
      `det_c <= in_data1_buf[11]; `det_d <= in_data1_buf[12]; `det_e <= in_data1_buf[5];
    end else if (c27) begin
      `det_a <= in_data1_buf[8];  `det_b <= in_data1_buf[13];
      `det_c <= in_data1_buf[9];  `det_d <= in_data1_buf[12]; `det_e <= in_data1_buf[7];
    end else if (c29) begin
      `det_a <= in_data1_buf[9];  `det_b <= in_data1_buf[14];
      `det_c <= in_data1_buf[10]; `det_d <= in_data1_buf[13]; `det_e <= in_data1_buf[4];
    end else if (c30) begin
      `det_a <= in_data1_buf[8];  `det_b <= in_data1_buf[14];
      `det_c <= in_data1_buf[10]; `det_d <= in_data1_buf[12]; `det_e <= in_data1_buf[5];
    end else if (c31) begin
      `det_a <= in_data1_buf[8];  `det_b <= in_data1_buf[13];
      `det_c <= in_data1_buf[9];  `det_d <= in_data1_buf[12]; `det_e <= in_data1_buf[6];
    end
  end
end
//wire clk_detf;
//GATED_OR GATED_detf (.CLOCK(clk), .SLEEP_CTRL( cg_en & ~(cnt>=10'd17 && cnt<=10'd31) ), .RST_N(rst_n), .CLOCK_GATED(clk_detf));
always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    det_f <= 21'sd0;
    det_f_unused_pad <= 21'sd0;
  end else begin
    det_f <= (`det_a * `det_b - `det_c * `det_d) * `det_e;
    det_f_unused_pad <= det_f[20:1] ^ {`det_e, `det_d[4:0], `det_c[4:0], `det_b[4:0], `det_a[4:0]};
  end
end

wire [9:0] cm1 = cnt - 10'd1;
wire d18 = (cm1==10'd18), d19 = (cm1==10'd19), d20 = (cm1==10'd20), d21 = (cm1==10'd21);
wire d22 = (cm1==10'd22), d23 = (cm1==10'd23), d24 = (cm1==10'd24), d25 = (cm1==10'd25);
wire d26 = (cm1==10'd26), d27 = (cm1==10'd27), d28 = (cm1==10'd28), d29 = (cm1==10'd29);
wire d30 = (cm1==10'd30), d31 = (cm1==10'd31), d32 = (cm1==10'd32), d33 = (cm1==10'd33);
wire d34 = (cm1==10'd34);
//wire clk_detacc;
//GATED_OR GATED_detacc (.CLOCK(clk), .SLEEP_CTRL( cg_en & ~(cnt>=10'd19 && cnt<=10'd35) ), .RST_N(rst_n), .CLOCK_GATED(clk_detacc));
always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    Det[0] <= 32'sd0;  Det[1] <= 32'sd0;  Det[2] <= 32'sd0;
    Det[3] <= 32'sd0;  Det[4] <= 32'sd0;
  end else begin
    if (d18)      Det[0] <= det_f;
    else if (d19) Det[0] <= Det[0] - det_f;
    else if (d20) Det[0] <= Det[0] + det_f;
    else if (d21) Det[0] <= Det[0] * in_data1_buf[0];

    if (d22)      Det[1] <= det_f;
    else if (d23) Det[1] <= Det[1] - det_f;
    else if (d24) Det[1] <= Det[1] + det_f;
    else if (d25) Det[1] <= Det[1] * in_data1_buf[1];

    if (d26)      Det[2] <= det_f;
    else if (d27) Det[2] <= Det[2] - det_f;
    else if (d28) Det[2] <= Det[2] + det_f;
    else if (d29) Det[2] <= Det[2] * in_data1_buf[2];

    if (d30)      Det[3] <= det_f;
    else if (d31) Det[3] <= Det[3] - det_f;
    else if (d32) Det[3] <= Det[3] + det_f;
    else if (d33) Det[3] <= Det[3] * in_data1_buf[3];

    if (d34)      Det[4] <= Det[0] - Det[1] + Det[2] - Det[3];
  end
end
//wire clk_outans;
//GATED_OR GATED_outans (.CLOCK(clk), .SLEEP_CTRL( cg_en & ~in_drain_win ), .RST_N(rst_n), .CLOCK_GATED(clk_outans));
always @(posedge clk or negedge rst_n) begin
  if (~rst_n) outans <= 92'sd0;
  else        outans <= P * Det[4];
end
//wire clk_outansshf;
//GATED_OR GATED_outansshf (.CLOCK(clk), .SLEEP_CTRL( cg_en & ~in_drain_win ), .RST_N(rst_n), .CLOCK_GATED(clk_outansshf));
always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    outans_d1 <= 92'sd0; outans_d2 <= 92'sd0; outans_d3 <= 92'sd0;
  end else begin
    outans_d1 <= outans;
    outans_d2 <= outans_d1;
    outans_d3 <= outans_d2;
  end
end

// Output
reg               out_valid_n;
reg signed [91:0] out_data_n;

wire win_t1 = (t_buf==4'd1) && (cnt>=10'd192) && (cnt<=10'd199);
wire win_t4 = (t_buf==4'd4) && (cnt>=10'd192) && (cnt<=10'd223);
wire win_t8 = (t_buf==4'd8) && (cnt>=10'd192) && (cnt<=10'd255);

always @* begin
  out_valid_n = 1'b0;
  out_data_n  = 92'sd0;
  if (win_t1 | win_t4 | win_t8) begin
    out_valid_n = 1'b1;
    out_data_n  = outans_d3;
  end
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    out_valid <= 1'b0;
    out_data  <= 92'sd0;
  end else begin
    out_valid <= out_valid_n;
    out_data  <= out_data_n;
  end
end

endmodule

// ======================= Submodules =======================

module MAC(
  input  signed [7:0]  in_1,
  input  signed [7:0]  in_2,
  input  signed [18:0] psum_in,
  output signed [18:0] psum_out
);
  assign psum_out = psum_in + (in_1 * in_2);
endmodule

module MAC_19(
  input  signed [18:0] in_1,
  input  signed [18:0] in_2,
  input  signed [40:0] psum_in,
  output signed [40:0] psum_out
);
  assign psum_out = psum_in + (in_1 * in_2);
endmodule

module mult_41x19 (
  input  signed [40:0] in_1,
  input  signed [18:0] in_2,
  output signed [59:0] product
);
  assign product = in_1 * in_2;
endmodule

module MAC_8 (
  input  signed [7:0] in_1_a, in_2_a, in_3_a, in_4_a, in_5_a, in_6_a, in_7_a, in_8_a,
  input  signed [7:0] in_1_b, in_2_b, in_3_b, in_4_b, in_5_b, in_6_b, in_7_b, in_8_b,
  output signed [18:0] result
);
  assign result =
      in_1_a*in_1_b + in_2_a*in_2_b + in_3_a*in_3_b + in_4_a*in_4_b +
      in_5_a*in_5_b + in_6_a*in_6_b + in_7_a*in_7_b + in_8_a*in_8_b;
endmodule

module ReLU_div_3 (
  input  signed [40:0] in,
  output signed [40:0] out
);
  assign out = in[40] ? 41'sd0 : (in / 41'sd3);
endmodule

module add_60 (
  input  signed [59:0] in_0, in_1, in_2, in_3, in_4, in_5, in_6, in_7,
  output signed [60:0] out
);
  assign out = in_0 + in_1 + in_2 + in_3 + in_4 + in_5 + in_6 + in_7;
endmodule

module add_41x8(
  input  signed [40:0] i0, i1, i2, i3, i4, i5, i6, i7,
  output signed [40:0] o
);
  wire signed [41:0] s0 = $signed(i0) + $signed(i1);
  wire signed [41:0] s1 = $signed(i2) + $signed(i3);
  wire signed [41:0] s2 = $signed(i4) + $signed(i5);
  wire signed [41:0] s3 = $signed(i6) + $signed(i7);
  wire signed [42:0] t0 = $signed(s0) + $signed(s1);
  //wire signed [42:3] dummy_pad = 40'sd0; 
  wire signed [42:0] t1 = $signed(s2) + $signed(s3);
  wire signed [43:0] u0 = $signed(t0) + $signed(t1);
  assign o = u0[40:0];
endmodule