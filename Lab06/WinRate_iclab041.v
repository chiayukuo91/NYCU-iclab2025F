`timescale 1ns/10ps
`default_nettype none
`include "Poker.v"

module WinRate (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [71:0] in_hole_num,   // 18*4b
    input  wire [35:0] in_hole_suit,  // 18*2b
    input  wire [11:0] in_pub_num,    // 3*4b
    input  wire [5:0]  in_pub_suit,   // 3*2b (flop)
    output reg         out_valid,
    output reg  [62:0] out_win_rate
);

// 0..51 = ((num-2)<<2) | suit
function [5:0] enc52;
  input [3:0] num;  // 2..14
  input [1:0] suit; // 0..3
  begin
    enc52 = { (num-4'd2), suit } ; // (num-2)<<2 | suit
  end
endfunction

wire [8:0] out_winner;
localparam IDLE = 2'd0;
localparam LOAD = 2'd1;
localparam RUN  = 2'd2;

reg  [5:0] turn_c, river_c;
wire [3:0] turn_num   = turn_c [5:2] + 4'd2;
wire [1:0] turn_suit  = turn_c [1:0];
wire [3:0] river_num  = river_c[5:2] + 4'd2;
wire [1:0] river_suit = river_c[1:0];

wire       is_Poker_available;
reg  [125:0] in_pack;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    in_pack <= 126'd0;
  else if (in_valid)
    in_pack <= {in_hole_num, in_hole_suit, in_pub_num, in_pub_suit};
end

wire [71:0] in_hole_num_reg  = in_pack[125:54];
wire [35:0] in_hole_suit_reg = in_pack[ 53:18];
wire [11:0] in_pub_num_reg   = in_pack[ 17: 6];
wire [ 5:0] in_pub_suit_reg  = in_pack[  5: 0];

reg  [51:0] used_bitmap;     
wire [51:0] used_bitmap_nxt;

reg  [8:0] player_result [8:0];
reg        player_cut_2 [8:0];
reg  [1:0] player_cut_3 [8:0];
reg  [1:0] player_cut_4 [8:0];
reg  [3:0] player_cut_9 [8:0];

wire [8:0] nxt_player_result [8:0];
wire       nxt_player_cut_2 [8:0];
wire [1:0] nxt_player_cut_3 [8:0];
wire [1:0] nxt_player_cut_4 [8:0];
wire [3:0] nxt_player_cut_9 [8:0];

wire [10:0] rem1 [8:0];
wire [14:0] rem2 [8:0];
wire [6:0]  player_win_rate [8:0];
reg out_pulse_reg;

// Poker
Poker #(.IP_WIDTH(9)) I_Poker_IP (
    .IN_HOLE_CARD_NUM (in_hole_num_reg),
    .IN_HOLE_CARD_SUIT(in_hole_suit_reg),
    .IN_PUB_CARD_NUM  ({in_pub_num_reg,  turn_num,  river_num}),   // 20b
    .IN_PUB_CARD_SUIT ({in_pub_suit_reg, turn_suit, river_suit}),  // 10b
    .OUT_WINNER       (out_winner)
);

reg [1:0] state_now, state_nxt;
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) state_now <= IDLE;
  else        state_now <= state_nxt;
end

wire [5:0] nxt_river_free;    
wire [5:0] nxt_turn_free; 
wire       none_river;        
wire       none_turn;         
wire       no_more_pairs;

always @(*) begin
  case (state_now)
    IDLE: state_nxt = in_valid ? LOAD : IDLE;
    LOAD: state_nxt = RUN;
    RUN : state_nxt = (no_more_pairs ? IDLE : RUN);
    default: state_nxt = IDLE;
  endcase
end

wire [3:0] hn [0:17];
wire [1:0] hs [0:17];
genvar gh;
generate
  for (gh=0; gh<18; gh=gh+1) begin : G_HOLE_UNPACK
    assign hn[gh] = in_hole_num_reg [4*gh +: 4];
    assign hs[gh] = in_hole_suit_reg[2*gh +: 2];
  end
endgenerate

wire [3:0] pn0 = in_pub_num_reg [ 3:0];
wire [3:0] pn1 = in_pub_num_reg [ 7:4];
wire [3:0] pn2 = in_pub_num_reg [11:8];
wire [1:0] ps0 = in_pub_suit_reg[1:0];
wire [1:0] ps1 = in_pub_suit_reg[3:2];
wire [1:0] ps2 = in_pub_suit_reg[5:4];

reg  [51:0] set_mask;  
integer t;
always @(*) begin
  set_mask = 52'd0;
  for (t=0; t<18; t=t+1) begin
    if (hn[t]>=4'd2 && hn[t]<=4'd14) set_mask[ enc52(hn[t], hs[t]) ] = 1'b1;
  end
  if (pn0>=4'd2 && pn0<=4'd14) set_mask[ enc52(pn0, ps0) ] = 1'b1;
  if (pn1>=4'd2 && pn1<=4'd14) set_mask[ enc52(pn1, ps1) ] = 1'b1;
  if (pn2>=4'd2 && pn2<=4'd14) set_mask[ enc52(pn2, ps2) ] = 1'b1;
end
assign used_bitmap_nxt = set_mask;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) used_bitmap <= 52'd0;
  else if (state_now==LOAD) used_bitmap <= used_bitmap_nxt;
end

function [5:0] first_free;
  input [51:0] used;
  integer i; reg [5:0] ff;
  begin
    ff = 6'd63;
    for (i=0; i<52; i=i+1)
      if (!used[i] && ff==6'd63) ff = i[5:0];
    first_free = ff;
  end
endfunction

function [5:0] nxt_free_after;
  input [51:0] used;
  input [5:0]  start;
  integer i; reg [5:0] nf;
  begin
    nf = 6'd63;
    for (i=0; i<52; i=i+1)
      if ((i > start) && !used[i] && (nf==6'd63)) nf = i[5:0];
    nxt_free_after = nf;
  end
endfunction

assign nxt_river_free = nxt_free_after(used_bitmap, river_c);
assign nxt_turn_free  = nxt_free_after(used_bitmap, turn_c);
assign none_river      = (nxt_river_free == 6'd63);
assign none_turn       = (nxt_turn_free  == 6'd63);
assign no_more_pairs   = none_river && none_turn;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    turn_c   <= 6'd63; 
    river_c  <= 6'd63; 
    out_pulse_reg <= 1'b0;
  end else begin
    out_pulse_reg <= 1'b0;

    case (state_now)
      LOAD: begin
        turn_c  <= first_free(used_bitmap_nxt);
        river_c <= nxt_free_after(used_bitmap_nxt, first_free(used_bitmap_nxt));
      end
      RUN: begin
        if (!none_river) begin
          river_c <= nxt_river_free;
          turn_c  <= turn_c;
        end
        else if (!none_turn) begin
          turn_c  <= nxt_turn_free;
          river_c <= nxt_free_after(used_bitmap, nxt_turn_free);
        end
        else begin
          turn_c   <= turn_c;
          river_c  <= river_c;
          out_pulse_reg <= 1'b1; 
        end
      end
      default: begin
        turn_c  <= turn_c;
        river_c <= river_c;
      end
    endcase
  end
end

assign is_Poker_available = (state_now==RUN) &&
                            (turn_c  < 6'd52) &&
                            (river_c < 6'd52);

// winner_count
wire [1:0] s01   = out_winner[0] + out_winner[1];
wire [1:0] s23   = out_winner[2] + out_winner[3];
wire [1:0] s45   = out_winner[4] + out_winner[5];
wire [1:0] s67   = out_winner[6] + out_winner[7];
wire [2:0] s0123 = s01 + s23;
wire [2:0] s4567 = s45 + s67;
wire [3:0] winner_count = s0123 + s4567 + out_winner[8];

wire clr_counts = (state_now==LOAD);

genvar p;
generate
  for (p=0; p<9; p=p+1) begin : G_PER_PLAYER
    wire win_k = out_winner[p];

    wire is1 = (winner_count==4'd1);
    wire is2 = (winner_count==4'd2);
    wire is3 = (winner_count==4'd3);
    wire is4 = (winner_count==4'd4);
    wire is9 = (winner_count==4'd9);
    wire do_acc = is_Poker_available;

    wire inc2 = win_k & is2;
    wire inc3 = win_k & is3;
    wire inc4 = win_k & is4;
    wire inc9 = win_k & is9;

    wire wrap2 = inc2 &  player_cut_2[p];             // 0→1→(wrap)0
    wire wrap3 = inc3 & (player_cut_3[p]==2'd2);      // 0→1→2→(wrap)0
    wire wrap4 = inc4 & (player_cut_4[p]==2'd3);      // 0→1→2→3→(wrap)0
    wire wrap9 = inc9 & (player_cut_9[p]==4'd8);      // 0..8→(wrap)0

    wire add_win = (win_k & is1) | wrap2 | wrap3 | wrap4 | wrap9;

    wire       c2_n = inc2 ? ~player_cut_2[p] : player_cut_2[p];
    wire [1:0] c3_t = player_cut_3[p] + {1'b0,inc3};
    wire [1:0] c4_t = player_cut_4[p] + {1'b0,inc4};
    wire [3:0] c9_t = player_cut_9[p] + {3'd0,inc9};

    wire [1:0] c3_n = wrap3 ? 2'd0 : c3_t;
    wire [1:0] c4_n = wrap4 ? 2'd0 : c4_t;
    wire [3:0] c9_n = wrap9 ? 4'd0 : c9_t;

    wire [8:0] res_n = player_result[p] + {8'd0, add_win};

    assign nxt_player_result[p] = clr_counts ? 9'd0 : (do_acc ? res_n : player_result[p]);
    assign nxt_player_cut_2[p] = clr_counts ? 1'b0 : (do_acc ? c2_n : player_cut_2[p]);
    assign nxt_player_cut_3[p] = clr_counts ? 2'd0 : (do_acc ? c3_n : player_cut_3[p]);
    assign nxt_player_cut_4[p] = clr_counts ? 2'd0 : (do_acc ? c4_n : player_cut_4[p]);
    assign nxt_player_cut_9[p] = clr_counts ? 4'd0 : (do_acc ? c9_n : player_cut_9[p]);
  end
endgenerate

genvar gi;
generate
  for (gi = 0; gi < 9; gi = gi + 1) begin : G_PER_PLAYER_REGS
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        player_result[gi] <= 9'd0;
        player_cut_2[gi]  <= 1'b0;
        player_cut_3[gi]  <= 2'd0;
        player_cut_4[gi]  <= 2'd0;
        player_cut_9[gi]  <= 4'd0;
      end else begin
        player_result[gi] <= nxt_player_result[gi];
        player_cut_2[gi]  <= nxt_player_cut_2[gi];
        player_cut_3[gi]  <= nxt_player_cut_3[gi];
        player_cut_4[gi]  <= nxt_player_cut_4[gi];
        player_cut_9[gi]  <= nxt_player_cut_9[gi];
      end
    end
  end
endgenerate

genvar rk;
generate
  for (rk=0; rk<9; rk=rk+1) begin : G_RATE
    // rem1 = wins*4 + cut2*2 + cut4*1
    assign rem1[rk] = {player_result[rk], 2'b00} + {player_cut_2[rk], 1'b0} + player_cut_4[rk];
    // rem2 = cut3*60 + cut9*20
    assign rem2[rk] = (player_cut_3[rk]*15'd60) + (player_cut_9[rk]*15'd20);
    // player_win_rate = ( rem1*5 + floor(rem2/9) ) / 93
    assign player_win_rate[rk] = ( (rem1[rk]*5) + (rem2[rk]/9) ) / 93;
  end
endgenerate

wire [62:0] win_bus = {
  player_win_rate[8], player_win_rate[7], player_win_rate[6],
  player_win_rate[5], player_win_rate[4], player_win_rate[3],
  player_win_rate[2], player_win_rate[1], player_win_rate[0]
};
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    out_valid    <= 1'b0;
    out_win_rate <= 63'd0;
  end else begin
    out_valid    <= out_pulse_reg;
    out_win_rate <= win_bus & {63{out_pulse_reg}};
  end
end

endmodule

`default_nettype wire
