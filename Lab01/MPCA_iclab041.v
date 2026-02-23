module MPCA(
    input  [127:0] packets,
    input   [11:0] channel_load,      // [3:0]=ch0, [7:4]=ch1, [11:8]=ch2
    input    [8:0] channel_capacity,  // [2:0]=ch0, [5:3]=ch1, [8:6]=ch2
    input   [63:0] KEY,
    output reg [15:0] grant_channel
);

// ---------------------------------------------------------------
// Utils
// ---------------------------------------------------------------
function [15:0] ROR2; input [15:0] d; begin ROR2 = {d[1:0],  d[15:2]}; end endfunction
function [15:0] ROR7; input [15:0] d; begin ROR7 = {d[6:0],  d[15:7]}; end endfunction
function [15:0] ROL7; input [15:0] d; begin ROL7 = {d[8:0],  d[15:9]}; end endfunction

function [3:0] DIV3_4B; input [3:0] x; begin
  case (x)
    4'd0,4'd1,4'd2:    DIV3_4B = 4'd0;
    4'd3,4'd4,4'd5:    DIV3_4B = 4'd1;
    4'd6,4'd7,4'd8:    DIV3_4B = 4'd2;
    4'd9,4'd10,4'd11:  DIV3_4B = 4'd3;
    4'd12,4'd13,4'd14: DIV3_4B = 4'd4;
    default:           DIV3_4B = 4'd5;
  endcase
end endfunction

function [3:0] MOD10_6B; input [5:0] x; reg [5:0] r; begin
  r = (x >= 6'd20) ? (x - 6'd20) : x;
  MOD10_6B = (r >= 6'd10) ? (r - 6'd10) : r[3:0];
end endfunction

function [1:0] INC1_MOD3; input [1:0] x; begin
  case(x) 2'd0: INC1_MOD3=2'd1; 2'd1: INC1_MOD3=2'd2; default: INC1_MOD3=2'd0; endcase
end endfunction
function [1:0] INC2_MOD3; input [1:0] x; begin
  case(x) 2'd0: INC2_MOD3=2'd2; 2'd1: INC2_MOD3=2'd0; default: INC2_MOD3=2'd1; endcase
end endfunction

// base→[base,base+1,base+2]
function [1:0] sel3;
  input [1:0] base;
  input c0nz, c1nz, c2nz;
  reg [2:0] rot; reg [1:0] off;
begin
  case (base)
    2'd0: rot = {c2nz, c1nz, c0nz};
    2'd1: rot = {c0nz, c2nz, c1nz};
    default: rot = {c1nz, c0nz, c2nz};
  endcase
  casez (rot)
    3'b??1: off=2'd0;
    3'b?10: off=2'd1;
    3'b100: off=2'd2;
    default: off=2'd3;
  endcase
  case (base)
    2'd0: sel3 = (off==2'd0)?2'd0 : (off==2'd1)?2'd1 : (off==2'd2)?2'd2 : 2'b11;
    2'd1: sel3 = (off==2'd0)?2'd1 : (off==2'd1)?2'd2 : (off==2'd2)?2'd0 : 2'b11;
    default: sel3 = (off==2'd0)?2'd2 : (off==2'd1)?2'd0 : (off==2'd2)?2'd1 : 2'b11;
  endcase
end
endfunction

// ---------------------------------------------------------------
// SPECK32/64: 4-round backward decrypt
// ---------------------------------------------------------------
function [31:0] speck_dec4;
  input [31:0] blk; input [15:0] k0,k1,k2,k3;
  reg [15:0] x4,y4,x3,y3,x2,y2,x1,y1,x0,y0;
begin
  y4 = blk[31:16]; x4 = blk[15:0];

  y3 = ROR2(y4 ^ x4);
  x3 = ROL7((x4 ^ k3) - y3);

  y2 = ROR2(y3 ^ x3);
  x2 = ROL7((x3 ^ k2) - y2);

  y1 = ROR2(y2 ^ x2);
  x1 = ROL7((x2 ^ k1) - y1);   // <-- FIX

  y0 = ROR2(y1 ^ x1);
  x0 = ROL7((x1 ^ k0) - y0);

  speck_dec4 = {y0, x0};
end
endfunction

// ---------------------------------------------------------------
// Round keys
// ---------------------------------------------------------------
wire [15:0] K0 = KEY[15:0];
wire [15:0] L0 = KEY[31:16];
wire [15:0] L1 = KEY[47:32];
wire [15:0] L2 = KEY[63:48];

wire [15:0] RK0 = K0;
wire [15:0] RK1 = (ROR7(K0)  + L0) ^ 16'h0000;
wire [15:0] RK2 = (ROR7(RK1) + L1) ^ 16'h0001;
wire [15:0] RK3 = (ROR7(RK2) + L2) ^ 16'h0002;

// ---------------------------------------------------------------
// Decrypt 4x32b => 8x16b p[0..7]
// ---------------------------------------------------------------
reg [15:0] p [0:7];
always @* begin
  {p[1], p[0]} = speck_dec4(packets[31:0],   RK0,RK1,RK2,RK3);
  {p[3], p[2]} = speck_dec4(packets[63:32],  RK0,RK1,RK2,RK3);
  {p[5], p[4]} = speck_dec4(packets[95:64],  RK0,RK1,RK2,RK3);
  {p[7], p[6]} = speck_dec4(packets[127:96], RK0,RK1,RK2,RK3);
end

// ---------------------------------------------------------------
// Score: 7-bit signed, (q<<2) - (l<<1) - 3*c + s + 7
// ---------------------------------------------------------------
function signed [6:0] calc_score;
  input [15:0] pkt;
  reg [1:0]  qos_in, cong_in;
  reg [3:0]  len_in;
  reg [2:0]  src_in;
  reg        mode_in;
  reg  signed [6:0] qv, lv, cv, sv;
  reg  signed [8:0] t1, t2, t3, sum9;
begin
  qos_in  = pkt[14:13];
  len_in  = pkt[12:9];
  cong_in = pkt[8:7];
  src_in  = pkt[4:2];
  mode_in = pkt[1];

  if (!mode_in) begin
    qv = $signed({5'b0,  qos_in});
    lv = $signed({3'b0,  len_in});
    cv = $signed({5'b0,  cong_in});
    sv = $signed({4'b0,  src_in});
  end else begin
    qv = $signed({{5{qos_in[1]}},  qos_in});
    lv = $signed({{3{len_in[3]}},  len_in});
    cv = $signed({{5{cong_in[1]}}, cong_in});
    sv = $signed({{4{src_in[2]}},  src_in});
  end

  t1   = {qv,2'b00};                    // q<<2
  t2   = {lv,1'b0};                     // l<<1
  t3   = {cv,1'b0} + {{1{cv[6]}},cv};   // 3*c
  sum9 = t1 - t2 - t3 + {{2{sv[6]}},sv} + 9'sd7;
  calc_score = sum9[6:0];
end
endfunction

reg        req   [0:7];
reg  [1:0] pref  [0:7];
reg  [2:0] src   [0:7];
reg  signed [6:0] score [0:7];

integer si;
always @* begin
  for (si=0; si<8; si=si+1) begin
    req[si]   = p[si][15];
    pref[si]  = p[si][6:5];
    src[si]   = p[si][4:2];
    score[si] = calc_score(p[si]);
  end
end

// key：{req, score^7'h40, ~idx}
wire [10:0] key0 = { req[0], (score[0]^7'h40), ~3'd0 };
wire [10:0] key1 = { req[1], (score[1]^7'h40), ~3'd1 };
wire [10:0] key2 = { req[2], (score[2]^7'h40), ~3'd2 };
wire [10:0] key3 = { req[3], (score[3]^7'h40), ~3'd3 };
wire [10:0] key4 = { req[4], (score[4]^7'h40), ~3'd4 };
wire [10:0] key5 = { req[5], (score[5]^7'h40), ~3'd5 };
wire [10:0] key6 = { req[6], (score[6]^7'h40), ~3'd6 };
wire [10:0] key7 = { req[7], (score[7]^7'h40), ~3'd7 };

function [10:0] get_key; input [2:0] idx; begin
  case (idx)
    3'd0: get_key = key0; 3'd1: get_key = key1; 3'd2: get_key = key2; 3'd3: get_key = key3;
    3'd4: get_key = key4; 3'd5: get_key = key5; 3'd6: get_key = key6; default: get_key = key7;
  endcase
end endfunction

function [5:0] cs2;
  input [2:0] a_idx, b_idx;
  input [10:0] ka, kb;
begin
  cs2 = (ka > kb) ? {a_idx, b_idx} : {b_idx, a_idx};
end
endfunction

// ---------------------------------------------------------------
// Sorting network: index-only
// ---------------------------------------------------------------
reg [5:0] st1 [0:3], st2 [0:3], st3 [0:3];
reg [5:0] st4 [0:1], st5 [0:1], st6 [0:2];
reg [2:0]  sorted_idx [0:7];

always @* begin
  // r1: (0,2)(1,3)(4,6)(5,7)
  st1[0] = cs2(3'd0,3'd2, key0,key2);
  st1[1] = cs2(3'd1,3'd3, key1,key3);
  st1[2] = cs2(3'd4,3'd6, key4,key6);
  st1[3] = cs2(3'd5,3'd7, key5,key7);
  // r2: (0,4)(1,5)(2,6)(3,7)
  st2[0] = cs2(st1[0][5:3], st1[2][5:3], get_key(st1[0][5:3]), get_key(st1[2][5:3]));
  st2[1] = cs2(st1[1][5:3], st1[3][5:3], get_key(st1[1][5:3]), get_key(st1[3][5:3]));
  st2[2] = cs2(st1[0][2:0], st1[2][2:0], get_key(st1[0][2:0]), get_key(st1[2][2:0]));
  st2[3] = cs2(st1[1][2:0], st1[3][2:0], get_key(st1[1][2:0]), get_key(st1[3][2:0]));
  // r3: (0,1)(2,3)(4,5)(6,7)
  st3[0] = cs2(st2[0][5:3], st2[1][5:3], get_key(st2[0][5:3]), get_key(st2[1][5:3]));
  st3[1] = cs2(st2[2][5:3], st2[3][5:3], get_key(st2[2][5:3]), get_key(st2[3][5:3]));
  st3[2] = cs2(st2[0][2:0], st2[1][2:0], get_key(st2[0][2:0]), get_key(st2[1][2:0]));
  st3[3] = cs2(st2[2][2:0], st2[3][2:0], get_key(st2[2][2:0]), get_key(st2[3][2:0]));
  // r4: (2,4)(3,5)
  st4[0] = cs2(st3[1][5:3], st3[2][5:3], get_key(st3[1][5:3]), get_key(st3[2][5:3]));
  st4[1] = cs2(st3[1][2:0], st3[2][2:0], get_key(st3[1][2:0]), get_key(st3[2][2:0]));
  // r5: (1,4)(3,6)
  st5[0] = cs2(st3[0][2:0], st4[0][2:0], get_key(st3[0][2:0]), get_key(st4[0][2:0]));
  st5[1] = cs2(st4[1][5:3], st3[3][5:3], get_key(st4[1][5:3]), get_key(st3[3][5:3]));
  // r6: (1,2)(3,4)(5,6)
  st6[0] = cs2(st5[0][5:3], st4[0][5:3], get_key(st5[0][5:3]), get_key(st4[0][5:3]));
  st6[1] = cs2(st5[1][5:3], st5[0][2:0], get_key(st5[1][5:3]), get_key(st5[0][2:0]));
  st6[2] = cs2(st4[1][2:0], st5[1][2:0], get_key(st4[1][2:0]), get_key(st5[1][2:0]));

  sorted_idx[0] = st3[0][5:3];
  sorted_idx[1] = st6[0][5:3];
  sorted_idx[2] = st6[0][2:0];
  sorted_idx[3] = st6[1][5:3];
  sorted_idx[4] = st6[1][2:0];
  sorted_idx[5] = st6[2][5:3];
  sorted_idx[6] = st6[2][2:0];
  sorted_idx[7] = st3[3][2:0];
end

// ---------------------------------------------------------------
// Allocation + Mask + Rebalance
// ---------------------------------------------------------------
wire [3:0] ld_init0 = channel_load[3:0];
wire [3:0] ld_init1 = channel_load[7:4];
wire [3:0] ld_init2 = channel_load[11:8];

wire [2:0] cap_init0 = channel_capacity[2:0];
wire [2:0] cap_init1 = channel_capacity[5:3];
wire [2:0] cap_init2 = channel_capacity[8:6];

reg [1:0] assign_ch [0:7];
reg [1:0] final_ch  [0:7];

reg [2:0] c0,c1,c2;
reg [4:0] l0,l1,l2;

reg [1:0] cur_pivot;

reg        mask_fail [0:7];
reg [3:0]  thresh    [0:7];
reg [3:0]  mod10_val [0:7];

reg [6:0] sum_ld7;
reg [4:0] max_ld;
reg [1:0] ch_max;
reg       need_reb;
reg       found;
reg [2:0] pick_i;

integer i;

always @* begin
  // init
  for (i=0;i<8;i=i+1) begin
    assign_ch[i] = 2'b11;
    final_ch [i] = 2'b11;
    mask_fail[i] = 1'b0;
    thresh[i]    = 4'd0;
    mod10_val[i] = 4'd0;
  end

  c0 = cap_init0; c1 = cap_init1; c2 = cap_init2;
  l0 = ld_init0;  l1 = ld_init1;  l2 = ld_init2;
  cur_pivot = 2'b11;

  // walk by priority
  for (i=0;i<8;i=i+1) begin
    reg        rq;
    reg [1:0]  pf, ch_sel;
    reg [2:0]  idx;

    idx = sorted_idx[i];
    rq  = req [idx];
    pf  = pref[idx];

    if (!rq) begin
      assign_ch[idx] = 2'b11;
    end else begin
      ch_sel = 2'b11;
      // exact preference first
      case (pf)
        2'd0: if (c0>0) ch_sel=2'd0;
        2'd1: if (c1>0) ch_sel=2'd1;
        2'd2: if (c2>0) ch_sel=2'd2;
        default: ch_sel=2'b11;
      endcase

      // fallback anchored at pivot
      if (ch_sel==2'b11) begin
        reg [1:0] base;
        base   = (cur_pivot==2'b11) ? pf : cur_pivot;
        ch_sel = sel3(base, (c0>0), (c1>0), (c2>0));
        cur_pivot = (ch_sel==2'b11) ? INC2_MOD3(base) : INC1_MOD3(base);
      end

      // commit
      case (ch_sel)
        2'd0: begin assign_ch[idx]=2'd0; c0=c0-3'd1; l0=l0+5'd1; end
        2'd1: begin assign_ch[idx]=2'd1; c1=c1-3'd1; l1=l1+5'd1; end
        2'd2: begin assign_ch[idx]=2'd2; c2=c2-3'd1; l2=l2+5'd1; end
        default: assign_ch[idx]=2'b11;
      endcase
    end
  end

  // mask
  for (i=0;i<8;i=i+1) begin
    reg [3:0] ld_sel; reg [5:0] sum6; reg [3:0] sc4;
    if (assign_ch[i] != 2'b11) begin
      ld_sel = (assign_ch[i]==2'd0) ? ld_init0 :
               (assign_ch[i]==2'd1) ? ld_init1 : ld_init2;
      sc4   = {1'b0, $unsigned(score[i][2:1]), 1'b0}; // 0..14
      sum6  = {2'b00, sc4}
            + {4'b0000, p[i][6:5]}
            + {3'b000,  (p[i][4:2]^3'd3)}
            + {2'b00,   ld_sel};
      mod10_val[i] = MOD10_6B(sum6);
      thresh[i]    = 4'd7 + DIV3_4B(ld_sel);
      mask_fail[i] = (mod10_val[i] >= thresh[i]);
    end else begin
      mod10_val[i] = 4'd0; thresh[i]=4'd0; mask_fail[i]=1'b1;
    end
  end

  // rebalance (3*max > total)
  sum_ld7 = {2'b00,l0} + {2'b00,l1} + {2'b00,l2};
  ch_max = 2'd0; max_ld = l0;
  if (l1 > max_ld) begin ch_max=2'd1; max_ld=l1; end
  if (l2 > max_ld) begin ch_max=2'd2; max_ld=l2; end
  need_reb = ( ( {2'b00,max_ld} << 1 ) + {2'b00,max_ld} ) > sum_ld7;

  for (i=0;i<8;i=i+1) final_ch[i] = assign_ch[i];

  if (need_reb) begin
    found = 1'b0; pick_i = 3'd0;
    for (i=0; i<8; i=i+1) begin
      reg [2:0] j; j = sorted_idx[i];
      if (assign_ch[j]==ch_max && !mask_fail[j]) begin
        found  = 1'b1; pick_i = j;
      end
    end
    if (found) begin
      reg [1:0] dest1, dest2;
      dest1 = INC1_MOD3(ch_max);
      dest2 = INC2_MOD3(ch_max);
      if ( (dest1==2'd0 && c0>0 && l0<5'd15) ||
           (dest1==2'd1 && c1>0 && l1<5'd15) ||
           (dest1==2'd2 && c2>0 && l2<5'd15) ) begin
        final_ch[pick_i] = dest1;
      end else if ( (dest2==2'd0 && c0>0 && l0<5'd15) ||
                    (dest2==2'd1 && c1>0 && l1<5'd15) ||
                    (dest2==2'd2 && c2>0 && l2<5'd15) ) begin
        final_ch[pick_i] = dest2;
      end else begin
        final_ch[pick_i] = 2'b11;
      end
    end
  end

  // pack
  grant_channel = { final_ch[7], final_ch[6], final_ch[5], final_ch[4],
                    final_ch[3], final_ch[2], final_ch[1], final_ch[0] };
end

endmodule
