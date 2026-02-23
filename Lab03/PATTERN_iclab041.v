`ifdef RTL
  `define CYCLE_TIME 40.0
`endif
`ifdef GATE
  `define CYCLE_TIME 40.0
`endif

module PATTERN(
  rst_n,
  clk,
  in_valid,
  pt_num,
  in_x,
  in_y,
  out_valid,
  out_x,
  out_y,
  drop_num
);

output reg rst_n;
output reg clk;
output reg in_valid;
output reg [8:0] pt_num;
output reg [9:0] in_x;
output reg [9:0] in_y;

input out_valid;
input [9:0] out_x;
input [9:0] out_y;
input [6:0] drop_num;

real CYCLE = `CYCLE_TIME;
parameter LIM = 1000;

integer fin;
integer patt_cnt, point_cnt;
integer t_sum, t_step;
integer p_idx, q_idx;
integer code_r;

integer hull_n;
integer ix, iy;
integer vx [0:127];
integer vy [0:127];

integer produced_now;
integer drops_seen;

reg hit_span;
reg on_edge;
reg first_two;
reg dup_v;
reg gap_seen;
reg wrapped;
integer span_sz;
integer ins_pos;
integer erase_k;

initial clk = 0;
always #(CYCLE/2.0) clk = ~clk;

initial begin
  fin = $fopen("../00_TESTBED/input.txt","r");
  if(!fin) begin
    $display("Pattern cannot open input file.");
    $finish;
  end
  do_init;
  t_sum = 0;
  code_r = $fscanf(fin,"%d",patt_cnt);
  for(p_idx=1; p_idx<=patt_cnt; p_idx=p_idx+1) begin
    hull_n = 0;
    for(q_idx=0;q_idx<128;q_idx=q_idx+1) begin
      vx[q_idx]=0; vy[q_idx]=0;
    end
    code_r = $fscanf(fin,"%d",point_cnt);
    for(q_idx=1; q_idx<=point_cnt; q_idx=q_idx+1) begin
      drive_one;
      wait_valid;
      pre_eval;
      produced_now = 0;
      verify_and_commit;
      t_sum = t_sum + t_step;
    end
  end
  $fclose(fin);
  done_msg;
  $finish;
end

task do_init; begin
  force clk = 0;
  rst_n = 1'b1;
  in_valid = 1'b0;
  pt_num = 'dx;
  in_x = 'dx;
  in_y = 'dx;
  #(CYCLE/2.0) rst_n = 1'b0;
  #(CYCLE/2.0) rst_n = 1'b1;
  #(10);
  if(out_valid!==0 || drop_num!==0 || out_x!==0 || out_y!==0) begin
    $display("                     SPEC-4 FAIL                       ");
    $display("    Output signal should be 0 at %-12d ps", $time*1000);
    $finish;
  end
  #(CYCLE/2.0) release clk;
end endtask

always @(*) begin
  if(out_valid===1'b1 && in_valid===1'b1) begin
    $display("                     SPEC-6 FAIL                       ");
    $finish;
  end
end

always begin
  if(out_valid===1'b0 && (drop_num!==0 || out_x!==0 || out_y!==0)) begin
    $display("                     SPEC-5 FAIL                       ");
    $finish;
  end else @(negedge clk);
end

always begin
  if(drop_num===0 && (out_x!==0 || out_y!==0)) begin
    $display("                     SPEC-5 FAIL                       ");
    $finish;
  end else @(negedge clk);
end

task drive_one; begin
  code_r = $fscanf(fin,"%d %d",ix,iy);
  in_valid = 1'b1;
  pt_num = (q_idx==1)? point_cnt : 'dx;
  in_x = ix;
  in_y = iy;
  @(negedge clk);
  in_valid = 1'b0;
  in_x = 'bx;
  in_y = 'bx;
end endtask

task wait_valid; begin
  t_step = -1;
  while(out_valid!==1) begin
    if(t_step==LIM) begin
      $display("                     SPEC-7 FAIL                       ");
      $finish;
    end
    t_step = t_step + 1;
    @(negedge clk);
  end
end endtask

function is_nl;
  input [9:0] PX, PY;
  input [9:0] AX, AY;
  input [9:0] BX, BY;
  integer dx1,dy1,dx2,dy2;
begin
  dx1 = BX-AX; dy1 = PY-AY; dx2 = PX-AX; dy2 = BY-AY;
  is_nl = (dx1*dy1) <= (dx2*dy2);
end
endfunction

function is_cl;
  input [9:0] PX, PY;
  input [9:0] AX, AY;
  input [9:0] BX, BY;
  integer dx1,dy1,dx2,dy2;
begin
  dx1 = BX-AX; dy1 = PY-AY; dx2 = PX-AX; dy2 = BY-AY;
  is_cl = (dx1*dy1) == (dx2*dy2);
end
endfunction

task pre_eval; integer t; begin
  hit_span = 0;
  on_edge = 0;
  first_two = 0;
  dup_v = 0;
  gap_seen = 0;
  wrapped = 0;
  span_sz = 0;
  ins_pos = 0;
  erase_k = 0;

  if(hull_n<=1) begin
    vx[hull_n]=ix; vy[hull_n]=iy; hull_n=hull_n+1; first_two=1;
  end else if(hull_n==2) begin
    if(is_nl(ix,iy,vx[0],vy[0],vx[1],vy[1])) begin
      vx[2]=vx[1]; vy[2]=vy[1]; vx[1]=ix; vy[1]=iy;
    end else begin
      vx[2]=ix; vy[2]=iy;
    end
    hull_n = 3; first_two=1;
  end else begin
    for(t=0;t<hull_n;t=t+1) if(ix==vx[t] && iy==vy[t]) dup_v=1;
    for(t=0;t<hull_n;t=t+1) begin
      if(is_nl(ix,iy,vx[t],vy[t],vx[(t+1)%hull_n],vy[(t+1)%hull_n])) begin
        if(!hit_span) begin
          if(is_cl(ix,iy,vx[t],vy[t],vx[(t+1)%hull_n],vy[(t+1)%hull_n])) on_edge=1;
          hit_span = 1;
          span_sz = span_sz + 1;
          ins_pos = t + 1;
        end else begin
          span_sz = span_sz + 1;
          erase_k = erase_k + 1;
          if(gap_seen && !wrapped) begin
            ins_pos = t + 1;
            wrapped = 1;
          end
        end
      end else if(hit_span) begin
        gap_seen = 1;
      end
    end
  end
end endtask

task verify_and_commit; integer a,b; begin
  while(out_valid) begin
    drops_seen = drop_num;
    if(drop_num===0 && (out_x!==0 || out_y!==0)) begin
      $display("                     SPEC-5 FAIL                       ");
      $finish;
    end
    if(in_valid===1) begin
      $display("                     SPEC-6 FAIL                       ");
      $finish;
    end
    if(first_two) begin
      if(out_x!==0 || out_y!==0) begin
        $display("                     SPEC-8 FAIL                       ");
        $finish;
      end
    end else if(dup_v) begin
      if(out_x!==ix || out_y!==iy) begin
        $display("                     SPEC-8 FAIL                       ");
        $finish;
      end
    end else if(!hit_span) begin
      if(out_x!==ix || out_y!==iy) begin
        $display("                     SPEC-8 FAIL                       ");
        $finish;
      end
    end else begin
      if(span_sz==1) begin
        if(on_edge) begin
          if(out_x!==ix || out_y!==iy) begin
            $display("                     SPEC-8 FAIL                       ");
            $finish;
          end
        end else begin
          if(out_x!==0 || out_y!==0) begin
            $display("                     SPEC-8 FAIL                       ");
            $finish;
          end
          for(a=hull_n-erase_k; a>ins_pos; a=a-1) begin
            vx[a]=vx[a-1]; vy[a]=vy[a-1];
          end
          vx[ins_pos]=ix; vy[ins_pos]=iy;
          hull_n = hull_n - erase_k + 1;
        end
      end else if(span_sz==2) begin
        if(out_x!==vx[(ins_pos)%hull_n] || out_y!==vy[(ins_pos)%hull_n]) begin
          $display("                     SPEC-8 FAIL                       ");
          $finish;
        end
        vx[(ins_pos)%hull_n]=ix; vy[(ins_pos)%hull_n]=iy;
        hull_n = hull_n - erase_k + 1;
      end else begin
        for(a=ins_pos; a<=ins_pos+span_sz-2; a=a+1) begin
          if(out_x===vx[(a)%hull_n] && out_y===vy[(a)%hull_n]) begin
            vx[(a)%hull_n]=0; vy[(a)%hull_n]=0;
            break;
          end else if((a==ins_pos+span_sz-2) && (out_x!==vx[(a)%hull_n] || out_y!==vy[(a)%hull_n])) begin
            for(b=ins_pos; b<=ins_pos+span_sz-2; b=b+1) begin
              if(vx[(b)%hull_n]!==0 || vy[(b)%hull_n]!==0) begin
                $display("                     SPEC-8 FAIL                       ");
                $finish;
              end
            end
          end
        end
      end
    end
    @(negedge clk);
    produced_now = produced_now + 1;
  end

  if(produced_now < drops_seen && drops_seen>=2) begin
    $display("                     SPEC-9 FAIL                       ");
    $finish;
  end

  if(span_sz>=3 && hit_span && !first_two && !dup_v) begin
    if(wrapped) begin
      for(a=0; a<hull_n-erase_k+1; a=a+1) begin
        vx[a]=vx[a+span_sz-2]; vy[a]=vy[a+span_sz-2];
      end
      vx[hull_n-erase_k]=ix; vy[hull_n-erase_k]=iy;
    end else begin
      for(a=ins_pos; a<hull_n-erase_k+1; a=a+1) begin
        vx[a]=vx[a+span_sz-2]; vy[a]=vy[a+span_sz-2];
      end
      vx[ins_pos]=ix; vy[ins_pos]=iy;
    end
    hull_n = hull_n - erase_k + 1;
  end
end endtask

task done_msg; begin
  $display("**********************************************************");
  $display("*                 Congratulations!                       *");
  $display("*           execution cycles = %7d                       *", t_sum);
  $display("*           clock period = %4f ns                        *", CYCLE);
  $display("*           Total Latency = %.1f ns                      *", t_sum*CYCLE);
  $display("**********************************************************");
end endtask

endmodule
