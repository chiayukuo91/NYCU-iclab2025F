`timescale 1ns/10ps
`default_nettype none

module CONVEX (
    input  wire        rst_n,
    input  wire        clk,
    input  wire        in_valid,
    input  wire [8:0]  pt_num,
    input  wire [9:0]  in_x,
    input  wire [9:0]  in_y,
    output reg         out_valid,
    output reg  [9:0]  out_x,
    output reg  [9:0]  out_y,
    output reg  [6:0]  drop_num
);

reg [2:0] current_state;
reg [2:0] next_state;
localparam WAIT_STATE    = 3'd0;
localparam CONVEX_STATE  = 3'd1;
localparam MOVE_STATE    = 3'd2;
localparam OUTPUT_STATE  = 3'd3;

reg  signed [10:0] coordinates_x [0:127];
reg  signed [10:1] dummy_unused; 
reg  signed [10:0] coordinates_y [0:127];
reg  signed [10:0] temp_x;
reg  signed [10:0] temp_y;
reg         [9:0]  removed_x[0:127];
reg         [9:0]  removed_y[0:127];
reg         [7:0]  point_count;
reg         [7:0]  idx;
reg                finished;
reg         [0:127] left_flag;
reg         [0:127] right_flag;
reg         [0:127] zero_flag;
reg         [7:0]  add_point_idx, subtract_point_idx;
reg                replace_flag;
reg                add_flag;
reg         [7:0]  output_counter;
reg         [2:0]  direction;
reg         [6:0]  temp_discarded_points;
reg                all_valid;
reg         [0:127] point_valid;
reg         [7:0]  move_counter;
reg         [7:0]  shift_idx_3;
reg         [7:0]  shift_idx_1;
reg         [7:0]  shift_idx_2;
reg         [8:0]  refresh_counter;
reg         [8:0]  point_register;

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= WAIT_STATE;
    else
        current_state <= next_state;
end

//------------------------------------------------------------------------------
// Next-state 
//------------------------------------------------------------------------------
always @(*) begin
    case(current_state)
        WAIT_STATE   : next_state = (in_valid) ? CONVEX_STATE : WAIT_STATE;
        CONVEX_STATE : next_state = (idx == point_count + 8'd4) ? MOVE_STATE : CONVEX_STATE;
        MOVE_STATE   : next_state = (move_counter == 8'd128) ? OUTPUT_STATE : MOVE_STATE;
        OUTPUT_STATE : next_state = ((drop_num == 7'd0) || (output_counter == drop_num)) ? WAIT_STATE : OUTPUT_STATE;
        default      : next_state = WAIT_STATE;
    endcase
end

//------------------------------------------------------------------------------
// point_count
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        point_count <= 8'd0;
    end else if (in_valid && (refresh_counter == 9'd501)) begin
        point_count <= 8'd0;
    end else if (current_state == OUTPUT_STATE && next_state == WAIT_STATE) begin
        if (point_count < 3)
            point_count <= point_count + 8'd1;
        else
            point_count <= (replace_flag) ? (point_count - {1'b0,temp_discarded_points} + 8'd1) :
                           (add_flag    ) ? (point_count + 8'd1) : point_count;
    end
end

//------------------------------------------------------------------------------
// direction
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        direction <= 3'd0;
    end else if (in_valid && (refresh_counter == 9'd501)) begin
        direction <= 3'd1;
    end else if (current_state == WAIT_STATE && next_state == CONVEX_STATE && direction < 3'd4) begin
        direction <= direction + 3'd1;
    end
end

//------------------------------------------------------------------------------
// refresh_counter
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        refresh_counter <= 9'd501;
    end else if (current_state == MOVE_STATE && next_state == OUTPUT_STATE) begin
        if (refresh_counter > (9'd502 - point_register))
            refresh_counter <= refresh_counter - 9'd1;
        if (refresh_counter == (9'd502 - point_register))
            refresh_counter <= 9'd501;
    end
end

//------------------------------------------------------------------------------
// point_register
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        point_register <= 9'd0;
    end else if (in_valid && (refresh_counter == 9'd501)) begin
        point_register <= pt_num;
    end
end

//------------------------------------------------------------------------------
// shift index
//------------------------------------------------------------------------------
always @(*) begin
    shift_idx_1 = 8'd0;
    shift_idx_2 = 8'd0;
    shift_idx_3 = 8'd0;

    if (point_count >= 3) begin
        shift_idx_1 = (idx - 8'd1 + point_count) % point_count;
        shift_idx_2 = (idx - 8'd2 + point_count) % point_count;
        shift_idx_3 = (idx - 8'd3 + point_count) % point_count;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 128; i = i + 1) begin
            coordinates_x[i] <= 11'sd0;
            coordinates_y[i] <= 11'sd0;
        end
    end else if (in_valid) begin
        if (refresh_counter == 9'd501) begin
            coordinates_x[0] <= $signed({1'b0,in_x});
            coordinates_y[0] <= $signed({1'b0,in_y});
            for (i = 1; i < 128; i = i + 1) begin
                coordinates_x[i] <= 11'sd0;
                coordinates_y[i] <= 11'sd0;
            end
        end else if (point_count < 2) begin
            coordinates_x[point_count] <= $signed({1'b0,in_x});
            coordinates_y[point_count] <= $signed({1'b0,in_y});
        end
    end else if (next_state == MOVE_STATE) begin
        case(direction)
            3: begin
                if (((coordinates_x[1] - coordinates_x[0]) * (temp_y - coordinates_y[0]) -
                     (coordinates_y[1] - coordinates_y[0]) * (temp_x - coordinates_x[0])) < 0) begin
                    coordinates_x[2] <= temp_x;
                    coordinates_y[2] <= temp_y;
                end else begin
                    if (move_counter == 8'd0) begin
                        coordinates_x[2] <= coordinates_x[1];
                        coordinates_y[2] <= coordinates_y[1];
                    end else if (move_counter == 8'd1) begin
                        coordinates_x[1] <= temp_x;
                        coordinates_y[1] <= temp_y;
                    end
                end
            end
            default: begin
                if (replace_flag) begin
                    if (temp_discarded_points == 7'd1) begin
                        coordinates_x[subtract_point_idx] <= temp_x;
                        coordinates_y[subtract_point_idx] <= temp_y;
                    end else if (temp_discarded_points > 7'd1) begin
                        if (subtract_point_idx >= (temp_discarded_points - 7'd1)) begin
                            if (move_counter == subtract_point_idx) begin
                                coordinates_x[subtract_point_idx - temp_discarded_points + 7'd1] <= temp_x;
                                coordinates_y[subtract_point_idx - temp_discarded_points + 7'd1] <= temp_y;
                            end else if (move_counter > subtract_point_idx && move_counter < point_count) begin
                                coordinates_x[move_counter - temp_discarded_points + 7'd1] <= coordinates_x[move_counter];
                                coordinates_y[move_counter - temp_discarded_points + 7'd1] <= coordinates_y[move_counter];
                            end
                        end else begin
                            if (move_counter == subtract_point_idx) begin
                                coordinates_x[move_counter - subtract_point_idx] <= temp_x;
                                coordinates_y[move_counter - subtract_point_idx] <= temp_y;
                            end else if (move_counter > subtract_point_idx && move_counter < point_count) begin
                                coordinates_x[move_counter - subtract_point_idx] <= coordinates_x[move_counter];
                                coordinates_y[move_counter - subtract_point_idx] <= coordinates_y[move_counter];
                            end
                        end
                    end
                end else if (add_flag) begin
                    if (move_counter < (point_count - add_point_idx)) begin
                        coordinates_x[point_count - move_counter] <= coordinates_x[point_count - move_counter - 8'd1];
                        coordinates_y[point_count - move_counter] <= coordinates_y[point_count - move_counter - 8'd1];
                    end else if (move_counter == (point_count - add_point_idx)) begin
                        coordinates_x[add_point_idx] <= temp_x;
                        coordinates_y[add_point_idx] <= temp_y;
                    end
                end
            end
        endcase
    end
end

//------------------------------------------------------------------------------
// move_counter
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        move_counter <= 8'd0;
    else
        move_counter <= (next_state == MOVE_STATE) ? (move_counter + 8'd1) : 8'd0;
end

//------------------------------------------------------------------------------
// out_valid
//------------------------------------------------------------------------------
always @(*) begin
    out_valid = (current_state == OUTPUT_STATE);
end

//------------------------------------------------------------------------------
// temp_discarded_points
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        temp_discarded_points <= 7'd0;
    end else if (current_state == CONVEX_STATE) begin
        if (idx <= point_count + 8'd1) begin
            if ((left_flag[shift_idx_2] && left_flag[shift_idx_1]) ||
                (left_flag[shift_idx_1] && zero_flag[shift_idx_2]) ||
                (left_flag[shift_idx_2] && zero_flag[shift_idx_1]) ||
                (zero_flag[shift_idx_2] && right_flag[shift_idx_1] && right_flag[shift_idx_3]) ||
                (zero_flag[shift_idx_2] && zero_flag[shift_idx_1])) begin
                temp_discarded_points <= temp_discarded_points + 7'd1;
            end else if (idx == point_count && all_valid && (add_flag == 1'b0)) begin
                temp_discarded_points <= temp_discarded_points + 7'd1;
            end
        end else if (idx == point_count + 8'd2) begin
            if (zero_flag[shift_idx_2] && right_flag[shift_idx_1] && right_flag[shift_idx_3]) begin
                temp_discarded_points <= temp_discarded_points + 7'd1;
            end
        end
    end else if (current_state == WAIT_STATE) begin
        temp_discarded_points <= 7'd0;
    end
end

//------------------------------------------------------------------------------
// drop_num
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        drop_num <= 7'd0;
    end else if (next_state == OUTPUT_STATE) begin
        drop_num <= (direction < 3'd4) ? 7'd0 : temp_discarded_points;
    end else begin
        drop_num <= 7'd0;
    end
end

//------------------------------------------------------------------------------
// out_x/out_y
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_x <= 10'd0;
        out_y <= 10'd0;
    end else if (next_state == OUTPUT_STATE) begin
        out_x <= removed_x[output_counter];
        out_y <= removed_y[output_counter];
    end else if (next_state == WAIT_STATE) begin
        out_x <= 10'd0;
        out_y <= 10'd0;
    end
end

//------------------------------------------------------------------------------
// temp_x/temp_y
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        temp_x <= 11'sd0;
        temp_y <= 11'sd0;
    end else if (in_valid && point_count >= 2) begin
        temp_x <= $signed({1'b0,in_x});
        temp_y <= $signed({1'b0,in_y});
    end
end

//------------------------------------------------------------------------------
// idx
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        idx <= 8'd0;
    end else begin
        idx <= (current_state == CONVEX_STATE) ? (idx + 8'd1) : 8'd0;
    end
end

//------------------------------------------------------------------------------
// flag（left/right/zero）
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 128; i = i + 1) begin
            left_flag[i]  <= 1'b0;
            right_flag[i] <= 1'b0;
            zero_flag[i]  <= 1'b0;
        end
    end else if (current_state == CONVEX_STATE) begin
        if (point_count > 2) begin
            if (idx < point_count - 1)
                compute_flag(idx, idx + 8'd1);
            else if (idx == (point_count - 1))
                compute_flag(idx, 8'd0);
        end
    end else if (current_state == WAIT_STATE) begin
        for (i = 0; i < 128; i = i + 1) begin
            left_flag[i]  <= 1'b0;
            right_flag[i] <= 1'b0;
            zero_flag[i]  <= 1'b0;
        end
    end
end

task automatic compute_flag(input [7:0] idx1, input [7:0] idx2);
    integer diff_x, diff_y;
    integer cros;
begin
    diff_x = coordinates_x[idx2] - coordinates_x[idx1];
    diff_y = coordinates_y[idx2] - coordinates_y[idx1];
    cros   = diff_x * (temp_y - coordinates_y[idx1]) - diff_y * (temp_x - coordinates_x[idx1]);

    if (cros > 0) begin
        left_flag[idx1]  <= 1'b1;
        right_flag[idx1] <= 1'b0;
        zero_flag[idx1]  <= 1'b0;
    end else if (cros < 0) begin
        left_flag[idx1]  <= 1'b0;
        right_flag[idx1] <= 1'b1;
        zero_flag[idx1]  <= 1'b0;
    end else begin
        left_flag[idx1]  <= 1'b0;
        right_flag[idx1] <= 1'b0;
        zero_flag[idx1]  <= 1'b1;
    end
end
endtask

//------------------------------------------------------------------------------
// add/subtract index
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        add_point_idx      <= 8'd0;
        subtract_point_idx <= 8'd0;
    end else if (current_state == CONVEX_STATE) begin
        if (idx <= point_count + 8'd1) begin
            if ((left_flag[shift_idx_2] && left_flag[shift_idx_1]) ||
                (left_flag[shift_idx_1] && zero_flag[shift_idx_2]) ||
                (left_flag[shift_idx_2] && zero_flag[shift_idx_1])) begin
                update_subtract_point_idx(shift_idx_1);
            end else if (right_flag[shift_idx_1] && left_flag[shift_idx_2] && (replace_flag == 1'b0)) begin
                add_point_idx <= shift_idx_1;
            end
        end
    end else if (current_state == WAIT_STATE) begin
        add_point_idx      <= 8'd0;
        subtract_point_idx <= 8'd0;
    end
end

task automatic update_subtract_point_idx(input [7:0] idx1);
begin
    if (subtract_point_idx == 8'd0) begin
        subtract_point_idx <= idx1;
    end else if ((idx1 == subtract_point_idx + 8'd1) ||
                 (subtract_point_idx == (point_count - 8'd1) && idx1 == 8'd0)) begin
        subtract_point_idx <= idx1;
    end
end
endtask

//------------------------------------------------------------------------------
// replace_flag
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        replace_flag <= 1'b0;
    end else if (current_state == CONVEX_STATE && idx <= point_count + 8'd1) begin
        if ((left_flag[shift_idx_2] && left_flag[shift_idx_1]) ||
            (left_flag[shift_idx_1] && zero_flag[shift_idx_2]) ||
            (left_flag[shift_idx_2] && zero_flag[shift_idx_1])) begin
            replace_flag <= 1'b1;
        end
    end else if (current_state == WAIT_STATE) begin
        replace_flag <= 1'b0;
    end
end

//------------------------------------------------------------------------------
// add_flag
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        add_flag <= 1'b0;
    end else if (current_state == CONVEX_STATE) begin
        if (idx <= point_count + 8'd1) begin
            if (right_flag[shift_idx_1] && left_flag[shift_idx_2] && (replace_flag == 1'b0)) begin
                add_flag <= 1'b1;
            end
        end
    end else if (current_state == WAIT_STATE) begin
        add_flag <= 1'b0;
    end
end

//------------------------------------------------------------------------------
// removed_x/removed_y
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 128; i = i + 1) begin
            removed_x[i] <= 10'd0;
            removed_y[i] <= 10'd0;
        end
    end else if (current_state == CONVEX_STATE) begin
        if (direction < 3'd4) begin
            for (i = 0; i < 128; i = i + 1) begin
                removed_x[i] <= 10'd0;
                removed_y[i] <= 10'd0;
            end
        end else begin
            if (idx <= point_count + 8'd1) begin
                if (left_flag[shift_idx_1] && left_flag[shift_idx_2]) begin
                    removed_x[temp_discarded_points] <= $unsigned(coordinates_x[shift_idx_1][9:0]);
                    removed_y[temp_discarded_points] <= $unsigned(coordinates_y[shift_idx_1][9:0]);
                end else if (left_flag[shift_idx_1] && zero_flag[shift_idx_2]) begin
                    removed_x[temp_discarded_points] <= $unsigned(coordinates_x[shift_idx_1][9:0]);
                    removed_y[temp_discarded_points] <= $unsigned(coordinates_y[shift_idx_1][9:0]);
                end else if (left_flag[shift_idx_2] && zero_flag[shift_idx_1]) begin
                    removed_x[temp_discarded_points] <= $unsigned(coordinates_x[shift_idx_1][9:0]);
                    removed_y[temp_discarded_points] <= $unsigned(coordinates_y[shift_idx_1][9:0]);
                end else if (zero_flag[shift_idx_2] && right_flag[shift_idx_1] && right_flag[shift_idx_3]) begin
                    removed_x[temp_discarded_points] <= $unsigned(temp_x[9:0]);
                    removed_y[temp_discarded_points] <= $unsigned(temp_y[9:0]);
                end else if (zero_flag[shift_idx_2] && zero_flag[shift_idx_1]) begin
                    removed_x[temp_discarded_points] <= $unsigned(temp_x[9:0]);
                    removed_y[temp_discarded_points] <= $unsigned(temp_y[9:0]);
                end else if (idx == point_count) begin
                    if (all_valid && (temp_discarded_points == 7'd0) && (add_flag == 1'b0)) begin
                        removed_x[temp_discarded_points] <= $unsigned(temp_x[9:0]);
                        removed_y[temp_discarded_points] <= $unsigned(temp_y[9:0]);
                    end
                end
            end else if (idx == point_count + 8'd2) begin
                if (zero_flag[shift_idx_2] && right_flag[shift_idx_1] && right_flag[shift_idx_3]) begin
                    removed_x[temp_discarded_points] <= $unsigned(temp_x[9:0]);
                    removed_y[temp_discarded_points] <= $unsigned(temp_y[9:0]);
                end
            end
        end
    end else if (current_state == WAIT_STATE) begin
        for (i = 0; i < 128; i = i + 1) begin
            removed_x[i] <= 10'd0;
            removed_y[i] <= 10'd0;
        end
    end
end

//------------------------------------------------------------------------------
// point_valid
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 128; i = i + 1) begin
            point_valid[i] <= 1'b1;
        end
    end else if (current_state == CONVEX_STATE) begin
        if (idx <= point_count + 8'd1) begin
            if (should_invalidate_point(shift_idx_1, shift_idx_2))
                point_valid[shift_idx_1] <= 1'b0;
        end
    end else if (current_state == WAIT_STATE) begin
        for (i = 0; i < 128; i = i + 1) begin
            point_valid[i] <= 1'b1;
        end
    end
end

function automatic should_invalidate_point;
    input [7:0] idx1;
    input [7:0] idx2;
begin
    should_invalidate_point =
          (left_flag[idx1] && left_flag[idx2])
       || (left_flag[idx1] && zero_flag[idx2])
       || (left_flag[idx2] && zero_flag[idx1]);
end
endfunction

//------------------------------------------------------------------------------
// all_valid
//------------------------------------------------------------------------------
always @(*) begin
    all_valid = (point_count >= 3) && (current_state == CONVEX_STATE) && (idx >= point_count);
    if (all_valid) begin
        for (i = 0; i < point_count; i = i + 1) begin
            if (right_flag[i] == 1'b0) begin
                all_valid = 1'b0;
                break;
            end
        end
    end
end

//------------------------------------------------------------------------------
// output_counter
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_counter <= 8'd0;
    end else if (current_state == WAIT_STATE) begin
        output_counter <= 8'd0;
    end else if (next_state == OUTPUT_STATE) begin
        output_counter <= output_counter + 8'd1;
    end
end

endmodule

`default_nettype wire
