`timescale 1ns/10ps
`default_nettype none

module priority_top13(
  input  wire [12:0] m,
  output reg  [3:0]  top
);
  always @(*) begin
    casez (m)
	  13'b1???????????? : top = 4'd14;
	  13'b01??????????? : top = 4'd13;
	  13'b001?????????? : top = 4'd12;
	  13'b0001????????? : top = 4'd11;
	  13'b00001???????? : top = 4'd10;
	  13'b000001??????? : top = 4'd9;
	  13'b0000001?????? : top = 4'd8;
	  13'b00000001????? : top = 4'd7;
	  13'b000000001???? : top = 4'd6;
	  13'b0000000001??? : top = 4'd5;
	  13'b00000000001?? : top = 4'd4;
	  13'b000000000001? : top = 4'd3;
	  13'b0000000000001 : top = 4'd2;
	  default           : top = 4'd0;
	endcase
  end
endmodule

module peel5_top(
  input  wire [12:0] m,
  output wire [3:0]  t4, t3, t2, t1, t0
);
  function automatic [12:0] rank2mask;
    input [3:0] r;
    begin
      case (r)
        4'd14: rank2mask = 13'b1_0000_0000_0000;
        4'd13: rank2mask = 13'b0_1000_0000_0000;
        4'd12: rank2mask = 13'b0_0100_0000_0000;
        4'd11: rank2mask = 13'b0_0010_0000_0000;
        4'd10: rank2mask = 13'b0_0001_0000_0000;
        4'd9 : rank2mask = 13'b0_0000_1000_0000;
        4'd8 : rank2mask = 13'b0_0000_0100_0000;
        4'd7 : rank2mask = 13'b0_0000_0010_0000;
        4'd6 : rank2mask = 13'b0_0000_0001_0000;
        4'd5 : rank2mask = 13'b0_0000_0000_1000;
        4'd4 : rank2mask = 13'b0_0000_0000_0100;
        4'd3 : rank2mask = 13'b0_0000_0000_0010;
        4'd2 : rank2mask = 13'b0_0000_0000_0001;
        default: rank2mask = 13'b0;
      endcase
    end
  endfunction

  wire [3:0]  T4, T3, T2, T1, T0;
  wire [12:0] M3, M2, M1, M0;

  priority_top13 PE4(.m(m),  .top(T4));  assign M3 = m  & ~rank2mask(T4);
  priority_top13 PE3(.m(M3), .top(T3));  assign M2 = M3 & ~rank2mask(T3);
  priority_top13 PE2(.m(M2), .top(T2));  assign M1 = M2 & ~rank2mask(T2);
  priority_top13 PE1(.m(M1), .top(T1));  assign M0 = M1 & ~rank2mask(T1);
  priority_top13 PE0(.m(M0), .top(T0));

  assign t4=T4; assign t3=T3; assign t2=T2; assign t1=T1; assign t0=T0;
endmodule

module Rank7_hist (
  input  wire [27:0] NUM7,   // 7*4b (2..14)
  input  wire [13:0] SUT7,   // 7*2b (0..3)
  output wire [23:0] SCORE
);
  function automatic [12:0] rank2mask;
    input [3:0] r;
    begin
      case (r)
        4'd14: rank2mask = 13'b1_0000_0000_0000;
        4'd13: rank2mask = 13'b0_1000_0000_0000;
        4'd12: rank2mask = 13'b0_0100_0000_0000;
        4'd11: rank2mask = 13'b0_0010_0000_0000;
        4'd10: rank2mask = 13'b0_0001_0000_0000;
        4'd9 : rank2mask = 13'b0_0000_1000_0000;
        4'd8 : rank2mask = 13'b0_0000_0100_0000;
        4'd7 : rank2mask = 13'b0_0000_0010_0000;
        4'd6 : rank2mask = 13'b0_0000_0001_0000;
        4'd5 : rank2mask = 13'b0_0000_0000_1000;
        4'd4 : rank2mask = 13'b0_0000_0000_0100;
        4'd3 : rank2mask = 13'b0_0000_0000_0010;
        4'd2 : rank2mask = 13'b0_0000_0000_0001;
        default: rank2mask = 13'b0;
      endcase
    end
  endfunction

  wire [3:0] n0 = NUM7[ 3: 0], n1 = NUM7[ 7: 4], n2 = NUM7[11: 8],
             n3 = NUM7[15:12], n4 = NUM7[19:16], n5 = NUM7[23:20], n6 = NUM7[27:24];
  wire [1:0] s0 = SUT7[ 1: 0], s1 = SUT7[ 3: 2], s2 = SUT7[ 5: 4],
             s3 = SUT7[ 7: 6], s4 = SUT7[ 9: 8], s5 = SUT7[11:10], s6 = SUT7[13:12];

  wire [12:0] r1hot0, r1hot1, r1hot2, r1hot3, r1hot4, r1hot5, r1hot6;
  genvar gi;
  generate
    for (gi=0; gi<13; gi=gi+1) begin : G_HOT
      assign r1hot0[gi] = (n0 == (gi[3:0] + 4'd2));
      assign r1hot1[gi] = (n1 == (gi[3:0] + 4'd2));
      assign r1hot2[gi] = (n2 == (gi[3:0] + 4'd2));
      assign r1hot3[gi] = (n3 == (gi[3:0] + 4'd2));
      assign r1hot4[gi] = (n4 == (gi[3:0] + 4'd2));
      assign r1hot5[gi] = (n5 == (gi[3:0] + 4'd2));
      assign r1hot6[gi] = (n6 == (gi[3:0] + 4'd2));
    end
  endgenerate

  wire s0is0=(s0==2'd0), s0is1=(s0==2'd1), s0is2=(s0==2'd2), s0is3=(s0==2'd3);
  wire s1is0=(s1==2'd0), s1is1=(s1==2'd1), s1is2=(s1==2'd2), s1is3=(s1==2'd3);
  wire s2is0=(s2==2'd0), s2is1=(s2==2'd1), s2is2=(s2==2'd2), s2is3=(s2==2'd3);
  wire s3is0=(s3==2'd0), s3is1=(s3==2'd1), s3is2=(s3==2'd2), s3is3=(s3==2'd3);
  wire s4is0=(s4==2'd0), s4is1=(s4==2'd1), s4is2=(s4==2'd2), s4is3=(s4==2'd3);
  wire s5is0=(s5==2'd0), s5is1=(s5==2'd1), s5is2=(s5==2'd2), s5is3=(s5==2'd3);
  wire s6is0=(s6==2'd0), s6is1=(s6==2'd1), s6is2=(s6==2'd2), s6is3=(s6==2'd3);

  wire [12:0] rank_mask = r1hot0 | r1hot1 | r1hot2 | r1hot3 | r1hot4 | r1hot5 | r1hot6;

  wire [12:0] srm0 = (r1hot0 & {13{s0is0}}) | (r1hot1 & {13{s1is0}}) | (r1hot2 & {13{s2is0}})
                    |(r1hot3 & {13{s3is0}}) | (r1hot4 & {13{s4is0}}) | (r1hot5 & {13{s5is0}}) | (r1hot6 & {13{s6is0}});
  wire [12:0] srm1 = (r1hot0 & {13{s0is1}}) | (r1hot1 & {13{s1is1}}) | (r1hot2 & {13{s2is1}})
                    |(r1hot3 & {13{s3is1}}) | (r1hot4 & {13{s4is1}}) | (r1hot5 & {13{s5is1}}) | (r1hot6 & {13{s6is1}});
  wire [12:0] srm2 = (r1hot0 & {13{s0is2}}) | (r1hot1 & {13{s1is2}}) | (r1hot2 & {13{s2is2}})
                    |(r1hot3 & {13{s3is2}}) | (r1hot4 & {13{s4is2}}) | (r1hot5 & {13{s5is2}}) | (r1hot6 & {13{s6is2}});
  wire [12:0] srm3 = (r1hot0 & {13{s0is3}}) | (r1hot1 & {13{s1is3}}) | (r1hot2 & {13{s2is3}})
                    |(r1hot3 & {13{s3is3}}) | (r1hot4 & {13{s4is3}}) | (r1hot5 & {13{s5is3}}) | (r1hot6 & {13{s6is3}});

  wire [2:0] sc0 = s0is0 + s1is0 + s2is0 + s3is0 + s4is0 + s5is0 + s6is0;
  wire [2:0] sc1 = s0is1 + s1is1 + s2is1 + s3is1 + s4is1 + s5is1 + s6is1;
  wire [2:0] sc2 = s0is2 + s1is2 + s2is2 + s3is2 + s4is2 + s5is2 + s6is2;
  wire [2:0] sc3 = s0is3 + s1is3 + s2is3 + s3is3 + s4is3 + s5is3 + s6is3;

  wire [12:0] str_head_vec = rank_mask &
                             (rank_mask << 1) &
                             (rank_mask << 2) &
                             (rank_mask << 3) &
                             (rank_mask << 4);
  wire wheel_any = rank_mask[12] & rank_mask[3] & rank_mask[2] & rank_mask[1] & rank_mask[0];

  wire [3:0] straight_head_from_vec;
  priority_top13 U_PE_ST (.m(str_head_vec), .top(straight_head_from_vec));

  wire       straight_yes   = (|str_head_vec) | wheel_any;
  wire [3:0] straight_head  = (|str_head_vec) ? straight_head_from_vec : 4'd5;

  wire [12:0] sfv0 = srm0 & (srm0<<1) & (srm0<<2) & (srm0<<3) & (srm0<<4);
  wire [12:0] sfv1 = srm1 & (srm1<<1) & (srm1<<2) & (srm1<<3) & (srm1<<4);
  wire [12:0] sfv2 = srm2 & (srm2<<1) & (srm2<<2) & (srm2<<3) & (srm2<<4);
  wire [12:0] sfv3 = srm3 & (srm3<<1) & (srm3<<2) & (srm3<<3) & (srm3<<4);
  wire        swh0 = srm0[12] & srm0[3] & srm0[2] & srm0[1] & srm0[0];
  wire        swh1 = srm1[12] & srm1[3] & srm1[2] & srm1[1] & srm1[0];
  wire        swh2 = srm2[12] & srm2[3] & srm2[2] & srm2[1] & srm2[0];
  wire        swh3 = srm3[12] & srm3[3] & srm3[2] & srm3[1] & srm3[0];

  wire [12:0] sf_head_all  = sfv0 | sfv1 | sfv2 | sfv3;
  wire        sf_wheel_any = swh0 | swh1 | swh2 | swh3;

  wire [3:0] sf_head_from_vec;
  priority_top13 U_PE_SF (.m(sf_head_all), .top(sf_head_from_vec));

  wire       straight_flush_yes  = (|sf_head_all) | sf_wheel_any;
  wire [3:0] straight_flush_head = (|sf_head_all) ? sf_head_from_vec : 4'd5;

  wire ge5_0 = (sc0>=3'd5), ge5_1=(sc1>=3'd5), ge5_2=(sc2>=3'd5), ge5_3=(sc3>=3'd5);
  wire [12:0] flush_mask_sel =
      ge5_3 ? srm3 :
      ge5_2 ? srm2 :
      ge5_1 ? srm1 :
      ge5_0 ? srm0 : 13'd0;
  wire flush_yes = |flush_mask_sel;

  wire [3:0] f4,f3,f2,f1,f0;
  peel5_top U_PEEL_FLUSH (.m(flush_mask_sel), .t4(f4), .t3(f3), .t2(f2), .t1(f1), .t0(f0));

  wire [2:0] rc0  = r1hot0[0]  + r1hot1[0]  + r1hot2[0]  + r1hot3[0]  + r1hot4[0]  + r1hot5[0]  + r1hot6[0];
  wire [2:0] rc1  = r1hot0[1]  + r1hot1[1]  + r1hot2[1]  + r1hot3[1]  + r1hot4[1]  + r1hot5[1]  + r1hot6[1];
  wire [2:0] rc2  = r1hot0[2]  + r1hot1[2]  + r1hot2[2]  + r1hot3[2]  + r1hot4[2]  + r1hot5[2]  + r1hot6[2];
  wire [2:0] rc3  = r1hot0[3]  + r1hot1[3]  + r1hot2[3]  + r1hot3[3]  + r1hot4[3]  + r1hot5[3]  + r1hot6[3];
  wire [2:0] rc4  = r1hot0[4]  + r1hot1[4]  + r1hot2[4]  + r1hot3[4]  + r1hot4[4]  + r1hot5[4]  + r1hot6[4];
  wire [2:0] rc5  = r1hot0[5]  + r1hot1[5]  + r1hot2[5]  + r1hot3[5]  + r1hot4[5]  + r1hot5[5]  + r1hot6[5];
  wire [2:0] rc6  = r1hot0[6]  + r1hot1[6]  + r1hot2[6]  + r1hot3[6]  + r1hot4[6]  + r1hot5[6]  + r1hot6[6];
  wire [2:0] rc7  = r1hot0[7]  + r1hot1[7]  + r1hot2[7]  + r1hot3[7]  + r1hot4[7]  + r1hot5[7]  + r1hot6[7];
  wire [2:0] rc8  = r1hot0[8]  + r1hot1[8]  + r1hot2[8]  + r1hot3[8]  + r1hot4[8]  + r1hot5[8]  + r1hot6[8];
  wire [2:0] rc9  = r1hot0[9]  + r1hot1[9]  + r1hot2[9]  + r1hot3[9]  + r1hot4[9]  + r1hot5[9]  + r1hot6[9];
  wire [2:0] rc10 = r1hot0[10] + r1hot1[10] + r1hot2[10] + r1hot3[10] + r1hot4[10] + r1hot5[10] + r1hot6[10];
  wire [2:0] rc11 = r1hot0[11] + r1hot1[11] + r1hot2[11] + r1hot3[11] + r1hot4[11] + r1hot5[11] + r1hot6[11];
  wire [2:0] rc12 = r1hot0[12] + r1hot1[12] + r1hot2[12] + r1hot3[12] + r1hot4[12] + r1hot5[12] + r1hot6[12];

  wire [12:0] mask_eq4 = { (rc12==3'd4),(rc11==3'd4),(rc10==3'd4),(rc9==3'd4),(rc8==3'd4),
                           (rc7==3'd4),(rc6==3'd4),(rc5==3'd4),(rc4==3'd4),(rc3==3'd4),
                           (rc2==3'd4),(rc1==3'd4),(rc0==3'd4) };

  wire [12:0] mask_eq3 = { (rc12==3'd3),(rc11==3'd3),(rc10==3'd3),(rc9==3'd3),(rc8==3'd3),
                           (rc7==3'd3),(rc6==3'd3),(rc5==3'd3),(rc4==3'd3),(rc3==3'd3),
                           (rc2==3'd3),(rc1==3'd3),(rc0==3'd3) };

  wire [12:0] mask_eq2 = { (rc12==3'd2),(rc11==3'd2),(rc10==3'd2),(rc9==3'd2),(rc8==3'd2),
                           (rc7==3'd2),(rc6==3'd2),(rc5==3'd2),(rc4==3'd2),(rc3==3'd2),
                           (rc2==3'd2),(rc1==3'd2),(rc0==3'd2) };

  wire       have_four = |mask_eq4;
  wire [3:0] quad_rank;
  priority_top13 U_PE_4 (.m(mask_eq4), .top(quad_rank));
  wire [12:0] mask_not_quad = rank_mask & ~rank2mask(quad_rank);
  wire [3:0] quad_kicker;
  priority_top13 U_PE_4K (.m(mask_not_quad), .top(quad_kicker));

  wire       have_trip = |mask_eq3;
  wire [3:0] trip_rank_A, trip_rank_B;
  priority_top13 U_PE_3A (.m(mask_eq3), .top(trip_rank_A));
  wire [12:0] mask_eq3_wo_A = mask_eq3 & ~rank2mask(trip_rank_A);
  priority_top13 U_PE_3B (.m(mask_eq3_wo_A), .top(trip_rank_B));

  wire       have_pair = |mask_eq2;
  wire [3:0] pair_high, pair_low;
  priority_top13 U_PE_2H (.m(mask_eq2), .top(pair_high));
  wire [12:0] mask_eq2_wo_H = mask_eq2 & ~rank2mask(pair_high);
  priority_top13 U_PE_2L (.m(mask_eq2_wo_H), .top(pair_low));

  wire       have_two_pair = (pair_high!=4'd0) && (pair_low!=4'd0);
  wire       have_full =
      ((trip_rank_A!=4'd0) && (trip_rank_B!=4'd0)) ||
      ((trip_rank_A!=4'd0) && (pair_high  !=4'd0));
  wire [3:0] full_trip = (trip_rank_A!=4'd0) ? trip_rank_A : 4'd0;
  wire [3:0] full_pair = (trip_rank_B!=4'd0) ? trip_rank_B :
                         (pair_high  !=4'd0) ? pair_high   : 4'd0;

  wire [12:0] mask_wo_tripA = rank_mask & ~rank2mask(trip_rank_A);
  wire [3:0] tk1, tk0;
  peel5_top U_PEEL_2K (.m(mask_wo_tripA), .t4(tk1), .t3(tk0), .t2(), .t1(), .t0());

  wire [12:0] mask_wo_2pair = rank_mask & ~rank2mask(pair_high) & ~rank2mask(pair_low);
  wire [3:0] two_kicker;
  priority_top13 U_PE_2K (.m(mask_wo_2pair), .top(two_kicker));

  wire [12:0] mask_wo_pairH = rank_mask & ~rank2mask(pair_high);
  wire [3:0] p_k2, p_k1, p_k0;
  peel5_top U_PEEL_3K (.m(mask_wo_pairH), .t4(p_k2), .t3(p_k1), .t2(p_k0), .t1(), .t0());

  wire [3:0] h4,h3,h2,h1,h0;
  peel5_top U_PEEL_HIGH (.m(rank_mask), .t4(h4), .t3(h3), .t2(h2), .t1(h1), .t0(h0));

  localparam HIGH_CARD       = 4'd0,
             ONE_PAIR        = 4'd1,
             TWO_PAIR        = 4'd2,
             THREE_OF_A_KIND = 4'd3,
             STRAIGHT        = 4'd4,
             FLUSH           = 4'd5,
             FULL_HOUSE      = 4'd6,
             FOUR_OF_A_KIND  = 4'd7,
             STRAIGHT_FLUSH  = 4'd8;

  reg [3:0] rank_type, b4,b3,b2,b1,b0;
  always @(*) begin
    if (straight_flush_yes) begin
      rank_type=STRAIGHT_FLUSH; b4=straight_flush_head; b3=0; b2=0; b1=0; b0=0;
    end else if (have_four) begin
      rank_type=FOUR_OF_A_KIND; b4=quad_rank; b3=quad_kicker; b2=0; b1=0; b0=0;
    end else if (have_full) begin
      rank_type=FULL_HOUSE;     b4=full_trip; b3=full_pair; b2=0; b1=0; b0=0;
    end else if (flush_yes) begin
      rank_type=FLUSH;          b4=f4; b3=f3; b2=f2; b1=f1; b0=f0;
    end else if (straight_yes) begin
      rank_type=STRAIGHT;       b4=straight_head; b3=0; b2=0; b1=0; b0=0;
    end else if (have_trip) begin
      rank_type=THREE_OF_A_KIND;b4=trip_rank_A; b3=tk1; b2=tk0; b1=0; b0=0;
    end else if (have_two_pair) begin
      rank_type=TWO_PAIR;       b4=pair_high; b3=pair_low; b2=two_kicker; b1=0; b0=0;
    end else if (have_pair) begin
      rank_type=ONE_PAIR;       b4=pair_high; b3=p_k2; b2=p_k1; b1=p_k0; b0=0;
    end else begin
      rank_type=HIGH_CARD;      b4=h4; b3=h3; b2=h2; b1=h1; b0=h0;
    end
  end

  assign SCORE = {rank_type, b4,b3,b2,b1,b0};
endmodule

module Poker #(parameter IP_WIDTH = 9) (
  input  wire [IP_WIDTH*8-1:0] IN_HOLE_CARD_NUM,
  input  wire [IP_WIDTH*4-1:0] IN_HOLE_CARD_SUIT,
  input  wire [19:0]           IN_PUB_CARD_NUM,
  input  wire [9:0]            IN_PUB_CARD_SUIT,
  output wire [IP_WIDTH-1:0]   OUT_WINNER
);
  wire [IP_WIDTH*24-1:0] score_bus;

  genvar gi;
  generate
    for (gi=0; gi<IP_WIDTH; gi=gi+1) begin : G_RANK7
      Rank7_hist R7 (
        .NUM7 ( {IN_PUB_CARD_NUM,  IN_HOLE_CARD_NUM [8*gi +: 8]} ),
        .SUT7 ( {IN_PUB_CARD_SUIT, IN_HOLE_CARD_SUIT[4*gi +: 4]} ),
        .SCORE( score_bus[24*gi +: 24] )
      );
    end
  endgenerate

  genvar i,j;
  generate
    for (i=0; i<IP_WIDTH; i=i+1) begin : G_WIN
      wire [IP_WIDTH-1:0] gt_vec;
      for (j=0; j<IP_WIDTH; j=j+1) begin : G_CMP
        if (i==j) assign gt_vec[j] = 1'b0;
        else      assign gt_vec[j] = (score_bus[24*j +: 24] > score_bus[24*i +: 24]);
      end
      assign OUT_WINNER[i] = ~(|gt_vec);
    end
  endgenerate
endmodule

`default_nettype wire
