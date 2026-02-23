`timescale 1ns/10ps

module CLK_1_MODULE (
    input             clk,
    input             rst_n,
    input             in_valid,
    input      [31:0] in_data,
    input             out_idle,                // Handshake_syn.sidle
    output reg        out_valid,               // Handshake_syn.sready (1-cycle)
    output reg [31:0] out_data,                // Handshake_syn.din
    input             flag_handshake_to_clk1,  // sack (unused; keep port)
    output            flag_clk1_to_handshake   // = out_valid
);
  assign flag_clk1_to_handshake = out_valid;

  localparam S_IDLE = 3'd0, S_IN = 3'd1, S_GIVE = 3'd2;
  reg [2:0] ps, ns;
  reg [4:0]  cnt_in, cnt_out;
  reg        idle_d1;
  reg [31:0] buf32x16 [0:15];
  integer ii;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) ps <= S_IDLE;
    else        ps <= ns;
  end
  always @* begin
    case (ps)
      S_IDLE: ns = in_valid ? S_IN : S_IDLE;
      S_IN  : ns = in_valid ? S_IN : S_GIVE;
      S_GIVE: ns = (cnt_out == 5'd16) ? S_IDLE : S_GIVE;
      default: ns = S_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          cnt_in <= 5'd0;
    else if (in_valid)   cnt_in <= cnt_in + 5'd1;
    else                 cnt_in <= 5'd0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ii=0; ii<16; ii=ii+1) buf32x16[ii] <= 32'd0;
    end else if (in_valid) begin
      buf32x16[cnt_in] <= in_data;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) idle_d1 <= 1'b0;
    else        idle_d1 <= out_idle;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                   cnt_out <= 5'd0;
    else if (cnt_in == 5'd1)      cnt_out <= 5'd0;
    else if (in_valid && (cnt_in > 5'd9) && out_idle && ~idle_d1)
                                  cnt_out <= cnt_out + 5'd1;
    else if (ps==S_GIVE && out_idle && ~idle_d1)
                                  cnt_out <= cnt_out + 5'd1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_valid <= 1'b0;
    else if (ps==S_IN || ps==S_GIVE) begin
      if (out_idle) out_valid <= 1'b1;
      else          out_valid <= 1'b0;
    end else begin
      out_valid <= 1'b0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_data <= 32'd0;
    else if (ps==S_IN || ps==S_GIVE) begin
      if (out_idle) out_data <= buf32x16[cnt_out];
      else          out_data <= out_data;
    end else begin
      out_data <= 32'd0;
    end
  end
endmodule

module GMb_ROM (
  input  wire [6:0] idx,
  output wire [15:0] val
);
  localparam [15:0] LUT [0:127] = '{
    16'd4091,16'd7888,16'd11060,16'd11208,16'd6960,16'd4342,16'd6275,16'd9759,
    16'd1591,16'd6399,16'd9477,16'd5266,16'd586 ,16'd5825,16'd7538,16'd9710,
    16'd1134,16'd6407,16'd1711,16'd965 ,16'd7099,16'd7674,16'd3743,16'd6442,
    16'd10414,16'd8100,16'd1885,16'd1688,16'd1364,16'd10329,16'd10164,16'd9180,
    16'd12210,16'd6240,16'd997 ,16'd117 ,16'd4783,16'd4407,16'd1549,16'd7072,
    16'd2829,16'd6458,16'd4431,16'd8877,16'd7144,16'd2564,16'd5664,16'd4042,
    16'd12189,16'd432 ,16'd10751,16'd1237,16'd7610,16'd1534,16'd3983,16'd7863,
    16'd2181,16'd6308,16'd8720,16'd6570,16'd4843,16'd1690,16'd14  ,16'd3872,
    16'd5569,16'd9368,16'd12163,16'd2019,16'd7543,16'd2315,16'd4673,16'd7340,
    16'd1553,16'd1156,16'd8401,16'd11389,16'd1020,16'd2967,16'd10772,16'd7045,
    16'd3316,16'd11236,16'd5285,16'd11578,16'd10637,16'd10086,16'd9493,16'd6180,
    16'd9277,16'd6130,16'd3323,16'd883 ,16'd10469,16'd489 ,16'd1502,16'd2851,
    16'd11061,16'd9729,16'd2742,16'd12241,16'd4970,16'd10481,16'd10078,16'd1195,
    16'd730 ,16'd1762,16'd3854,16'd2030,16'd5892,16'd10922,16'd9020,16'd5274,
    16'd9179,16'd3604,16'd3782,16'd10206,16'd3180,16'd3467,16'd4668,16'd2446,
    16'd7613,16'd9386,16'd834 ,16'd7703,16'd6836,16'd3403,16'd5351,16'd12276
  };
  assign val = LUT[idx];
endmodule

module CLK_2_MODULE (
    input               clk,
    input               rst_n,
    input               in_valid,
    input       [31:0]  in_data,
    input               fifo_full,
    output reg          out_valid,
    output reg  [15:0]  out_data,
    output              busy,

    input               flag_handshake_to_clk2,
    output              flag_clk2_to_handshake,

    input               flag_fifo_to_clk2,
    output              flag_clk2_to_fifo
);
  localparam C_IDLE=5'd0, C_IN=5'd1,
             C_L1=5'd2, C_L2=5'd3, C_L3=5'd4, C_L4=5'd5,
             C_L5=5'd6, C_L6=5'd7, C_L7=5'd8,
             C_OUT=5'd9;
  reg [4:0] cs, ns, in_cnt2;
  reg [31:0] din_pack [0:15];
  reg [11:0] step_cnt, walk_a, walk_b, out_cnt2;
  wire [15:0] tw_val;
  reg  [7:0]  tw_idx, idx_a, idx_b;
  reg  [15:0] stage_mem [0:127];
  reg  [6:0] addr_q [0:127]; 
  reg  [7:0] q_wptr, q_rptr;  // 0..127
  reg  [8:0] q_count;         // 0..128

  // Busy/flags
  assign busy = (cs == C_OUT);
  assign flag_clk2_to_handshake = busy;
  assign flag_clk2_to_fifo      = 1'b0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cs <= C_IDLE;
    else        cs <= ns;
  end

  wire in_layer = (cs>=C_L1 && cs<=C_L7);
  wire in_win   = (step_cnt>=12'd5 && step_cnt<=12'd68);

  always @* begin
    case (cs)
      C_IDLE: ns = in_valid ? C_IN : C_IDLE;
      C_IN  : ns = (in_cnt2 == 5'd16) ? C_L1 : C_IN;
      C_L1  : ns = (step_cnt == 12'd68) ? C_L2 : C_L1;
      C_L2  : ns = (step_cnt == 12'd68) ? C_L3 : C_L2;
      C_L3  : ns = (step_cnt == 12'd68) ? C_L4 : C_L3;
      C_L4  : ns = (step_cnt == 12'd68) ? C_L5 : C_L4;
      C_L5  : ns = (step_cnt == 12'd68) ? C_L6 : C_L5;
      C_L6  : ns = (step_cnt == 12'd68) ? C_L7 : C_L6;
      C_L7  : ns = (step_cnt == 12'd68) ? ((out_cnt2==12'd127 && q_count==0) ? C_IDLE : C_OUT) : C_L7;
      C_OUT : ns = (out_cnt2 == 12'd127) ? C_IDLE : C_OUT;
      default: ns = C_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          in_cnt2 <= 5'd0;
    else if (in_valid)   in_cnt2 <= in_cnt2 + 5'd1;
    else if (cs==C_OUT || cs==C_IDLE) in_cnt2 <= 5'd0;
  end
  
  integer jj;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (jj=0; jj<16; jj=jj+1) din_pack[jj] <= 32'd0;
    end else if (in_valid) begin
      din_pack[in_cnt2] <= in_data;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                     step_cnt <= 12'd0;
    else if (in_layer)              step_cnt <= (step_cnt==12'd68) ? 12'd0 : (step_cnt + 12'd1);
    else                            step_cnt <= 12'd0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      walk_a <= 12'd0; walk_b <= 12'd64;
    end else begin
      case (cs)
        C_L1: if (in_win) begin
                walk_a <= walk_a + 12'd1; walk_b <= walk_b + 12'd1;
              end
        C_L2: begin
                if (step_cnt==12'd0) begin walk_a<=12'd0; walk_b<=12'd32; end
                else if (in_win) begin
                  if (step_cnt==12'd36) begin walk_a<=12'd64; walk_b<=12'd96; end
                  else begin walk_a<=walk_a+12'd1; walk_b<=walk_b+12'd1; end
                end
              end
        C_L3: begin
                if (step_cnt==12'd0) begin walk_a<=12'd0; walk_b<=12'd16; end
                else if (in_win) begin
                  if (walk_a[3:0]==4'd15) begin walk_a<=walk_a+12'd17; walk_b<=walk_b+12'd17; end
                  else begin walk_a<=walk_a+12'd1; walk_b<=walk_b+12'd1; end
                end
              end
        C_L4: begin
                if (step_cnt==12'd0) begin walk_a<=12'd0; walk_b<=12'd8; end
                else if (in_win) begin
                  if (walk_a[2:0]==3'd7) begin walk_a<=walk_a+12'd9; walk_b<=walk_b+12'd9; end
                  else begin walk_a<=walk_a+12'd1; walk_b<=walk_b+12'd1; end
                end
              end
        C_L5: begin
                if (step_cnt==12'd0) begin walk_a<=12'd0; walk_b<=12'd4; end
                else if (in_win) begin
                  if (walk_a[1:0]==2'd3) begin walk_a<=walk_a+12'd5; walk_b<=walk_b+12'd5; end
                  else begin walk_a<=walk_a+12'd1; walk_b<=walk_b+12'd1; end
                end
              end
        C_L6: begin
                if (step_cnt==12'd0) begin walk_a<=12'd0; walk_b<=12'd2; end
                else if (in_win) begin
                  if (walk_a[0]==1'b1) begin walk_a<=walk_a+12'd3; walk_b<=walk_b+12'd3; end
                  else begin walk_a<=walk_a+12'd1; walk_b<=walk_b+12'd1; end
                end
              end
        C_L7: begin
                if (step_cnt==12'd0) begin walk_a<=12'd0; walk_b<=12'd1; end
                else if (in_win) begin
                  walk_a <= walk_a + 12'd2; walk_b <= walk_b + 12'd2; // 0,1,2,3,... 正序
                end
              end
        C_IDLE: begin walk_a<=12'd0; walk_b<=12'd64; end
      endcase
    end
  end

  GMb_ROM U_GMB (.idx(tw_idx[6:0]), .val(tw_val));

  // NTT butterfly
  wire [15:0] a_in = tw_val;
  wire [15:0] b_in = stage_mem[idx_a];
  wire [15:0] u_in = stage_mem[idx_b];
  wire [15:0] up_w, dn_w;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (jj=0; jj<128; jj=jj+1) stage_mem[jj] <= 16'd0;
    end else if (in_layer) begin
      if (in_win) begin
        stage_mem[walk_a] <= up_w;
        stage_mem[walk_b] <= dn_w;
      end
    end else if (in_valid) begin
      stage_mem[in_cnt2*8 + 0] <= in_data[ 3: 0];
      stage_mem[in_cnt2*8 + 1] <= in_data[ 7: 4];
      stage_mem[in_cnt2*8 + 2] <= in_data[11: 8];
      stage_mem[in_cnt2*8 + 3] <= in_data[15:12];
      stage_mem[in_cnt2*8 + 4] <= in_data[19:16];
      stage_mem[in_cnt2*8 + 5] <= in_data[23:20];
      stage_mem[in_cnt2*8 + 6] <= in_data[27:24];
      stage_mem[in_cnt2*8 + 7] <= in_data[31:28];
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tw_idx <= 8'd1;
    else begin
      case (cs)
        C_L1: if (step_cnt>=12'd63)        tw_idx <= 8'd2;
        C_L2: begin
                if (step_cnt>=12'd63)      tw_idx <= 8'd4;
                else if (step_cnt==12'd31) tw_idx <= 8'd3;
              end
        C_L3: begin
                if      (step_cnt==12'd63)     tw_idx <= 8'd8;
                else if (step_cnt[3:0]==4'd15) tw_idx <= tw_idx + 8'd1;
              end
        C_L4: begin
                if      (step_cnt>=12'd63)     tw_idx <= 8'd16;
                else if (step_cnt[2:0]==3'd7)  tw_idx <= tw_idx + 8'd1;
              end
        C_L5: begin
                if      (step_cnt>=12'd63)     tw_idx <= 8'd32;
                else if (step_cnt[1:0]==2'd3)  tw_idx <= tw_idx + 8'd1;
              end
        C_L6: begin
                if      (step_cnt>=12'd63)     tw_idx <= 8'd64;
                else if (step_cnt[0]==1'b1)    tw_idx <= tw_idx + 8'd1;
              end
        C_L7: if (tw_idx!=8'd127)              tw_idx <= 8'd1 + tw_idx;
        C_IDLE:                                 tw_idx <= 8'd1;
      endcase
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin idx_a<=8'd64; idx_b<=8'd0; end
    else begin
      case (cs)
        C_L1: begin
                if (step_cnt>=12'd63) begin idx_a<=8'd32; idx_b<=8'd0; end
                else                  begin idx_a<=idx_a+8'd1; idx_b<=idx_b+8'd1; end
              end
        C_L2: begin
                if (step_cnt>=12'd63) begin idx_a<=8'd16; idx_b<=8'd0; end
                else if (step_cnt==12'd31) begin idx_a<=8'd96; idx_b<=8'd64; end
                else                  begin idx_a<=idx_a+8'd1; idx_b<=idx_b+8'd1; end
              end
        C_L3: begin
                if (step_cnt>=12'd63) begin idx_a<=8'd8;  idx_b<=8'd0; end
                else if (step_cnt[3:0]==4'd15) begin idx_a<=idx_a+8'd17; idx_b<=idx_b+8'd17; end
                else                  begin idx_a<=idx_a+8'd1; idx_b<=idx_b+8'd1; end
              end
        C_L4: begin
                if (step_cnt>=12'd63) begin idx_a<=8'd4;  idx_b<=8'd0; end
                else if (step_cnt[2:0]==3'd7) begin idx_a<=idx_a+8'd9; idx_b<=idx_b+8'd9; end
                else                  begin idx_a<=idx_a+8'd1; idx_b<=idx_b+8'd1; end
              end
        C_L5: begin
                if (step_cnt>=12'd63) begin idx_a<=8'd2;  idx_b<=8'd0; end
                else if (step_cnt[1:0]==2'd3) begin idx_a<=idx_a+8'd5; idx_b<=idx_b+8'd5; end
                else                  begin idx_a<=idx_a+8'd1; idx_b<=idx_b+8'd1; end
              end
        C_L6: begin
                if (step_cnt>=12'd63) begin idx_a<=8'd1;  idx_b<=8'd0; end
                else if (step_cnt[0]==1'b1) begin idx_a<=idx_a+8'd3; idx_b<=idx_b+8'd3; end
                else                  begin idx_a<=idx_a+8'd1; idx_b<=idx_b+8'd1; end
              end
        C_L7: begin idx_a <= idx_a + 8'd2; idx_b <= idx_b + 8'd2; end
        C_IDLE: begin idx_a<=8'd64; idx_b<=8'd0; end
      endcase
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_wptr  <= 8'd0;
      q_rptr  <= 8'd0;
      q_count <= 9'd0;
    end else begin
      if (cs==C_L7 && in_win) begin
        addr_q[q_wptr] <= walk_a[6:0]; q_wptr <= q_wptr + 8'd1;
        addr_q[q_wptr + 8'd1] <= walk_b[6:0]; q_wptr <= q_wptr + 8'd2;
        q_count <= q_count + 9'd2;
      end

      if ((cs==C_L7) && (q_count!=9'd0) && ~fifo_full) begin
        q_rptr  <= q_rptr + 8'd1;
        q_count <= q_count - 9'd1;
      end

      if (cs==C_IDLE) begin
        q_wptr  <= 8'd0;
        q_rptr  <= 8'd0;
        q_count <= 9'd0;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_cnt2 <= 12'd0;
    else if ((cs==C_L7) && (q_count!=0) && ~fifo_full) begin
      out_cnt2 <= out_cnt2 + 12'd1;
    end
    else if ((cs==C_OUT) && ~fifo_full) begin
      out_cnt2 <= out_cnt2 + 12'd1;
    end
    else if (cs==C_IDLE) begin
      out_cnt2 <= 12'd0;
    end
  end

  always @* begin
    out_valid = 1'b0;
    out_data  = 16'd0;
    if (cs==C_L7) begin
      out_valid = (q_count!=0) && ~fifo_full;
      out_data  = out_valid ? stage_mem[ addr_q[q_rptr] ] : 16'd0;
    end
    else if (cs==C_OUT) begin
      out_valid = ~fifo_full;
      out_data  = ~fifo_full ? stage_mem[out_cnt2] : 16'd0;
    end
  end

  NTT_cal U0 (
    .clk  (clk),
    .rst_n(rst_n),
    .a    (a_in),
    .b    (b_in),
    .u    (u_in),
    .up   (up_w),
    .down (dn_w)
  );
endmodule

module NTT_cal(
    input           clk,
    input           rst_n,
    input   [15:0]  a,
    input   [15:0]  b,
    input   [15:0]  u,
    output reg [15:0] up,
    output reg [15:0] down
);
  parameter Q   = 16'd12289;
  parameter QOI = 16'd12287;

  reg  [49:0] x_mul, y_mul, z_acc, x_dly;
  reg  [15:0] z_hi, v_mod, u_dly[0:3];
  wire [15:0] y_lo;

  // x = a*b
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) x_mul <= 50'd0;
    else        x_mul <= a * b;
  end

  // x_delay
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) x_dly <= 50'd0;
    else        x_dly <= x_mul;
  end

  // y = x*QOI
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) y_mul <= 50'd0;
    else        y_mul <= x_mul * QOI;
  end
  assign y_lo = y_mul[15:0];

  // z = x_delay + (y_res * Q)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) z_acc <= 50'd0;
    else        z_acc <= x_dly + y_lo * Q;
  end

  // >>16
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) z_hi <= 16'd0;
    else        z_hi <= z_acc[31:16];
  end

  // v = (z >= Q) ? z-Q : z
  always @* begin
    v_mod = (z_hi >= Q) ? (z_hi - Q) : z_hi;
  end

  // u align
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      u_dly[0] <= 16'd0;
      u_dly[1] <= 16'd0;
      u_dly[2] <= 16'd0;
      u_dly[3] <= 16'd0;
    end else begin
      u_dly[3] <= u_dly[2];
      u_dly[2] <= u_dly[1];
      u_dly[1] <= u_dly[0];
      u_dly[0] <= u;
    end
  end

  // up / down
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) up <= 16'd0;
    else        up <= (u_dly[3] + v_mod) % Q;
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) down <= 16'd0;
    else        down <= (u_dly[3] >= v_mod) ? (u_dly[3] - v_mod) : (u_dly[3] - v_mod + Q);
  end
endmodule

module CLK_3_MODULE (
    input               clk,
    input               rst_n,
    input               fifo_empty,
    input       [15:0]  fifo_rdata,
    output reg          fifo_rinc,
    output reg          out_valid,
    output reg  [15:0]  out_data,
    input               flag_fifo_to_clk3,
    output              flag_clk3_to_fifo
);
  assign flag_clk3_to_fifo = 1'b0;

  reg empty_d1, empty_d2;
  reg go_ps, go_ns;
  reg [8:0] cnt_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) go_ps <= 1'b0;
    else        go_ps <= go_ns;
  end

  // next state
  always @* begin
    case (go_ps)
      1'b0: go_ns = (~empty_d2) ? 1'b1 : 1'b0;
      1'b1: go_ns = (cnt_q==9'd127) ? 1'b0 : 1'b1;
    endcase
  end

  always @* begin
    fifo_rinc = ~fifo_empty;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)       cnt_q <= 9'd0;
    else if (out_valid) cnt_q <= cnt_q + 9'd1;
    else                cnt_q <= 9'd0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      empty_d1 <= 1'b1; empty_d2 <= 1'b1;
    end else begin
      empty_d1 <= fifo_empty;
      empty_d2 <= empty_d1;
    end
  end

  // out_valid / out_data
  always @* begin
    out_valid = (~empty_d2 && cnt_q <= 9'd127);
  end

  always @* begin
    out_data  = out_valid ? fifo_rdata : 16'd0;
  end
endmodule
