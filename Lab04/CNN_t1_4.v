module CNN(
    // Input Port
    clk,
    rst_n,
    in_valid,
    Image,
    Kernel_ch1,
    Kernel_ch2,
    Weight_Bias,
    task_number,
    mode,
    capacity_cost,
    // Output Port
    out_valid,
    out
    );
    
// IEEE floating point parameter (You can't modify these parameters)
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch_type = 0;
parameter inst_arch = 0;
parameter inst_faithful_round = 0;

input           clk, rst_n, in_valid;
input   [31:0]  Image;
input   [31:0]  Kernel_ch1;
input   [31:0]  Kernel_ch2;
input   [31:0]  Weight_Bias;
input           task_number;
input   [1:0]   mode;
input   [3:0]   capacity_cost;
output  reg         out_valid;
output  reg [31:0]  out;

// REG / integers
reg task_num;
reg [7:0] cnt;
reg [7:0] x_cnt;
wire [7:0] img_cnt;
reg [31:0] img_map [0:35]; 
reg [31:0] ker_1 [0:17]; 
reg [31:0] ker_2 [0:17]; 
reg [31:0] weight_bias_reg [0:56]; 
reg [3:0] cost_cap_reg [0:4];
reg [1:0] mode_reg;

reg [7:0] fmap_cnt;
reg [7:0] fmap_cnt2;
reg [31:0] fmap1 [0:35]; 
reg [31:0] fmap2 [0:35]; 

reg [31:0] max0 [0:3];
reg [31:0] max1 [0:3];

reg [31:0] soft_exp0, soft_exp1, soft_exp2;
reg [31:0] exp_total;

wire [7:0] final_cost [0:15];
reg [31:0] value [0:15];
reg [31:0] max_val [0:7];
reg [31:0] cmp3_a, cmp3_b;
reg [31:0] cmp4_a, cmp4_b;
reg [31:0] cmp5_a, cmp5_b;
reg [31:0] cmp6_a, cmp6_b;
wire [31:0] max_res3, max_res4, max_res5, max_res6;
reg[31:0] choose;

integer i, k, t; 
function [31:0] leaky_relu_coeff;
    input [31:0] x;
    begin
        // 1.0f  = 32'b00111111100000000000000000000000
        // 0.01f = 32'b00111100001000111101011100001010
        leaky_relu_coeff = x[31] ? 32'b00111100001000111101011100001010
                                 : 32'b00111111100000000000000000000000;
    end
endfunction

reg [31:0] mul0_img, mul0_ker;
reg [31:0] mul1_img, mul1_ker;
reg [31:0] mul2_img, mul2_ker;
reg [31:0] mul3_img, mul3_ker;
reg [31:0] mul4_img, mul4_ker;
reg [31:0] mul5_img, mul5_ker;  
reg [31:0] mul6_img, mul6_ker;
reg [31:0] mul7_img, mul7_ker;
reg [31:0] mul8_img, mul8_ker;
reg [31:0] mul9_ker;
reg [31:0] mul10_ker;
reg [31:0] mul11_ker;
reg [31:0] mul12_ker;
reg [31:0] mul13_ker;
reg [31:0] mul14_ker;  
reg [31:0] mul15_ker;
reg [31:0] mul16_ker;
reg [31:0] mul17_ker;

wire [31:0] mul0_fin;
wire [31:0] mul1_fin;
wire [31:0] mul2_fin;
wire [31:0] mul3_fin;
wire [31:0] mul4_fin;
wire [31:0] mul5_fin;
wire [31:0] mul6_fin;
wire [31:0] mul7_fin;
wire [31:0] mul8_fin;
wire [31:0] mul9_fin;
wire [31:0] mul10_fin;
wire [31:0] mul11_fin;
wire [31:0] mul12_fin;
wire [31:0] mul13_fin;
wire [31:0] mul14_fin;
wire [31:0] mul15_fin;
wire [31:0] mul16_fin;
wire [31:0] mul17_fin;

reg [31:0] conv_cross0;
reg [31:0] conv_cross1;
reg [31:0] conv_cross2;
reg [31:0] conv_cross3;
reg [31:0] conv_cross4;
reg [31:0] conv_cross5;
reg [31:0] conv_cross6;
reg [31:0] conv_cross7;
reg [31:0] conv_cross8;
reg [31:0] conv_cross9;
reg [31:0] conv_cross10;
reg [31:0] conv_cross11;
reg [31:0] conv_cross12;
reg [31:0] conv_cross13;
reg [31:0] conv_cross14;
reg [31:0] conv_cross15;
reg [31:0] conv_cross16;
reg [31:0] conv_cross17;

reg [31:0] in_a1, in_b1, in_c1;
reg [31:0] in_a2, in_b2, in_c2;
reg [31:0] in_a3, in_b3, in_c3;
reg [31:0] in_a4, in_b4, in_c4;
reg [31:0] in_a5, in_b5, in_c5;
reg [31:0] in_a6, in_b6, in_c6;
reg [31:0] in_a7, in_b7, in_c7;
reg [31:0] in_a8, in_b8, in_c8;
wire [31:0] sum_res1, sum_res2, sum_res3, sum_res4;
wire [31:0] sum_res5, sum_res6, sum_res7, sum_res8;
reg [31:0] s_res1, s_res2, s_res3, s_res4;
reg [31:0] s_res5, s_res6, s_res7, s_res8;

reg [31:0] add_a1, add_b1;
reg [31:0] add_a2, add_b2;
reg [31:0] add_op1, add_op2;
wire[31:0] add_res1, add_res2, add_res3;
reg [31:0] minus_op1, minus_op2;
wire[31:0] minus_res;

reg [31:0] cmp11_a, cmp11_b;
reg [31:0] cmp12_a, cmp12_b;
reg [31:0] cmp21_a, cmp21_b;
reg [31:0] cmp22_a, cmp22_b;
wire [31:0] max_temp1_1, max_temp1_2;
wire [31:0] max_temp2_1, max_temp2_2;

reg  [31:0] exp_in1, exp_in2;
wire [31:0] exp_res1, exp_res2;
reg [31:0] div_op1, div_op2;
wire[31:0] div_res;

// counter (sequential)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt <= 8'd0;
    end else begin
        cnt <= x_cnt;
    end
end
// counter next-state (combinational)
always @(*) begin
    if (!in_valid && (cnt == 8'd0)) begin
        x_cnt = 8'd0;
    end else if (task_num && (cnt == 8'd90)) begin
        x_cnt = 8'd0;
    end else if (!task_num && (cnt == 8'd105)) begin
        x_cnt = 8'd0;
    end else begin
        x_cnt = cnt + 8'd1;
    end
end
reg [7:0] img_cnt_c;
always @(*) begin
    case (1'b1)
        (cnt >= 8'd36): img_cnt_c = cnt - 8'd36;
        default       : img_cnt_c = 8'd0;
    endcase
end
assign img_cnt = img_cnt_c;

// img_map
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 36; i = i + 1) begin
            img_map[i] <= 32'd0;
        end
    end else begin
        case (1'b1)
            ( in_valid && (cnt < 8'd36) )                 : img_map[cnt]     <= Image;
            ( in_valid && (cnt >= 8'd36) && (cnt < 8'd72) ): img_map[img_cnt] <= Image;
            default                                       : /* hold */ ;
        endcase
    end
end

// ker_1
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 18; i = i + 1) begin
            ker_1[i] <= 32'd0;
        end
    end else begin
        case (1'b1)
            ( in_valid && (cnt < 8'd18) ) : ker_1[cnt] <= Kernel_ch1;
            default                       : /* hold */ ;
        endcase
    end
end
// ker_2
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 18; i = i + 1) begin
            ker_2[i] <= 32'd0;
        end
    end else begin
        case (1'b1)
            ( in_valid && (cnt < 8'd18) ) : ker_2[cnt] <= Kernel_ch2;
            default                       : /* hold */ ;
        endcase
    end
end

// task_num
always @(posedge clk) begin
    if (!rst_n) begin
        task_num <= 1'b0;
    end else begin
        case (1'b1)
            (in_valid && (cnt == 8'd0)) : task_num <= task_number;
            default                     : /* hold */;
        endcase
    end
end
// weight_bias_reg
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 57; i = i + 1) begin
            weight_bias_reg[i] <= 32'd0;
        end
    end else begin
        case (1'b1)
            (in_valid && (cnt < 8'd57)) : weight_bias_reg[cnt] <= Weight_Bias;
            default                     : /* hold */;
        endcase
    end
end
// cost_cap_reg
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 5; i = i + 1) begin
            cost_cap_reg[i] <= 4'd0;
        end
    end else begin
        case (1'b1)
            (in_valid && (cnt <= 8'd4)) : cost_cap_reg[cnt] <= capacity_cost;
            default                     : /* hold */;
        endcase
    end
end
// mode_reg
always @(posedge clk) begin
    if (!rst_n) begin
        mode_reg <= 2'd0;
    end else begin
        case (1'b1)
            (in_valid && (cnt == 8'd0)) : mode_reg <= mode;
            default                     : /* hold */;
        endcase
    end
end

// Conv & FC
reg [31:0] FC1_in [0:7];
reg [31:0] FC1_out [0:4];
reg [7:0] FC1_out_cnt;
reg [31:0] RELU_out [0:4];
reg [31:0] FC2_out [0:2];

fp_mult mult0 (.inst_a(mul0_img), .inst_b(mul0_ker), .inst_rnd(3'b000), .z_inst(mul0_fin));
fp_mult mult1 (.inst_a(mul1_img), .inst_b(mul1_ker), .inst_rnd(3'b000), .z_inst(mul1_fin));
fp_mult mult2 (.inst_a(mul2_img), .inst_b(mul2_ker), .inst_rnd(3'b000), .z_inst(mul2_fin));
fp_mult mult3 (.inst_a(mul3_img), .inst_b(mul3_ker), .inst_rnd(3'b000), .z_inst(mul3_fin));
fp_mult mult4 (.inst_a(mul4_img), .inst_b(mul4_ker), .inst_rnd(3'b000), .z_inst(mul4_fin));
fp_mult mult5 (.inst_a(mul5_img), .inst_b(mul5_ker), .inst_rnd(3'b000), .z_inst(mul5_fin));
fp_mult mult6 (.inst_a(mul6_img), .inst_b(mul6_ker), .inst_rnd(3'b000), .z_inst(mul6_fin));
fp_mult mult7 (.inst_a(mul7_img), .inst_b(mul7_ker), .inst_rnd(3'b000), .z_inst(mul7_fin));
fp_mult mult8 (.inst_a(mul8_img), .inst_b(mul8_ker), .inst_rnd(3'b000), .z_inst(mul8_fin));

fp_mult mult9  (.inst_a(mul0_img), .inst_b(mul9_ker),  .inst_rnd(3'b000), .z_inst(mul9_fin));
fp_mult mult10 (.inst_a(mul1_img), .inst_b(mul10_ker), .inst_rnd(3'b000), .z_inst(mul10_fin));
fp_mult mult11 (.inst_a(mul2_img), .inst_b(mul11_ker), .inst_rnd(3'b000), .z_inst(mul11_fin));
fp_mult mult12 (.inst_a(mul3_img), .inst_b(mul12_ker), .inst_rnd(3'b000), .z_inst(mul12_fin));
fp_mult mult13 (.inst_a(mul4_img), .inst_b(mul13_ker), .inst_rnd(3'b000), .z_inst(mul13_fin));
fp_mult mult14 (.inst_a(mul5_img), .inst_b(mul14_ker), .inst_rnd(3'b000), .z_inst(mul14_fin));
fp_mult mult15 (.inst_a(mul6_img), .inst_b(mul15_ker), .inst_rnd(3'b000), .z_inst(mul15_fin));
fp_mult mult16 (.inst_a(mul7_img), .inst_b(mul16_ker), .inst_rnd(3'b000), .z_inst(mul16_fin));
fp_mult mult17 (.inst_a(mul8_img), .inst_b(mul17_ker), .inst_rnd(3'b000), .z_inst(mul17_fin));

always @(*) begin
    case (1'b1)
        // CONV
        (cnt > 8  && cnt <= 44): begin
            mul0_ker = ker_1[0];
            mul1_ker = ker_1[1];
            mul2_ker = ker_1[2];
            mul3_ker = ker_1[3];
            mul4_ker = ker_1[4];
            mul5_ker = ker_1[5];
            mul6_ker = ker_1[6];
            mul7_ker = ker_1[7];
            mul8_ker = ker_1[8];
        end
        (cnt >= 45 && cnt <  81): begin
            mul0_ker = ker_1[9];
            mul1_ker = ker_1[10];
            mul2_ker = ker_1[11];
            mul3_ker = ker_1[12];
            mul4_ker = ker_1[13];
            mul5_ker = ker_1[14];
            mul6_ker = ker_1[15];
            mul7_ker = ker_1[16];
            mul8_ker = ker_1[17];
        end
        // FC1
        (cnt == 88): begin
            mul0_ker = weight_bias_reg[0];
            mul1_ker = weight_bias_reg[1];
            mul2_ker = weight_bias_reg[2];
            mul3_ker = weight_bias_reg[3];
            mul4_ker = weight_bias_reg[4];
            mul5_ker = weight_bias_reg[5];
            mul6_ker = weight_bias_reg[6];
            mul7_ker = weight_bias_reg[7];
            mul8_ker = 32'd0;
        end
        (cnt == 89): begin
            mul0_ker = weight_bias_reg[8];
            mul1_ker = weight_bias_reg[9];
            mul2_ker = weight_bias_reg[10];
            mul3_ker = weight_bias_reg[11];
            mul4_ker = weight_bias_reg[12];
            mul5_ker = weight_bias_reg[13];
            mul6_ker = weight_bias_reg[14];
            mul7_ker = weight_bias_reg[15];
            mul8_ker = 32'd0;
        end
        (cnt == 90): begin
            mul0_ker = weight_bias_reg[16];
            mul1_ker = weight_bias_reg[17];
            mul2_ker = weight_bias_reg[18];
            mul3_ker = weight_bias_reg[19];
            mul4_ker = weight_bias_reg[20];
            mul5_ker = weight_bias_reg[21];
            mul6_ker = weight_bias_reg[22];
            mul7_ker = weight_bias_reg[23];
            mul8_ker = 32'd0;
        end
        (cnt == 91): begin
            mul0_ker = weight_bias_reg[24];
            mul1_ker = weight_bias_reg[25];
            mul2_ker = weight_bias_reg[26];
            mul3_ker = weight_bias_reg[27];
            mul4_ker = weight_bias_reg[28];
            mul5_ker = weight_bias_reg[29];
            mul6_ker = weight_bias_reg[30];
            mul7_ker = weight_bias_reg[31];
            mul8_ker = 32'd0;
        end
        (cnt == 92): begin
            mul0_ker = weight_bias_reg[32];
            mul1_ker = weight_bias_reg[33];
            mul2_ker = weight_bias_reg[34];
            mul3_ker = weight_bias_reg[35];
            mul4_ker = weight_bias_reg[36];
            mul5_ker = weight_bias_reg[37];
            mul6_ker = weight_bias_reg[38];
            mul7_ker = weight_bias_reg[39];
            mul8_ker = 32'd0;
        end
        // Leaky ReLU
        (cnt == 95): begin
            mul0_ker = leaky_relu_coeff(FC1_out[0]);
            mul1_ker = leaky_relu_coeff(FC1_out[1]);
            mul2_ker = leaky_relu_coeff(FC1_out[2]);
            mul3_ker = leaky_relu_coeff(FC1_out[3]);
            mul4_ker = leaky_relu_coeff(FC1_out[4]);
            mul5_ker = 32'd0;
            mul6_ker = 32'd0;
            mul7_ker = 32'd0;
            mul8_ker = 32'd0;
        end
        // FC2
        (cnt == 96): begin
            mul0_ker = weight_bias_reg[41];
            mul1_ker = weight_bias_reg[42];
            mul2_ker = weight_bias_reg[43];
            mul3_ker = weight_bias_reg[44];
            mul4_ker = weight_bias_reg[45];
            mul5_ker = 32'd0;
            mul6_ker = 32'd0;
            mul7_ker = 32'd0;
            mul8_ker = 32'd0;
        end
        (cnt == 97): begin
            mul0_ker = weight_bias_reg[46];
            mul1_ker = weight_bias_reg[47];
            mul2_ker = weight_bias_reg[48];
            mul3_ker = weight_bias_reg[49];
            mul4_ker = weight_bias_reg[50];
            mul5_ker = 32'd0;
            mul6_ker = 32'd0;
            mul7_ker = 32'd0;
            mul8_ker = 32'd0;
        end
        (cnt == 98): begin
            mul0_ker = weight_bias_reg[51];
            mul1_ker = weight_bias_reg[52];
            mul2_ker = weight_bias_reg[53];
            mul3_ker = weight_bias_reg[54];
            mul4_ker = weight_bias_reg[55];
            mul5_ker = 32'd0;
            mul6_ker = 32'd0;
            mul7_ker = 32'd0;
            mul8_ker = 32'd0;
        end
        default: begin
            mul0_ker = 32'd0;
            mul1_ker = 32'd0;
            mul2_ker = 32'd0;
            mul3_ker = 32'd0;
            mul4_ker = 32'd0;
            mul5_ker = 32'd0;
            mul6_ker = 32'd0;
            mul7_ker = 32'd0;
            mul8_ker = 32'd0;
        end
    endcase
end

always @(*) begin
    case (1'b1)
        (cnt > 8  && cnt <= 44): begin
            mul9_ker  = ker_2[0];
            mul10_ker = ker_2[1];
            mul11_ker = ker_2[2];
            mul12_ker = ker_2[3];
            mul13_ker = ker_2[4];
            mul14_ker = ker_2[5];
            mul15_ker = ker_2[6];
            mul16_ker = ker_2[7];
            mul17_ker = ker_2[8];
        end
        (cnt >= 45 && cnt <  81): begin
            mul9_ker  = ker_2[9];
            mul10_ker = ker_2[10];
            mul11_ker = ker_2[11];
            mul12_ker = ker_2[12];
            mul13_ker = ker_2[13];
            mul14_ker = ker_2[14];
            mul15_ker = ker_2[15];
            mul16_ker = ker_2[16];
            mul17_ker = ker_2[17];
        end
        default: begin
            mul9_ker  = 32'd0;
            mul10_ker = 32'd0;
            mul11_ker = 32'd0;
            mul12_ker = 32'd0;
            mul13_ker = 32'd0;
            mul14_ker = 32'd0;
            mul15_ker = 32'd0;
            mul16_ker = 32'd0;
            mul17_ker = 32'd0;
        end
    endcase
end

always @(*) begin
    case (cnt)
        9, 45: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[0];  mul1_img = img_map[0];  mul2_img = img_map[1];
                    mul3_img = img_map[0];  mul4_img = img_map[0];  mul5_img = img_map[1];
                    mul6_img = img_map[6];  mul7_img = img_map[6];  mul8_img = img_map[7];
                end
                1'b1: begin
                    mul0_img = img_map[7];  mul1_img = img_map[6];  mul2_img = img_map[7];
                    mul3_img = img_map[1];  mul4_img = img_map[0];  mul5_img = img_map[1];
                    mul6_img = img_map[7];  mul7_img = img_map[6];  mul8_img = img_map[7];
                end
            endcase
        end
        10, 46: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[0];  mul1_img = img_map[1];  mul2_img = img_map[2];
                    mul3_img = img_map[0];  mul4_img = img_map[1];  mul5_img = img_map[2];
                    mul6_img = img_map[6];  mul7_img = img_map[7];  mul8_img = img_map[8];
                end
                1'b1: begin
                    mul0_img = img_map[6];  mul1_img = img_map[7];  mul2_img = img_map[8];
                    mul3_img = img_map[0];  mul4_img = img_map[1];  mul5_img = img_map[2];
                    mul6_img = img_map[6];  mul7_img = img_map[7];  mul8_img = img_map[8];
                end
            endcase
        end
        11, 47: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[1];  mul1_img = img_map[2];  mul2_img = img_map[3];
                    mul3_img = img_map[1];  mul4_img = img_map[2];  mul5_img = img_map[3];
                    mul6_img = img_map[7];  mul7_img = img_map[8];  mul8_img = img_map[9];
                end
                1'b1: begin
                    mul0_img = img_map[7];  mul1_img = img_map[8];  mul2_img = img_map[9];
                    mul3_img = img_map[1];  mul4_img = img_map[2];  mul5_img = img_map[3];
                    mul6_img = img_map[7];  mul7_img = img_map[8];  mul8_img = img_map[9];
                end
            endcase
        end
        12, 48: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[2];  mul1_img = img_map[3];  mul2_img = img_map[4];
                    mul3_img = img_map[2];  mul4_img = img_map[3];  mul5_img = img_map[4];
                    mul6_img = img_map[8];  mul7_img = img_map[9];  mul8_img = img_map[10];
                end
                1'b1: begin
                    mul0_img = img_map[8];  mul1_img = img_map[9];  mul2_img = img_map[10];
                    mul3_img = img_map[2];  mul4_img = img_map[3];  mul5_img = img_map[4];
                    mul6_img = img_map[8];  mul7_img = img_map[9];  mul8_img = img_map[10];
                end
            endcase
        end
        13, 49: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[3];  mul1_img = img_map[4];  mul2_img = img_map[5];
                    mul3_img = img_map[3];  mul4_img = img_map[4];  mul5_img = img_map[5];
                    mul6_img = img_map[9];  mul7_img = img_map[10]; mul8_img = img_map[11];
                end
                1'b1: begin
                    mul0_img = img_map[9];  mul1_img = img_map[10]; mul2_img = img_map[11];
                    mul3_img = img_map[3];  mul4_img = img_map[4];  mul5_img = img_map[5];
                    mul6_img = img_map[9];  mul7_img = img_map[10]; mul8_img = img_map[11];
                end
            endcase
        end
        14, 50: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[4];  mul1_img = img_map[5];  mul2_img = img_map[5];
                    mul3_img = img_map[4];  mul4_img = img_map[5];  mul5_img = img_map[5];
                    mul6_img = img_map[10]; mul7_img = img_map[11]; mul8_img = img_map[11];
                end
                1'b1: begin
                    mul0_img = img_map[10]; mul1_img = img_map[11]; mul2_img = img_map[10];
                    mul3_img = img_map[4];  mul4_img = img_map[5];  mul5_img = img_map[4];
                    mul6_img = img_map[10]; mul7_img = img_map[11]; mul8_img = img_map[10];
                end
            endcase
        end
        15, 51: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[0];  mul1_img = img_map[0];  mul2_img = img_map[1];
                    mul3_img = img_map[6];  mul4_img = img_map[6];  mul5_img = img_map[7];
                    mul6_img = img_map[12]; mul7_img = img_map[12]; mul8_img = img_map[13];
                end
                1'b1: begin
                    mul0_img = img_map[1];  mul1_img = img_map[0];  mul2_img = img_map[1];
                    mul3_img = img_map[7];  mul4_img = img_map[6];  mul5_img = img_map[7];
                    mul6_img = img_map[13]; mul7_img = img_map[12]; mul8_img = img_map[13];
                end
            endcase
        end
        16, 52: begin
            mul0_img = img_map[0];  mul1_img = img_map[1];  mul2_img = img_map[2];
            mul3_img = img_map[6];  mul4_img = img_map[7];  mul5_img = img_map[8];
            mul6_img = img_map[12]; mul7_img = img_map[13]; mul8_img = img_map[14];
        end
        17, 53: begin
            mul0_img = img_map[1];  mul1_img = img_map[2];  mul2_img = img_map[3];
            mul3_img = img_map[7];  mul4_img = img_map[8];  mul5_img = img_map[9];
            mul6_img = img_map[13]; mul7_img = img_map[14]; mul8_img = img_map[15];
        end
        18, 54: begin
            mul0_img = img_map[2];  mul1_img = img_map[3];  mul2_img = img_map[4];
            mul3_img = img_map[8];  mul4_img = img_map[9];  mul5_img = img_map[10];
            mul6_img = img_map[14]; mul7_img = img_map[15]; mul8_img = img_map[16];
        end
        19, 55: begin
            mul0_img = img_map[3];  mul1_img = img_map[4];  mul2_img = img_map[5];
            mul3_img = img_map[9];  mul4_img = img_map[10]; mul5_img = img_map[11];
            mul6_img = img_map[15]; mul7_img = img_map[16]; mul8_img = img_map[17];
        end
        20, 56: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[4];  mul1_img = img_map[5];  mul2_img = img_map[5];
                    mul3_img = img_map[10]; mul4_img = img_map[11]; mul5_img = img_map[11];
                    mul6_img = img_map[16]; mul7_img = img_map[17]; mul8_img = img_map[17];
                end
                1'b1: begin
                    mul0_img = img_map[4];  mul1_img = img_map[5];  mul2_img = img_map[4];
                    mul3_img = img_map[10]; mul4_img = img_map[11]; mul5_img = img_map[10];
                    mul6_img = img_map[16]; mul7_img = img_map[17]; mul8_img = img_map[16];
                end
            endcase
        end
        21, 57: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[6];  mul1_img = img_map[6];  mul2_img = img_map[7];
                    mul3_img = img_map[12]; mul4_img = img_map[12]; mul5_img = img_map[13];
                    mul6_img = img_map[18]; mul7_img = img_map[18]; mul8_img = img_map[19];
                end
                1'b1: begin
                    mul0_img = img_map[7];  mul1_img = img_map[6];  mul2_img = img_map[7];
                    mul3_img = img_map[13]; mul4_img = img_map[12]; mul5_img = img_map[13];
                    mul6_img = img_map[19]; mul7_img = img_map[18]; mul8_img = img_map[19];
                end
            endcase
        end
        22, 58: begin
            mul0_img = img_map[6];  mul1_img = img_map[7];  mul2_img = img_map[8];
            mul3_img = img_map[12]; mul4_img = img_map[13]; mul5_img = img_map[14];
            mul6_img = img_map[18]; mul7_img = img_map[19]; mul8_img = img_map[20];
        end
        23, 59: begin
            mul0_img = img_map[7];  mul1_img = img_map[8];  mul2_img = img_map[9];
            mul3_img = img_map[13]; mul4_img = img_map[14]; mul5_img = img_map[15];
            mul6_img = img_map[19]; mul7_img = img_map[20]; mul8_img = img_map[21];
        end
        24, 60: begin
            mul0_img = img_map[8];  mul1_img = img_map[9];  mul2_img = img_map[10];
            mul3_img = img_map[14]; mul4_img = img_map[15]; mul5_img = img_map[16];
            mul6_img = img_map[20]; mul7_img = img_map[21]; mul8_img = img_map[22];
        end
        25, 61: begin
            mul0_img = img_map[9];  mul1_img = img_map[10]; mul2_img = img_map[11];
            mul3_img = img_map[15]; mul4_img = img_map[16]; mul5_img = img_map[17];
            mul6_img = img_map[21]; mul7_img = img_map[22]; mul8_img = img_map[23];
        end
        26, 62: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[10]; mul1_img = img_map[11]; mul2_img = img_map[11];
                    mul3_img = img_map[16]; mul4_img = img_map[17]; mul5_img = img_map[17];
                    mul6_img = img_map[22]; mul7_img = img_map[23]; mul8_img = img_map[23];
                end
                1'b1: begin
                    mul0_img = img_map[10]; mul1_img = img_map[11]; mul2_img = img_map[10];
                    mul3_img = img_map[16]; mul4_img = img_map[17]; mul5_img = img_map[16];
                    mul6_img = img_map[22]; mul7_img = img_map[23]; mul8_img = img_map[22];
                end
            endcase
        end
        27, 63: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[12]; mul1_img = img_map[12]; mul2_img = img_map[13];
                    mul3_img = img_map[18]; mul4_img = img_map[18]; mul5_img = img_map[19];
                    mul6_img = img_map[24]; mul7_img = img_map[24]; mul8_img = img_map[25];
                end
                1'b1: begin
                    mul0_img = img_map[13]; mul1_img = img_map[12]; mul2_img = img_map[13];
                    mul3_img = img_map[19]; mul4_img = img_map[18]; mul5_img = img_map[19];
                    mul6_img = img_map[25]; mul7_img = img_map[24]; mul8_img = img_map[25];
                end
            endcase
        end
        28, 64: begin
            mul0_img = img_map[12]; mul1_img = img_map[13]; mul2_img = img_map[14];
            mul3_img = img_map[18]; mul4_img = img_map[19]; mul5_img = img_map[20];
            mul6_img = img_map[24]; mul7_img = img_map[25]; mul8_img = img_map[26];
        end
        29, 65: begin
            mul0_img = img_map[13]; mul1_img = img_map[14]; mul2_img = img_map[15];
            mul3_img = img_map[19]; mul4_img = img_map[20]; mul5_img = img_map[21];
            mul6_img = img_map[25]; mul7_img = img_map[26]; mul8_img = img_map[27];
        end
        30, 66: begin
            mul0_img = img_map[14]; mul1_img = img_map[15]; mul2_img = img_map[16];
            mul3_img = img_map[20]; mul4_img = img_map[21]; mul5_img = img_map[22];
            mul6_img = img_map[26]; mul7_img = img_map[27]; mul8_img = img_map[28];
        end
        31, 67: begin
            mul0_img = img_map[15]; mul1_img = img_map[16]; mul2_img = img_map[17];
            mul3_img = img_map[21]; mul4_img = img_map[22]; mul5_img = img_map[23];
            mul6_img = img_map[27]; mul7_img = img_map[28]; mul8_img = img_map[29];
        end
        32, 68: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[16]; mul1_img = img_map[17]; mul2_img = img_map[17];
                    mul3_img = img_map[22]; mul4_img = img_map[23]; mul5_img = img_map[23];
                    mul6_img = img_map[28]; mul7_img = img_map[29]; mul8_img = img_map[29];
                end
                1'b1: begin
                    mul0_img = img_map[16]; mul1_img = img_map[17]; mul2_img = img_map[16];
                    mul3_img = img_map[22]; mul4_img = img_map[23]; mul5_img = img_map[22];
                    mul6_img = img_map[28]; mul7_img = img_map[29]; mul8_img = img_map[28];
                end
            endcase
        end
        33, 69: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[18]; mul1_img = img_map[18]; mul2_img = img_map[19];
                    mul3_img = img_map[24]; mul4_img = img_map[24]; mul5_img = img_map[25];
                    mul6_img = img_map[30]; mul7_img = img_map[30]; mul8_img = img_map[31];
                end
                1'b1: begin
                    mul0_img = img_map[19]; mul1_img = img_map[18]; mul2_img = img_map[19];
                    mul3_img = img_map[25]; mul4_img = img_map[24]; mul5_img = img_map[25];
                    mul6_img = img_map[31]; mul7_img = img_map[30]; mul8_img = img_map[31];
                end
            endcase
        end
        34, 70: begin
            mul0_img = img_map[18]; mul1_img = img_map[19]; mul2_img = img_map[20];
            mul3_img = img_map[24]; mul4_img = img_map[25]; mul5_img = img_map[26];
            mul6_img = img_map[30]; mul7_img = img_map[31]; mul8_img = img_map[32];
        end
        35, 71: begin
            mul0_img = img_map[19]; mul1_img = img_map[20]; mul2_img = img_map[21];
            mul3_img = img_map[25]; mul4_img = img_map[26]; mul5_img = img_map[27];
            mul6_img = img_map[31]; mul7_img = img_map[32]; mul8_img = img_map[33];
        end
        36, 72: begin
            mul0_img = img_map[20]; mul1_img = img_map[21]; mul2_img = img_map[22];
            mul3_img = img_map[26]; mul4_img = img_map[27]; mul5_img = img_map[28];
            mul6_img = img_map[32]; mul7_img = img_map[33]; mul8_img = img_map[34];
        end
        37, 73: begin
            mul0_img = img_map[21]; mul1_img = img_map[22]; mul2_img = img_map[23];
            mul3_img = img_map[27]; mul4_img = img_map[28]; mul5_img = img_map[29];
            mul6_img = img_map[33]; mul7_img = img_map[34]; mul8_img = img_map[35];
        end
        38, 74: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[22]; mul1_img = img_map[23]; mul2_img = img_map[23];
                    mul3_img = img_map[28]; mul4_img = img_map[29]; mul5_img = img_map[29];
                    mul6_img = img_map[34]; mul7_img = img_map[35]; mul8_img = img_map[35];
                end
                1'b1: begin
                    mul0_img = img_map[22]; mul1_img = img_map[23]; mul2_img = img_map[22];
                    mul3_img = img_map[28]; mul4_img = img_map[29]; mul5_img = img_map[28];
                    mul6_img = img_map[34]; mul7_img = img_map[35]; mul8_img = img_map[34];
                end
            endcase
        end
        39, 75: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[24]; mul1_img = img_map[24]; mul2_img = img_map[25];
                    mul3_img = img_map[30]; mul4_img = img_map[30]; mul5_img = img_map[31];
                    mul6_img = img_map[30]; mul7_img = img_map[30]; mul8_img = img_map[31];
                end
                1'b1: begin
                    mul0_img = img_map[25]; mul1_img = img_map[24]; mul2_img = img_map[25];
                    mul3_img = img_map[31]; mul4_img = img_map[30]; mul5_img = img_map[31];
                    mul6_img = img_map[25]; mul7_img = img_map[24]; mul8_img = img_map[25];
                end
            endcase
        end
        40, 76: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[24]; mul1_img = img_map[25]; mul2_img = img_map[26];
                    mul3_img = img_map[30]; mul4_img = img_map[31]; mul5_img = img_map[32];
                    mul6_img = img_map[30]; mul7_img = img_map[31]; mul8_img = img_map[32];
                end
                1'b1: begin
                    mul0_img = img_map[24]; mul1_img = img_map[25]; mul2_img = img_map[26];
                    mul3_img = img_map[30]; mul4_img = img_map[31]; mul5_img = img_map[32];
                    mul6_img = img_map[24]; mul7_img = img_map[25]; mul8_img = img_map[26];
                end
            endcase
        end
        41, 77: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[25]; mul1_img = img_map[26]; mul2_img = img_map[27];
                    mul3_img = img_map[31]; mul4_img = img_map[32]; mul5_img = img_map[33];
                    mul6_img = img_map[31]; mul7_img = img_map[32]; mul8_img = img_map[33];
                end
                1'b1: begin
                    mul0_img = img_map[25]; mul1_img = img_map[26]; mul2_img = img_map[27];
                    mul3_img = img_map[31]; mul4_img = img_map[32]; mul5_img = img_map[33];
                    mul6_img = img_map[25]; mul7_img = img_map[26]; mul8_img = img_map[27];
                end
            endcase
        end
        42, 78: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[26]; mul1_img = img_map[27]; mul2_img = img_map[28];
                    mul3_img = img_map[32]; mul4_img = img_map[33]; mul5_img = img_map[34];
                    mul6_img = img_map[32]; mul7_img = img_map[33]; mul8_img = img_map[34];
                end
                1'b1: begin
                    mul0_img = img_map[26]; mul1_img = img_map[27]; mul2_img = img_map[28];
                    mul3_img = img_map[32]; mul4_img = img_map[33]; mul5_img = img_map[34];
                    mul6_img = img_map[26]; mul7_img = img_map[27]; mul8_img = img_map[28];
                end
            endcase
        end
        43, 79: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[27]; mul1_img = img_map[28]; mul2_img = img_map[29];
                    mul3_img = img_map[33]; mul4_img = img_map[34]; mul5_img = img_map[35];
                    mul6_img = img_map[33]; mul7_img = img_map[34]; mul8_img = img_map[35];
                end
                1'b1: begin
                    mul0_img = img_map[27]; mul1_img = img_map[28]; mul2_img = img_map[29];
                    mul3_img = img_map[33]; mul4_img = img_map[34]; mul5_img = img_map[35];
                    mul6_img = img_map[27]; mul7_img = img_map[28]; mul8_img = img_map[29];
                end
            endcase
        end
        44, 80: begin
            case (mode_reg[1])
                1'b0: begin
                    mul0_img = img_map[28]; mul1_img = img_map[29]; mul2_img = img_map[29];
                    mul3_img = img_map[34]; mul4_img = img_map[35]; mul5_img = img_map[35];
                    mul6_img = img_map[34]; mul7_img = img_map[35]; mul8_img = img_map[35];
                end
                1'b1: begin
                    mul0_img = img_map[28]; mul1_img = img_map[29]; mul2_img = img_map[28];
                    mul3_img = img_map[34]; mul4_img = img_map[35]; mul5_img = img_map[34];
                    mul6_img = img_map[28]; mul7_img = img_map[29]; mul8_img = img_map[28];
                end
            endcase
        end
        88, 89, 90, 91, 92: begin
            mul0_img = FC1_in[0];  mul1_img = FC1_in[1];  mul2_img = FC1_in[2];
            mul3_img = FC1_in[3];  mul4_img = FC1_in[4];  mul5_img = FC1_in[5];
            mul6_img = FC1_in[6];  mul7_img = FC1_in[7];  mul8_img = 32'd0;
        end
        95: begin
            mul0_img = FC1_out[0]; mul1_img = FC1_out[1]; mul2_img = FC1_out[2];
            mul3_img = FC1_out[3]; mul4_img = FC1_out[4];
            mul5_img = 32'd0;      mul6_img = 32'd0;      mul7_img = 32'd0; mul8_img = 32'd0;
        end
        96, 97, 98: begin
            mul0_img = RELU_out[0]; mul1_img = RELU_out[1]; mul2_img = RELU_out[2];
            mul3_img = RELU_out[3]; mul4_img = RELU_out[4];
            mul5_img = 32'd0;       mul6_img = 32'd0;       mul7_img = 32'd0; mul8_img = 32'd0;
        end
        default: begin
            mul0_img = 32'd0; mul1_img = 32'd0; mul2_img = 32'd0;
            mul3_img = 32'd0; mul4_img = 32'd0; mul5_img = 32'd0;
            mul6_img = 32'd0; mul7_img = 32'd0; mul8_img = 32'd0;
        end
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        conv_cross0  <= 32'd0;
        conv_cross1  <= 32'd0;
        conv_cross2  <= 32'd0;
        conv_cross3  <= 32'd0;
        conv_cross4  <= 32'd0;
        conv_cross5  <= 32'd0;
        conv_cross6  <= 32'd0;
        conv_cross7  <= 32'd0;
        conv_cross8  <= 32'd0;
        conv_cross9  <= 32'd0;
        conv_cross10 <= 32'd0;
        conv_cross11 <= 32'd0;
        conv_cross12 <= 32'd0;
        conv_cross13 <= 32'd0;
        conv_cross14 <= 32'd0;
        conv_cross15 <= 32'd0;
        conv_cross16 <= 32'd0;
        conv_cross17 <= 32'd0;
    end else begin
        conv_cross0  <= mul0_fin;
        conv_cross1  <= mul1_fin;
        conv_cross2  <= mul2_fin;
        conv_cross3  <= mul3_fin;
        conv_cross4  <= mul4_fin;
        conv_cross5  <= mul5_fin;
        conv_cross6  <= mul6_fin;
        conv_cross7  <= mul7_fin;
        conv_cross8  <= mul8_fin;
        conv_cross9  <= mul9_fin;
        conv_cross10 <= mul10_fin;
        conv_cross11 <= mul11_fin;
        conv_cross12 <= mul12_fin;
        conv_cross13 <= mul13_fin;
        conv_cross14 <= mul14_fin;
        conv_cross15 <= mul15_fin;
        conv_cross16 <= mul16_fin;
        conv_cross17 <= mul17_fin;
    end
end

wire [inst_sig_width+inst_exp_width:0] SUM31_t;
fp_add SUM31_add1 ( .inst_a(in_a1), .inst_b(in_b1), .inst_rnd(3'b000), .z_inst(SUM31_t) );
fp_add SUM31_add2 ( .inst_a(SUM31_t), .inst_b(in_c1), .inst_rnd(3'b000), .z_inst(sum_res1) );
wire [inst_sig_width+inst_exp_width:0] SUM32_t;
fp_add SUM32_add1 ( .inst_a(in_a2), .inst_b(in_b2), .inst_rnd(3'b000), .z_inst(SUM32_t) );
fp_add SUM32_add2 ( .inst_a(SUM32_t), .inst_b(in_c2), .inst_rnd(3'b000), .z_inst(sum_res2) );
wire [inst_sig_width+inst_exp_width:0] SUM33_t;
fp_add SUM33_add1 ( .inst_a(in_a3), .inst_b(in_b3), .inst_rnd(3'b000), .z_inst(SUM33_t) );
fp_add SUM33_add2 ( .inst_a(SUM33_t), .inst_b(in_c3), .inst_rnd(3'b000), .z_inst(sum_res3) );
wire [inst_sig_width+inst_exp_width:0] SUM34_t;
fp_add SUM34_add1 ( .inst_a(in_a4), .inst_b(in_b4), .inst_rnd(3'b000), .z_inst(SUM34_t) );
fp_add SUM34_add2 ( .inst_a(SUM34_t), .inst_b(in_c4), .inst_rnd(3'b000), .z_inst(sum_res4) );
wire [inst_sig_width+inst_exp_width:0] SUM35_t;
fp_add SUM35_add1 ( .inst_a(in_a5), .inst_b(in_b5), .inst_rnd(3'b000), .z_inst(SUM35_t) );
fp_add SUM35_add2 ( .inst_a(SUM35_t), .inst_b(in_c5), .inst_rnd(3'b000), .z_inst(sum_res5) );
wire [inst_sig_width+inst_exp_width:0] SUM36_t;
fp_add SUM36_add1 ( .inst_a(in_a6), .inst_b(in_b6), .inst_rnd(3'b000), .z_inst(SUM36_t) );
fp_add SUM36_add2 ( .inst_a(SUM36_t), .inst_b(in_c6), .inst_rnd(3'b000), .z_inst(sum_res6) );
wire [inst_sig_width+inst_exp_width:0] SUM37_t;
fp_add SUM37_add1 ( .inst_a(in_a7), .inst_b(in_b7), .inst_rnd(3'b000), .z_inst(SUM37_t) );
fp_add SUM37_add2 ( .inst_a(SUM37_t), .inst_b(in_c7), .inst_rnd(3'b000), .z_inst(sum_res7) );
wire [inst_sig_width+inst_exp_width:0] SUM38_t;
fp_add SUM38_add1 ( .inst_a(in_a8), .inst_b(in_b8), .inst_rnd(3'b000), .z_inst(SUM38_t) );
fp_add SUM38_add2 ( .inst_a(SUM38_t), .inst_b(in_c8), .inst_rnd(3'b000), .z_inst(sum_res8) );

fp_add ADD1 (.inst_a(add_a1), .inst_b(add_b1), .inst_rnd(3'b000), .z_inst(add_res1));
fp_add ADD2 (.inst_a(add_a2), .inst_b(add_b2), .inst_rnd(3'b000), .z_inst(add_res2));
reg [31:0] ker_A, ker_B, ker_C, ker_D;

always @(*) begin
    case (1'b1)
        ((cnt > 8'd9  && cnt <= 8'd81) ||
         (cnt > 8'd88 && cnt <= 8'd93) ||
         (cnt > 8'd96 && cnt <= 8'd99)) : begin
            in_a1 = conv_cross0;
            in_b1 = conv_cross1;
            in_c1 = conv_cross2;
        end
        (cnt == 8'd84) : begin
            in_a1 = ker_A;
            in_b1 = ker_B;
            in_c1 = ker_C;
        end
        default: begin
            in_a1 = 32'd0;
            in_b1 = 32'd0;
            in_c1 = 32'd0;
        end
    endcase
end

always @(*) begin
    case (1'b1)
        ((cnt > 8'd9  && cnt <= 8'd81) ||
         (cnt > 8'd88 && cnt <= 8'd93)) : begin
            in_a2 = conv_cross3;
            in_b2 = conv_cross4;
            in_c2 = conv_cross5;
        end
        (cnt == 8'd84) : begin
            in_a2 = ker_A;
            in_b2 = ker_B;
            in_c2 = ker_D;
        end
        ((cnt > 8'd96 && cnt <= 8'd99)) : begin // FC2
            in_a2 = conv_cross3;
            in_b2 = conv_cross4;
            in_c2 = weight_bias_reg[56];
        end
        default: begin
            in_a2 = 32'd0;
            in_b2 = 32'd0;
            in_c2 = 32'd0;
        end
    endcase
end

always @(*) begin
    case (1'b1)
        (cnt > 8'd9 && cnt <= 8'd81) : begin
            in_a3 = conv_cross6;
            in_b3 = conv_cross7;
            in_c3 = conv_cross8;
        end
        (cnt == 8'd84) : begin
            in_a3 = ker_A;
            in_b3 = ker_C;
            in_c3 = ker_D;
        end
        (cnt > 8'd88 && cnt <= 8'd93) : begin // FC1
            in_a3 = conv_cross6;
            in_b3 = conv_cross7;
            in_c3 = weight_bias_reg[40];
        end
        default: begin
            in_a3 = 32'd0;
            in_b3 = 32'd0;
            in_c3 = 32'd0;
        end
    endcase
end

always @(posedge clk) begin
    if (!rst_n)    s_res1 <= 32'd0;
    else           s_res1 <= sum_res1;
end

always @(posedge clk) begin
    if (!rst_n)    s_res2 <= 32'd0;
    else           s_res2 <= sum_res2;
end

always @(posedge clk) begin
    if (!rst_n)    s_res3 <= 32'd0;
    else           s_res3 <= sum_res3;
end

always @(*) begin
    case (1'b1)
        ((cnt > 8'd10 && cnt <= 8'd82) ||
         (cnt > 8'd89 && cnt <= 8'd94)) : begin
            in_a4 = s_res1;
            in_b4 = s_res2;
            in_c4 = s_res3;
        end
        (cnt == 8'd84) : begin
            in_a4 = ker_B;
            in_b4 = ker_C;
            in_c4 = ker_D;
        end
        default: begin
            in_a4 = 32'd0;
            in_b4 = 32'd0;
            in_c4 = 32'd0;
        end
    endcase
end

always @(posedge clk) begin
    if (!rst_n)    s_res4 <= 32'd0;
    else           s_res4 <= sum_res4;
end

always @(*) begin
    case (1'b1)
        (cnt > 8'd9 && cnt <= 8'd81) : begin
            in_a5 = conv_cross9;
            in_b5 = conv_cross10;
            in_c5 = conv_cross11;
        end
        (cnt == 8'd84) : begin
            in_a5 = ker_A;
            in_b5 = ker_C;
            in_c5 = 32'd0;
        end
        default: begin
            in_a5 = 32'd0;
            in_b5 = 32'd0;
            in_c5 = 32'd0;
        end
    endcase
end

always @(*) begin
    case (1'b1)
        (cnt > 8'd9 && cnt <= 8'd81) : begin
            in_a6 = conv_cross12;
            in_b6 = conv_cross13;
            in_c6 = conv_cross14;
        end
        (cnt == 8'd84) : begin
            in_a6 = ker_A;
            in_b6 = ker_D;
            in_c6 = 32'd0;
        end
        default: begin
            in_a6 = 32'd0;
            in_b6 = 32'd0;
            in_c6 = 32'd0;
        end
    endcase
end

always @(*) begin
    case (1'b1)
        (cnt > 8'd9 && cnt <= 8'd81) : begin
            in_a7 = conv_cross15;
            in_b7 = conv_cross16;
            in_c7 = conv_cross17;
        end
        (cnt == 8'd84) : begin
            in_a7 = ker_B;
            in_b7 = ker_C;
            in_c7 = 32'd0;
        end
        default: begin
            in_a7 = 32'd0;
            in_b7 = 32'd0;
            in_c7 = 32'd0;
        end
    endcase
end

always @(posedge clk) begin
    if (!rst_n)    s_res5 <= 32'd0;
    else           s_res5 <= sum_res5;
end

always @(posedge clk) begin
    if (!rst_n)    s_res6 <= 32'd0;
    else           s_res6 <= sum_res6;
end

always @(posedge clk) begin
    if (!rst_n)    s_res7 <= 32'd0;
    else           s_res7 <= sum_res7;
end

always @(*) begin
    case (1'b1)
        (cnt > 8'd10 && cnt <= 8'd82) : begin
            in_a8 = s_res5;
            in_b8 = s_res6;
            in_c8 = s_res7;
        end
        (cnt == 8'd84) : begin
            in_a8 = ker_B;
            in_b8 = ker_D;
            in_c8 = 32'd0;
        end
        default: begin
            in_a8 = 32'd0;
            in_b8 = 32'd0;
            in_c8 = 32'd0;
        end
    endcase
end

always @(posedge clk) begin
    if (!rst_n)    s_res8 <= 32'd0;
    else           s_res8 <= sum_res8;
end

always @(*) begin
    case (1'b1)
        (cnt >= 8'd11): fmap_cnt = cnt - 8'd11;
        default:        fmap_cnt = 8'd0;
    endcase
end

always @(*) begin
    case (1'b1)
        (fmap_cnt >= 8'd36): fmap_cnt2 = fmap_cnt - 8'd36;
        default:              fmap_cnt2 = 8'd0;
    endcase
end

// fmap1
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 36; i = i + 1)
            fmap1[i] <= 32'd0;
    end else begin
        case (1'b1)
            (cnt > 8'd10 && cnt <= 8'd46):  fmap1[fmap_cnt]  <= sum_res4;
            (cnt > 8'd46 && cnt <= 8'd82):  fmap1[fmap_cnt2] <= add_res1;
            default: /* hold */ ;
        endcase
    end
end

// fmap2
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 36; i = i + 1)
            fmap2[i] <= 32'd0;
    end else begin
        case (1'b1)
            (cnt > 8'd10 && cnt <= 8'd46):  fmap2[fmap_cnt]  <= sum_res8;
            (cnt > 8'd46 && cnt <= 8'd82):  fmap2[fmap_cnt2] <= add_res2;
            default: /* hold */ ;
        endcase
    end
end
// ker_A 
always @(posedge clk) begin
    if (!rst_n) ker_A <= 32'd0;
    else begin
        case (1'b1)
            (cnt == 8'd11):                   ker_A <= sum_res4;
            (cnt >  8'd12 && cnt <= 8'd47):  ker_A <= add_res1;
            default:                          ker_A <= ker_A;
        endcase
    end
end
// ker_B 
always @(posedge clk) begin
    if (!rst_n) ker_B <= 32'd0;
    else begin
        case (1'b1)
            (cnt == 8'd47):                   ker_B <= sum_res4;
            (cnt >  8'd48 && cnt <= 8'd83):  ker_B <= add_res1;
            default:                          ker_B <= ker_B;
        endcase
    end
end
// ker_C
always @(posedge clk) begin
    if (!rst_n) ker_C <= 32'd0;
    else begin
        case (1'b1)
            (cnt == 8'd11):                   ker_C <= sum_res8;
            (cnt >  8'd12 && cnt <= 8'd47):  ker_C <= add_res2;
            default:                          ker_C <= ker_C;
        endcase
    end
end
// ker_D 
always @(posedge clk) begin
    if (!rst_n) ker_D <= 32'd0;
    else begin
        case (1'b1)
            (cnt == 8'd47):                   ker_D <= sum_res8;
            (cnt >  8'd48 && cnt <= 8'd83):  ker_D <= add_res2;
            default:                          ker_D <= ker_D;
        endcase
    end
end

always @(*) begin
    case (task_num)
        1'b1: begin  // task 1
            case (1'b1)
                (cnt > 8'd12 && cnt <= 8'd47): begin
                    add_a1 = ker_A; add_b1 = s_res4;
                end
                (cnt > 8'd48 && cnt <= 8'd83): begin
                    add_a1 = ker_B; add_b1 = s_res4;
                end
                (cnt == 8'd84): begin
                    add_a1 = ker_A; add_b1 = ker_B;
                end
                (cnt == 8'd85): begin
                    add_a1 = value[4]; add_b1 = value[9];
                end
                default: begin
                    add_a1 = 32'd0; add_b1 = 32'd0;
                end
            endcase
        end
        default: begin // task 0
            case (1'b1)
                (cnt > 8'd46 && cnt <= 8'd82): begin
                    add_a1 = fmap1[fmap_cnt2]; add_b1 = sum_res4;
                end
                (cnt > 8'd97 && cnt <= 8'd100): begin
                    add_a1 = s_res1; add_b1 = s_res2;
                end
                default: begin
                    add_a1 = 32'd0; add_b1 = 32'd0;
                end
            endcase
        end
    endcase
end

always @(*) begin
    case (task_num)
        1'b1: begin  // task 1
            case (1'b1)
                (cnt > 8'd12 && cnt <= 8'd47): begin
                    add_a2 = ker_C; add_b2 = s_res8;
                end
                (cnt > 8'd48 && cnt <= 8'd83): begin
                    add_a2 = ker_D; add_b2 = s_res8;
                end
                (cnt == 8'd84): begin
                    add_a2 = ker_C; add_b2 = ker_D;
                end
                default: begin
                    add_a2 = 32'd0; add_b2 = 32'd0;
                end
            endcase
        end
        default: begin // task 0
            case (1'b1)
                (cnt > 8'd46 && cnt <= 8'd82): begin
                    add_a2 = fmap2[fmap_cnt2]; add_b2 = sum_res8;
                end
                default: begin
                    add_a2 = 32'd0; add_b2 = 32'd0;
                end
            endcase
        end
    endcase
end

always @(*) begin
    case (cnt)
        8'd90:  FC1_out_cnt = 8'd0;
        8'd91:  FC1_out_cnt = 8'd1;
        8'd92:  FC1_out_cnt = 8'd2;
        8'd93:  FC1_out_cnt = 8'd3;
        8'd94:  FC1_out_cnt = 8'd4;
        default:FC1_out_cnt = 8'd0;
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (k = 0; k < 5; k = k + 1) FC1_out[k] <= 32'd0;
    end else begin
        case (cnt)
            8'd90, 8'd91, 8'd92, 8'd93, 8'd94: FC1_out[FC1_out_cnt] <= sum_res4;
            default: /* hold */;
        endcase
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (k = 0; k < 5; k = k + 1) RELU_out[k] <= 32'd0;
    end else begin
        case (cnt)
            8'd95: begin
                RELU_out[0] <= mul0_fin;
                RELU_out[1] <= mul1_fin;
                RELU_out[2] <= mul2_fin;
                RELU_out[3] <= mul3_fin;
                RELU_out[4] <= mul4_fin;
            end
            default: /* hold */;
        endcase
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (k = 0; k < 3; k = k + 1) FC2_out[k] <= 32'd0;
    end else begin
        case (cnt)
            8'd98:  FC2_out[0] <= add_res1;
            8'd99:  FC2_out[1] <= add_res1;
            8'd100: FC2_out[2] <= add_res1;
            default: /* hold */;
        endcase
    end
end

// Max-Pooling
reg [31:0] exp_reg1, exp_reg2;
reg [31:0] exp_minus_reg, exp_add_reg;
// fmap1
fp_max CMP1_1(.inst_a(cmp11_a), .inst_b(cmp11_b), .max_inst(max_temp1_1));
fp_max CMP1_2(.inst_a(cmp12_a), .inst_b(cmp12_b), .max_inst(max_temp1_2));
// fmap2
fp_max CMP2_1(.inst_a(cmp21_a), .inst_b(cmp21_b), .max_inst(max_temp2_1));
fp_max CMP2_2(.inst_a(cmp22_a), .inst_b(cmp22_b), .max_inst(max_temp2_2));

always @(*) begin
    case (cnt)
        8'd49: begin cmp11_a = fmap1[0];  cmp11_b = fmap1[1];  end
        8'd50: begin cmp11_a = max0[0];    cmp11_b = fmap1[2];  end
        8'd54: begin cmp11_a = max0[0];    cmp11_b = fmap1[6];  end
        8'd55: begin cmp11_a = max0[0];    cmp11_b = fmap1[7];  end
        8'd56: begin cmp11_a = max0[0];    cmp11_b = fmap1[8];  end
        8'd60: begin cmp11_a = max0[0];    cmp11_b = fmap1[12]; end
        8'd61: begin cmp11_a = max0[0];    cmp11_b = fmap1[13]; end
        8'd62: begin cmp11_a = max0[0];    cmp11_b = fmap1[14]; end
        8'd67: begin cmp11_a = fmap1[18]; cmp11_b = fmap1[19]; end
        8'd68: begin cmp11_a = max0[2];    cmp11_b = fmap1[20]; end
        8'd72: begin cmp11_a = max0[2];    cmp11_b = fmap1[24]; end
        8'd73: begin cmp11_a = max0[2];    cmp11_b = fmap1[25]; end
        8'd74: begin cmp11_a = max0[2];    cmp11_b = fmap1[26]; end
        8'd78: begin cmp11_a = max0[2];    cmp11_b = fmap1[30]; end
        8'd79: begin cmp11_a = max0[2];    cmp11_b = fmap1[31]; end
        8'd80: begin cmp11_a = max0[2];    cmp11_b = fmap1[32]; end
        8'd86: begin cmp11_a = value[8];   cmp11_b = value[9];   end
        default: begin cmp11_a = 32'd0;    cmp11_b = 32'd0;      end
    endcase
end

always @(*) begin
    case (cnt)
        8'd52: begin cmp12_a = fmap1[3];  cmp12_b = fmap1[4];  end
        8'd53: begin cmp12_a = max0[1];    cmp12_b = fmap1[5];  end
        8'd57: begin cmp12_a = max0[1];    cmp12_b = fmap1[9];  end
        8'd58: begin cmp12_a = max0[1];    cmp12_b = fmap1[10]; end
        8'd59: begin cmp12_a = max0[1];    cmp12_b = fmap1[11]; end
        8'd63: begin cmp12_a = max0[1];    cmp12_b = fmap1[15]; end
        8'd64: begin cmp12_a = max0[1];    cmp12_b = fmap1[16]; end
        8'd65: begin cmp12_a = max0[1];    cmp12_b = fmap1[17]; end
        8'd70: begin cmp12_a = fmap1[21]; cmp12_b = fmap1[22]; end
        8'd71: begin cmp12_a = max0[3];    cmp12_b = fmap1[23]; end
        8'd75: begin cmp12_a = max0[3];    cmp12_b = fmap1[27]; end
        8'd76: begin cmp12_a = max0[3];    cmp12_b = fmap1[28]; end
        8'd77: begin cmp12_a = max0[3];    cmp12_b = fmap1[29]; end
        8'd81: begin cmp12_a = max0[3];    cmp12_b = fmap1[33]; end
        8'd82: begin cmp12_a = max0[3];    cmp12_b = fmap1[34]; end
        8'd83: begin cmp12_a = max0[3];    cmp12_b = fmap1[35]; end
        8'd86: begin cmp12_a = value[10];  cmp12_b = value[11];  end
        default: begin cmp12_a = 32'd0;    cmp12_b = 32'd0;      end
    endcase
end

always @(*) begin
    case (cnt)
        8'd49: begin cmp21_a = fmap2[0];  cmp21_b = fmap2[1];  end
        8'd50: begin cmp21_a = max1[0];    cmp21_b = fmap2[2];  end
        8'd54: begin cmp21_a = max1[0];    cmp21_b = fmap2[6];  end
        8'd55: begin cmp21_a = max1[0];    cmp21_b = fmap2[7];  end
        8'd56: begin cmp21_a = max1[0];    cmp21_b = fmap2[8];  end
        8'd60: begin cmp21_a = max1[0];    cmp21_b = fmap2[12]; end
        8'd61: begin cmp21_a = max1[0];    cmp21_b = fmap2[13]; end
        8'd62: begin cmp21_a = max1[0];    cmp21_b = fmap2[14]; end
        8'd67: begin cmp21_a = fmap2[18]; cmp21_b = fmap2[19]; end
        8'd68: begin cmp21_a = max1[2];    cmp21_b = fmap2[20]; end
        8'd72: begin cmp21_a = max1[2];    cmp21_b = fmap2[24]; end
        8'd73: begin cmp21_a = max1[2];    cmp21_b = fmap2[25]; end
        8'd74: begin cmp21_a = max1[2];    cmp21_b = fmap2[26]; end
        8'd78: begin cmp21_a = max1[2];    cmp21_b = fmap2[30]; end
        8'd79: begin cmp21_a = max1[2];    cmp21_b = fmap2[31]; end
        8'd80: begin cmp21_a = max1[2];    cmp21_b = fmap2[32]; end
        8'd86: begin cmp21_a = value[12];  cmp21_b = value[13];  end
        default: begin cmp21_a = 32'd0;    cmp21_b = 32'd0;      end
    endcase
end

always @(*) begin
    case (cnt)
        8'd52: begin cmp22_a = fmap2[3];  cmp22_b = fmap2[4];  end
        8'd53: begin cmp22_a = max1[1];    cmp22_b = fmap2[5];  end
        8'd57: begin cmp22_a = max1[1];    cmp22_b = fmap2[9];  end
        8'd58: begin cmp22_a = max1[1];    cmp22_b = fmap2[10]; end
        8'd59: begin cmp22_a = max1[1];    cmp22_b = fmap2[11]; end
        8'd63: begin cmp22_a = max1[1];    cmp22_b = fmap2[15]; end
        8'd64: begin cmp22_a = max1[1];    cmp22_b = fmap2[16]; end
        8'd65: begin cmp22_a = max1[1];    cmp22_b = fmap2[17]; end
        8'd70: begin cmp22_a = fmap2[21]; cmp22_b = fmap2[22]; end
        8'd71: begin cmp22_a = max1[3];    cmp22_b = fmap2[23]; end
        8'd75: begin cmp22_a = max1[3];    cmp22_b = fmap2[27]; end
        8'd76: begin cmp22_a = max1[3];    cmp22_b = fmap2[28]; end
        8'd77: begin cmp22_a = max1[3];    cmp22_b = fmap2[29]; end
        8'd81: begin cmp22_a = max1[3];    cmp22_b = fmap2[33]; end
        8'd82: begin cmp22_a = max1[3];    cmp22_b = fmap2[34]; end
        8'd83: begin cmp22_a = max1[3];    cmp22_b = fmap2[35]; end
        8'd86: begin cmp22_a = value[14];  cmp22_b = value[15];  end
        default: begin cmp22_a = 32'd0;    cmp22_b = 32'd0;      end
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 4; i = i + 1) max0[i] <= 32'd0;
    end else begin
        case (cnt)
            8'd49,8'd50,8'd54,8'd55,8'd56,8'd60,8'd61,8'd62:
                max0[0] <= max_temp1_1;

            8'd52,8'd53,8'd57,8'd58,8'd59,8'd63,8'd64,8'd65:
                max0[1] <= max_temp1_2;

            8'd67,8'd68,8'd72,8'd73,8'd74,8'd78,8'd79,8'd80:
                max0[2] <= max_temp1_1;

            8'd70,8'd71,8'd75,8'd76,8'd77,8'd81,8'd82,8'd83:
                max0[3] <= max_temp1_2;

            default: /* hold */;
        endcase
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 4; i = i + 1) max1[i] <= 32'd0;
    end else begin
        case (cnt)
            8'd49,8'd50,8'd54,8'd55,8'd56,8'd60,8'd61,8'd62:
                max1[0] <= max_temp2_1;

            8'd52,8'd53,8'd57,8'd58,8'd59,8'd63,8'd64,8'd65:
                max1[1] <= max_temp2_2;

            8'd67,8'd68,8'd72,8'd73,8'd74,8'd78,8'd79,8'd80:
                max1[2] <= max_temp2_1;

            8'd70,8'd71,8'd75,8'd76,8'd77,8'd81,8'd82,8'd83:
                max1[3] <= max_temp2_2;

            default: /* hold */;
        endcase
    end
end

// Activation Func. & Softmax
fp_exp exp1(.inst_a(exp_in1), .z_inst(exp_res1));
fp_exp exp2(.inst_a(exp_in2), .z_inst(exp_res2));

wire [inst_sig_width+inst_exp_width:0] minus_b_neg;
assign minus_b_neg = {~minus_op2[inst_sig_width+inst_exp_width], minus_op2[inst_sig_width+inst_exp_width-1:0]};

fp_add minus_add ( .inst_a(minus_op1), .inst_b(minus_b_neg), .inst_rnd(3'b000), .z_inst(minus_res) );
fp_add ADD3    ( .inst_a(add_op1), .inst_b(add_op2),   .inst_rnd(3'b000), .z_inst(add_res3) );
fp_div DIV     ( .inst_a(div_op1), .inst_b(div_op2),                       .z_inst(div_res) );

always @(*) begin
    case (cnt)
        8'd63: begin exp_in1 = max0[0]; exp_in2 = {~max0[0][31], max0[0][30:0]}; end
        8'd64: begin exp_in1 = max1[0]; exp_in2 = {~max1[0][31], max1[0][30:0]}; end
        8'd66: begin exp_in1 = max0[1]; exp_in2 = {~max0[1][31], max0[1][30:0]}; end
        8'd67: begin exp_in1 = max1[1]; exp_in2 = {~max1[1][31], max1[1][30:0]}; end
        8'd81: begin exp_in1 = max0[2]; exp_in2 = {~max0[2][31], max0[2][30:0]}; end
        8'd82: begin exp_in1 = max1[2]; exp_in2 = {~max1[2][31], max1[2][30:0]}; end
        8'd84: begin exp_in1 = max0[3]; exp_in2 = {~max0[3][31], max0[3][30:0]}; end
        8'd85: begin exp_in1 = max1[3]; exp_in2 = {~max1[3][31], max1[3][30:0]}; end
        8'd99: begin exp_in1 = FC2_out[0]; exp_in2 = 32'd0; end
        8'd100:begin exp_in1 = FC2_out[1]; exp_in2 = 32'd0; end
        8'd101:begin exp_in1 = FC2_out[2]; exp_in2 = 32'd0; end
        default: begin exp_in1 = 32'd0; exp_in2 = 32'd0; end
    endcase
end

always @(posedge clk) begin
    if (!rst_n)      soft_exp0 <= 32'd0;
    else             case (cnt)
                         8'd99:   soft_exp0 <= exp_res1;
                         default: /* hold */;
                     endcase
end

always @(posedge clk) begin
    if (!rst_n)      soft_exp1 <= 32'd0;
    else             case (cnt)
                         8'd100:  soft_exp1 <= exp_res1;
                         default: /* hold */;
                     endcase
end

always @(posedge clk) begin
    if (!rst_n)      soft_exp2 <= 32'd0;
    else             case (cnt)
                         8'd101:  soft_exp2 <= exp_res1;
                         default: /* hold */;
                     endcase
end

always @(posedge clk) begin
    if (!rst_n)    exp_total <= 32'd0;
    else           case (cnt)
                     8'd101, 8'd102: exp_total <= add_res3;
                     default: /* hold */;
                   endcase
end

always @(posedge clk) begin
    if (!rst_n)    exp_reg1 <= 32'd0;
    else           case (cnt)
                     8'd63,8'd64,8'd66,8'd67,8'd81,8'd82,8'd84,8'd85: exp_reg1 <= exp_res1;
                     default: /* hold */;
                   endcase
end

always @(posedge clk) begin
    if (!rst_n)    exp_reg2 <= 32'd0;
    else           case (cnt)
                     8'd63,8'd64,8'd66,8'd67,8'd81,8'd82,8'd84,8'd85: exp_reg2 <= exp_res2;
                     default: /* hold */;
                   endcase
end

always @(*) begin
    case (cnt)
        8'd64: begin minus_op1 = (mode_reg[0]) ? max0[0] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd65: begin minus_op1 = (mode_reg[0]) ? max1[0] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd67: begin minus_op1 = (mode_reg[0]) ? max0[1] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd68: begin minus_op1 = (mode_reg[0]) ? max1[1] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd82: begin minus_op1 = (mode_reg[0]) ? max0[2] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd83: begin minus_op1 = (mode_reg[0]) ? max1[2] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd85: begin minus_op1 = (mode_reg[0]) ? max0[3] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        8'd86: begin minus_op1 = (mode_reg[0]) ? max1[3] : exp_reg1; minus_op2 = (mode_reg[0]) ? 32'd0 : exp_reg2; end
        default: begin minus_op1 = 32'd0; minus_op2 = 32'd0; end
    endcase
end

always @(*) begin
    case (cnt)
        8'd64,8'd65,8'd67,8'd68,8'd82,8'd83,8'd85,8'd86: begin
            add_op1 = (mode_reg[0]) ? 32'b00111111100000000000000000000000 : exp_reg1; // 1.0
            add_op2 = exp_reg2;
        end
        8'd101: begin add_op1 = soft_exp0; add_op2 = soft_exp1; end
        8'd102: begin add_op1 = exp_total; add_op2 = soft_exp2; end
        default: begin add_op1 = 32'd0; add_op2 = 32'd0; end
    endcase
end

always @(posedge clk) begin
    if (!rst_n)    exp_minus_reg <= 32'd0;
    else           case (cnt)
                     8'd64,8'd65,8'd67,8'd68,8'd82,8'd83,8'd85,8'd86: exp_minus_reg <= minus_res;
                     default: /* hold */;
                   endcase
end

always @(posedge clk) begin
    if (!rst_n)    exp_add_reg <= 32'd0;
    else           case (cnt)
                     8'd64,8'd65,8'd67,8'd68,8'd82,8'd83,8'd85,8'd86: exp_add_reg <= add_res3;
                     default: /* hold */;
                   endcase
end

always @(*) begin
    case (cnt)
        8'd65,8'd66,8'd68,8'd69,
        8'd83,8'd84,8'd86,8'd87: begin
            div_op1 = exp_minus_reg;
            div_op2 = exp_add_reg;
        end
        8'd103: begin div_op1 = soft_exp0; div_op2 = exp_total; end
        8'd104: begin div_op1 = soft_exp1; div_op2 = exp_total; end
        8'd105: begin div_op1 = soft_exp2; div_op2 = exp_total; end
        default: begin
            div_op1 = 32'b00111111100000000000000000000000; // 1.0
            div_op2 = 32'b00111111100000000000000000000000; // 1.0
        end
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (t = 0; t < 8; t = t + 1) FC1_in[t] <= 32'd0;
    end else begin
        case (cnt)
            8'd65: FC1_in[0] <= div_res;
            8'd66: FC1_in[4] <= div_res;
            8'd68: FC1_in[1] <= div_res;
            8'd69: FC1_in[5] <= div_res;
            8'd83: FC1_in[2] <= div_res;
            8'd84: FC1_in[6] <= div_res;
            8'd86: FC1_in[3] <= div_res;
            8'd87: FC1_in[7] <= div_res;
            default: /* hold */;
        endcase
    end
end

// Task1
fp_max CMP3(.inst_a(cmp3_a), .inst_b(cmp3_b), .max_inst(max_res3));
fp_max CMP4(.inst_a(cmp4_a), .inst_b(cmp4_b), .max_inst(max_res4));
fp_max CMP5(.inst_a(cmp5_a), .inst_b(cmp5_b), .max_inst(max_res5));
fp_max CMP6(.inst_a(cmp6_a), .inst_b(cmp6_b), .max_inst(max_res6));

wire [7:0] sA = cost_cap_reg[1];
wire [7:0] sB = cost_cap_reg[2];
wire [7:0] sC = cost_cap_reg[3];
wire [7:0] sD = cost_cap_reg[4];

wire [7:0] pAB = sA + sB;
wire [7:0] pAC = sA + sC;
wire [7:0] pAD = sA + sD;
wire [7:0] pBC = sB + sC;
wire [7:0] pBD = sB + sD;
wire [7:0] pCD = sC + sD;
wire [7:0] tABC  = sA + sB + sC;
wire [7:0] tABD  = sA + sB + sD;
wire [7:0] tACD  = sA + sC + sD;
wire [7:0] tBCD  = sB + sC + sD;
wire [7:0] qABCD = sA + sB + sC + sD;

assign final_cost[0]  = sA;   
assign final_cost[1]  = sB;   
assign final_cost[2]  = sC;   
assign final_cost[3]  = sD;  
assign final_cost[4]  = pAB;  
assign final_cost[5]  = pAC;   
assign final_cost[6]  = pAD;   
assign final_cost[7]  = pBC;  
assign final_cost[8]  = pBD; 
assign final_cost[9]  = pCD;   
assign final_cost[10] = tABC; 
assign final_cost[11] = tABD;
assign final_cost[12] = tACD;  
assign final_cost[13] = tBCD;  
assign final_cost[14] = qABCD;  
assign final_cost[15] = 8'd0; 

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 16; i = i + 1) value[i] <= 32'd0;
    end else begin
        case (cnt)
            8'd48: begin
                value[0]  <= (final_cost[0]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : ker_A;
                value[2]  <= (final_cost[2]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : ker_C;
                value[15] <= 32'd0;
            end
            8'd84: begin
                value[1]  <= (final_cost[1]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : ker_B;
                value[3]  <= (final_cost[3]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : ker_D;
                value[4]  <= (final_cost[4]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : add_res1;
                value[9]  <= (final_cost[9]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : add_res2;
                value[10] <= (final_cost[10] > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res1;
                value[11] <= (final_cost[11] > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res2;
                value[12] <= (final_cost[12] > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res3;
                value[13] <= (final_cost[13] > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res4;
                value[5]  <= (final_cost[5]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res5;
                value[6]  <= (final_cost[6]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res6;
                value[7]  <= (final_cost[7]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res7;
                value[8]  <= (final_cost[8]  > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : sum_res8;
            end
            8'd85: begin
                value[14] <= (final_cost[14] > cost_cap_reg[0]) ? 32'b10111111100000000000000000000000 : add_res1;
            end
            default: /* hold */;
        endcase
    end
end

always @(*) begin
    case (cnt)
        8'd86: begin cmp3_a = value[0];   cmp3_b = value[1]; end
        8'd87: begin cmp3_a = max_val[0]; cmp3_b = max_val[1]; end
        8'd88: begin cmp3_a = max_val[0]; cmp3_b = max_val[1]; end
        8'd89: begin cmp3_a = max_val[0]; cmp3_b = max_val[1]; end
        default: begin cmp3_a = 32'd0; cmp3_b = 32'd0; end
    endcase
end

always @(*) begin
    case (cnt)
        8'd86: begin cmp4_a = value[2];   cmp4_b = value[3]; end
        8'd87: begin cmp4_a = max_val[2]; cmp4_b = max_val[3]; end
        8'd88: begin cmp4_a = max_val[2]; cmp4_b = max_val[3]; end
        default: begin cmp4_a = 32'd0; cmp4_b = 32'd0; end
    endcase
end

always @(*) begin
    case (cnt)
        8'd86: begin cmp5_a = value[4];   cmp5_b = value[5]; end
        8'd87: begin cmp5_a = max_val[4]; cmp5_b = max_val[5]; end
        default: begin cmp5_a = 32'd0; cmp5_b = 32'd0; end
    endcase
end

always @(*) begin
    case (cnt)
        8'd86: begin cmp6_a = value[6];   cmp6_b = value[7]; end
        8'd87: begin cmp6_a = max_val[6]; cmp6_b = max_val[7]; end
        default: begin cmp6_a = 32'd0; cmp6_b = 32'd0; end
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 8; i = i + 1) max_val[i] <= 32'd0;
    end else begin
        case (cnt)
            8'd86: begin
                max_val[0] <= max_res3;
                max_val[1] <= max_res4;
                max_val[2] <= max_res5;
                max_val[3] <= max_res6;
                max_val[4] <= max_temp1_1;
                max_val[5] <= max_temp1_2;
                max_val[6] <= max_temp2_1;
                max_val[7] <= max_temp2_2;
            end
            8'd87: begin
                max_val[0] <= max_res3;
                max_val[1] <= max_res4;
                max_val[2] <= max_res5;
                max_val[3] <= max_res6;
            end
            8'd88: begin
                max_val[0] <= max_res3;
                max_val[1] <= max_res4;
            end
            8'd89: begin
                max_val[0] <= max_res3;
            end
            default: /* hold */;
        endcase
    end
end

always @(*) begin
    case (1'b1)
        (max_val[0] == value[0]):   choose = 32'b00000000000000000000000000001000;
        (max_val[0] == value[1]):   choose = 32'b00000000000000000000000000000100;
        (max_val[0] == value[2]):   choose = 32'b00000000000000000000000000000010;
        (max_val[0] == value[3]):   choose = 32'b00000000000000000000000000000001;
        (max_val[0] == value[4]):   choose = 32'b00000000000000000000000000001100;
        (max_val[0] == value[5]):   choose = 32'b00000000000000000000000000001010;
        (max_val[0] == value[6]):   choose = 32'b00000000000000000000000000001001;
        (max_val[0] == value[7]):   choose = 32'b00000000000000000000000000000110;
        (max_val[0] == value[8]):   choose = 32'b00000000000000000000000000000101;
        (max_val[0] == value[9]):   choose = 32'b00000000000000000000000000000011;
        (max_val[0] == value[10]):  choose = 32'b00000000000000000000000000001110;
        (max_val[0] == value[11]):  choose = 32'b00000000000000000000000000001101;
        (max_val[0] == value[12]):  choose = 32'b00000000000000000000000000001011;
        (max_val[0] == value[13]):  choose = 32'b00000000000000000000000000000111;
        (max_val[0] == value[14]):  choose = 32'b00000000000000000000000000001111;
        default:                    choose = 32'b00000000000000000000000000000000;
    endcase
end

// output
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid <= 1'b0;
    end else begin
        if (task_num) begin
            out_valid <= (cnt == 8'd90);
        end else begin
            out_valid <= (cnt == 8'd103) || (cnt == 8'd104) || (cnt == 8'd105);
        end
    end
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out <= 32'd0;
    end else begin
        if (task_num) begin
            out <= (cnt == 8'd90) ? choose : 32'd0;
        end else begin
            case (cnt)
                8'd103, 8'd104, 8'd105: out <= div_res;
                default:                 out <= 32'd0;
            endcase
        end
    end
end
endmodule

// IP
module fp_mult( inst_a, inst_b, inst_rnd, z_inst);
parameter sig_width = 23;
parameter exp_width = 8;
parameter ieee_compliance = 0;
parameter en_ubr_flag = 0;
input [sig_width+exp_width : 0] inst_a;
input [sig_width+exp_width : 0] inst_b;
input [2 : 0] inst_rnd;
output [sig_width+exp_width : 0] z_inst;
    DW_fp_mult #(sig_width, exp_width, ieee_compliance, en_ubr_flag)
      U1 ( .a(inst_a), .b(inst_b), .rnd(inst_rnd), .z(z_inst), .status() );
endmodule

module fp_add(inst_a, inst_b, inst_rnd, z_inst);
parameter sig_width = 23;
parameter exp_width = 8;
parameter ieee_compliance = 0;
input [sig_width+exp_width : 0] inst_a;
input [sig_width+exp_width : 0] inst_b;
input [2 : 0] inst_rnd;
output [sig_width+exp_width : 0] z_inst;
    DW_fp_add #(sig_width, exp_width, ieee_compliance)
      U1 ( .a(inst_a), .b(inst_b), .rnd(inst_rnd), .z(z_inst), .status() );
endmodule

module fp_max( inst_a, inst_b, max_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
input [inst_sig_width+inst_exp_width:0] inst_b;
output [inst_sig_width+inst_exp_width:0] max_inst;
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U1( .a(inst_a), .b(inst_b), .zctr(1'b0), .z1(max_inst) );
endmodule

module fp_exp( inst_a, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
output [inst_sig_width+inst_exp_width:0] z_inst;
DW_fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch) 
        U1 ( .a(inst_a), .z(z_inst) );
endmodule

module fp_div( inst_a, inst_b, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_faithful_round = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
input [inst_sig_width+inst_exp_width:0] inst_b;
output [inst_sig_width+inst_exp_width:0] z_inst;
DW_fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_faithful_round) 
        U1( .a(inst_a), .b(inst_b), .rnd(3'b000), .z(z_inst) );
endmodule
