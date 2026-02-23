`include "Usertype.sv"

module Checker (input clk, INF.CHECKER inf);
    import usertype::*;

    //============================================================
    //  Record latest Type / Mode / Action for coverage & assertion
    //============================================================
    Action        act_q;
    Training_Type type_q;
    Mode          mode_q;

    always_ff @(posedge clk or negedge inf.rst_n) begin
        if (!inf.rst_n) begin
            act_q  <= Login;
            type_q <= Type_A;
            mode_q <= Easy;
        end
        else begin
            if (inf.sel_action_valid) act_q  <= inf.D.d_act[0];
            if (inf.type_valid)       type_q <= inf.D.d_type[0];
            if (inf.mode_valid)       mode_q <= inf.D.d_mode[0];
        end
    end

    //============================================================
    //  Coverage
    //============================================================

    // 1. Each case of Training_Type >= 200 hits
    covergroup cg_type @(posedge clk iff inf.type_valid);
        option.per_instance = 1;
        option.at_least     = 200;

        cp_type : coverpoint inf.D.d_type[0] {
            bins TYPE_A = {Type_A};
            bins TYPE_B = {Type_B};
            bins TYPE_C = {Type_C};
            bins TYPE_D = {Type_D};
        }
    endgroup
    cg_type cov_type = new();

    // 2. Each case of Mode >= 200 hits
    covergroup cg_mode @(posedge clk iff (inf.mode_valid));
        option.per_instance = 1;
        option.at_least     = 200;

        cp_mode : coverpoint inf.D.d_mode[0] {
            bins EASY   = {Easy};
            bins NORMAL = {Normal};
            bins HARD   = {Hard};
        }
    endgroup
    cg_mode cov_mode = new();

    // 3. Cross (Training_Type x Mode) for Level_Up, each >= 200 hits
    covergroup cg_type_mode @(
		posedge clk iff (inf.player_no_valid && act_q == Level_Up)
	);
		option.per_instance = 1;
		option.at_least     = 200;

		// Use the latched values, ensuring Type/Mode are stable
		cp_t : coverpoint type_q;
		cp_m : coverpoint mode_q;

		// Cross coverage for (Type × Mode)
		type_mode_cross : cross cp_t, cp_m;
	endgroup

	cg_type_mode cov_type_mode = new();

    // 4. player_no with auto_bin_max = 256, each bin >= 2 hits
    //    （Sample when player_no_valid = 1）
    covergroup spec4 @(posedge clk iff inf.player_no_valid);
        option.per_instance = 1;
        option.at_least     = 2;

        cp_player_id : coverpoint inf.D.d_player_no[0] {
            option.auto_bin_max = 256;
        }
    endgroup
    spec4 cg_4 = new();

    // 5. Transition bins for action from [Login:Check_Inactive] → [Login:Check_Inactive]
    //    each transition >= 200 hits
    covergroup spec5 @(posedge clk iff inf.sel_action_valid);
        option.per_instance = 1;
        option.at_least     = 200;

        cp_action_trans : coverpoint inf.D.d_act[0] {
            bins act_flow[] =
                ([Login       : Check_Inactive] =>
                 [Login       : Check_Inactive]);
        }
    endgroup
    spec5 cg_5 = new();

    // 6. MP consumed by Use_Skill, auto_bin_max=32, each bin >= 1 hit
    covergroup CG_MP_USAGE @(posedge clk iff (act_q == Use_Skill && inf.MP_valid));
        option.per_instance = 1;
        option.at_least     = 1;

        // MP consumed value distribution
        cp_mp_cost : coverpoint inf.D.d_attribute[0] {
            option.auto_bin_max = 32;
        }
    endgroup
    CG_MP_USAGE cv_mp_usage = new();

    // 7. Warn_Msg distribution, each kind >= 20 hits
    covergroup spec7 @(posedge clk iff inf.out_valid);
        option.per_instance = 1;
        option.at_least     = 20;

        cp_warn_msg : coverpoint inf.warn_msg {
            bins warn_kinds[] = {
                No_Warn,
                Date_Warn,
                Exp_Warn,
                HP_Warn,
                MP_Warn,
                Saturation_Warn
            };
        }
    endgroup
    spec7 cg_7 = new();

    //============================================================
    //  Assertions
    //============================================================

    // -----------------------------------------------------------
    // Assertion 1: All outputs should be zero right after reset
    // -----------------------------------------------------------
    always @(negedge inf.rst_n) begin
        #2;
        if ( (inf.out_valid !== 1'b0)   ||
             (inf.warn_msg  !== No_Warn)||
             (inf.complete  !== 1'b0)   ||
             (inf.AR_VALID  !== 1'b0)   ||
             (inf.AR_ADDR   !== '0)     ||
             (inf.R_READY   !== 1'b0)   ||
             (inf.AW_VALID  !== 1'b0)   ||
             (inf.AW_ADDR   !== '0)     ||
             (inf.W_VALID   !== 1'b0)   ||
             (inf.W_DATA    !== '0)     ||
             (inf.B_READY   !== 1'b0) ) begin
            $display("===================================================");
            $display("              Assertion 1 is violated              ");
            $display("===================================================");
            $fatal;
        end
    end

    // -----------------------------------------------------------
    // Assertion 2: Latency of each operation < 1000 cycles
    // -----------------------------------------------------------
    property p_latency_login;
        @(posedge clk)
            (act_q == Login       && inf.player_no_valid) |-> ##[1:1000] inf.out_valid;
    endproperty

    property p_latency_lvup;
        @(posedge clk)
            (act_q == Level_Up    && inf.player_no_valid) |-> ##[1:1000] inf.out_valid;
    endproperty

    property p_latency_battle;
        @(posedge clk)
            (act_q == Battle      && inf.monster_valid)   |-> ##[1:1000] inf.out_valid;
    endproperty

    property p_latency_skill;
        @(posedge clk)
            (act_q == Use_Skill   && inf.MP_valid)        |-> ##[1:1000] inf.out_valid;
    endproperty

    property p_latency_inactive;
        @(posedge clk)
            (act_q == Check_Inactive && inf.player_no_valid) |-> ##[1:1000] inf.out_valid;
    endproperty

    ASSERT_2_LOGIN:    assert property (p_latency_login)
    else begin
        $display("===================================================");
        $display("              Assertion 2 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_2_LVUP:     assert property (p_latency_lvup)
    else begin
        $display("===================================================");
        $display("              Assertion 2 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_2_BATTLE:   assert property (p_latency_battle)
    else begin
        $display("===================================================");
        $display("              Assertion 2 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_2_SKILL:    assert property (p_latency_skill)
    else begin
        $display("===================================================");
        $display("              Assertion 2 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_2_INACTIVE: assert property (p_latency_inactive)
    else begin
        $display("===================================================");
        $display("              Assertion 2 is violated              ");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 3: complete=1 ⇒ warn_msg must be No_Warn
    // -----------------------------------------------------------
    property p_complete_must_be_no_warn;
        @(negedge clk)
            inf.complete |-> (inf.warn_msg == No_Warn);
    endproperty

    ASSERT_3: assert property (p_complete_must_be_no_warn)
    else begin
        $display("===================================================");
        $display("              Assertion 3 is violated              ");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 4: Input sequence timing (1~4 cycles gap)
    // -----------------------------------------------------------
    property p_sel_to_first_input;
        @(posedge clk)
            inf.sel_action_valid
            |-> ##[1:4] (inf.player_no_valid || inf.date_valid || inf.type_valid);
    endproperty

    ASSERT_4_SEL: assert property (p_sel_to_first_input)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  SEL         ");
        $display("===================================================");
        $fatal;
    end

    // LOGIN flow: date_valid →(1~4 cycles)→ player_no_valid
    property p_login_flow;
        @(posedge clk)
            (inf.date_valid && act_q == Login)
            |-> ##[1:4] inf.player_no_valid;
    endproperty

    ASSERT_4_LOGIN: assert property (p_login_flow)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  LOGIN       ");
        $display("===================================================");
        $fatal;
    end

    // LVUP flow: type_valid → mode_valid → player_no_valid
    property p_lvup_type_to_mode;
        @(posedge clk)
            inf.type_valid |-> ##[1:4] inf.mode_valid;
    endproperty

    property p_lvup_mode_to_player;
        @(posedge clk)
            inf.mode_valid |-> ##[1:4] inf.player_no_valid;
    endproperty

    ASSERT_4_LVUP_1: assert property (p_lvup_type_to_mode)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  LVUP        ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_4_LVUP_2: assert property (p_lvup_mode_to_player)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  LVUP        ");
        $display("===================================================");
        $fatal;
    end

    // BATTLE flow: 3 monsters within gaps of 1~4 cycles
    property p_battle_flow;
        @(posedge clk)
            (inf.player_no_valid && act_q == Battle)
            |-> ##[1:4] inf.monster_valid
                ##[1:4] inf.monster_valid
                ##[1:4] inf.monster_valid;
    endproperty

    ASSERT_4_BATTLE_1: assert property (p_battle_flow)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  BATTLE      ");
        $display("===================================================");
        $fatal;
    end

    // USE SKILL flow: 4 MP_valid within 1~4 cycles each
    property p_skill_flow;
        @(posedge clk)
            (inf.player_no_valid && act_q == Use_Skill)
            |-> ##[1:4] inf.MP_valid
                ##[1:4] inf.MP_valid
                ##[1:4] inf.MP_valid
                ##[1:4] inf.MP_valid;
    endproperty

    ASSERT_4_SKILL_1: assert property (p_skill_flow)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  SKILL       ");
        $display("===================================================");
        $fatal;
    end

    // Check_Inactive flow: date_valid → player_no_valid
    property p_inactive_flow;
        @(posedge clk)
            (inf.date_valid && act_q == Check_Inactive)
            |-> ##[1:4] inf.player_no_valid;
    endproperty

    ASSERT_4_INACT: assert property (p_inactive_flow)
    else begin
        $display("===================================================");
        $display("              Assertion 4 is violated  Check_Inactive");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 5: All input valid signals won't overlap
    // -----------------------------------------------------------
    property p_onehot_valid;
        @(posedge clk)
            // Count number of 1s = 1 OR all zero
            ((inf.sel_action_valid +
              inf.type_valid +
              inf.mode_valid +
              inf.date_valid +
              inf.player_no_valid +
              inf.monster_valid +
              inf.MP_valid) == 1)
            ||
            ((inf.sel_action_valid +
              inf.type_valid +
              inf.mode_valid +
              inf.date_valid +
              inf.player_no_valid +
              inf.monster_valid +
              inf.MP_valid) == 0);
    endproperty

    ASSERT_5: assert property (p_onehot_valid)
    else begin
        $display("===================================================");
        $display("              Assertion 5 is violated              ");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 6: out_valid can only be high for exactly 1 cycle
    // -----------------------------------------------------------
    property p_out_one_cycle;
        @(posedge clk) inf.out_valid |=> !inf.out_valid;
    endproperty

    ASSERT_6: assert property (p_out_one_cycle)
    else begin
        $display("===================================================");
        $display("              Assertion 6 is violated              ");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 7: Next operation 1–4 cycles after out_valid falls
    // -----------------------------------------------------------
    property p_next_op_after_out;
        @(posedge clk)
            inf.out_valid |-> ##[1:4] inf.sel_action_valid;
    endproperty

    ASSERT_7: assert property (p_next_op_after_out)
    else begin
        $display("===================================================");
        $display("              Assertion 7 is violated              ");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 8: Date must be legal calendar date
    // -----------------------------------------------------------
    property p_date_month_range;
        @(posedge clk)
            inf.date_valid |-> (inf.D.d_date[0].M inside {[1:12]});
    endproperty

    // 31-day months: 1,3,5,7,8,10,12
    property p_date_day_31;
        @(posedge clk)
            (inf.date_valid &&
             (inf.D.d_date[0].M inside {1,3,5,7,8,10,12}))
            |-> (inf.D.d_date[0].D inside {[1:31]});
    endproperty

    // 30-day months: 4,6,9,11
    property p_date_day_30;
        @(posedge clk)
            (inf.date_valid &&
             (inf.D.d_date[0].M inside {4,6,9,11}))
            |-> (inf.D.d_date[0].D inside {[1:30]});
    endproperty

    // February: 1~28
    property p_date_day_feb;
        @(posedge clk)
            (inf.date_valid &&
             (inf.D.d_date[0].M == 2))
            |-> (inf.D.d_date[0].D inside {[1:28]});
    endproperty

    ASSERT_8_1: assert property (p_date_month_range)
    else begin
        $display("===================================================");
        $display("              Assertion 8 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_8_2: assert property (p_date_day_31)
    else begin
        $display("===================================================");
        $display("              Assertion 8 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_8_3: assert property (p_date_day_30)
    else begin
        $display("===================================================");
        $display("              Assertion 8 is violated              ");
        $display("===================================================");
        $fatal;
    end

    ASSERT_8_4: assert property (p_date_day_feb)
    else begin
        $display("===================================================");
        $display("              Assertion 8 is violated              ");
        $display("===================================================");
        $fatal;
    end

    // -----------------------------------------------------------
    // Assertion 9: AR_VALID and AW_VALID must not overlap
    // -----------------------------------------------------------
    property p_read_write_exclusive;
        @(posedge clk) !(inf.AR_VALID && inf.AW_VALID);
    endproperty

    ASSERT_9: assert property (p_read_write_exclusive)
    else begin
        $display("===================================================");
        $display("              Assertion 9 is violated              ");
        $display("===================================================");
        $fatal;
    end

endmodule
