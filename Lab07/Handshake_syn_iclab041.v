`timescale 1ns/10ps
module Handshake_syn #(parameter WIDTH=32) (
    input  wire                sclk,
    input  wire                dclk,
    input  wire                rst_n,
    input  wire                sready,
    input  wire [WIDTH-1:0]    din,
    input  wire                dbusy,
    output wire                sidle,
    output reg                 dvalid,
    output reg  [WIDTH-1:0]    dout,

    output wire                flag_handshake_to_clk1,
    input  wire                flag_clk1_to_handshake, // unused
    output wire                flag_handshake_to_clk2,
    input  wire                flag_clk2_to_handshake  // unused
);
  reg  sreq;
  wire dreq;
  reg  dack;
  wire sack;

  reg [WIDTH-1:0] src_data, dst_data;

  NDFF_syn SRC(.D(sreq), .Q(dreq), .clk(dclk), .rst_n(rst_n));
  NDFF_syn DST(.D(dack), .Q(sack), .clk(sclk), .rst_n(rst_n));

  assign flag_handshake_to_clk1 = sack;
  assign flag_handshake_to_clk2 = dreq;

  localparam S0_IDLE = 2'b00;
  localparam S0_SEND = 2'b01;
  localparam S0_WAIT = 2'b10;

  reg [1:0] src_cs, src_ns;

  assign sidle = (src_cs == S0_IDLE);

  always @(posedge sclk or negedge rst_n) begin
    if (!rst_n) src_cs <= S0_IDLE;
    else        src_cs <= src_ns;
  end

  always @* begin
    src_ns = src_cs;
    case (src_cs)
      S0_IDLE: src_ns = (sready && ~sreq) ? S0_SEND : S0_IDLE;
      S0_SEND: src_ns = (sreq && sack)    ? S0_WAIT : S0_SEND;
      S0_WAIT: src_ns = (~sreq && ~sack)  ? S0_IDLE : S0_WAIT;
      default: src_ns = S0_IDLE;
    endcase
  end

  always @(posedge sclk or negedge rst_n) begin
    if (!rst_n) begin
      sreq     <= 1'b0;
      src_data <= {WIDTH{1'b0}};
    end else begin
      src_data <= din; 
      case (src_cs)
        S0_IDLE: sreq <= (sready && ~sreq);
        S0_SEND: sreq <= (sreq && ~sack);  
        default: sreq <= sreq;
      endcase
    end
  end

  localparam S1_IDLE = 2'b00;
  localparam S1_SEND = 2'b01;
  localparam S1_OUT  = 2'b10;

  reg [1:0] dst_cs, dst_ns;

  always @(posedge dclk or negedge rst_n) begin
    if (!rst_n) dst_cs <= S1_IDLE;
    else        dst_cs <= dst_ns;
  end

  always @* begin
    dst_ns = dst_cs;
    case (dst_cs)
      S1_IDLE: dst_ns = (~dbusy && dreq)     ? S1_SEND : S1_IDLE;
      S1_SEND: dst_ns = (~dreq && dack)      ? S1_OUT  : S1_SEND;
      S1_OUT : dst_ns = S1_IDLE;
      default: dst_ns = S1_IDLE;
    endcase
  end

  // dack、dst_data
  always @(posedge dclk or negedge rst_n) begin
    if (!rst_n) begin
      dack     <= 1'b0;
      dst_data <= {WIDTH{1'b0}};
    end else begin
      case (dst_cs)
        S1_IDLE: dack <= (~dbusy && dreq);
        S1_SEND: dack <= (~dreq) ? 1'b0 : 1'b1;
        default: dack <= 1'b0;
      endcase

      if (dst_cs==S1_SEND && ~dreq && dack)
        dst_data <= src_data;
    end
  end

  // dvalid / dout：OUT 
  always @(posedge dclk or negedge rst_n) begin
    if (!rst_n) begin
      dvalid <= 1'b0;
      dout   <= {WIDTH{1'b0}};
    end else begin
      dvalid <= (dst_cs == S1_OUT);
      dout   <= (dst_cs == S1_OUT) ? dst_data : {WIDTH{1'b0}};
    end
  end
endmodule
