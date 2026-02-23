//`include "../00_TESTBED/pseudo_DRAM.sv"
`include "Usertype.sv"

program automatic PATTERN (
    input  clk,
    INF.PATTERN inf
);
    import usertype::*;

    integer              SEED            = 59487;
    localparam int       PATTERN_NUM     = 6401;
    localparam int       MAX_CYCLE_LIMIT = 1000;
    localparam string    DRAM_PATH       = "../00_TESTBED/DRAM/dram.dat";
    localparam bit       ENABLE_DEBUG    = 0;

    integer cyc_latency        = 0;
    integer cyc_total          = 0;
    integer pattern_idx        = 0;
    integer ov_cycle_cnt       = 0;
    integer loop_var           = 0;
    integer lvup_round         = 0;

    // Action encoding
    localparam logic [2:0]
        OP_LOGIN          = 3'd0,
        OP_LEVELUP        = 3'd1,
        OP_BATTLE         = 3'd2,
        OP_USE_SKILL      = 3'd3,
        OP_CHECK_INACTIVE = 3'd4;

    // Warning messages (Warn_Msg)
    localparam logic [2:0]
        WARN_NONE_CODE       = 3'b000,  // No_Warn
        WARN_DATE_CODE       = 3'b001,  // Date_Warn
        WARN_EXP_CODE        = 3'b010,  // Exp_Warn
        WARN_HP_CODE         = 3'b011,  // HP_Warn
        WARN_MP_CODE         = 3'b100,  // MP_Warn
        WARN_SAT_CODE        = 3'b101;  // Saturation_Warn

    // Scene mode (Table 2)
    localparam logic [1:0]
        MODE_EZ      = 2'b00,
        MODE_NORMALZ = 2'b01,
        MODE_HARDZ   = 2'b10;

    // Training type (Table 3)
    localparam logic [1:0]
        TRAIN_A = 2'd0,
        TRAIN_B = 2'd1,
        TRAIN_C = 2'd2,
        TRAIN_D = 2'd3;

    // 96 bits per player => 12 bytes/player, address from @10000
    localparam int DRAM_BASE_ADDR      = 17'd65536;
    localparam int DRAM_BYTES_PER_USER = 12;
    localparam int DRAM_USER_COUNT     = 256;
    localparam int DRAM_TOP_ADDR =
        DRAM_BASE_ADDR + DRAM_BYTES_PER_USER * DRAM_USER_COUNT - 1;

    logic [7:0] ref_dram [DRAM_TOP_ADDR : DRAM_BASE_ADDR];

    // Golden inputs
    logic [2:0] act_ref;         // Action
    logic [1:0] type_ref;        // Training_Type
    logic [1:0] mode_ref;        // Mode
    logic [7:0] player_id_ref;   // 0 ~ 255

    // Date (input & stored)
    logic [3:0] date_in_month;
    logic [4:0] date_in_day;
    logic [3:0] date_mem_month;
    logic [4:0] date_mem_day;

    // Player attributes
    logic [15:0] attr_exp_ref;
    logic [15:0] attr_mp_ref;
    logic [15:0] attr_hp_ref;
    logic [15:0] attr_atk_ref;
    logic [15:0] attr_def_ref;

    // Monster attributes (Battle)
    logic [15:0] mon_atk_ref;
    logic [15:0] mon_def_ref;
    logic [15:0] mon_hp_ref;

    // Use Skill: 4 skills MP cost
    logic [15:0] skill_cost_ref[0:3];

    // Golden outputs
    logic       complete_ref;
    logic [2:0] warn_ref;

    //================================================================
    // Randomization helper classes
    //================================================================
    class delay_rng_c;
        rand int unsigned gap;
        function new (int seed = 0);
            if (seed != 0) this.srandom(seed);
        endfunction
        constraint gap_range { gap inside {[0:3]}; }
    endclass

    class date_rng_c;
        rand Date dt;
        function new (int seed = 0);
            if (seed != 0) this.srandom(seed);
        endfunction
        constraint date_limit {
            dt.M inside {[1:12]};
            // 31 days
            (dt.M == 1  || dt.M == 3  || dt.M == 5  || dt.M == 7  ||
             dt.M == 8  || dt.M == 10 || dt.M == 12) -> dt.D inside {[1:31]};
            // 30 days
            (dt.M == 4  || dt.M == 6  || dt.M == 9  || dt.M == 11) -> dt.D inside {[1:30]};
            // Feb
            (dt.M == 2) -> dt.D inside {[1:28]};
        }
    endclass

    class player_rng_c;
        rand Player_No pid;
        function new (int seed = 0);
            if (seed != 0) this.srandom(seed);
        endfunction
        constraint id_range { pid inside {[0:255]}; }
    endclass

    class attr_rng_c;
        rand Attribute val;
        function new (int seed = 0);
            if (seed != 0) this.srandom(seed);
        endfunction
        constraint attr_range { val inside {[0:65535]}; }
    endclass

    delay_rng_c  rng_delay;
    date_rng_c   rng_date;
    player_rng_c rng_player;
    attr_rng_c   rng_attr0, rng_attr1, rng_attr2, rng_attr3;

    // ------------------------------------------------------------
    // Helper Functions
    // ------------------------------------------------------------

    // 16-bit saturating addition
    function automatic logic [19:0] sat_add16_fn(
        input  logic [19:0] a,
        input  logic [19:0] b,
        output bit          sat_flag
    );
        logic [19:0] sum20;
        begin
            sum20 = a + b;
            if (sum20 > 20'(16'hFFFF)) begin
                sat_add16_fn = 20'(16'hFFFF);
                sat_flag     = 1'b1;
            end
            else begin
                sat_add16_fn = {4'b0, sum20[15:0]};
                sat_flag     = 1'b0;
            end
        end
    endfunction

    // 16-bit saturating subtraction
    function automatic logic [19:0] sat_sub16_fn(
        input  logic [19:0] a,
        input  logic [19:0] b,
        output bit          sat_flag
    );
        logic signed [19:0] diff20;
        begin
            diff20 = $signed({1'b0, a[18:0]}) - $signed({1'b0, b[18:0]});
            if (diff20 < 0) begin
                sat_sub16_fn = 20'(16'd0);
                sat_flag     = 1'b1;
            end
            else begin
                sat_sub16_fn = {4'b0, diff20[15:0]};
                sat_flag     = 1'b0;
            end
        end
    endfunction

    function automatic int unsigned day_of_year_fn(
        input logic [3:0] m,
        input logic [4:0] d
    );
        int unsigned base;
        begin
            unique case (m)
                4'd1 : base = 0;
                4'd2 : base = 31;
                4'd3 : base = 31+28;
                4'd4 : base = 31+28+31;
                4'd5 : base = 31+28+31+30;
                4'd6 : base = 31+28+31+30+31;
                4'd7 : base = 31+28+31+30+31+30;
                4'd8 : base = 31+28+31+30+31+30+31;
                4'd9 : base = 31+28+31+30+31+30+31+31;
                4'd10: base = 31+28+31+30+31+30+31+31+30;
                4'd11: base = 31+28+31+30+31+30+31+31+30+31;
                4'd12: base = 31+28+31+30+31+30+31+31+30+31+30;
                default: base = 0;
            endcase
            day_of_year_fn = base + int'(d);
        end
    endfunction

    function automatic int unsigned day_diff_fn(
        input logic [3:0] oldM, input logic [4:0] oldD,
        input logic [3:0] newM, input logic [4:0] newD
    );
        int unsigned idx_old, idx_new;
        begin
			idx_old = day_of_year_fn(oldM, oldD);
			idx_new = day_of_year_fn(newM, newD);
			return (idx_new >= idx_old) ? (idx_new - idx_old)
										: (365 - idx_old + idx_new);
		end
    endfunction

    // mode scaling：Easy(-25%) / Normal / Hard(+25%)
    function automatic logic [19:0] apply_mode_fn(
        input logic [1:0]  mode,
        input logic [19:0] di
    );
        logic [19:0] base, quarter_step, result;
        begin
            base         = di;
            quarter_step = di >> 2;

            result = (mode == MODE_EZ)      ? (base - quarter_step) :
					 (mode == MODE_HARDZ)   ? (base + quarter_step) :
											   base;

            return result;
        end
    endfunction

    function automatic logic [19:0] delta_d_fn(
        input logic [19:0] attr
    );
        localparam logic [19:0] BASE_VAL = 16'd3000;
        localparam logic [19:0] MAX_VAL  = 16'd5047;
        logic [19:0] raw_val;
        begin
            raw_val = BASE_VAL + ((20'(16'hFFFF) - attr) >> 4);

            if (raw_val > MAX_VAL)
                return MAX_VAL;
            else
                return raw_val;
        end
    endfunction

    // ------------------------------------------------------------
    // MAIN FLOW
    // ------------------------------------------------------------
    initial begin : MAIN_FLOW
        rng_delay  = new(SEED);
        rng_date   = new(SEED + 1);
        rng_player = new(SEED + 2);
        rng_attr0  = new(SEED + 3);
        rng_attr1  = new(SEED + 4);
        rng_attr2  = new(SEED + 5);
        rng_attr3  = new(SEED + 6);

        $readmemh(DRAM_PATH, ref_dram);

        // reset all handshakes in one shot
		{
			inf.rst_n,
			inf.sel_action_valid,
			inf.type_valid,
			inf.mode_valid,
			inf.date_valid,
			inf.player_no_valid,
			inf.monster_valid,
			inf.MP_valid
		} = '{
			1'b1, // rst default high
			1'b0,
			1'b0,
			1'b0,
			1'b0,
			1'b0,
			1'b0,
			1'b0
		};

        lvup_round           = 0;
        cyc_total            = 0;

        #5.0;
        inf.rst_n = 1'b0;
        #3.0;
        inf.rst_n = 1'b1;
        @(negedge clk);

        for (pattern_idx = 0; pattern_idx < PATTERN_NUM; pattern_idx++) begin
            choose_action_task();  

            unique case (act_ref)
                Login          : pattern_login_task();
                Level_Up       : pattern_levelup_task();
                Battle         : pattern_battle_task();
                Use_Skill      : pattern_use_skill_task();
                Check_Inactive : pattern_inactive_task();
                default        : pattern_login_task();
            endcase

            wait_out_valid();
            verify_response_task();

            $display("[PASS] Pattern %7d | latency = %4d cycles",
                     pattern_idx, cyc_latency);
            $display("       action=%0d type=%0d mode=%0d player_no=%0d",
                     act_ref, type_ref, mode_ref, player_id_ref);

            if (ENABLE_DEBUG) begin
                $display("------------------------------------------------");
                $display("[DEBUG] Golden vs DUT");
                $display("  complete_ref = %0d, DUT = %0d",
                         complete_ref, inf.complete);
                $display("  warn_ref     = %0d, DUT = %0d",
                         warn_ref, inf.warn_msg);
            end

            insert_random_gap();
        end

        report_all_pass_task();
    end

    // ------------------------------------------------------------
    // Action selection
    // ------------------------------------------------------------
    task choose_action_task;
        int idx;
        begin
            if (pattern_idx <= 5000) begin
                idx     = pattern_idx % 25;
                act_ref = Login; // default

                if (idx inside {0,1,3,5,7,25})
                    act_ref = Login;
                else if (idx inside {2,9,10,12,14})
                    act_ref = Level_Up;
                else if (idx inside {4,11,16,17,19})
                    act_ref = Battle;
                else if (idx inside {6,13,18,21,22})
                    act_ref = Use_Skill;
                else if (idx inside {8,15,20,23,24})
                    act_ref = Check_Inactive;
            end
            else begin
                act_ref = Level_Up;
            end
        end
    endtask

	function automatic logic [15:0] load_word_from_dram (input int base_addr);
		load_word_from_dram = {ref_dram[base_addr + 1], ref_dram[base_addr]};
	endfunction

    // ------------------------------------------------------------
    // DRAM helper
    // ------------------------------------------------------------
    task load_player_from_mem;
        int base_addr;
        int addr_mp, addr_exp, addr_def, addr_atk;
        int addr_date_d, addr_date_m, addr_hp;
        begin
            // 12 * player_no = (player_no << 3) + (player_no << 2)
            base_addr   = DRAM_BASE_ADDR +
                          (player_id_ref << 3) +
                          (player_id_ref << 2);

            addr_mp     = base_addr + 0;
            addr_exp    = base_addr + 2;
            addr_def    = base_addr + 4;
            addr_atk    = base_addr + 6;
            addr_date_d = base_addr + 8;
            addr_date_m = base_addr + 9;
            addr_hp     = base_addr + 10;

			attr_mp_ref    = load_word_from_dram(addr_mp);      // MP
			attr_exp_ref   = load_word_from_dram(addr_exp);     // EXP
			attr_def_ref   = load_word_from_dram(addr_def);     // DEF
			attr_atk_ref   = load_word_from_dram(addr_atk);     // ATK
			attr_hp_ref    = load_word_from_dram(addr_hp);      // HP

			date_mem_day   = ref_dram[addr_date_d][4:0];        // DATE - day
			date_mem_month = ref_dram[addr_date_m][3:0];        // DATE - month

        end
    endtask
	
	task automatic store_word_to_dram(
		input int base,
		input logic [15:0] val
	);
		ref_dram[base]     = val[7:0];
		ref_dram[base + 1] = val[15:8];
	endtask
	
    task write_back_player_to_mem;
        int base_addr;
        int addr_mp, addr_exp, addr_def, addr_atk;
        int addr_date_d, addr_date_m, addr_hp;
        begin
            base_addr   = DRAM_BASE_ADDR +
                          (player_id_ref << 3) +
                          (player_id_ref << 2);

            addr_mp     = base_addr + 0;
            addr_exp    = base_addr + 2;
            addr_def    = base_addr + 4;
            addr_atk    = base_addr + 6;
            addr_date_d = base_addr + 8;
            addr_date_m = base_addr + 9;
            addr_hp     = base_addr + 10;

            unique case (act_ref)
				// Login
				Login: begin
					// date
					ref_dram[addr_date_d] = {3'b000, date_in_day};
					ref_dram[addr_date_m] = {4'b0000, date_in_month};
					// MP / EXP
					store_word_to_dram(addr_mp ,  attr_mp_ref );
					store_word_to_dram(addr_exp,  attr_exp_ref);
				end

				// Level Up：DEF / ATK / HP / MP
				Level_Up: begin
					store_word_to_dram(addr_def, attr_def_ref);
					store_word_to_dram(addr_atk, attr_atk_ref);
					store_word_to_dram(addr_hp , attr_hp_ref );
					store_word_to_dram(addr_mp , attr_mp_ref );
				end

				// Battle：DEF / ATK / HP / MP / EXP
				Battle: begin
					store_word_to_dram(addr_def, attr_def_ref);
					store_word_to_dram(addr_atk, attr_atk_ref);
					store_word_to_dram(addr_hp , attr_hp_ref );
					store_word_to_dram(addr_mp , attr_mp_ref );
					store_word_to_dram(addr_exp, attr_exp_ref);
				end

				// Use Skill
				Use_Skill: begin
					store_word_to_dram(addr_mp, attr_mp_ref);
				end
                default: ;
            endcase
        end
    endtask

    // ------------------------------------------------------------
    // Login Pattern (D = 0)
    // ------------------------------------------------------------
    task pattern_login_task;
        bit          sat_exp, sat_mp;
        int unsigned diff;
        logic [8:0]  date_pack;
        logic [19:0] tmp20;
        begin
            void'(rng_date.randomize());
            date_in_month = rng_date.dt.M;
            date_in_day   = rng_date.dt.D;

            void'(rng_player.randomize());
            player_id_ref = rng_player.pid;

            load_player_from_mem();

            complete_ref = 1'b1;
            sat_exp      = 1'b0;
            sat_mp       = 1'b0;
            warn_ref     = WARN_NONE_CODE;

            diff = day_diff_fn(
                       date_mem_month, date_mem_day,
                       date_in_month,  date_in_day
                   );

            if (diff == 1) begin
                tmp20        = sat_add16_fn(attr_exp_ref, 20'(16'd512),  sat_exp);
                attr_exp_ref = tmp20[15:0];

                tmp20        = sat_add16_fn(attr_mp_ref , 20'(16'd1024), sat_mp );
                attr_mp_ref  = tmp20[15:0];
            end

            if (sat_exp || sat_mp) begin
                complete_ref = 1'b0;
                warn_ref     = WARN_SAT_CODE;
            end

            // action
            inf.sel_action_valid = 1'b1;
            inf.D                = Data'(act_ref);
            @(negedge clk);
            inf.sel_action_valid = 1'b0;
            inf.D                = '0;
            insert_random_gap();

            // date
            date_pack       = {date_in_month, date_in_day};
            inf.date_valid  = 1'b1;
            inf.D           = Data'(date_pack);
            @(negedge clk);
            inf.date_valid  = 1'b0;
            inf.D           = '0;
            insert_random_gap();

            // player_no
            inf.player_no_valid = 1'b1;
            cyc_latency         = 0;
            inf.D               = Data'(player_id_ref);
            @(negedge clk);
            inf.player_no_valid = 1'b0;
            inf.D               = '0;
            @(negedge clk);

            write_back_player_to_mem();
        end
    endtask

    // ------------------------------------------------------------
    // Level Up Pattern (D = 1)
    // ------------------------------------------------------------
    task pattern_levelup_task;
        bit          sat_flag,sat_any;
        int unsigned exp_need;
        logic [19:0] dMP, dHP, dATK, dDEF;
        logic [19:0] fMP, fHP, fATK, fDEF;
        logic [19:0] tmp20;

        logic [15:0] s0, s1, s2, s3;
        logic [15:0] m0, m1, m2, m3;
        logic [15:0] A0, A1, A2, A3;
        logic [15:0] delta_A0, delta_A1;
        logic [15:0] old_hp, old_mp, old_atk, old_def;
        logic [15:0] delta_hp16, delta_mp16, delta_atk16, delta_def16;
        logic [1:0]  idxA0, idxA1;
        logic        hasA1;
        begin
            case (lvup_round % 4)
                0: type_ref = TRAIN_A;
                1: type_ref = TRAIN_B;
                2: type_ref = TRAIN_C;
                default: type_ref = TRAIN_D;
            endcase

            case (lvup_round % 3)
                0: mode_ref = MODE_EZ;
                1: mode_ref = MODE_NORMALZ;
                default: mode_ref = MODE_HARDZ;
            endcase

            lvup_round++;

            rng_player.randomize();
            player_id_ref = rng_player.pid;

            load_player_from_mem();

            complete_ref = 1'b1;
            warn_ref     = WARN_NONE_CODE;
            sat_any      = 1'b0;

            exp_need = (mode_ref == MODE_EZ)      ? 4095  :
                       (mode_ref == MODE_NORMALZ) ? 16383 :
                       (mode_ref == MODE_HARDZ)   ? 32767 :
                                                   4095;

            if (attr_exp_ref < exp_need) begin
                complete_ref = 1'b0;
                warn_ref     = WARN_EXP_CODE;

                // action
                inf.sel_action_valid = 1'b1;
                inf.D                = Data'(act_ref);
                @(negedge clk);
                inf.sel_action_valid = 1'b0;
                inf.D                = '0;
                insert_random_gap();

                // type
                inf.type_valid = 1'b1;
                inf.D          = Data'(type_ref);
                @(negedge clk);
                inf.type_valid = 1'b0;
                inf.D          = '0;
                insert_random_gap();

                // mode
                inf.mode_valid = 1'b1;
                inf.D          = Data'(mode_ref);
                @(negedge clk);
                inf.mode_valid = 1'b0;
                inf.D          = '0;
                insert_random_gap();

                // player_no
                inf.player_no_valid = 1'b1;
                cyc_latency         = 0;
                inf.D               = Data'(player_id_ref);
                @(negedge clk);
                inf.player_no_valid = 1'b0;
                inf.D               = '0;
                @(negedge clk);
            end
            else begin
                dMP  = 20'd0;
                dHP  = 20'd0;
                dATK = 20'd0;
                dDEF = 20'd0;

                unique case (type_ref)
                    // TYPE A
                    TRAIN_A: begin
                        logic [18:0] sum_all;
                        logic [15:0] delta16;
                        sum_all = {3'b0, attr_mp_ref}  +
                                  {3'b0, attr_hp_ref}  +
                                  {3'b0, attr_atk_ref} +
                                  {3'b0, attr_def_ref};
                        delta16 = sum_all[18:3]; // /8
                        dMP  = {4'b0, delta16};
                        dHP  = {4'b0, delta16};
                        dATK = {4'b0, delta16};
                        dDEF = {4'b0, delta16};
                    end

                    // TYPE B
                    TRAIN_B: begin
                        old_hp  = attr_hp_ref;
                        old_mp  = attr_mp_ref;
                        old_atk = attr_atk_ref;
                        old_def = attr_def_ref;

                        if (old_mp < old_hp) begin
                            s0 = old_mp;  s1 = old_hp;
                        end
                        else begin
                            s0 = old_hp;  s1 = old_mp;
                        end

                        if (old_atk < old_def) begin
                            s2 = old_atk; s3 = old_def;
                        end
                        else begin
                            s2 = old_def; s3 = old_atk;
                        end

                        m0 = (s0 < s2) ? s0 : s2;
                        m2 = (s0 < s2) ? s2 : s0;

                        m1 = (s1 < s3) ? s1 : s3;
                        m3 = (s1 < s3) ? s3 : s1;

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

                        delta_A0 = A2 - A0;
                        delta_A1 = A3 - A1;

                        // idx: 3=MP, 2=HP, 1=ATK, 0=DEF
                        if      (old_mp  == A0) idxA0 = 2'b11;
                        else if (old_hp  == A0) idxA0 = 2'b10;
                        else if (old_atk == A0) idxA0 = 2'b01;
                        else                    idxA0 = 2'b00;

                        hasA1 = 1'b0;
                        idxA1 = 2'b00;

                        if (!hasA1 && (old_mp == A1) && (idxA0 != 2'b11)) begin
                            idxA1 = 2'b11; hasA1 = 1'b1;
                        end
                        if (!hasA1 && (old_hp == A1) && (idxA0 != 2'b10)) begin
                            idxA1 = 2'b10; hasA1 = 1'b1;
                        end
                        if (!hasA1 && (old_atk == A1) && (idxA0 != 2'b01)) begin
                            idxA1 = 2'b01; hasA1 = 1'b1;
                        end
                        if (!hasA1 && (old_def == A1) && (idxA0 != 2'b00)) begin
                            idxA1 = 2'b00; hasA1 = 1'b1;
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

                        dMP  = {4'b0, delta_mp16};
                        dHP  = {4'b0, delta_hp16};
                        dATK = {4'b0, delta_atk16};
                        dDEF = {4'b0, delta_def16};
                    end

                    // TYPE C
                    TRAIN_C: begin
                        logic [15:0] dmp16, dhp16, datk16, ddef16;
                        case (1'b1)
							(attr_mp_ref  < 16'd16383):  dmp16  = 16'd16383 - attr_mp_ref;
							default:                     dmp16  = 16'd0;
						endcase
						case (1'b1)
							(attr_hp_ref  < 16'd16383):  dhp16  = 16'd16383 - attr_hp_ref;
							default:                     dhp16  = 16'd0;
						endcase
						case (1'b1)
							(attr_atk_ref < 16'd16383):  datk16 = 16'd16383 - attr_atk_ref;
							default:                     datk16 = 16'd0;
						endcase
						case (1'b1)
							(attr_def_ref < 16'd16383):  ddef16 = 16'd16383 - attr_def_ref;
							default:                     ddef16 = 16'd0;
						endcase

                        dMP  = {4'b0, dmp16};
                        dHP  = {4'b0, dhp16};
                        dATK = {4'b0, datk16};
                        dDEF = {4'b0, ddef16};
                    end

                    // TYPE D
                    TRAIN_D: begin
                        dMP  = delta_d_fn({4'b0, attr_mp_ref});
                        dHP  = delta_d_fn({4'b0, attr_hp_ref});
                        dATK = delta_d_fn({4'b0, attr_atk_ref});
                        dDEF = delta_d_fn({4'b0, attr_def_ref});
                    end

                    default: begin
                        dMP  = 20'd0;
                        dHP  = 20'd0;
                        dATK = 20'd0;
                        dDEF = 20'd0;
                    end
                endcase

                // mode scale
                fMP  = apply_mode_fn(mode_ref, dMP );
                fHP  = apply_mode_fn(mode_ref, dHP );
                fATK = apply_mode_fn(mode_ref, dATK);
                fDEF = apply_mode_fn(mode_ref, dDEF);

                // MP
                tmp20        = sat_add16_fn({4'b0, attr_mp_ref}, fMP, sat_flag);
                attr_mp_ref  = tmp20[15:0];
                sat_any     |= sat_flag;
                // HP
                tmp20        = sat_add16_fn({4'b0, attr_hp_ref}, fHP, sat_flag);
                attr_hp_ref  = tmp20[15:0];
                sat_any     |= sat_flag;
                // ATK
                tmp20        = sat_add16_fn({4'b0, attr_atk_ref}, fATK, sat_flag);
                attr_atk_ref = tmp20[15:0];
                sat_any     |= sat_flag;
                // DEF
                tmp20        = sat_add16_fn({4'b0, attr_def_ref}, fDEF, sat_flag);
                attr_def_ref = tmp20[15:0];
                sat_any     |= sat_flag;

                if (sat_any) begin
                    complete_ref = 1'b0;
                    warn_ref     = WARN_SAT_CODE;
                end
                else begin
                    complete_ref = 1'b1;
                    warn_ref     = WARN_NONE_CODE;
                end

                // action
                inf.sel_action_valid = 1'b1;
                inf.D                = Data'(act_ref);
                @(negedge clk);
                inf.sel_action_valid = 1'b0;
                inf.D                = '0;
                insert_random_gap();

                // type
                inf.type_valid = 1'b1;
                inf.D          = Data'(type_ref);
                @(negedge clk);
                inf.type_valid = 1'b0;
                inf.D          = '0;
                insert_random_gap();

                // mode
                inf.mode_valid = 1'b1;
                inf.D          = Data'(mode_ref);
                @(negedge clk);
                inf.mode_valid = 1'b0;
                inf.D          = '0;
                insert_random_gap();

                // player_no
                inf.player_no_valid = 1'b1;
                cyc_latency         = 0;
                inf.D               = Data'(player_id_ref);
                @(negedge clk);
                inf.player_no_valid = 1'b0;
                inf.D               = '0;
                @(negedge clk);

                if (warn_ref != WARN_EXP_CODE)
                    write_back_player_to_mem();
            end
        end
    endtask

    // ------------------------------------------------------------
    // Battle Pattern (D = 2)
    // ------------------------------------------------------------
    task pattern_battle_task;
        bit        sat_exp, sat_mp, sat_atk, sat_def;
        bit        sat_any;
        int signed dmg_p, dmg_m;
        int signed hp_p_tmp, hp_m_tmp;
        logic [19:0] tmp20;
        begin
            rng_player.randomize();
            player_id_ref = rng_player.pid;

            rng_attr0.randomize(); mon_atk_ref = rng_attr0.val;
            rng_attr1.randomize(); mon_def_ref = rng_attr1.val;
            rng_attr2.randomize(); mon_hp_ref  = rng_attr2.val;

            load_player_from_mem();

            complete_ref = 1'b1;
            sat_any      = 1'b0;
            warn_ref     = WARN_NONE_CODE;

            if (attr_hp_ref == 16'd0) begin
                complete_ref = 1'b0;
                warn_ref     = WARN_HP_CODE;
            end
            else begin
                dmg_p = mon_atk_ref - attr_def_ref;
                dmg_m = attr_atk_ref - mon_def_ref;

                hp_p_tmp = (dmg_p > 0) ? (attr_hp_ref - dmg_p) : attr_hp_ref;
                hp_m_tmp = (dmg_m > 0) ? (mon_hp_ref - dmg_m)  : mon_hp_ref;

                if (hp_p_tmp > 0 && hp_m_tmp <= 0) begin
                    // Win
                    attr_hp_ref = (hp_p_tmp < 0)        ? 16'd0     :
								  (hp_p_tmp > 65535)    ? 16'hFFFF :
														  hp_p_tmp[15:0];

                    tmp20        = sat_add16_fn({4'b0, attr_exp_ref}, 20'(16'd2048), sat_exp);
                    attr_exp_ref = tmp20[15:0];

                    tmp20        = sat_add16_fn({4'b0, attr_mp_ref}, 20'(16'd2048), sat_mp);
                    attr_mp_ref  = tmp20[15:0];

                    sat_any     |= (sat_exp | sat_mp);
                end
                else if (hp_p_tmp <= 0) begin
                    // Loss
                    attr_hp_ref  = 16'd0;

                    tmp20        = sat_sub16_fn({4'b0, attr_exp_ref}, 20'(16'd2048), sat_exp);
                    attr_exp_ref = tmp20[15:0];

                    tmp20        = sat_sub16_fn({4'b0, attr_atk_ref}, 20'(16'd2048), sat_atk);
                    attr_atk_ref = tmp20[15:0];

                    tmp20        = sat_sub16_fn({4'b0, attr_def_ref}, 20'(16'd2048), sat_def);
                    attr_def_ref = tmp20[15:0];

                    sat_any     |= (sat_exp | sat_atk | sat_def);
                end
                else begin
                    // Tie
                    attr_hp_ref = (hp_p_tmp < 0)         ? 16'd0     :
								  (hp_p_tmp > 16'd65535) ? 16'hFFFF :
														   hp_p_tmp[15:0];
                end

                if (sat_any) begin
                    complete_ref = 1'b0;
                    warn_ref     = WARN_SAT_CODE;
                end
            end

            // action
            inf.sel_action_valid = 1'b1;
            inf.D                = Data'(act_ref);
            @(negedge clk);
            inf.sel_action_valid = 1'b0;
            inf.D                = '0;
            insert_random_gap();

            // player
            inf.player_no_valid = 1'b1;
            inf.D               = Data'(player_id_ref);
            @(negedge clk);
            inf.player_no_valid = 1'b0;
            inf.D               = '0;
            insert_random_gap();

            // monster atk
            inf.monster_valid = 1'b1;
            inf.D             = Data'(mon_atk_ref);
            @(negedge clk);
            inf.monster_valid = 1'b0;
            inf.D             = '0;
            insert_random_gap();

            // monster def
            inf.monster_valid = 1'b1;
            inf.D             = Data'(mon_def_ref);
            @(negedge clk);
            inf.monster_valid = 1'b0;
            inf.D             = '0;
            insert_random_gap();

            // monster HP
            inf.monster_valid = 1'b1;
            inf.D             = Data'(mon_hp_ref);
            cyc_latency       = 0;
            @(negedge clk);
            inf.monster_valid = 1'b0;
            inf.D             = '0;
            @(negedge clk);

            if (warn_ref != WARN_HP_CODE)
                write_back_player_to_mem();
        end
    endtask

    // ------------------------------------------------------------
    // Use Skill Pattern (D = 3)
    // ------------------------------------------------------------
    task pattern_use_skill_task;
        int  k;
        int  used_count;
        int unsigned mp_remain;

        logic [15:0] s0, s1, s2, s3;
        logic [15:0] m0, m1, m2, m3;
        logic [15:0] c0, c1, c2, c3;
        logic [16:0] sum1, sum2;
        logic [17:0] sum3, sum4;
        logic [18:0] diff4, diff3;
        logic [17:0] diff2;
        logic [16:0] diff1;
        begin
            rng_player.randomize();
            player_id_ref = rng_player.pid;

            rng_attr0.randomize(); skill_cost_ref[0] = rng_attr0.val;
            rng_attr1.randomize(); skill_cost_ref[1] = rng_attr1.val;
            rng_attr2.randomize(); skill_cost_ref[2] = rng_attr2.val;
            rng_attr3.randomize(); skill_cost_ref[3] = rng_attr3.val;

            load_player_from_mem();

            complete_ref = 1'b1;
            warn_ref     = WARN_NONE_CODE;

            // sort skill costs
            s0 = (skill_cost_ref[0] < skill_cost_ref[1]) ? skill_cost_ref[0] : skill_cost_ref[1];
            s1 = (skill_cost_ref[0] < skill_cost_ref[1]) ? skill_cost_ref[1] : skill_cost_ref[0];
            s2 = (skill_cost_ref[2] < skill_cost_ref[3]) ? skill_cost_ref[2] : skill_cost_ref[3];
            s3 = (skill_cost_ref[2] < skill_cost_ref[3]) ? skill_cost_ref[3] : skill_cost_ref[2];

            m0 = (s0 < s2) ? s0 : s2;
            m2 = (s0 < s2) ? s2 : s0;

            m1 = (s1 < s3) ? s1 : s3;
            m3 = (s1 < s3) ? s3 : s1;

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

            sum1 = {1'b0, c0};
            sum2 = {1'b0, c0} + {1'b0, c1};
            sum3 = {1'b0, c0} + {1'b0, c1} + {1'b0, c2};
            sum4 = {1'b0, c0} + {1'b0, c1} + {1'b0, c2} + {1'b0, c3};

            diff4 = {3'b0, attr_mp_ref} - {1'b0, sum4};
            diff3 = {3'b0, attr_mp_ref} - {1'b0, sum3};
            diff2 = {2'b0, attr_mp_ref} - {1'b0, sum2};
            diff1 = {1'b0, attr_mp_ref} - {1'b0, sum1};

            used_count = 0;
            mp_remain  = attr_mp_ref;

            if (!diff4[18]) begin
                used_count = 4;
                mp_remain  = diff4[15:0];
            end
            else if (!diff3[18]) begin
                used_count = 3;
                mp_remain  = diff3[15:0];
            end
            else if (!diff2[17]) begin
                used_count = 2;
                mp_remain  = diff2[15:0];
            end
            else if (!diff1[16]) begin
                used_count = 1;
                mp_remain  = diff1[15:0];
            end
            else begin
                used_count = 0;
                mp_remain  = attr_mp_ref;
            end

            case (used_count)
				0: begin
					complete_ref = 1'b0;
					warn_ref     = WARN_MP_CODE;
				end

				default: begin
					attr_mp_ref = mp_remain[15:0];
				end
			endcase

            // action
            inf.sel_action_valid = 1'b1;
            inf.D                = Data'(act_ref);
            @(negedge clk);
            inf.sel_action_valid = 1'b0;
            inf.D                = '0;
            insert_random_gap();

            // player_no
            inf.player_no_valid = 1'b1;
            inf.D               = Data'(player_id_ref);
            @(negedge clk);
            inf.player_no_valid = 1'b0;
            inf.D               = '0;
            insert_random_gap();

            // 4 skills
            for (k = 0; k < 4; k++) begin
				inf.MP_valid = 1'b1;
				inf.D        = Data'(skill_cost_ref[k]);

				case (k)
					0,1,2: begin
						@(negedge clk);
						inf.MP_valid = 1'b0;
						inf.D        = '0;
						insert_random_gap();
					end

					3: begin
						cyc_latency = 0;
						@(negedge clk);
						inf.MP_valid = 1'b0;
						inf.D        = '0;
						@(negedge clk);
					end
				endcase
			end

            if (warn_ref != WARN_MP_CODE)
                write_back_player_to_mem();
        end
    endtask

    // ------------------------------------------------------------
    // Check Inactive Pattern (D = 4)
    // ------------------------------------------------------------
    task pattern_inactive_task;
        int unsigned day_gap;
        logic [8:0]  dt_bundle;
        begin
            void'(rng_date.randomize());
            date_in_month = rng_date.dt.M;
            date_in_day   = rng_date.dt.D;

            void'(rng_player.randomize());
            player_id_ref = rng_player.pid;

            load_player_from_mem();

            complete_ref = 1'b1;
            warn_ref     = WARN_NONE_CODE;

            day_gap = day_diff_fn(
                          date_mem_month, date_mem_day,
                          date_in_month,  date_in_day
                      );

            case (1'b1)
			(day_gap > 90): begin
				complete_ref = 1'b0;
				warn_ref     = WARN_DATE_CODE;
			end

			default: begin
				complete_ref = 1'b1;
				warn_ref     = WARN_NONE_CODE;
			end
		    endcase

            // Action — Check Inactive
            inf.sel_action_valid = 1'b1;
            inf.D                = Data'(act_ref);
            @(negedge clk);
            inf.sel_action_valid = 1'b0;
            inf.D                = '0;
            insert_random_gap();

            dt_bundle       = {date_in_month, date_in_day};
            inf.date_valid  = 1'b1;
            inf.D           = Data'(dt_bundle);
            @(negedge clk);
            inf.date_valid  = 1'b0;
            inf.D           = '0;
            insert_random_gap();

            inf.player_no_valid = 1'b1;
            cyc_latency         = 0;
            inf.D               = Data'(player_id_ref);
            @(negedge clk);
            inf.player_no_valid = 1'b0;
            inf.D               = '0;
            @(negedge clk);
            insert_random_gap();
        end
    endtask

    // ------------------------------------------------------------
    // wait_out_valid / check_ans / random_delay / pass / fail
    // ------------------------------------------------------------
    task wait_out_valid;
        begin
            cyc_latency = 0;
            while (inf.out_valid !== 1'b1) begin
                cyc_latency += 1;
                @(negedge clk);
            end
            cyc_total += cyc_latency;
        end
    endtask

    task verify_response_task;
        begin
            ov_cycle_cnt = 0;
            while (inf.out_valid === 1'b1) begin
                if (ov_cycle_cnt == 0) begin
                    if ((inf.complete !== complete_ref) ||
                        (inf.warn_msg !== warn_ref)) begin

                        string action_name;
                        case (act_ref)
                            Login          : action_name = "Login";
                            Level_Up       : action_name = "Level-Up";
                            Battle         : action_name = "Battle";
                            Use_Skill      : action_name = "Use-Skill";
                            Check_Inactive : action_name = "Check-Inactive";
                            default        : action_name = "Unknown";
                        endcase

                        $display("------------------ FAIL: %s ------------------", action_name);
                        $display("expected_complete = %0d, actual_complete = %0d",
                                 complete_ref, inf.complete);
                        $display("expected_warn     = %0d, actual_warn     = %0d",
                                 warn_ref, inf.warn_msg);

                        $display("------------------------------------------------");
                        $display("[Inputs]");
                        $display("  action    = %0d", act_ref);
                        $display("  type      = %0d", type_ref);
                        $display("  mode      = %0d", mode_ref);
                        $display("  player_no = %0d", player_id_ref);

                        $display("[Date]");
                        $display("  input date  : %0d/%0d", date_in_month, date_in_day);
                        $display("  dram  date  : %0d/%0d", date_mem_month, date_mem_day);

                        $display("[Player Attr]");
                        $display("  EXP = %0d", attr_exp_ref);
                        $display("  MP  = %0d", attr_mp_ref);
                        $display("  HP  = %0d", attr_hp_ref);
                        $display("  ATK = %0d", attr_atk_ref);
                        $display("  DEF = %0d", attr_def_ref);

                        $display("[Monster Attr]");
                        $display("  ATK = %0d", mon_atk_ref);
                        $display("  DEF = %0d", mon_def_ref);
                        $display("  HP  = %0d", mon_hp_ref);

                        $display("[Skill MP Cost]");
                        $display("  S0 = %0d", skill_cost_ref[0]);
                        $display("  S1 = %0d", skill_cost_ref[1]);
                        $display("  S2 = %0d", skill_cost_ref[2]);
                        $display("  S3 = %0d", skill_cost_ref[3]);

                        $display("================================================");
                        $display("             Pattern FAIL — Stop               ");
                        $display("================================================");

                        report_fail_task();
                        $finish;
                    end
                end
                @(negedge clk);
                ov_cycle_cnt += 1;
            end
        end
    endtask
	
    task report_fail_task;
        begin
            $display("===================================================");
            $display("                    Wrong Answer!                  ");
            $display("===================================================");
        end
    endtask

    task insert_random_gap;
        begin
            rng_delay.randomize();
            repeat (rng_delay.gap) begin
                @(negedge clk);
            end
        end
    endtask
	
    task report_all_pass_task;
        begin
            $display("===================================================");
            $display("  Congratulations! All patterns passed!");
            $display("  Total execution cycles = %7d cycles", cyc_total);
            $display("===================================================");
            $finish;
        end
    endtask

endprogram
