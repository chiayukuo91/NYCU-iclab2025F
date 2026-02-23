`ifndef USERTYPE
`define USERTYPE

package usertype;

typedef enum logic  [2:0] { Login	        = 3'd0,
                            Level_Up	    = 3'd1,
							Battle          = 3'd2,
                            Use_Skill       = 3'd3,
                            Check_Inactive  = 3'd4
							}  Action ;

typedef enum logic  [2:0] { No_Warn       		    = 3'b000, 
                            Date_Warn               = 3'b001, 
							Exp_Warn                = 3'b010,
                            HP_Warn                 = 3'b011,
                            MP_Warn                 = 3'b100,
                            Saturation_Warn         = 3'b101 
                            }  Warn_Msg ;

typedef enum logic  [1:0] { Type_A = 2'd0,
							Type_B = 2'd1,
							Type_C = 2'd2,
							Type_D = 2'd3
                            }  Training_Type; 

typedef enum logic  [1:0]	{ Easy   = 2'b00,
							  Normal = 2'b01,
							  Hard   = 2'b10
                            } Mode ;

typedef logic [15:0] Attribute; //Flowers
typedef logic [3:0] Month;
typedef logic [4:0] Day;
typedef logic [7:0] Player_No;

typedef struct packed {
    Month M;
    Day D;
} Date;

typedef struct packed {
    Attribute Exp;
    Attribute MP;
    Attribute HP;
    Attribute Attack;
    Attribute Defense;
    Month M;
    Day D;
} Player_Info;


typedef union packed{ 
    Action       [47:0] d_act;        // 3
    Training_Type[71:0] d_type;       // 2
    Mode         [71:0] d_mode;       // 2
    Date         [15:0] d_date;       // 9
    Player_No    [17:0] d_player_no;  // 8
    Attribute    [8:0]  d_attribute;  // 16
} Data; //144

//################################################## Don't revise the code above

//#################################
// Type your user define type here
//#################################

typedef struct packed {
    Attribute    HP;         
    logic [7:0]  login_M; 
    logic [7:0]  login_D;    
    Attribute    Attack;     
    Attribute    Defense;    
    Attribute    Exp;      
    Attribute    MP;    
} Player_DRAM;              

typedef struct packed {
    Attribute HP;
    Attribute MP;
    Attribute Attack;
    Attribute Defense;
} Attribute_Group;

typedef struct packed {
    Attribute A0;  // smallest
    Attribute A1;  
    Attribute A2;  
    Attribute A3;  // Biggest
} Attribute_Sorted;

typedef struct packed {
    Attribute Attack;
    Attribute Defense;
    Attribute HP;
} Monster_Info;

typedef logic [8:0] Day_Count;

//################################################## Don't revise the code below
endpackage

import usertype::*; //import usertype into $unit

`endif
