`timescale 1ns/10ps
module CPU(
  clk, rst_n, IO_stall,
  awid_m_inf, awaddr_m_inf, awsize_m_inf, awburst_m_inf, awlen_m_inf, awvalid_m_inf, awready_m_inf,
  wdata_m_inf, wlast_m_inf,  wvalid_m_inf,  wready_m_inf,
  bid_m_inf,   bresp_m_inf,  bvalid_m_inf,  bready_m_inf,
  arid_m_inf,  araddr_m_inf, arlen_m_inf,   arsize_m_inf, arburst_m_inf, arvalid_m_inf,
  arready_m_inf, rid_m_inf,  rdata_m_inf,   rresp_m_inf,  rlast_m_inf,   rvalid_m_inf, rready_m_inf
);
  // ------------------------------------------------------------------
  // I/O
  // ------------------------------------------------------------------
  input  wire clk;
  input  wire rst_n;
  output reg  IO_stall;

  parameter ID_WIDTH   = 4;
  parameter ADDR_WIDTH = 32;
  parameter DATA_WIDTH = 16;
  parameter DRAM_NUMBER= 2;
  parameter WRIT_NUMBER= 1;

  // ================= AXI Write Address =================
  output wire [WRIT_NUMBER*ID_WIDTH-1:0]   awid_m_inf;
  output wire [WRIT_NUMBER*ADDR_WIDTH-1:0] awaddr_m_inf;
  output wire [WRIT_NUMBER*3-1:0]          awsize_m_inf;
  output wire [WRIT_NUMBER*2-1:0]          awburst_m_inf;
  output wire [WRIT_NUMBER*7-1:0]          awlen_m_inf;
  output wire [WRIT_NUMBER-1:0]            awvalid_m_inf;
  input  wire [WRIT_NUMBER-1:0]            awready_m_inf;

  // ================= AXI Write Data =====================
  output wire [WRIT_NUMBER*DATA_WIDTH-1:0] wdata_m_inf;
  output wire [WRIT_NUMBER-1:0]            wlast_m_inf;
  output wire [WRIT_NUMBER-1:0]            wvalid_m_inf;
  input  wire [WRIT_NUMBER-1:0]            wready_m_inf;

  // ================= AXI Write Resp =====================
  input  wire [WRIT_NUMBER*ID_WIDTH-1:0]   bid_m_inf;
  input  wire [WRIT_NUMBER*2-1:0]          bresp_m_inf;
  input  wire [WRIT_NUMBER-1:0]            bvalid_m_inf;
  output wire [WRIT_NUMBER-1:0]            bready_m_inf;

  // ================= AXI Read Address ===================
  output wire [DRAM_NUMBER*ID_WIDTH-1:0]   arid_m_inf;
  output wire [DRAM_NUMBER*ADDR_WIDTH-1:0] araddr_m_inf;
  output wire [DRAM_NUMBER*7-1:0]          arlen_m_inf;
  output wire [DRAM_NUMBER*3-1:0]          arsize_m_inf;
  output wire [DRAM_NUMBER*2-1:0]          arburst_m_inf;
  output wire [DRAM_NUMBER-1:0]            arvalid_m_inf;
  input  wire [DRAM_NUMBER-1:0]            arready_m_inf;

  // ================= AXI Read Data ======================
  input  wire [DRAM_NUMBER*ID_WIDTH-1:0]   rid_m_inf;
  input  wire [DRAM_NUMBER*DATA_WIDTH-1:0] rdata_m_inf;
  input  wire [DRAM_NUMBER*2-1:0]          rresp_m_inf;
  input  wire [DRAM_NUMBER-1:0]            rlast_m_inf;
  input  wire [DRAM_NUMBER-1:0]            rvalid_m_inf;
  output wire [DRAM_NUMBER-1:0]            rready_m_inf;

  // Core registers
  reg signed [15:0] core_r0;
  reg signed [15:0] core_r1;
  reg signed [15:0] core_r2;
  reg signed [15:0] core_r3;
  reg signed [15:0] core_r4;
  reg signed [15:0] core_r5;
  reg signed [15:0] core_r6;
  reg signed [15:0] core_r7;
  reg signed [15:0] core_r8;
  reg signed [15:0] core_r9;
  reg signed [15:0] core_r10;
  reg signed [15:0] core_r11;
  reg signed [15:0] core_r12;
  reg signed [15:0] core_r13;
  reg signed [15:0] core_r14;
  reg signed [15:0] core_r15;

  // REG & WIRE
  reg  [4:0]  state;
  reg  [4:0]  next_state;
  reg  [6:0]  cnt;
  reg  [7:0]  sram_addr;

  reg  [15:0] pc, sram_din, inst;
  reg         sram_low_web;
  reg         in_ld_data;
  wire [15:0] sram_dout;

  reg  [2:0]        inst_opcode_r;
  reg  [3:0]        inst_rs_r, inst_rt_r, inst_rd_r;
  reg               inst_func_r;
  reg  signed [4:0] inst_imm_r;
  reg  [12:0]       inst_address_r;

  wire [2:0]        inst_opcode = inst_opcode_r;
  wire [3:0]        inst_rs     = inst_rs_r;
  wire [3:0]        inst_rt     = inst_rt_r;
  wire [3:0]        inst_rd     = inst_rd_r;
  wire              inst_func   = inst_func_r;
  wire signed [4:0] inst_imm    = inst_imm_r;
  wire [12:0]       inst_address= inst_address_r;

  reg  signed [15:0] inst_rs_buf, inst_rt_buf, inst_rd_buf;
  wire signed [31:0] mul;

  reg  [4:0]  block_inst, block_data;
  wire signed [15:0] store_load_addr;

  // Read path buffers  [1] = inst, [0] = data
  reg [ADDR_WIDTH-1:0] rd_addr_q [0:1];
  reg                  rd_arv_q  [0:1];
  reg                  rd_rdy_q  [0:1];

  // Write path buffers (data DRAM)
  reg [ADDR_WIDTH-1:0] wr_addr_q;
  reg [DATA_WIDTH-1:0] wr_wdat_q;
  reg                  wr_awv_q, wr_wlast_q, wr_wv_q, wr_bready_q;

  localparam [4:0]
    ST_BOOT        = 5'h1E,
    ST_IF_CHK      = 5'h04,
    ST_IF_RDY      = 5'h13,
    ST_IF_FILL     = 5'h00,
    ST_IF_DONE     = 5'h0F, 
    ST_IF_SRAM     = 5'h09,

    ST_DF_CHK      = 5'h12, 
    ST_DF_RDY      = 5'h06, 
    ST_DF_FILL     = 5'h1B,
    ST_DF_DONE     = 5'h0A,
    ST_DF_SRAM     = 5'h1D,

    ST_DEC_I       = 5'h02,
    ST_DEC_R       = 5'h15,
    ST_DEC_B       = 5'h0C,

    ST_ST_AW       = 5'h17,
    ST_ST_WB       = 5'h08, 
    ST_ALU         = 5'h10;

  always @(posedge clk or negedge rst_n)
    if (!rst_n) state <= ST_BOOT;
    else        state <= next_state;

  wire f_BOOT   = (state==ST_BOOT);
  wire f_IF_CHK = (state==ST_IF_CHK);
  wire f_IF_RDY = (state==ST_IF_RDY);
  wire f_IF_FILL= (state==ST_IF_FILL);
  wire f_IF_DONE= (state==ST_IF_DONE);
  wire f_IF_SRAM= (state==ST_IF_SRAM);

  wire f_DF_CHK = (state==ST_DF_CHK);
  wire f_DF_RDY = (state==ST_DF_RDY);
  wire f_DF_FILL= (state==ST_DF_FILL);
  wire f_DF_DONE= (state==ST_DF_DONE);
  wire f_DF_SRAM= (state==ST_DF_SRAM);

  wire f_DEC_I  = (state==ST_DEC_I);
  wire f_DEC_R  = (state==ST_DEC_R);
  wire f_DEC_B  = (state==ST_DEC_B);

  wire f_ST_AW  = (state==ST_ST_AW);
  wire f_ST_WB  = (state==ST_ST_WB);
  wire f_ALU    = (state==ST_ALU);

  wire [4:0] nx_BOOT    = ST_IF_RDY;

  wire [4:0] nx_IF_CHK  = (block_inst != pc[11:7]) ? ST_IF_RDY : ST_IF_DONE;
  wire [4:0] nx_IF_RDY  = (arready_m_inf[1]) ? ST_IF_FILL : ST_IF_RDY;
  wire [4:0] nx_IF_FILL = (rlast_m_inf[1])   ? ST_IF_DONE : ST_IF_FILL;
  wire [4:0] nx_IF_DONE = (~in_ld_data) ? ST_DF_RDY : ST_IF_SRAM;
  wire [4:0] nx_IF_SRAM = ST_DEC_I;

  wire [4:0] nx_DF_CHK  = (block_data != store_load_addr[12:8]) ? ST_DF_RDY : ST_DF_DONE;
  wire [4:0] nx_DF_RDY  = (arready_m_inf[0]) ? ST_DF_FILL : ST_DF_RDY;
  wire [4:0] nx_DF_FILL = (rlast_m_inf[0])   ? ST_DF_DONE : ST_DF_FILL;
  wire [4:0] nx_DF_DONE = (~in_ld_data) ? ST_IF_DONE : ST_DF_SRAM;
  wire [4:0] nx_DF_SRAM = ST_IF_CHK;

  wire       is_calc_op = (inst_opcode[2:1]==2'b00);
  wire [4:0] nx_DEC_I   = ST_DEC_R;
  wire [4:0] nx_DEC_R   = ST_DEC_B;
  wire [4:0] nx_DEC_B   = is_calc_op            ? ST_ALU :
                          (inst_opcode==3'b011) ? ST_DF_CHK :
                          (inst_opcode==3'b010) ? ST_ST_AW : ST_IF_CHK;

  wire [4:0] nx_ST_AW   = (awready_m_inf[0]) ? ST_ST_WB : ST_ST_AW;
  wire [4:0] nx_ST_WB   = (bvalid_m_inf[0])  ? ST_IF_CHK : ST_ST_WB;

  wire [4:0] nx_ALU     = ST_IF_CHK;

  always @(*) begin
    next_state = ST_BOOT;
    if      (f_BOOT)    next_state = nx_BOOT;
    else if (f_IF_CHK)  next_state = nx_IF_CHK;
    else if (f_IF_RDY)  next_state = nx_IF_RDY;
    else if (f_IF_FILL) next_state = nx_IF_FILL;
    else if (f_IF_DONE) next_state = nx_IF_DONE;
    else if (f_IF_SRAM) next_state = nx_IF_SRAM;
    else if (f_DF_CHK)  next_state = nx_DF_CHK;
    else if (f_DF_RDY)  next_state = nx_DF_RDY;
    else if (f_DF_FILL) next_state = nx_DF_FILL;
    else if (f_DF_DONE) next_state = nx_DF_DONE;
    else if (f_DF_SRAM) next_state = nx_DF_SRAM;
    else if (f_DEC_I)   next_state = nx_DEC_I;
    else if (f_DEC_R)   next_state = nx_DEC_R;
    else if (f_DEC_B)   next_state = nx_DEC_B;
    else if (f_ST_AW)   next_state = nx_ST_AW;
    else if (f_ST_WB)   next_state = nx_ST_WB;
    else if (f_ALU)     next_state = nx_ALU;
  end

// in_ld_data
always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    in_ld_data <= 1'b0;
  else
    in_ld_data <= (state == ST_DF_DONE) ? 1'b1 : in_ld_data;
end

// cnt
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    cnt <= 8'd0;
  end else begin
    case (state)
      ST_IF_FILL,
      ST_DF_FILL:  cnt <= (rvalid_m_inf) ? (cnt + 8'd1) : cnt;
      default:     cnt <= 8'd0;
    endcase
  end
end

// opcode
localparam [2:0] OPC_J   = 3'h4;  // jump
localparam [2:0] OPC_BEQ = 3'h5;  // beq
wire               decB      = (state == ST_DEC_B);
wire [15:0]        pc_inc    = pc + 16'h0001;
wire               is_jump   = (inst_opcode == OPC_J);
wire               is_beq    = (inst_opcode == OPC_BEQ);
wire               beq_take  = is_beq && (inst_rs_buf == inst_rt_buf);
wire [15:0]        j_addr_w  = {3'b000, inst_address} >> 1;                // byte->word
wire [15:0]        beq_ofs   = {{11{inst_imm[4]}}, inst_imm};              // 5-bit sign-extend
wire [15:0]        beq_next  = pc_inc + beq_ofs;
wire [15:0]        next_pc   = is_jump ? j_addr_w : (beq_take ? beq_next : pc_inc);

// PC 
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    pc <= 16'h0800;  // 2048 (word address)
  end else if (decB) begin
    pc <= next_pc;
  end
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    inst <= 16'd0;
  end else begin
    inst <= (state == ST_DEC_I) ? sram_dout : inst;
  end
end

  always @(*) begin
    inst_opcode_r  = inst[15:13];
    inst_rs_r      = inst[12:9];
    inst_rt_r      = inst[8:5];
    inst_rd_r      = inst[4:1];
    inst_func_r    = inst[0];
    inst_imm_r     = inst[4:0];
    inst_address_r = inst[12:0];
  end

// RS
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    inst_rs_buf <= 16'sd0;
  end else if (state == ST_DEC_R) begin
    casez (inst_rs)
      4'b0000: inst_rs_buf <= core_r0;
      4'b0001: inst_rs_buf <= core_r1;
      4'b001?: inst_rs_buf <= (inst_rs[0]) ? core_r3 : core_r2;
      4'b010?: inst_rs_buf <= (inst_rs[0]) ? core_r5 : core_r4;
      4'b011?: inst_rs_buf <= (inst_rs[0]) ? core_r7 : core_r6;
      4'b10??: begin
        casez (inst_rs[1:0])
          2'b00: inst_rs_buf <= core_r8;
          2'b01: inst_rs_buf <= core_r9;
          2'b10: inst_rs_buf <= core_r10;
          2'b11: inst_rs_buf <= core_r11;
        endcase
      end
      4'b11??: begin
        casez (inst_rs[1:0])
          2'b00: inst_rs_buf <= core_r12;
          2'b01: inst_rs_buf <= core_r13;
          2'b10: inst_rs_buf <= core_r14;
          2'b11: inst_rs_buf <= core_r15;
        endcase
      end
      default: inst_rs_buf <= 16'sd0;
    endcase
  end
end

// RT
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    inst_rt_buf <= 16'sd0;
  end else if (state == ST_DEC_R) begin
    casez (inst_rt)
      4'b0000: inst_rt_buf <= core_r0;
      4'b0001: inst_rt_buf <= core_r1;
      4'b001?: inst_rt_buf <= (inst_rt[0]) ? core_r3 : core_r2;
      4'b010?: inst_rt_buf <= (inst_rt[0]) ? core_r5 : core_r4;
      4'b011?: inst_rt_buf <= (inst_rt[0]) ? core_r7 : core_r6;
      4'b10??: begin
        casez (inst_rt[1:0])
          2'b00: inst_rt_buf <= core_r8;
          2'b01: inst_rt_buf <= core_r9;
          2'b10: inst_rt_buf <= core_r10;
          2'b11: inst_rt_buf <= core_r11;
        endcase
      end
      4'b11??: begin
        casez (inst_rt[1:0])
          2'b00: inst_rt_buf <= core_r12;
          2'b01: inst_rt_buf <= core_r13;
          2'b10: inst_rt_buf <= core_r14;
          2'b11: inst_rt_buf <= core_r15;
        endcase
      end
      default: inst_rt_buf <= 16'sd0;
    endcase
  end
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    inst_rd_buf <= 16'sd0;
  else if (state == ST_ALU)
    inst_rd_buf <= (inst_opcode==3'h0) ? (inst_func ? inst_rs_buf + inst_rt_buf 
                                                    : inst_rs_buf - inst_rt_buf)
                  : (inst_opcode==3'h1) ? (inst_func ? ((inst_rs_buf < inst_rt_buf) ? 16'sd1 : 16'sd0)
                                                    : mul[15:0])
                  : inst_rd_buf;
end

//DW02_mult_2_stage #(A_width, B_width) U1 ( .A(inst_A), .B(inst_B), .TC(inst_TC), .CLK(inst_CLK), .PRODUCT(PRODUCT_inst) );
DW02_mult_2_stage #(16,16) U_MUL (.A(inst_rs_buf), .B(inst_rt_buf), .TC(1'b1), .CLK(clk), .PRODUCT(mul));

always @(posedge clk or negedge rst_n)
  block_inst <= (!rst_n) ? 5'd0 :
                (state == ST_IF_RDY) ? pc[11:7] : block_inst;
				
assign store_load_addr = ($signed(inst_rs_buf + inst_imm) <<< 1) + 16'h1000;

always @(posedge clk or negedge rst_n)
  block_data <= (!rst_n) ? 5'd0 :
                (state == ST_DF_RDY) ? store_load_addr[12:8] : block_data;

  // IO_stall
always @(posedge clk or negedge rst_n)
  IO_stall <= (!rst_n) ? 1'b1 :
              (state == ST_IF_CHK) ? 1'b0 : 1'b1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      core_r0<=16'sh0000; core_r1<=16'sh0000; core_r2<=16'sh0000; core_r3<=16'sh0000;
      core_r4<=16'sh0000; core_r5<=16'sh0000; core_r6<=16'sh0000; core_r7<=16'sh0000;
      core_r8<=16'sh0000; core_r9<=16'sh0000; core_r10<=16'sh0000; core_r11<=16'sh0000;
      core_r12<=16'sh0000; core_r13<=16'sh0000; core_r14<=16'sh0000; core_r15<=16'sh0000;
    end else if (state==ST_IF_CHK) begin
      if (inst_opcode[2:1]==2'h0) begin
        case(inst_rd)
          4'h0:  core_r0  <= inst_rd_buf;  4'h1:  core_r1  <= inst_rd_buf;
          4'h2:  core_r2  <= inst_rd_buf;  4'h3:  core_r3  <= inst_rd_buf;
          4'h4:  core_r4  <= inst_rd_buf;  4'h5:  core_r5  <= inst_rd_buf;
          4'h6:  core_r6  <= inst_rd_buf;  4'h7:  core_r7  <= inst_rd_buf;
          4'h8:  core_r8  <= inst_rd_buf;  4'h9:  core_r9  <= inst_rd_buf;
          4'hA:  core_r10 <= inst_rd_buf;  4'hB:  core_r11 <= inst_rd_buf;
          4'hC:  core_r12 <= inst_rd_buf;  4'hD:  core_r13 <= inst_rd_buf;
          4'hE:  core_r14 <= inst_rd_buf;  4'hF:  core_r15 <= inst_rd_buf;
        endcase
      end else if (inst_opcode==3'h3) begin
        case(inst_rt)
          4'h0:  core_r0  <= sram_dout;    4'h1:  core_r1  <= sram_dout;
          4'h2:  core_r2  <= sram_dout;    4'h3:  core_r3  <= sram_dout;
          4'h4:  core_r4  <= sram_dout;    4'h5:  core_r5  <= sram_dout;
          4'h6:  core_r6  <= sram_dout;    4'h7:  core_r7  <= sram_dout;
          4'h8:  core_r8  <= sram_dout;    4'h9:  core_r9  <= sram_dout;
          4'hA:  core_r10 <= sram_dout;    4'hB:  core_r11 <= sram_dout;
          4'hC:  core_r12 <= sram_dout;    4'hD:  core_r13 <= sram_dout;
          4'hE:  core_r14 <= sram_dout;    4'hF:  core_r15 <= sram_dout;
        endcase
      end
    end
  end

  // AXI
  reg [DRAM_NUMBER*ID_WIDTH-1:0]   arid_pack;
  reg [DRAM_NUMBER*ADDR_WIDTH-1:0] araddr_pack;
  reg [DRAM_NUMBER*7-1:0]          arlen_pack;
  reg [DRAM_NUMBER*3-1:0]          arsize_pack;
  reg [DRAM_NUMBER*2-1:0]          arburst_pack;
  reg [DRAM_NUMBER-1:0]            arvalid_pack;

  reg [WRIT_NUMBER*DATA_WIDTH-1:0] wdata_pack;
  reg [WRIT_NUMBER-1:0]            wlast_pack;
  reg [WRIT_NUMBER-1:0]            wvalid_pack;

  reg [WRIT_NUMBER*ID_WIDTH-1:0]   awid_pack;
  reg [WRIT_NUMBER*ADDR_WIDTH-1:0] awaddr_pack;
  reg [WRIT_NUMBER*7-1:0]          awlen_pack;
  reg [WRIT_NUMBER*3-1:0]          awsize_pack;
  reg [WRIT_NUMBER*2-1:0]          awburst_pack;
  reg [WRIT_NUMBER-1:0]            awvalid_pack;

  reg [DRAM_NUMBER-1:0]            rready_pack;
  reg [WRIT_NUMBER-1:0]            bready_pack;

  always @(*) begin
    arid_pack    = { {ID_WIDTH{1'b0}}, {ID_WIDTH{1'b0}} };
    araddr_pack  = { rd_addr_q[1], rd_addr_q[0] };
    arlen_pack   = 14'h3FFF;
    arsize_pack  = 6'h09;
    arburst_pack = 4'h5;
    arvalid_pack = { rd_arv_q[1], rd_arv_q[0] };

    wdata_pack   = wr_wdat_q;
    wlast_pack   = wr_wlast_q;
    wvalid_pack  = wr_wv_q;

    awid_pack    = {ID_WIDTH{1'b0}};
    awaddr_pack  = wr_addr_q;
    awlen_pack   = 7'h00;
    awsize_pack  = 3'h1;
    awburst_pack = 2'h1;
    awvalid_pack = wr_awv_q;

    rready_pack  = { rd_rdy_q[1], rd_rdy_q[0] };
    bready_pack  = wr_bready_q;
  end

  assign arid_m_inf    = arid_pack;
  assign araddr_m_inf  = araddr_pack;
  assign arlen_m_inf   = arlen_pack;
  assign arsize_m_inf  = arsize_pack;
  assign arburst_m_inf = arburst_pack;
  assign arvalid_m_inf = arvalid_pack;

  assign wdata_m_inf   = wdata_pack;
  assign wlast_m_inf   = wlast_pack;
  assign wvalid_m_inf  = wvalid_pack;

  assign awid_m_inf    = awid_pack;
  assign awaddr_m_inf  = awaddr_pack;
  assign awlen_m_inf   = awlen_pack;
  assign awsize_m_inf  = awsize_pack;
  assign awburst_m_inf = awburst_pack;
  assign awvalid_m_inf = awvalid_pack;

  assign rready_m_inf  = rready_pack;
  assign bready_m_inf  = bready_pack;


  localparam [2:0] IF_Q  = 3'b100; 
  localparam [2:0] IF_AR = 3'b010; 
  localparam [2:0] IF_R  = 3'b001;

  reg [2:0] if_st, if_st_nx;
  wire      if_trig = (state==ST_IF_RDY);

  always @(posedge clk or negedge rst_n)
    if (!rst_n) if_st <= IF_Q; else if_st <= if_st_nx;

  always @(*) begin
    if_st_nx = if_st;
    if (if_st[2]) begin
      if_st_nx = if_trig ? IF_AR : IF_Q;
    end
    else if (if_st[1]) begin
      if_st_nx = (arready_m_inf[1]) ? IF_R : IF_AR;
    end
    else if (if_st[0]) begin
      if_st_nx = (rlast_m_inf[1]) ? IF_Q : IF_R;
    end
  end

  // araddr for inst channel -> rd_addr_q[1]
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rd_addr_q[1] <= {ADDR_WIDTH{1'b0}};
    else if (if_st[2] && if_trig)          rd_addr_q[1] <= {16'h0000, pc[14:7], 8'h00};
    else if (if_st[0] && rlast_m_inf[1])   rd_addr_q[1] <= {ADDR_WIDTH{1'b0}};
  end

  // valid/ready
  always @(*) rd_arv_q[1] = if_st[1];
  always @(*) rd_rdy_q[1] = if_st[0];

  localparam DF_Q  = 2'd0;
  localparam DF_AR = 2'd1;
  localparam DF_R  = 2'd2; 
  reg [1:0] df_st, df_st_nx;
  wire      df_trig = (state==ST_DF_RDY);

  always @(posedge clk or negedge rst_n)
    if (!rst_n) df_st <= DF_Q; else df_st <= df_st_nx;

  always @(*) begin
    case (df_st)
      DF_Q : df_st_nx = df_trig ? DF_AR : DF_Q;
      DF_AR: df_st_nx = (arready_m_inf[0]) ? DF_R : DF_AR;
      DF_R : df_st_nx = (rlast_m_inf[0])   ? DF_Q : DF_R;
      default: df_st_nx = DF_Q;
    endcase
  end

  // araddr for data channel -> rd_addr_q[0]
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rd_addr_q[0] <= {ADDR_WIDTH{1'b0}};
    else if (df_st==DF_Q  && df_trig)        rd_addr_q[0] <= {16'h0000, store_load_addr[15:8], 8'h00};
    else if (df_st==DF_R  && rlast_m_inf[0]) rd_addr_q[0] <= {ADDR_WIDTH{1'b0}};
  end

  always @(*) rd_arv_q[0] = (df_st==DF_AR);
  always @(*) rd_rdy_q[0] = (df_st==DF_R);


  localparam WB_Q  = 2'd0; 
  localparam WB_AW = 2'd1; 
  localparam WB_W  = 2'd2; 
  localparam WB_B  = 2'd3;
  reg [1:0] wb_st, wb_st_nx;
  wire      wb_trig = (state==ST_ST_AW);

  always @(posedge clk or negedge rst_n)
    if (!rst_n) wb_st <= WB_Q; else wb_st <= wb_st_nx;

  always @(*) begin
    case (wb_st)
      WB_Q : wb_st_nx = wb_trig ? WB_AW : WB_Q;
      WB_AW: wb_st_nx = (awready_m_inf[0]) ? WB_W : WB_AW;
      WB_W : wb_st_nx = (wready_m_inf[0])  ? WB_B : WB_W;
      WB_B : wb_st_nx = (bvalid_m_inf[0])  ? WB_Q : WB_B;
      default: wb_st_nx = WB_Q;
    endcase
  end

  // AW addr/data/handshake -> wr_*
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) wr_addr_q <= {ADDR_WIDTH{1'b0}};
    else if (wb_st==WB_Q  && wb_trig)     wr_addr_q <= store_load_addr;
    else if (wb_st==WB_B && bvalid_m_inf[0]) wr_addr_q <= {ADDR_WIDTH{1'b0}};
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) wr_wdat_q <= {DATA_WIDTH{1'b0}};
    else if (wb_st==WB_W)                     wr_wdat_q <= inst_rt_buf;
    else if (wb_st==WB_B && bvalid_m_inf[0])  wr_wdat_q <= {DATA_WIDTH{1'b0}};
  end

  always @(*) wr_awv_q    = (wb_st==WB_AW);
  always @(*) wr_wv_q     = (wb_st==WB_W);
  always @(*) wr_wlast_q  = (wb_st==WB_W);
  always @(*) wr_bready_q = (wb_st==WB_B);

  Spad256x16 u_spad (
    .A  (sram_addr), .DI (sram_din), .DO (sram_dout),
    .CK (clk), .WEB(sram_low_web), .OE (1'b1), .CS (1'b1)
  );

  always @(posedge clk or negedge rst_n)
    if (!rst_n) sram_addr <= 8'h00;
    else if (state==ST_IF_FILL)                  sram_addr <= {1'b1, cnt[6:0]};
    else if (state==ST_IF_DONE)                  sram_addr <= {1'b1, pc[6:0]};
    else if (state==ST_DF_FILL)                  sram_addr <= {1'b0, cnt[6:0]};
    else if (state==ST_DF_DONE)                  sram_addr <= {1'b0, store_load_addr[7:1]};
    else if (state==ST_ST_AW && (store_load_addr[12:8]==block_data))
                                                 sram_addr <= {1'b0, store_load_addr[7:1]};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sram_din <= 16'h0000;
    else if (state==ST_IF_FILL) sram_din <= rdata_m_inf[31:16];
    else if (state==ST_DF_FILL) sram_din <= rdata_m_inf[15:0];
    else if (state==ST_ST_AW && (store_load_addr[12:8]==block_data)) sram_din <= inst_rt_buf;
    else sram_din <= 16'h0000;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sram_low_web <= 1'b1;
    else if (state==ST_IF_FILL) sram_low_web <= 1'b0;
    else if (state==ST_DF_FILL) sram_low_web <= 1'b0;
    else if (state==ST_ST_AW && (store_load_addr[12:8]==block_data)) sram_low_web <= 1'b0;
    else sram_low_web <= 1'b1;
  end

endmodule

module Spad256x16 (
  input  [7:0]  A,
  input  [15:0] DI,
  output [15:0] DO,
  input         CK,
  input         WEB,
  input         OE,
  input         CS
);
  MEM256 u_mem_primitive (
    .A0 (A[0]), .A1 (A[1]), .A2 (A[2]), .A3 (A[3]),
    .A4 (A[4]), .A5 (A[5]), .A6 (A[6]), .A7 (A[7]),
    .DO0 (DO[0]),  .DO1 (DO[1]),  .DO2 (DO[2]),  .DO3 (DO[3]),
    .DO4 (DO[4]),  .DO5 (DO[5]),  .DO6 (DO[6]),  .DO7 (DO[7]),
    .DO8 (DO[8]),  .DO9 (DO[9]),  .DO10(DO[10]), .DO11(DO[11]),
    .DO12(DO[12]), .DO13(DO[13]), .DO14(DO[14]), .DO15(DO[15]),
    .DI0 (DI[0]),  .DI1 (DI[1]),  .DI2 (DI[2]),  .DI3 (DI[3]),
    .DI4 (DI[4]),  .DI5 (DI[5]),  .DI6 (DI[6]),  .DI7 (DI[7]),
    .DI8 (DI[8]),  .DI9 (DI[9]),  .DI10(DI[10]), .DI11(DI[11]),
    .DI12(DI[12]), .DI13(DI[13]), .DI14(DI[14]), .DI15(DI[15]),
    .CK  (CK), .WEB (WEB), .OE (OE), .CS (CS)
  );
endmodule
