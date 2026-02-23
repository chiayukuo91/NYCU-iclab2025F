`timescale 1ns/10ps
module SUDOKU(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [3:0]  in,
    output reg         out_valid,  
    output reg  [3:0]  out         
);

// =================== FSM ===================
localparam S_IDLE   = 2'd0;
localparam S_LOAD   = 2'd1;
localparam S_SOLVE  = 2'd2;
localparam S_OUT    = 2'd3;

reg [1:0] state, nstate;

// ================== Storage =================
reg [3:0] grid   [0:80];
reg [3:0] grid_n [0:80];

reg [6:0] in_cnt, in_cnt_n;
reg       load_done, load_done_n;

reg [6:0] out_idx, out_idx_n;  

// ================== Small helpers ==================
function [3:0] pick_num; input [8:0] num; begin
    pick_num[3] = num[7] | num[8];                           // 8,9
    pick_num[2] = num[3] | num[4] | num[5] | num[6];         // 4..7
    pick_num[1] = num[1] | num[2] | num[5] | num[6];         // 2,3,6,7
    pick_num[0] = num[0] | num[2] | num[4] | num[6] | num[8];// 1,3,5,7,9
end endfunction

function [1:0] fn_br2; input [3:0] rr; reg b1,b0; begin
    b1     = rr[3] | (rr[2] & rr[1]);
    b0     = (~rr[2] & rr[1] & rr[0]) | (rr[2] & ~rr[1]);
    fn_br2 = {b1,b0};
end endfunction
function [1:0] fn_bc2; input [3:0] cc; reg b1,b0; begin
    b1     = cc[3] | (cc[2] & cc[1]);
    b0     = (~cc[2] & cc[1] & cc[0]) | (cc[2] & ~cc[1]);
    fn_bc2 = {b1,b0};
end endfunction

// ============== one-hot of filled numbers (area-lean decoder) =========
wire [8:0] cell_oh [0:80];
genvar gi;
generate
for (gi=0; gi<81; gi=gi+1) begin: G_CELL_OH
    wire [3:0] v  = grid[gi];
    wire v3 = v[3], v2 = v[2], v1 = v[1], v0 = v[0];
    wire nv3 = ~v3, nv2 = ~v2, nv1 = ~v1, nv0 = ~v0;

    assign cell_oh[gi][0] = nv3 & nv2 & nv1 &  v0;  // 1 = 0001
    assign cell_oh[gi][1] = nv3 & nv2 &  v1 & nv0;  // 2 = 0010
    assign cell_oh[gi][2] = nv3 & nv2 &  v1 &  v0;  // 3 = 0011
    assign cell_oh[gi][3] = nv3 &  v2 & nv1 & nv0;  // 4 = 0100
    assign cell_oh[gi][4] = nv3 &  v2 & nv1 &  v0;  // 5 = 0101
    assign cell_oh[gi][5] = nv3 &  v2 &  v1 & nv0;  // 6 = 0110
    assign cell_oh[gi][6] = nv3 &  v2 &  v1 &  v0;  // 7 = 0111
    assign cell_oh[gi][7] =  v3 & nv2 & nv1 & nv0;  // 8 = 1000
    assign cell_oh[gi][8] =  v3 & nv2 & nv1 &  v0;  // 9 = 1001
end
endgenerate

// ============== row_used / col_used / box_used ==================
wire [8:0] row_used_w [0:8];
wire [8:0] col_used_w [0:8];
wire [8:0] box_used_w [0:8];

genvar rr,cc;
generate
for (rr=0; rr<9; rr=rr+1) begin: G_ROW_USED
    assign row_used_w[rr] =
        cell_oh[rr*9+0] | cell_oh[rr*9+1] | cell_oh[rr*9+2] |
        cell_oh[rr*9+3] | cell_oh[rr*9+4] | cell_oh[rr*9+5] |
        cell_oh[rr*9+6] | cell_oh[rr*9+7] | cell_oh[rr*9+8];
end
for (cc=0; cc<9; cc=cc+1) begin: G_COL_USED
    assign col_used_w[cc] =
        cell_oh[0*9+cc] | cell_oh[1*9+cc] | cell_oh[2*9+cc] |
        cell_oh[3*9+cc] | cell_oh[4*9+cc] | cell_oh[5*9+cc] |
        cell_oh[6*9+cc] | cell_oh[7*9+cc] | cell_oh[8*9+cc];
end
endgenerate

assign box_used_w[0] = cell_oh[ 0]|cell_oh[ 1]|cell_oh[ 2]|cell_oh[ 9]|cell_oh[10]|cell_oh[11]|cell_oh[18]|cell_oh[19]|cell_oh[20];
assign box_used_w[1] = cell_oh[ 3]|cell_oh[ 4]|cell_oh[ 5]|cell_oh[12]|cell_oh[13]|cell_oh[14]|cell_oh[21]|cell_oh[22]|cell_oh[23];
assign box_used_w[2] = cell_oh[ 6]|cell_oh[ 7]|cell_oh[ 8]|cell_oh[15]|cell_oh[16]|cell_oh[17]|cell_oh[24]|cell_oh[25]|cell_oh[26];
assign box_used_w[3] = cell_oh[27]|cell_oh[28]|cell_oh[29]|cell_oh[36]|cell_oh[37]|cell_oh[38]|cell_oh[45]|cell_oh[46]|cell_oh[47];
assign box_used_w[4] = cell_oh[30]|cell_oh[31]|cell_oh[32]|cell_oh[39]|cell_oh[40]|cell_oh[41]|cell_oh[48]|cell_oh[49]|cell_oh[50];
assign box_used_w[5] = cell_oh[33]|cell_oh[34]|cell_oh[35]|cell_oh[42]|cell_oh[43]|cell_oh[44]|cell_oh[51]|cell_oh[52]|cell_oh[53];
assign box_used_w[6] = cell_oh[54]|cell_oh[55]|cell_oh[56]|cell_oh[63]|cell_oh[64]|cell_oh[65]|cell_oh[72]|cell_oh[73]|cell_oh[74];
assign box_used_w[7] = cell_oh[57]|cell_oh[58]|cell_oh[59]|cell_oh[66]|cell_oh[67]|cell_oh[68]|cell_oh[75]|cell_oh[76]|cell_oh[77];
assign box_used_w[8] = cell_oh[60]|cell_oh[61]|cell_oh[62]|cell_oh[69]|cell_oh[70]|cell_oh[71]|cell_oh[78]|cell_oh[79]|cell_oh[80];

// ============== base candidates =================
wire [8:0] cand_w  [0:80];
genvar cr, cc2;
generate
for (cr=0; cr<9; cr=cr+1) begin: G_CAND_R
  for (cc2=0; cc2<9; cc2=cc2+1) begin: G_CAND_C
    localparam integer LIDX = cr*9 + cc2;
    wire [1:0] br2w = fn_br2(cr[3:0]);
    wire [1:0] bc2w = fn_bc2(cc2[3:0]);
    wire [3:0] box  = {br2w,1'b0} + br2w + bc2w; // 3*br + bc
    wire [8:0] used = row_used_w[cr] | col_used_w[cc2] | box_used_w[box];
    assign cand_w[LIDX] = (grid[LIDX]==4'd0) ? ((~used) & 9'h1FF) : 9'b0;
  end
end
endgenerate

// ============== any blank? =================
wire any_blank_w =
    (grid[ 0]==4'd0)|(grid[ 1]==4'd0)|(grid[ 2]==4'd0)|(grid[ 3]==4'd0)|(grid[ 4]==4'd0)|
    (grid[ 5]==4'd0)|(grid[ 6]==4'd0)|(grid[ 7]==4'd0)|(grid[ 8]==4'd0)|(grid[ 9]==4'd0)|
    (grid[10]==4'd0)|(grid[11]==4'd0)|(grid[12]==4'd0)|(grid[13]==4'd0)|(grid[14]==4'd0)|
    (grid[15]==4'd0)|(grid[16]==4'd0)|(grid[17]==4'd0)|(grid[18]==4'd0)|(grid[19]==4'd0)|
    (grid[20]==4'd0)|(grid[21]==4'd0)|(grid[22]==4'd0)|(grid[23]==4'd0)|(grid[24]==4'd0)|
    (grid[25]==4'd0)|(grid[26]==4'd0)|(grid[27]==4'd0)|(grid[28]==4'd0)|(grid[29]==4'd0)|
    (grid[30]==4'd0)|(grid[31]==4'd0)|(grid[32]==4'd0)|(grid[33]==4'd0)|(grid[34]==4'd0)|
    (grid[35]==4'd0)|(grid[36]==4'd0)|(grid[37]==4'd0)|(grid[38]==4'd0)|(grid[39]==4'd0)|
    (grid[40]==4'd0)|(grid[41]==4'd0)|(grid[42]==4'd0)|(grid[43]==4'd0)|(grid[44]==4'd0)|
    (grid[45]==4'd0)|(grid[46]==4'd0)|(grid[47]==4'd0)|(grid[48]==4'd0)|(grid[49]==4'd0)|
    (grid[50]==4'd0)|(grid[51]==4'd0)|(grid[52]==4'd0)|(grid[53]==4'd0)|(grid[54]==4'd0)|
    (grid[55]==4'd0)|(grid[56]==4'd0)|(grid[57]==4'd0)|(grid[58]==4'd0)|(grid[59]==4'd0)|
    (grid[60]==4'd0)|(grid[61]==4'd0)|(grid[62]==4'd0)|(grid[63]==4'd0)|(grid[64]==4'd0)|
    (grid[65]==4'd0)|(grid[66]==4'd0)|(grid[67]==4'd0)|(grid[68]==4'd0)|(grid[69]==4'd0)|
    (grid[70]==4'd0)|(grid[71]==4'd0)|(grid[72]==4'd0)|(grid[73]==4'd0)|(grid[74]==4'd0)|
    (grid[75]==4'd0)|(grid[76]==4'd0)|(grid[77]==4'd0)|(grid[78]==4'd0)|(grid[79]==4'd0)|
    (grid[80]==4'd0);

// ============== NAKED SINGLE（assign）============
wire naked_w [0:80][0:8];
genvar ni, nd;
generate
for (ni=0; ni<81; ni=ni+1) begin: G_NAKED
  for (nd=0; nd<9; nd=nd+1) begin: G_NAKED_D
    localparam [8:0] ONEHOT = (9'b1 << nd);
    wire [8:0] others_mask = (cand_w[ni] & ~ONEHOT);
    wire       others_or   = |others_mask;
    assign naked_w[ni][nd] = cand_w[ni][nd] & ~others_or;
  end
end
endgenerate

// ============== HIDDEN SINGLE — ROW/COL/BOX（assign）============
wire row_hidden_w [0:80][0:8];
wire col_hidden_w [0:80][0:8];
wire box_hidden_w [0:80][0:8];

genvar hr, hd, hc, hcd, bb, bd;
generate
// row hidden
for (hr=0; hr<9; hr=hr+1) begin: G_HR
  for (hd=0; hd<9; hd=hd+1) begin: G_HR_D
    wire rv0 = cand_w[hr*9+0][hd];
    wire rv1 = cand_w[hr*9+1][hd];
    wire rv2 = cand_w[hr*9+2][hd];
    wire rv3 = cand_w[hr*9+3][hd];
    wire rv4 = cand_w[hr*9+4][hd];
    wire rv5 = cand_w[hr*9+5][hd];
    wire rv6 = cand_w[hr*9+6][hd];
    wire rv7 = cand_w[hr*9+7][hd];
    wire rv8 = cand_w[hr*9+8][hd];

    wire p0  = 1'b0;
    wire p1  = p0 | rv0;
    wire p2  = p1 | rv1;
    wire p3  = p2 | rv2;
    wire p4  = p3 | rv3;
    wire p5  = p4 | rv4;
    wire p6  = p5 | rv5;
    wire p7  = p6 | rv6;
    wire p8  = p7 | rv7;
    wire p9  = p8 | rv8;

    wire s9  = 1'b0;
    wire s8  = s9 | rv8;
    wire s7  = s8 | rv7;
    wire s6  = s7 | rv6;
    wire s5  = s6 | rv5;
    wire s4  = s5 | rv4;
    wire s3  = s4 | rv3;
    wire s2  = s3 | rv2;
    wire s1  = s2 | rv1;
    wire s0  = s1 | rv0;

    wire o0 = p0 | s1;
    wire o1 = p1 | s2;
    wire o2 = p2 | s3;
    wire o3 = p3 | s4;
    wire o4 = p4 | s5;
    wire o5 = p5 | s6;
    wire o6 = p6 | s7;
    wire o7 = p7 | s8;
    wire o8 = p8 | s9;

    assign row_hidden_w[hr*9+0][hd] = rv0 & ~o0;
    assign row_hidden_w[hr*9+1][hd] = rv1 & ~o1;
    assign row_hidden_w[hr*9+2][hd] = rv2 & ~o2;
    assign row_hidden_w[hr*9+3][hd] = rv3 & ~o3;
    assign row_hidden_w[hr*9+4][hd] = rv4 & ~o4;
    assign row_hidden_w[hr*9+5][hd] = rv5 & ~o5;
    assign row_hidden_w[hr*9+6][hd] = rv6 & ~o6;
    assign row_hidden_w[hr*9+7][hd] = rv7 & ~o7;
    assign row_hidden_w[hr*9+8][hd] = rv8 & ~o8;
  end
end
// col hidden
for (hc=0; hc<9; hc=hc+1) begin: G_HC
  for (hcd=0; hcd<9; hcd=hcd+1) begin: G_HC_D
    wire rv0 = cand_w[0*9+hc][hcd];
    wire rv1 = cand_w[1*9+hc][hcd];
    wire rv2 = cand_w[2*9+hc][hcd];
    wire rv3 = cand_w[3*9+hc][hcd];
    wire rv4 = cand_w[4*9+hc][hcd];
    wire rv5 = cand_w[5*9+hc][hcd];
    wire rv6 = cand_w[6*9+hc][hcd];
    wire rv7 = cand_w[7*9+hc][hcd];
    wire rv8 = cand_w[8*9+hc][hcd];

    wire p0  = 1'b0;
    wire p1  = p0 | rv0;
    wire p2  = p1 | rv1;
    wire p3  = p2 | rv2;
    wire p4  = p3 | rv3;
    wire p5  = p4 | rv4;
    wire p6  = p5 | rv5;
    wire p7  = p6 | rv6;
    wire p8  = p7 | rv7;
    wire p9  = p8 | rv8;

    wire s9  = 1'b0;
    wire s8  = s9 | rv8;
    wire s7  = s8 | rv7;
    wire s6  = s7 | rv6;
    wire s5  = s6 | rv5;
    wire s4  = s5 | rv4;
    wire s3  = s4 | rv3;
    wire s2  = s3 | rv2;
    wire s1  = s2 | rv1;
    wire s0  = s1 | rv0;

    wire o0 = p0 | s1;
    wire o1 = p1 | s2;
    wire o2 = p2 | s3;
    wire o3 = p3 | s4;
    wire o4 = p4 | s5;
    wire o5 = p5 | s6;
    wire o6 = p6 | s7;
    wire o7 = p7 | s8;
    wire o8 = p8 | s9;

    assign col_hidden_w[0*9+hc][hcd] = rv0 & ~o0;
    assign col_hidden_w[1*9+hc][hcd] = rv1 & ~o1;
    assign col_hidden_w[2*9+hc][hcd] = rv2 & ~o2;
    assign col_hidden_w[3*9+hc][hcd] = rv3 & ~o3;
    assign col_hidden_w[4*9+hc][hcd] = rv4 & ~o4;
    assign col_hidden_w[5*9+hc][hcd] = rv5 & ~o5;
    assign col_hidden_w[6*9+hc][hcd] = rv6 & ~o6;
    assign col_hidden_w[7*9+hc][hcd] = rv7 & ~o7;
    assign col_hidden_w[8*9+hc][hcd] = rv8 & ~o8;
  end
end
// box hidden
for (bb=0; bb<9; bb=bb+1) begin: G_HB
  localparam integer BR = (bb/3);
  localparam integer BC = (bb%3);
  localparam integer R0 = BR*3;
  localparam integer C0 = BC*3;
  for (bd=0; bd<9; bd=bd+1) begin: G_HB_D
    wire rv0 = cand_w[(R0+0)*9+(C0+0)][bd];
    wire rv1 = cand_w[(R0+0)*9+(C0+1)][bd];
    wire rv2 = cand_w[(R0+0)*9+(C0+2)][bd];
    wire rv3 = cand_w[(R0+1)*9+(C0+0)][bd];
    wire rv4 = cand_w[(R0+1)*9+(C0+1)][bd];
    wire rv5 = cand_w[(R0+1)*9+(C0+2)][bd];
    wire rv6 = cand_w[(R0+2)*9+(C0+0)][bd];
    wire rv7 = cand_w[(R0+2)*9+(C0+1)][bd];
    wire rv8 = cand_w[(R0+2)*9+(C0+2)][bd];

    wire p0  = 1'b0;
    wire p1  = p0 | rv0;
    wire p2  = p1 | rv1;
    wire p3  = p2 | rv2;
    wire p4  = p3 | rv3;
    wire p5  = p4 | rv4;
    wire p6  = p5 | rv5;
    wire p7  = p6 | rv6;
    wire p8  = p7 | rv7;
    wire p9  = p8 | rv8;

    wire s9  = 1'b0;
    wire s8  = s9 | rv8;
    wire s7  = s8 | rv7;
    wire s6  = s7 | rv6;
    wire s5  = s6 | rv5;
    wire s4  = s5 | rv4;
    wire s3  = s4 | rv3;
    wire s2  = s3 | rv2;
    wire s1  = s2 | rv1;
    wire s0  = s1 | rv0;

    wire o0 = p0 | s1;
    wire o1 = p1 | s2;
    wire o2 = p2 | s3;
    wire o3 = p3 | s4;
    wire o4 = p4 | s5;
    wire o5 = p5 | s6;
    wire o6 = p6 | s7;
    wire o7 = p7 | s8;
    wire o8 = p8 | s9;

    assign box_hidden_w[(R0+0)*9+(C0+0)][bd] = rv0 & ~o0;
    assign box_hidden_w[(R0+0)*9+(C0+1)][bd] = rv1 & ~o1;
    assign box_hidden_w[(R0+0)*9+(C0+2)][bd] = rv2 & ~o2;
    assign box_hidden_w[(R0+1)*9+(C0+0)][bd] = rv3 & ~o3;
    assign box_hidden_w[(R0+1)*9+(C0+1)][bd] = rv4 & ~o4;
    assign box_hidden_w[(R0+1)*9+(C0+2)][bd] = rv5 & ~o5;
    assign box_hidden_w[(R0+2)*9+(C0+0)][bd] = rv6 & ~o6;
    assign box_hidden_w[(R0+2)*9+(C0+1)][bd] = rv7 & ~o7;
    assign box_hidden_w[(R0+2)*9+(C0+2)][bd] = rv8 & ~o8;
  end
end
endgenerate

wire [8:0] fill_oh [0:80];
wire       fill_en [0:80];

genvar fi, fd;
generate
for (fi=0; fi<81; fi=fi+1) begin: G_FILL
  wire [8:0] naked_vec;
  wire [8:0] rowhid_vec;
  wire [8:0] colhid_vec;
  wire [8:0] boxhid_vec;
  for (fd=0; fd<9; fd=fd+1) begin: G_FILL_D
    assign naked_vec[fd]  = naked_w[fi][fd];
    assign rowhid_vec[fd] = row_hidden_w[fi][fd];
    assign colhid_vec[fd] = col_hidden_w[fi][fd];
    assign boxhid_vec[fd] = box_hidden_w[fi][fd];
  end
  assign fill_oh[fi] = naked_vec | rowhid_vec | colhid_vec | boxhid_vec;
  assign fill_en[fi] = |fill_oh[fi];
end
endgenerate

wire any_conflict_w;
genvar ci3;
generate
wire [80:0] conflict_vec;
for (ci3=0; ci3<81; ci3=ci3+1) begin: G_CONFLICT
  assign conflict_vec[ci3] = (grid[ci3]==4'd0) && (cand_w[ci3]==9'b0);
end
assign any_conflict_w = |conflict_vec;
endgenerate

// ================== grid_n ==================
integer t;
always @* begin
    for (t=0; t<81; t=t+1) grid_n[t] = grid[t];
    for (t=0; t<81; t=t+1) if (fill_en[t]) grid_n[t] = pick_num(fill_oh[t]);
end

// ================== FSM / Mealy ===============================
wire blanks_zero   = ~any_blank_w;
wire stop_solve    = any_conflict_w | blanks_zero;

// out_idx==80：7'b1010000
wire last80 =  out_idx[6] & ~out_idx[5] &  out_idx[4] &
              ~out_idx[3] & ~out_idx[2] & ~out_idx[1] & ~out_idx[0];

wire will_start_out = (state==S_SOLVE) && stop_solve;

always @* begin
    case (state)
        S_IDLE  : nstate = in_valid   ? S_LOAD   : S_IDLE;
        S_LOAD  : nstate = load_done  ? S_SOLVE  : S_LOAD;
        S_SOLVE : nstate = stop_solve ? S_OUT    : S_SOLVE; 
        S_OUT   : nstate = last80     ? S_IDLE   : S_OUT;
        default : nstate = S_IDLE;
    endcase
end

// ================== *_n：in / out_idx ==================
always @* begin
    in_cnt_n    = in_cnt;
    load_done_n = load_done;
    case (state)
      S_IDLE: begin
          if (in_valid) begin
              in_cnt_n    = 7'd1;
              load_done_n = 1'b0;
          end else begin
              in_cnt_n    = 7'd0;
              load_done_n = 1'b0;
          end
      end
      S_LOAD: begin
          if (in_valid) begin
              in_cnt_n    = in_cnt + 7'd1;
              load_done_n = (in_cnt==7'd80);
          end
      end
      default: ;
    endcase
end

// out_idx：Mealy 
always @* begin
    out_idx_n = out_idx;
    if (will_start_out) begin
        out_idx_n = 7'd1;               
    end else if (state==S_OUT && !last80) begin
        out_idx_n = out_idx + 7'd1;        
    end else if (state!=S_OUT) begin
        out_idx_n = 7'd0;                   
    end
end

// ================== Combinational Output（Mealy） ==================
wire        out_valid_c = will_start_out || (state==S_OUT);
wire [3:0]  out_data_c0 = grid_n[0];
wire [3:0]  out_data_cs = grid[out_idx]; 
wire [3:0]  out_data_c  = will_start_out ? out_data_c0 :
                          (state==S_OUT ? out_data_cs : 4'd0);

always @* begin
    out_valid = out_valid_c;
    out       = out_data_c;
end

// ================== Seq / IO ==================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= S_IDLE;
        in_cnt     <= 7'd0;
        load_done  <= 1'b0;
        out_idx    <= 7'd0;
        for (t=0;t<81;t=t+1) grid[t] <= 4'd0;
    end else begin
        state     <= nstate;
        in_cnt    <= in_cnt_n;
        load_done <= load_done_n;
        out_idx   <= out_idx_n;

        if (state==S_IDLE) begin
            if (in_valid) grid[0] <= in;
        end else if (state==S_LOAD) begin
            if (in_valid) grid[in_cnt] <= in;
        end else if (state==S_SOLVE) begin
            integer k;
            for (k=0; k<81; k=k+1) grid[k] <= grid_n[k];
        end
    end
end

endmodule
