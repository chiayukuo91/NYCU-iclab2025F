`timescale 1ns/10ps

module FIFO_syn #(parameter WIDTH=16, parameter WORDS=64) (
  input  wire                 wclk,
  input  wire                 rclk,
  input  wire                 rst_n,
  // write
  input  wire                 winc,
  input  wire [WIDTH-1:0]     wdata,
  output reg                  wfull,
  // read
  input  wire                 rinc,
  output reg  [WIDTH-1:0]     rdata,
  output reg                  rempty,
  // flags 
  output wire                 flag_fifo_to_clk2,
  input  wire                 flag_clk2_to_fifo,
  output wire                 flag_fifo_to_clk3,
  input  wire                 flag_clk3_to_fifo
);

  localparam P = $clog2(WORDS);          // 64 -> 6
  reg  [P:0] wptr;                        // gray-coded write ptr
  reg  [P:0] rptr;                        // gray-coded read  ptr

  reg  [P:0] wbin, rbin;
  wire [P:0] wbin_n, rbin_n;

  wire [P:0] wgray_n, rgray_n;

  wire [P:0] rptr_sync_wclk;
  wire [P:0] wptr_sync_rclk;

  reg  [P-1:0] wa, ra;
  wire [WIDTH-1:0] rdata_q;

  wire w_adv =  winc & ~wfull;
  wire r_adv =  rinc & ~rempty;

  reg  rinc_q;

  function [P:0] fn_bin2gray; input [P:0] b;
    begin fn_bin2gray = b ^ (b >> 1); end
  endfunction

  assign wbin_n  = wbin + {{P{1'b0}}, w_adv};
  assign rbin_n  = rbin + {{P{1'b0}}, r_adv};
  assign wgray_n = fn_bin2gray(wbin_n);
  assign rgray_n = fn_bin2gray(rbin_n);

  always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) rdata <= {WIDTH{1'b0}};
    else if (rinc | rinc_q) rdata <= rdata_q;
    else                    rdata <= rdata;
  end

  always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) rinc_q <= 1'b0;
    else        rinc_q <= rinc;
  end

  NDFF_BUS_syn #(.WIDTH(P+1)) U_SYNC_R2W (
    .D   (rptr),
    .Q   (rptr_sync_wclk),
    .clk (wclk),
    .rst_n(rst_n)
  );

  always @(posedge wclk or negedge rst_n) begin
    if (!rst_n) begin
      wbin  <= {P+1{1'b0}};
      wptr  <= {P+1{1'b0}};
    end else begin
      wbin  <= wbin_n;
      wptr  <= wgray_n;
    end
  end

  wire [P:0] wfull_cmp = {~rptr_sync_wclk[P:P-1], rptr_sync_wclk[P-2:0]};
  always @(posedge wclk or negedge rst_n) begin
    if (!rst_n) wfull <= 1'b0;
    else        wfull <= (wgray_n == wfull_cmp);
  end

  NDFF_BUS_syn #(.WIDTH(P+1)) U_SYNC_W2R (
    .D   (wptr),
    .Q   (wptr_sync_rclk),
    .clk (rclk),
    .rst_n(rst_n)
  );

  always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) begin
      rbin <= {P+1{1'b0}};
      rptr <= {P+1{1'b0}};
    end else begin
      rbin <= rbin_n;
      rptr <= rgray_n;
    end
  end

  always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) rempty <= 1'b1;
    else        rempty <= (rgray_n == wptr_sync_rclk);
  end

  always @* begin
    wa = wbin[P-1:0];
    ra = rbin[P-1:0];
  end

  DUAL_64X16X1BM1 u_dual_sram (
    .CKA (wclk), .CKB (rclk),
    .WEAN(~winc), .WEBN(1'b1),
    .CSA (1'b1),  .CSB (1'b1),
    .OEA (1'b1),  .OEB (1'b1),
    .A0 (wa[0]), .A1 (wa[1]), .A2 (wa[2]), .A3 (wa[3]), .A4 (wa[4]), .A5 (wa[5]),
    .B0 (ra[0]), .B1 (ra[1]), .B2 (ra[2]), .B3 (ra[3]), .B4 (ra[4]), .B5 (ra[5]),
    .DIA0 (wdata[0]),  .DIA1 (wdata[1]),  .DIA2 (wdata[2]),  .DIA3 (wdata[3]),
    .DIA4 (wdata[4]),  .DIA5 (wdata[5]),  .DIA6 (wdata[6]),  .DIA7 (wdata[7]),
    .DIA8 (wdata[8]),  .DIA9 (wdata[9]),  .DIA10(wdata[10]), .DIA11(wdata[11]),
    .DIA12(wdata[12]), .DIA13(wdata[13]), .DIA14(wdata[14]), .DIA15(wdata[15]),
    .DOB0 (rdata_q[0]),  .DOB1 (rdata_q[1]),  .DOB2 (rdata_q[2]),  .DOB3 (rdata_q[3]),
    .DOB4 (rdata_q[4]),  .DOB5 (rdata_q[5]),  .DOB6 (rdata_q[6]),  .DOB7 (rdata_q[7]),
    .DOB8 (rdata_q[8]),  .DOB9 (rdata_q[9]),  .DOB10(rdata_q[10]), .DOB11(rdata_q[11]),
    .DOB12(rdata_q[12]), .DOB13(rdata_q[13]), .DOB14(rdata_q[14]), .DOB15(rdata_q[15])
  );

  assign flag_fifo_to_clk2 = wfull;
  assign flag_fifo_to_clk3 = rempty;

endmodule
