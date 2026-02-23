`timescale 1ns/1ps
`include "Usertype.sv"

module RPG (
    input  clk,
    INF.RPG_inf inf
);
    import usertype::*;

    typedef enum logic [4:0] {
        S_IDLE,
        S_COLLECT,
        S_AR,
        S_WAIT_R,
        S_COMPUTE,
        S_LOGIN_APPLY,
        S_LVUP_PREP,
        S_LVUP_B1,
        S_LVUP_TB,
        S_LVUP_MODE,
        S_LVUP_APPLY,
        S_SKILL_PREP,
        S_SKILL_COST,
        S_SKILL_ACC,
        S_SKILL_APPLY,
        S_BATTLE_CALC,
        S_BATTLE_PIPE,
        S_BATTLE_APPLY,
        S_DECIDE,
        S_AW_W,
        S_WAIT_B,
        S_OUT
    } state_t;

    state_t state, next_state;

    Action          act_reg,        act_reg_n;
    Training_Type   type_reg,       type_reg_n;
    Mode            mode_reg,       mode_reg_n;
    Date            today_reg,      today_reg_n;
    Player_No       player_no_reg,  player_no_reg_n;
    Monster_Info    monster_reg,    monster_reg_n;

    Attribute       skill_mp   [0:3], skill_mp_n   [0:3];
    Attribute       skill_s    [0:3], skill_s_n    [0:3];
    Attribute       skill_m    [0:3], skill_m_n    [0:3];
    Attribute       skill_sort1[0:3], skill_sort1_n[0:3];

    logic [1:0] monster_cnt, monster_cnt_n;
    logic [1:0] mp_cnt,      mp_cnt_n;
    logic got_act,          got_act_n;
    logic got_type,         got_type_n;
    logic got_mode,         got_mode_n;
    logic got_date,         got_date_n;
    logic got_player,       got_player_n;
    logic got_monster_all,  got_monster_all_n;
    logic got_mp_all,       got_mp_all_n;

    Player_DRAM player_reg,    player_reg_n;

    logic [17:0] d_hp,  d_hp_n;
    logic [17:0] d_mp,  d_mp_n;
    logic [17:0] d_atk, d_atk_n;
    logic [17:0] d_def, d_def_n;
    logic [17:0] f_hp,  f_hp_n;
    logic [17:0] f_mp,  f_mp_n;
    logic [17:0] f_atk, f_atk_n;
    logic [17:0] f_def, f_def_n;

    Attribute   lvA0, lvA0_n;
    Attribute   lvA1, lvA1_n;
    Attribute   lvA2, lvA2_n;
    Attribute   lvA3, lvA3_n;

    Attribute   lvB0, lvB0_n;
    Attribute   lvB1, lvB1_n;
    Attribute   lvB2, lvB2_n;
    Attribute   lvB3, lvB3_n;

    Attribute cost0, cost1, cost2, cost3;
    logic [16:0] sum1, sum2;
    logic [17:0] sum3, sum4;
    logic [18:0] diff4, diff3;
    logic [17:0] diff2;
    logic [16:0] diff1;

    Warn_Msg warn_reg,       warn_reg_n;
    logic    complete_reg,   complete_reg_n;
    logic    need_write_reg, need_write_reg_n;

    logic    aw_done, aw_done_n;
    logic    w_done,  w_done_n;

    logic        ar_valid, ar_valid_n;
    logic [16:0] ar_addr,  ar_addr_n;
    logic        r_ready,  r_ready_n;

    logic        aw_valid, aw_valid_n;
    logic [16:0] aw_addr,  aw_addr_n;
    logic        w_valid,  w_valid_n;
    logic [95:0] w_data,   w_data_n;
    logic        b_ready,  b_ready_n;

    logic        out_valid, out_valid_n;

    typedef logic [8:0] Day_Count;

    logic login_bonus_reg, login_bonus_reg_n;

    logic      enough_exp;

    logic signed [17:0] hp_p_new_reg, hp_p_new_reg_n;
    logic signed [17:0] hp_m_new_reg, hp_m_new_reg_n;
    logic               battle_player_dead, battle_player_dead_n;
    logic               battle_mon_dead,    battle_mon_dead_n;

    logic signed [16:0] dmg_p_reg, dmg_p_reg_n;
    logic signed [16:0] dmg_m_reg, dmg_m_reg_n;

    function automatic Day_Count day_of_year_m4d5 (Month m, Day d);
        Day_Count base;
        begin
            unique case (m)
                4'd1:  base = 9'd0;
                4'd2:  base = 9'd31;
                4'd3:  base = 9'd59;
                4'd4:  base = 9'd90;
                4'd5:  base = 9'd120;
                4'd6:  base = 9'd151;
                4'd7:  base = 9'd181;
                4'd8:  base = 9'd212;
                4'd9:  base = 9'd243;
                4'd10: base = 9'd273;
                4'd11: base = 9'd304;
                4'd12: base = 9'd334;
                default: base = 9'd0;
            endcase
            day_of_year_m4d5 = base + Day_Count'(d) - 9'd1;
        end
    endfunction

    function automatic Day_Count day_diff_m4d5 (
        Month old_m, Day old_d,
        Month new_m, Day new_d
    );
        Day_Count o_idx, n_idx, diff;
        begin
            o_idx = day_of_year_m4d5(old_m, old_d);
            n_idx = day_of_year_m4d5(new_m, new_d);
            if (n_idx >= o_idx) diff = n_idx - o_idx;
            else                diff = (Day_Count'(9'd365) - o_idx) + n_idx;
            day_diff_m4d5 = diff;
        end
    endfunction

    function automatic logic is_consecutive_login (
        Month old_m, Day old_d,
        Month new_m, Day new_d
    );
        Day   last_day;
        Month next_m;
        Day   old_d_plus1;
        logic same_month_next;
        logic wrap_month_next;
        begin
            unique case (old_m)
                4'd1, 4'd3, 4'd5, 4'd7, 4'd8, 4'd10, 4'd12: last_day = Day'(5'd31);
                4'd4, 4'd6, 4'd9, 4'd11:                    last_day = Day'(5'd30);
                4'd2:                                       last_day = Day'(5'd28);
                default:                                    last_day = Day'(5'd31);
            endcase

            next_m       = (old_m == Month'(4'd12)) ? Month'(4'd1) : Month'(old_m + Month'(4'd1));
            old_d_plus1  = Day'(old_d + Day'(5'd1));

            same_month_next = (new_m == old_m) &&
                              (new_d == old_d_plus1);

            wrap_month_next = (new_m == next_m) &&
                              (new_d == Day'(5'd1)) &&
                              (old_d == last_day);

            is_consecutive_login = same_month_next | wrap_month_next;
        end
    endfunction

    function automatic logic [16:0] calc_player_addr (Player_No pno);
        logic [16:0] mul8, mul4;
        begin
            mul8 = {pno, 3'b000};
            mul4 = {pno, 2'b00};
            calc_player_addr = 17'h10000 + mul8 + mul4;
        end
    endfunction

    //============================================================
    //  AXI-like interface outputs
    //============================================================
    assign inf.AR_VALID  = (!inf.rst_n) ? 1'b0 : ar_valid;
    assign inf.AR_ADDR   = (!inf.rst_n) ? 17'd0 : ar_addr;
    assign inf.R_READY   = (!inf.rst_n) ? 1'b0 : r_ready;

    assign inf.AW_VALID  = (!inf.rst_n) ? 1'b0 : aw_valid;
    assign inf.AW_ADDR   = (!inf.rst_n) ? 17'd0 : aw_addr;
    assign inf.W_VALID   = (!inf.rst_n) ? 1'b0 : w_valid;
    assign inf.W_DATA    = (!inf.rst_n) ? 96'd0 : w_data;
    assign inf.B_READY   = (!inf.rst_n) ? 1'b0 : b_ready;

    assign inf.out_valid = (!inf.rst_n) ? 1'b0 : out_valid;
    assign inf.warn_msg  = (!inf.rst_n) ? Warn_Msg'(0) : warn_reg;
    assign inf.complete  = (!inf.rst_n) ? 1'b0 : complete_reg;

    logic inputs_ready;
    always_comb begin
        inputs_ready = 1'b0;
        if (got_act) begin
            unique case (act_reg)
                Login:          inputs_ready = (got_date && got_player);
                Level_Up:       inputs_ready = (got_type && got_mode && got_player);
                Battle:         inputs_ready = (got_player && got_monster_all);
                Use_Skill:      inputs_ready = (got_player && got_mp_all);
                Check_Inactive: inputs_ready = (got_date && got_player);
                default:        inputs_ready = 1'b0;
            endcase
        end
    end

    //============================================================
    //  Check_Inactive task
    //============================================================
    task automatic task_do_check_inactive (
        input  Player_DRAM in_p,
        input  Date        today,
        output Player_DRAM out_p,
        output Warn_Msg    o_warn,
        output logic       o_complete,
        output logic       o_need_write
    );
        Player_DRAM np;
        Warn_Msg    w;
        logic       c;
        Day_Count   diff;
        begin
            np   = in_p;
            diff = day_diff_m4d5(
                in_p.login_M[3:0], in_p.login_D[4:0],
                today.M,           today.D
            );

            if (diff > Day_Count'(9'd90)) begin
                w = Date_Warn;
                c = 1'b0;
            end
            else begin
                w = No_Warn;
                c = 1'b1;
            end

            out_p        = np;
            o_warn       = w;
            o_complete   = c;
            o_need_write = 1'b0;
        end
    endtask

    //============================================================
    //  Main combinational (next-state / next-data)
    //============================================================
    integer k;
    always_comb begin
        next_state       = state;

        act_reg_n        = act_reg;
        type_reg_n       = type_reg;
        mode_reg_n       = mode_reg;
        today_reg_n      = today_reg;
        player_no_reg_n  = player_no_reg;
        monster_reg_n    = monster_reg;

        skill_mp_n       = skill_mp;
        skill_sort1_n    = skill_sort1;
        skill_s_n        = skill_s;
        skill_m_n        = skill_m;

        monster_cnt_n    = monster_cnt;
        mp_cnt_n         = mp_cnt;

        got_act_n         = got_act;
        got_type_n        = got_type;
        got_mode_n        = got_mode;
        got_date_n        = got_date;
        got_player_n      = got_player;
        got_monster_all_n = got_monster_all;
        got_mp_all_n      = got_mp_all;

        player_reg_n      = player_reg;
        warn_reg_n        = warn_reg;
        complete_reg_n    = complete_reg;
        need_write_reg_n  = need_write_reg;

        d_hp_n            = d_hp;
        d_mp_n            = d_mp;
        d_atk_n           = d_atk;
        d_def_n           = d_def;
        f_hp_n            = f_hp;
        f_mp_n            = f_mp;
        f_atk_n           = f_atk;
        f_def_n           = f_def;

        lvA0_n           = lvA0;
        lvA1_n           = lvA1;
        lvA2_n           = lvA2;
        lvA3_n           = lvA3;

        lvB0_n           = lvB0;
        lvB1_n           = lvB1;
        lvB2_n           = lvB2;
        lvB3_n           = lvB3;

        login_bonus_reg_n = login_bonus_reg;

        ar_valid_n        = 1'b0; ar_addr_n = ar_addr; r_ready_n = 1'b0;
        aw_valid_n        = 1'b0; aw_addr_n = aw_addr; w_valid_n = 1'b0; w_data_n = w_data; b_ready_n = 1'b0;
        out_valid_n       = 1'b0;

        aw_done_n         = aw_done;
        w_done_n          = w_done;

        hp_p_new_reg_n       = hp_p_new_reg;
        hp_m_new_reg_n       = hp_m_new_reg;
        battle_player_dead_n = battle_player_dead;
        battle_mon_dead_n    = battle_mon_dead;
        dmg_p_reg_n          = dmg_p_reg;
        dmg_m_reg_n          = dmg_m_reg;

        cost0 = '0;
        cost1 = '0;
        cost2 = '0;
        cost3 = '0;
        sum1  = '0;
        sum2  = '0;
        sum3  = '0;
        sum4  = '0;
        diff4 = '0;
        diff3 = '0;
        diff2 = '0;
        diff1 = '0;

        //========================================================
        // enough_exp
        //========================================================
        unique case (mode_reg)
            Easy:    enough_exp = (player_reg.Exp >= 16'd4095);
            Normal:  enough_exp = (player_reg.Exp >= 16'd16383);
            Hard:    enough_exp = (player_reg.Exp >= 16'd32767);
            default: enough_exp = 1'b0;
        endcase

        //========================================================
        // S_IDLE / S_COLLECT
        //========================================================
        if (state == S_IDLE || state == S_COLLECT) begin
            if (inf.sel_action_valid) begin
                act_reg_n        = inf.D.d_act[0];
                got_act_n        = 1'b1;

                warn_reg_n       = No_Warn;
                complete_reg_n   = 1'b0;
                need_write_reg_n = 1'b0;

                login_bonus_reg_n = 1'b0;

                hp_p_new_reg_n      = 18'sd0;
                hp_m_new_reg_n      = 18'sd0;
                battle_player_dead_n= 1'b0;
                battle_mon_dead_n   = 1'b0;

                dmg_p_reg_n         = 17'sd0;
                dmg_m_reg_n         = 17'sd0;

                lvA0_n = 16'd0;
                lvA1_n = 16'd0;
                lvA2_n = 16'd0;
                lvA3_n = 16'd0;
                lvB0_n = 16'd0;
                lvB1_n = 16'd0;
                lvB2_n = 16'd0;
                lvB3_n = 16'd0;

                for (k = 0; k < 4; k = k + 1) begin
                    skill_sort1_n[k] = 16'd0;
                    skill_s_n[k]     = 16'd0;
                    skill_m_n[k]     = 16'd0;
                end
            end

            if (inf.type_valid) begin
                type_reg_n = inf.D.d_type[0];
                got_type_n = 1'b1;
            end
            if (inf.mode_valid) begin
                mode_reg_n = inf.D.d_mode[0];
                got_mode_n = 1'b1;
            end
            if (inf.date_valid) begin
                today_reg_n = inf.D.d_date[0];
                got_date_n  = 1'b1;
            end
            if (inf.player_no_valid) begin
                player_no_reg_n = inf.D.d_player_no[0];
                got_player_n    = 1'b1;
            end

            if (inf.monster_valid) begin
                unique case (monster_cnt)
                    2'd0: monster_reg_n.Attack  = inf.D.d_attribute[0];
                    2'd1: monster_reg_n.Defense = inf.D.d_attribute[0];
                    2'd2: monster_reg_n.HP      = inf.D.d_attribute[0];
                    default: ;
                endcase
                if (monster_cnt < 2'd2) monster_cnt_n = monster_cnt + 2'd1;
                else begin
                    monster_cnt_n      = monster_cnt;
                    got_monster_all_n  = 1'b1;
                end
            end

            if (inf.MP_valid) begin
                skill_mp_n[mp_cnt] = inf.D.d_attribute[0];
                if (mp_cnt < 2'd3) mp_cnt_n = mp_cnt + 2'd1;
                else begin
                    mp_cnt_n     = mp_cnt;
                    got_mp_all_n = 1'b1;
                end
            end
        end

        //========================================================
        // FSM
        //========================================================
        unique case (state)
            //----------------------------------------------------
            S_IDLE: begin
                if (inf.sel_action_valid) next_state = S_COLLECT;
            end

            //----------------------------------------------------
            S_COLLECT: begin
                if (inputs_ready) next_state = S_AR;
            end

            //----------------------------------------------------
            S_AR: begin
                ar_valid_n = 1'b1;
                ar_addr_n  = calc_player_addr(player_no_reg);
                if (inf.AR_READY) begin
                    ar_valid_n = 1'b0;
                    next_state = S_WAIT_R;
                end
            end

            //----------------------------------------------------
            S_WAIT_R: begin
                r_ready_n = 1'b1;
                if (inf.R_VALID) begin
                    player_reg_n = Player_DRAM'(inf.R_DATA);
                    r_ready_n    = 1'b0;

                    hp_p_new_reg_n      = 18'sd0;
                    hp_m_new_reg_n      = 18'sd0;
                    battle_player_dead_n= 1'b0;
                    battle_mon_dead_n   = 1'b0;

                    dmg_p_reg_n         = 17'sd0;
                    dmg_m_reg_n         = 17'sd0;

                    lvA0_n = 16'd0;
                    lvA1_n = 16'd0;
                    lvA2_n = 16'd0;
                    lvA3_n = 16'd0;

                    for (k = 0; k < 4; k = k + 1) begin
                        skill_s_n[k]     = 16'd0;
                        skill_m_n[k]     = 16'd0;
                        skill_sort1_n[k] = 16'd0;
                    end

                    if (act_reg == Level_Up)
                        next_state = S_LVUP_PREP;
                    else if (act_reg == Use_Skill)
                        next_state = S_SKILL_PREP;
                    else if (act_reg == Battle)
                        next_state = S_BATTLE_CALC;
                    else
                        next_state = S_COMPUTE;
                end
            end

            //----------------------------------------------------
            // COMUTE: Login / Check_Inactive 
            //----------------------------------------------------
            S_COMPUTE: begin
                Player_DRAM np;
                Warn_Msg    w;
                logic       c, nw;

                np = player_reg;
                w  = warn_reg;
                c  = complete_reg;
                nw = need_write_reg;

                unique case (act_reg)
                    // ------------------ Login ------------------
                    Login: begin
                        login_bonus_reg_n = is_consecutive_login(
                            player_reg.login_M[3:0], player_reg.login_D[4:0],
                            today_reg.M,             today_reg.D
                        );
                        next_state = S_LOGIN_APPLY;
                    end

                    // --------------- Check_Inactive ------------
                    Check_Inactive: begin
                        task_do_check_inactive(player_reg, today_reg, np, w, c, nw);
                        player_reg_n     = np;
                        warn_reg_n       = w;
                        complete_reg_n   = c;
                        need_write_reg_n = nw;
                        next_state       = S_DECIDE;
                    end

                    default: begin
                        player_reg_n     = player_reg;
                        warn_reg_n       = No_Warn;
                        complete_reg_n   = 1'b0;
                        need_write_reg_n = 1'b0;
                        next_state       = S_DECIDE;
                    end
                endcase
            end

            //----------------------------------------------------
            // Login Apply
            //----------------------------------------------------
            S_LOGIN_APPLY: begin
                Player_DRAM  np;
                logic        sat_local;
                logic [17:0] sum_exp, sum_mp;

                np        = player_reg;
                sat_local = 1'b0;

                if (login_bonus_reg) begin
                    sum_exp = {2'b00, player_reg.Exp} + 18'd512;
                    sum_mp  = {2'b00, player_reg.MP}  + 18'd1024;

                    if (|sum_exp[17:16]) begin
                        np.Exp    = Attribute'(16'hFFFF);
                        sat_local = 1'b1;
                    end
                    else begin
                        np.Exp    = Attribute'(sum_exp[15:0]);
                    end

                    if (|sum_mp[17:16]) begin
                        np.MP     = Attribute'(16'hFFFF);
                        sat_local = 1'b1;
                    end
                    else begin
                        np.MP     = Attribute'(sum_mp[15:0]);
                    end
                end

                np.login_M = {4'b0, today_reg.M};
                np.login_D = {3'b0, today_reg.D};

                player_reg_n     = np;
                warn_reg_n       = sat_local ? Saturation_Warn : No_Warn;
                complete_reg_n   = sat_local ? 1'b0           : 1'b1;
                need_write_reg_n = 1'b1;

                next_state       = S_DECIDE;
            end

            //----------------------------------------------------
            // Level Up: PREP
            //----------------------------------------------------
            S_LVUP_PREP: begin
                if (!enough_exp) begin
                    warn_reg_n       = Exp_Warn;
                    complete_reg_n   = 1'b0;
                    need_write_reg_n = 1'b0;
                    d_hp_n           = 18'd0;
                    d_mp_n           = 18'd0;
                    d_atk_n          = 18'd0;
                    d_def_n          = 18'd0;
                    next_state       = S_DECIDE;
                end
                else begin
                    d_hp_n  = 18'd0;
                    d_mp_n  = 18'd0;
                    d_atk_n = 18'd0;
                    d_def_n = 18'd0;

                    unique case (type_reg)
                        Type_A: begin
                            logic [18:0] sum_all_attrs;
                            Attribute delta;
                            sum_all_attrs = {3'b0, player_reg.MP} +
                                            {3'b0, player_reg.HP} +
                                            {3'b0, player_reg.Attack} +
                                            {3'b0, player_reg.Defense};
                            delta   = Attribute'(sum_all_attrs[18:3]);
                            d_hp_n  = {2'b00, delta};
                            d_mp_n  = {2'b00, delta};
                            d_atk_n = {2'b00, delta};
                            d_def_n = {2'b00, delta};

                            next_state = S_LVUP_MODE;
                        end

                        Type_B: begin
                            Attribute s0, s1, s2, s3;

                            if (player_reg.MP < player_reg.HP) begin
                                s0 = player_reg.MP;
                                s1 = player_reg.HP;
                            end
                            else begin
                                s0 = player_reg.HP;
                                s1 = player_reg.MP;
                            end

                            if (player_reg.Attack < player_reg.Defense) begin
                                s2 = player_reg.Attack;
                                s3 = player_reg.Defense;
                            end
                            else begin
                                s2 = player_reg.Defense;
                                s3 = player_reg.Attack;
                            end

                            lvB0_n = s0;
                            lvB1_n = s1;
                            lvB2_n = s2;
                            lvB3_n = s3;

                            d_hp_n  = 18'd0;
                            d_mp_n  = 18'd0;
                            d_atk_n = 18'd0;
                            d_def_n = 18'd0;

                            next_state = S_LVUP_B1;
                        end

                        Type_C: begin
                            Attribute delta_hp16, delta_mp16, delta_atk16, delta_def16;

                            delta_hp16  = (player_reg.HP      < 16'd16383) ? (16'd16383 - player_reg.HP)      : 16'd0;
                            delta_mp16  = (player_reg.MP      < 16'd16383) ? (16'd16383 - player_reg.MP)      : 16'd0;
                            delta_atk16 = (player_reg.Attack  < 16'd16383) ? (16'd16383 - player_reg.Attack)  : 16'd0;
                            delta_def16 = (player_reg.Defense < 16'd16383) ? (16'd16383 - player_reg.Defense) : 16'd0;

                            d_hp_n  = {2'b00, delta_hp16};
                            d_mp_n  = {2'b00, delta_mp16};
                            d_atk_n = {2'b00, delta_atk16};
                            d_def_n = {2'b00, delta_def16};

                            next_state = S_LVUP_MODE;
                        end

                        Type_D: begin
                            Attribute d_hp16, d_mp16, d_atk16, d_def16;
                            Attribute temp;

                            temp   = 16'd3000 + ((16'hFFFF - player_reg.HP)      >> 4);
                            d_hp16 = (temp < 16'd5047) ? temp : 16'd5047;

                            temp   = 16'd3000 + ((16'hFFFF - player_reg.MP)      >> 4);
                            d_mp16 = (temp < 16'd5047) ? temp : 16'd5047;

                            temp   = 16'd3000 + ((16'hFFFF - player_reg.Attack)  >> 4);
                            d_atk16= (temp < 16'd5047) ? temp : 16'd5047;

                            temp   = 16'd3000 + ((16'hFFFF - player_reg.Defense) >> 4);
                            d_def16= (temp < 16'd5047) ? temp : 16'd5047;

                            d_hp_n  = {2'b00, d_hp16};
                            d_mp_n  = {2'b00, d_mp16};
                            d_atk_n = {2'b00, d_atk16};
                            d_def_n = {2'b00, d_def16};

                            next_state = S_LVUP_MODE;
                        end

                        default: begin
                            d_hp_n  = 18'd0;
                            d_mp_n  = 18'd0;
                            d_atk_n = 18'd0;
                            d_def_n = 18'd0;
                            next_state = S_LVUP_MODE;
                        end
                    endcase
                end
            end

            //----------------------------------------------------
            S_LVUP_B1: begin
                Attribute s0, s1, s2, s3;
                Attribute m0, m1, m2, m3;
                Attribute A0, A1, A2, A3;

                s0 = lvB0;
                s1 = lvB1;
                s2 = lvB2;
                s3 = lvB3;

                if (s0 < s2) begin
                    m0 = s0;
                    m2 = s2;
                end
                else begin
                    m0 = s2;
                    m2 = s0;
                end

                if (s1 < s3) begin
                    m1 = s1;
                    m3 = s3;
                end
                else begin
                    m1 = s3;
                    m3 = s1;
                end

                A0 = m0;
                if (m1 < m2) begin
                    A1 = m1;
                    A2 = m2;
                end
                else begin
                    A1 = m2;
                    A2 = m1;
                end
                A3 = m3;

                lvA0_n = A0;
                lvA1_n = A1;
                lvA2_n = A2;
                lvA3_n = A3;

                d_hp_n  = 18'd0;
                d_mp_n  = 18'd0;
                d_atk_n = 18'd0;
                d_def_n = 18'd0;

                next_state = S_LVUP_TB;
            end

            //----------------------------------------------------
            S_LVUP_TB: begin
                Attribute old_hp, old_mp, old_atk, old_def;
                logic [15:0] delta_A0, delta_A1;
                Attribute delta_hp16, delta_mp16, delta_atk16, delta_def16;

                logic [1:0] idxA0, idxA1;
                logic       hasA1;

                old_hp  = player_reg.HP;
                old_mp  = player_reg.MP;
                old_atk = player_reg.Attack;
                old_def = player_reg.Defense;

                delta_A0 = lvA2 - lvA0;
                delta_A1 = lvA3 - lvA1;

                if (old_mp == lvA0)
                    idxA0 = 2'b11;
                else if (old_hp == lvA0)
                    idxA0 = 2'b10;
                else if (old_atk == lvA0)
                    idxA0 = 2'b01;
                else
                    idxA0 = 2'b00;

                hasA1 = 1'b0;
                idxA1 = 2'b00;

                if (!hasA1 && (old_mp == lvA1) && (idxA0 != 2'b11)) begin
                    idxA1 = 2'b11;
                    hasA1 = 1'b1;
                end
                if (!hasA1 && (old_hp == lvA1) && (idxA0 != 2'b10)) begin
                    idxA1 = 2'b10;
                    hasA1 = 1'b1;
                end
                if (!hasA1 && (old_atk == lvA1) && (idxA0 != 2'b01)) begin
                    idxA1 = 2'b01;
                    hasA1 = 1'b1;
                end
                if (!hasA1 && (old_def == lvA1) && (idxA0 != 2'b00)) begin
                    idxA1 = 2'b00;
                    hasA1 = 1'b1;
                end

                if (idxA0 == 2'b11)
                    delta_mp16 = delta_A0;
                else if (hasA1 && (idxA1 == 2'b11))
                    delta_mp16 = delta_A1;
                else
                    delta_mp16 = 16'd0;

                if (idxA0 == 2'b10)
                    delta_hp16 = delta_A0;
                else if (hasA1 && (idxA1 == 2'b10))
                    delta_hp16 = delta_A1;
                else
                    delta_hp16 = 16'd0;

                if (idxA0 == 2'b01)
                    delta_atk16 = delta_A0;
                else if (hasA1 && (idxA1 == 2'b01))
                    delta_atk16 = delta_A1;
                else
                    delta_atk16 = 16'd0;

                if (idxA0 == 2'b00)
                    delta_def16 = delta_A0;
                else if (hasA1 && (idxA1 == 2'b00))
                    delta_def16 = delta_A1;
                else
                    delta_def16 = 16'd0;

                d_hp_n  = {2'b00, delta_hp16};
                d_mp_n  = {2'b00, delta_mp16};
                d_atk_n = {2'b00, delta_atk16};
                d_def_n = {2'b00, delta_def16};

                next_state = S_LVUP_MODE;
            end

            //----------------------------------------------------
            S_LVUP_MODE: begin
                unique case (mode_reg)
                    Easy: begin
                        f_hp_n  = d_hp  - (d_hp  >> 2);
                        f_mp_n  = d_mp  - (d_mp  >> 2);
                        f_atk_n = d_atk - (d_atk >> 2);
                        f_def_n = d_def - (d_def >> 2);
                    end
                    Normal: begin
                        f_hp_n  = d_hp;
                        f_mp_n  = d_mp;
                        f_atk_n = d_atk;
                        f_def_n = d_def;
                    end
                    Hard: begin
                        f_hp_n  = d_hp  + (d_hp  >> 2);
                        f_mp_n  = d_mp  + (d_mp  >> 2);
                        f_atk_n = d_atk + (d_atk >> 2);
                        f_def_n = d_def + (d_def >> 2);
                    end
                    default: begin
                        f_hp_n  = 18'd0;
                        f_mp_n  = 18'd0;
                        f_atk_n = 18'd0;
                        f_def_n = 18'd0;
                    end
                endcase
                next_state = S_LVUP_APPLY;
            end

            //----------------------------------------------------
            S_LVUP_APPLY: begin
                Player_DRAM  np;
                Warn_Msg     w;
                logic        sat_local;
                logic [17:0] sum_hp, sum_mp, sum_atk, sum_def;

                np        = player_reg;
                w         = warn_reg;

                sum_hp  = {2'b00, player_reg.HP}      + f_hp;
                sum_mp  = {2'b00, player_reg.MP}      + f_mp;
                sum_atk = {2'b00, player_reg.Attack}  + f_atk;
                sum_def = {2'b00, player_reg.Defense} + f_def;

                np.HP      = Attribute'((|sum_hp[17:16])  ? 16'hFFFF : sum_hp[15:0]);
                np.MP      = Attribute'((|sum_mp[17:16])  ? 16'hFFFF : sum_mp[15:0]);
                np.Attack  = Attribute'((|sum_atk[17:16]) ? 16'hFFFF : sum_atk[15:0]);
                np.Defense = Attribute'((|sum_def[17:16]) ? 16'hFFFF : sum_def[15:0]);

                sat_local = (|sum_hp[17:16]) | (|sum_mp[17:16]) |
                            (|sum_atk[17:16]) | (|sum_def[17:16]);

                player_reg_n     = np;
                warn_reg_n       = sat_local ? Saturation_Warn : No_Warn;
                complete_reg_n   = sat_local ? 1'b0           : 1'b1;
                need_write_reg_n = 1'b1;

                next_state = S_DECIDE;
            end

            //----------------------------------------------------
            // Battle
            //----------------------------------------------------
            S_BATTLE_CALC: begin
                if (player_reg.HP == Attribute'(16'd0)) begin
                    warn_reg_n       = HP_Warn;
                    complete_reg_n   = 1'b0;
                    need_write_reg_n = 1'b0;
                    next_state       = S_DECIDE;
                end
                else begin
                    logic signed [16:0] atk_m_s, def_p_s, atk_p_s, def_m_s;
                    logic signed [16:0] dmg_p_tmp, dmg_m_tmp;

                    atk_m_s = $signed({1'b0, monster_reg.Attack});
                    def_p_s = $signed({1'b0, player_reg.Defense});
                    atk_p_s = $signed({1'b0, player_reg.Attack});
                    def_m_s = $signed({1'b0, monster_reg.Defense});

                    dmg_p_tmp = atk_m_s - def_p_s;
                    dmg_m_tmp = atk_p_s - def_m_s;

                    dmg_p_reg_n = (dmg_p_tmp > 0) ? dmg_p_tmp : 17'sd0;
                    dmg_m_reg_n = (dmg_m_tmp > 0) ? dmg_m_tmp : 17'sd0;

                    next_state = S_BATTLE_PIPE;
                end
            end

            S_BATTLE_PIPE: begin
                logic signed [17:0] hp_p_new, hp_m_new;

                if (dmg_p_reg > 0) hp_p_new = $signed({2'b00, player_reg.HP}) - $signed({1'b0, dmg_p_reg});
                else               hp_p_new = $signed({2'b00, player_reg.HP});

                if (dmg_m_reg > 0) hp_m_new = $signed({2'b00, monster_reg.HP}) - $signed({1'b0, dmg_m_reg});
                else               hp_m_new = $signed({2'b00, monster_reg.HP});

                if (hp_p_new <= 0) hp_p_new = 18'sd0;
                if (hp_m_new <= 0) hp_m_new = 18'sd0;

                hp_p_new_reg_n       = hp_p_new;
                hp_m_new_reg_n       = hp_m_new;
                battle_player_dead_n = (hp_p_new == 18'sd0);
                battle_mon_dead_n    = (hp_m_new == 18'sd0);

                next_state           = S_BATTLE_APPLY;
            end

            S_BATTLE_APPLY: begin
                Player_DRAM  np;
                Warn_Msg     w;
                logic        sat;
                logic signed [17:0] tmp_s;
                logic [17:0]        tmp_u_exp, tmp_u_mp;

                np  = player_reg;
                w   = warn_reg;
                sat = 1'b0;

                if (!battle_player_dead && battle_mon_dead) begin
                    np.HP = Attribute'(hp_p_new_reg[15:0]);

                    tmp_u_exp = {2'b00, player_reg.Exp} + 18'd2048;
                    if (|tmp_u_exp[17:16]) begin
                        np.Exp = Attribute'(16'hFFFF);
                        sat    = 1'b1;
                    end
                    else begin
                        np.Exp = Attribute'(tmp_u_exp[15:0]);
                    end

                    tmp_u_mp = {2'b00, player_reg.MP} + 18'd2048;
                    if (|tmp_u_mp[17:16]) begin
                        np.MP = Attribute'(16'hFFFF);
                        sat   = 1'b1;
                    end
                    else begin
                        np.MP = Attribute'(tmp_u_mp[15:0]);
                    end
                end
                else if (battle_player_dead) begin
                    np.HP = Attribute'(16'd0);

                    tmp_s = $signed({2'b00, player_reg.Exp}) - 18'sd2048;
                    if (tmp_s[17]) begin
                        np.Exp = Attribute'(16'd0);
                        sat    = 1'b1;
                    end
                    else begin
                        np.Exp = Attribute'(tmp_s[15:0]);
                    end

                    tmp_s = $signed({2'b00, player_reg.Attack}) - 18'sd2048;
                    if (tmp_s[17]) begin
                        np.Attack = Attribute'(16'd0);
                        sat       = 1'b1;
                    end
                    else begin
                        np.Attack = Attribute'(tmp_s[15:0]);
                    end

                    tmp_s = $signed({2'b00, player_reg.Defense}) - 18'sd2048;
                    if (tmp_s[17]) begin
                        np.Defense = Attribute'(16'd0);
                        sat        = 1'b1;
                    end
                    else begin
                        np.Defense = Attribute'(tmp_s[15:0]);
                    end
                end
                else begin
                    np.HP = Attribute'(hp_p_new_reg[15:0]);
                end

                if (sat) begin
                    w              = Saturation_Warn;
                    complete_reg_n = 1'b0;
                end
                else begin
                    w              = No_Warn;
                    complete_reg_n = 1'b1;
                end

                player_reg_n     = np;
                warn_reg_n       = w;
                need_write_reg_n = 1'b1;

                next_state       = S_DECIDE;
            end

            //----------------------------------------------------
            // Use Skill pipeline
            //----------------------------------------------------
            S_SKILL_PREP: begin
                Attribute s0, s1, s2, s3;

                s0 = (skill_mp[0] < skill_mp[1]) ? skill_mp[0] : skill_mp[1];
                s1 = (skill_mp[0] < skill_mp[1]) ? skill_mp[1] : skill_mp[0];
                s2 = (skill_mp[2] < skill_mp[3]) ? skill_mp[2] : skill_mp[3];
                s3 = (skill_mp[2] < skill_mp[3]) ? skill_mp[3] : skill_mp[2];

                skill_s_n[0] = s0;
                skill_s_n[1] = s1;
                skill_s_n[2] = s2;
                skill_s_n[3] = s3;

                for (k = 0; k < 4; k = k + 1) begin
                    skill_m_n[k]     = 16'd0;
                    skill_sort1_n[k] = 16'd0;
                end

                next_state         = S_SKILL_COST;
            end

            S_SKILL_COST: begin
                Attribute s0, s1, s2, s3;
                Attribute m0, m1, m2, m3;

                s0 = skill_s[0];
                s1 = skill_s[1];
                s2 = skill_s[2];
                s3 = skill_s[3];

                m0 = (s0 < s2) ? s0 : s2;
                m2 = (s0 < s2) ? s2 : s0;

                m1 = (s1 < s3) ? s1 : s3;
                m3 = (s1 < s3) ? s3 : s1;

                skill_m_n[0] = m0;
                skill_m_n[1] = m1;
                skill_m_n[2] = m2;
                skill_m_n[3] = m3;

                next_state = S_SKILL_ACC;
            end

            S_SKILL_ACC: begin
                Attribute m0, m1, m2, m3;
                Attribute c0, c1, c2, c3;

                m0 = skill_m[0];
                m1 = skill_m[1];
                m2 = skill_m[2];
                m3 = skill_m[3];

                c0 = m0;
                if (m1 < m2) begin
                    c1 = m1;
                    c2 = m2;
                end
                else begin
                    c1 = m2;
                    c2 = m1;
                end
                c3 = m3;

                skill_sort1_n[0] = c0;
                skill_sort1_n[1] = c1;
                skill_sort1_n[2] = c2;
                skill_sort1_n[3] = c3;

                next_state        = S_SKILL_APPLY;
            end

            S_SKILL_APPLY: begin
                Player_DRAM np;
                np = player_reg;

                cost0 = skill_sort1[0];
                cost1 = skill_sort1[1];
                cost2 = skill_sort1[2];
                cost3 = skill_sort1[3];

                sum1 = {1'b0, cost0};
                sum2 = {1'b0, cost0} + {1'b0, cost1};
                sum3 = {1'b0, cost0} + {1'b0, cost1} + {1'b0, cost2};
                sum4 = {1'b0, cost0} + {1'b0, cost1} + {1'b0, cost2} + {1'b0, cost3};

                diff4 = {3'b0, player_reg.MP} - {1'b0, sum4};
                diff3 = {3'b0, player_reg.MP} - {1'b0, sum3};
                diff2 = {2'b0, player_reg.MP} - {1'b0, sum2};
                diff1 = {1'b0, player_reg.MP} - {1'b0, sum1};

                warn_reg_n        = MP_Warn;
                need_write_reg_n  = 1'b0;
                complete_reg_n    = 1'b0;

                if (diff4[18] == 1'b0) begin
                    np.MP          = Attribute'(diff4[15:0]);
                    warn_reg_n     = No_Warn;
                    need_write_reg_n = 1'b1;
                    complete_reg_n = 1'b1;
                end
                else if (diff3[18] == 1'b0) begin
                    np.MP          = Attribute'(diff3[15:0]);
                    warn_reg_n     = No_Warn;
                    need_write_reg_n = 1'b1;
                    complete_reg_n = 1'b1;
                end
                else if (diff2[17] == 1'b0) begin
                    np.MP          = Attribute'(diff2[15:0]);
                    warn_reg_n     = No_Warn;
                    need_write_reg_n = 1'b1;
                    complete_reg_n = 1'b1;
                end
                else if (diff1[16] == 1'b0) begin
                    np.MP          = Attribute'(diff1[15:0]);
                    warn_reg_n     = No_Warn;
                    need_write_reg_n = 1'b1;
                    complete_reg_n = 1'b1;
                end
                else begin
                    np              = player_reg;
                    warn_reg_n      = MP_Warn;
                    need_write_reg_n= 1'b0;
                    complete_reg_n  = 1'b0;
                end

                player_reg_n      = np;

                next_state         = S_DECIDE;
            end

            //----------------------------------------------------
            S_DECIDE: begin
                if (need_write_reg) next_state = S_AW_W;
                else                next_state = S_OUT;
            end

            //----------------------------------------------------
            S_AW_W: begin
                if (!aw_done) begin
                    aw_valid_n = 1'b1;
                    aw_addr_n  = calc_player_addr(player_no_reg);
                    if (inf.AW_READY) begin
                        aw_valid_n = 1'b0;
                        aw_done_n  = 1'b1;
                    end
                end

                if (!w_done) begin
                    w_valid_n = 1'b1;
                    w_data_n  = player_reg;
                    if (inf.W_READY) begin
                        w_valid_n = 1'b0;
                        w_done_n  = 1'b1;
                    end
                end

                if (aw_done_n && w_done_n) begin
                    next_state = S_WAIT_B;
                end
            end

            //----------------------------------------------------
            S_WAIT_B: begin
                b_ready_n = 1'b1;
                if (inf.B_VALID) begin
                    b_ready_n  = 1'b0;
                    next_state = S_OUT;
                end
            end

            //----------------------------------------------------
            S_OUT: begin
                out_valid_n = 1'b1;

                got_act_n         = 1'b0;
                got_type_n        = 1'b0;
                got_mode_n        = 1'b0;
                got_date_n        = 1'b0;
                got_player_n      = 1'b0;
                got_monster_all_n = 1'b0;
                got_mp_all_n      = 1'b0;
                monster_cnt_n     = 2'd0;
                mp_cnt_n          = 2'd0;
                aw_done_n         = 1'b0;
                w_done_n          = 1'b0;

                login_bonus_reg_n = 1'b0;

                hp_p_new_reg_n      = 18'sd0;
                hp_m_new_reg_n      = 18'sd0;
                battle_player_dead_n= 1'b0;
                battle_mon_dead_n   = 1'b0;

                dmg_p_reg_n         = 17'sd0;
                dmg_m_reg_n         = 17'sd0;

                lvA0_n = 16'd0;
                lvA1_n = 16'd0;
                lvA2_n = 16'd0;
                lvA3_n = 16'd0;

                for (k = 0; k < 4; k = k + 1) begin
                    skill_sort1_n[k] = 16'd0;
                    skill_s_n[k]     = 16'd0;
                    skill_m_n[k]     = 16'd0;
                end

                next_state        = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    //============================================================
    //  Sequential
    //============================================================
    always_ff @(posedge clk or negedge inf.rst_n) begin
        if (!inf.rst_n) begin
            state          <= S_IDLE;
            act_reg        <= Login;
            type_reg       <= Type_A;
            mode_reg       <= Easy;
            today_reg      <= '0;
            player_no_reg  <= '0;
            monster_reg    <= '0;
            for (int i = 0; i < 4; i++) begin
                skill_mp[i]     <= '0;
                skill_sort1[i]  <= '0;
                skill_s[i]      <= '0;
                skill_m[i]      <= '0;
            end
            monster_cnt    <= 2'd0;
            mp_cnt         <= 2'd0;

            got_act        <= 1'b0;
            got_type       <= 1'b0;
            got_mode       <= 1'b0;
            got_date       <= 1'b0;
            got_player     <= 1'b0;
            got_monster_all<= 1'b0;
            got_mp_all     <= 1'b0;

            player_reg     <= '0;
            warn_reg       <= No_Warn;
            complete_reg   <= 1'b0;
            need_write_reg <= 1'b0;

            d_hp           <= 18'd0;
            d_mp           <= 18'd0;
            d_atk          <= 18'd0;
            d_def          <= 18'd0;
            f_hp           <= 18'd0;
            f_mp           <= 18'd0;
            f_atk          <= 18'd0;
            f_def          <= 18'd0;

            ar_valid       <= 1'b0;
            ar_addr        <= 17'd0;
            r_ready        <= 1'b0;
            aw_valid       <= 1'b0;
            aw_addr        <= 17'd0;
            w_valid        <= 1'b0;
            w_data         <= '0;
            b_ready        <= 1'b0;
            out_valid      <= 1'b0;

            aw_done        <= 1'b0;
            w_done         <= 1'b0;

            hp_p_new_reg      <= 18'sd0;
            hp_m_new_reg      <= 18'sd0;
            battle_player_dead<= 1'b0;
            battle_mon_dead   <= 1'b0;

            dmg_p_reg         <= 17'sd0;
            dmg_m_reg         <= 17'sd0;

            lvA0              <= 16'd0;
            lvA1              <= 16'd0;
            lvA2              <= 16'd0;
            lvA3              <= 16'd0;
            lvB0              <= 16'd0;
            lvB1              <= 16'd0;
            lvB2              <= 16'd0;
            lvB3              <= 16'd0;

            login_bonus_reg   <= 1'b0;
        end
        else begin
            state          <= next_state;
            act_reg        <= act_reg_n;
            type_reg       <= type_reg_n;
            mode_reg       <= mode_reg_n;
            today_reg      <= today_reg_n;
            player_no_reg  <= player_no_reg_n;
            monster_reg    <= monster_reg_n;
            skill_mp       <= skill_mp_n;
            monster_cnt    <= monster_cnt_n;
            mp_cnt         <= mp_cnt_n;

            skill_sort1    <= skill_sort1_n;
            skill_s        <= skill_s_n;
            skill_m        <= skill_m_n;

            got_act        <= got_act_n;
            got_type       <= got_type_n;
            got_mode       <= got_mode_n;
            got_date       <= got_date_n;
            got_player     <= got_player_n;
            got_monster_all<= got_monster_all_n;
            got_mp_all     <= got_mp_all_n;

            player_reg     <= player_reg_n;
            warn_reg       <= warn_reg_n;
            complete_reg   <= complete_reg_n;
            need_write_reg <= need_write_reg_n;

            d_hp           <= d_hp_n;
            d_mp           <= d_mp_n;
            d_atk          <= d_atk_n;
            d_def          <= d_def_n;
            f_hp           <= f_hp_n;
            f_mp           <= f_mp_n;
            f_atk          <= f_atk_n;
            f_def          <= f_def_n;

            ar_valid       <= ar_valid_n;
            ar_addr        <= ar_addr_n;
            r_ready        <= r_ready_n;
            aw_valid       <= aw_valid_n;
            aw_addr        <= aw_addr_n;
            w_valid        <= w_valid_n;
            w_data         <= w_data_n;
            b_ready        <= b_ready_n;
            out_valid      <= out_valid_n;

            aw_done        <= aw_done_n;
            w_done         <= w_done_n;

            hp_p_new_reg      <= hp_p_new_reg_n;
            hp_m_new_reg      <= hp_m_new_reg_n;
            battle_player_dead<= battle_player_dead_n;
            battle_mon_dead   <= battle_mon_dead_n;

            dmg_p_reg         <= dmg_p_reg_n;
            dmg_m_reg         <= dmg_m_reg_n;

            lvA0              <= lvA0_n;
            lvA1              <= lvA1_n;
            lvA2              <= lvA2_n;
            lvA3              <= lvA3_n;
            lvB0              <= lvB0_n;
            lvB1              <= lvB1_n;
            lvB2              <= lvB2_n;
            lvB3              <= lvB3_n;

            login_bonus_reg   <= login_bonus_reg_n;
        end
    end

endmodule
