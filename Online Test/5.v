`timescale 1ns/10ps

module MOS(
  input        rst_n,
  input        clk,
  input        matrix_size,          // 0: 4x4, 1: 8x8
  input        in_valid,
  input  signed [15:0] in_data,
  output reg          out_valid,
  output reg  signed [39:0] out_data
);

  localparam S_IDLE = 1'b0;
  localparam S_RUN  = 1'b1;

  reg        state, state_nx;
  reg        size;                   // 0:4x4 / 1:8x8
  reg  [7:0] in_cnt;            
  reg  [7:0] run_cnt;              
  reg        in_valid_d;         

  wire       in_leading  =  in_valid & ~in_valid_d;
  wire       in_trailing = ~in_valid &  in_valid_d;

  wire [3:0] N          = (size==1'b0) ? 4 : 8;
  wire [7:0] LEN_W      = (size==1'b0) ? 8'd16 : 8'd64;
  wire [7:0] LEN_M      = LEN_W;
  wire [7:0] IN_TOTAL   = LEN_W + LEN_M;
  wire [7:0] INJECT_LEN = {4'd0,(N<<1)} - 8'd1;

  // 4x4: 5..11，8x8: 9..23
  wire [7:0] OV_S = (size==1'b0) ? 8'd5  : 8'd9;
  wire [7:0] OV_E = (size==1'b0) ? 8'd11 : 8'd23; // inclusive

  wire       run_done = (run_cnt==OV_E);

  integer i;
  reg signed [15:0] weight [0:63];
  reg signed [15:0] matrix [0:63];

  reg  signed [15:0] pe_weight [0:63];  
  reg  signed [15:0] pe_matrix [0:63];  
  reg  signed [39:0] pe_sum    [0:63];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) in_valid_d <= 1'b0;
    else        in_valid_d <= in_valid;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= state_nx;
  end

  always @(*) begin
    case (state)
      S_IDLE:  state_nx = (in_trailing) ? S_RUN : S_IDLE; 
      S_RUN :  state_nx = (run_done)    ? S_IDLE: S_RUN;
      default: state_nx = S_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) in_cnt <= 8'd0;
    else if (in_valid)  in_cnt <= in_cnt + 8'd1;
    else                in_cnt <= 8'd0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) size <= 1'b0;
    else if (in_leading) size <= matrix_size; 
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)             run_cnt <= 8'd0;
    else if (state==S_IDLE) run_cnt <= 8'd0;
    else                    run_cnt <= run_cnt + 8'd1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i=0;i<64;i=i+1) weight[i] <= 16'sd0;
    end else if (in_valid) begin
      if (in_cnt < LEN_W)              weight[in_cnt] <= in_data;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i=0;i<64;i=i+1) matrix[i] <= 16'sd0;
    end else if (in_valid) begin
      if (in_cnt >= LEN_W && in_cnt < IN_TOTAL) matrix[in_cnt-LEN_W] <= in_data;
    end
  end


integer r;
reg [7:0] N_u;
reg       eff;        
reg [5:0] w_idx;     
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (r=0; r<8; r=r+1) pe_weight[r*8] <= 16'sd0;
  end else if (state==S_IDLE) begin
    for (r=0; r<8; r=r+1) pe_weight[r*8] <= 16'sd0;
  end else begin
    N_u = (size==1'b0) ? 8'd4 : 8'd8;

    for (r=0; r<8; r=r+1) pe_weight[r*8] <= 16'sd0;

    if (run_cnt < ((N_u<<1)-1)) begin
      for (r=0; r<8; r=r+1) begin
        if (r < N_u) begin
          eff   = (run_cnt >= r) && ((run_cnt - r) < N_u); // r ≤ t < r+N
          w_idx = r*N_u + (N_u-1 - (run_cnt - r));        // r*N + (N-1-(t-r))
          if (eff) pe_weight[r*8] <= weight[w_idx];
        end
      end
    end
  end
end

  genvar gw;
  generate
    for (gw=0; gw<64; gw=gw+1) begin : G_W_SHIFT
      if (gw%8!=0) begin : NOT_HEAD
        always @(posedge clk or negedge rst_n) begin
          if (!rst_n)           pe_weight[gw] <= 0;
          else if (state==S_IDLE) pe_weight[gw] <= 0;
          else                  pe_weight[gw] <= pe_weight[gw-1];
        end
      end
    end
  endgenerate

integer rm;
reg [7:0] mN;
reg       meff;
reg [5:0] m_idx;  // 0..63
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (rm=0; rm<8; rm=rm+1) pe_matrix[rm] <= 16'sd0;
  end else if (state==S_IDLE) begin
    for (rm=0; rm<8; rm=rm+1) pe_matrix[rm] <= 16'sd0;
  end else begin
    mN = (size==1'b0) ? 8'd4 : 8'd8;

    for (rm=0; rm<8; rm=rm+1) pe_matrix[rm] <= 16'sd0;

    if (run_cnt < ((mN<<1)-1)) begin
      for (rm=0; rm<8; rm=rm+1) begin
        if (rm < mN) begin
          meff  = (run_cnt >= rm) && ((run_cnt - rm) < mN);          // rm ≤ t < rm+N
          m_idx = (mN-1 - (run_cnt - rm))*mN + rm;                   // (N-1-(t-r))*N + r
          if (meff) pe_matrix[rm] <= matrix[m_idx];
        end
      end
    end
  end
end

  genvar gm;
  generate
    for (gm=8; gm<64; gm=gm+1) begin : G_M_SHIFT
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             pe_matrix[gm] <= 0;
        else if (state==S_IDLE) pe_matrix[gm] <= 0;
        else                    pe_matrix[gm] <= pe_matrix[gm-8];
      end
    end
  endgenerate

  genvar gs;
  generate
    for (gs=0; gs<64; gs=gs+1) begin : G_MAC
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             pe_sum[gs] <= 40'sd0;
        else if (state==S_IDLE) pe_sum[gs] <= 40'sd0;
        else                    pe_sum[gs] <= pe_sum[gs] + $signed(pe_matrix[gs]) * $signed(pe_weight[gs]);
      end
    end
  endgenerate

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_valid <= 1'b0;
    else        out_valid <= (state==S_RUN) && (run_cnt>=OV_S) && (run_cnt<=OV_E);
  end

reg  signed [39:0] diag_sum;
integer rr;
reg [3:0] NN;        // 4 or 8
reg [7:0] kstep;   

always @(*) begin
  diag_sum = 40'sd0;
  if ((state==S_RUN) && (run_cnt>=OV_S) && (run_cnt<=OV_E)) begin
    NN    = (size==1'b0) ? 4 : 8;
    kstep = run_cnt - OV_S;          
    for (rr=0; rr<8; rr=rr+1) begin
      if (rr < NN) begin
        if ((kstep >= rr) && ((kstep - rr) < NN)) begin
          diag_sum = diag_sum + pe_sum[ rr*8 + (kstep - rr) ];
        end
      end
    end
  end
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    out_data <= 40'sd0;
  end else if ((state==S_RUN) && (run_cnt>=OV_S) && (run_cnt<=OV_E)) begin
    out_data <= diag_sum;
  end else begin
    out_data <= 40'sd0;
  end
end

endmodule
