###############################################################
#  CHIP.io  
###############################################################

(globals
    version = 3
    space   = 31
    io_order = default
)

(iopad
    (top
        (inst name="VDDC0"   place_status=placed)
        (inst name="GNDC0"   place_status=placed)
        (inst name="VDDP0"   place_status=placed)
        (inst name="GNDP0"   place_status=placed)

        (inst name="VDDC1"   place_status=placed)
        (inst name="GNDC1"   place_status=placed)
        (inst name="VDDP1"   place_status=placed)
        (inst name="GNDP1"   place_status=placed)

        ; ---- source / destination pins in the middle of top edge ----
        (inst name="I_SRC0"  place_status=placed)
        (inst name="I_SRC1"  place_status=placed)
        (inst name="I_SRC2"  place_status=placed)
        (inst name="I_SRC3"  place_status=placed)

        (inst name="I_DST0"  place_status=placed)
        (inst name="I_DST1"  place_status=placed)
        (inst name="I_DST2"  place_status=placed)
        (inst name="I_DST3"  place_status=placed)

        (inst name="VDDC2"   place_status=placed)
        (inst name="GNDC2"   place_status=placed)
        (inst name="VDDP2"   place_status=placed)
        (inst name="GNDP2"   place_status=placed)
    )

    (left
        (inst name="VDDC3"      place_status=placed)
        (inst name="GNDC3"      place_status=placed)
        (inst name="VDDP3"      place_status=placed)
        (inst name="GNDP3"      place_status=placed)

        ; ---- clk / reset / in_valid + delay pins ----
        (inst name="I_CLK"      place_status=placed)
        (inst name="I_RST"      place_status=placed)
        (inst name="I_IN_VALID" place_status=placed)

        (inst name="I_DELAY0"   place_status=placed)
        (inst name="I_DELAY1"   place_status=placed)
        (inst name="I_DELAY2"   place_status=placed)
        (inst name="I_DELAY3"   place_status=placed)

        (inst name="VDDC4"      place_status=placed)
        (inst name="GNDC4"      place_status=placed)
        (inst name="VDDP4"      place_status=placed)
        (inst name="GNDP4"      place_status=placed)

        (inst name="VDDC5"      place_status=placed)
        (inst name="GNDC5"      place_status=placed)
        (inst name="VDDP5"      place_status=placed)
        (inst name="GNDP5"      place_status=placed)
    )

    (bottom
        (inst name="VDDC6"      place_status=placed)
        (inst name="GNDC6"      place_status=placed)
        (inst name="VDDP6"      place_status=placed)
        (inst name="GNDP6"      place_status=placed)

        ; ---- path + out_valid pins in the middle of edge ----
        (inst name="O_PATH0"    place_status=placed)
        (inst name="O_PATH1"    place_status=placed)
        (inst name="O_PATH2"    place_status=placed)
        (inst name="O_PATH3"    place_status=placed)
        (inst name="O_VALID"    place_status=placed)

        (inst name="VDDC7"      place_status=placed)
        (inst name="GNDC7"      place_status=placed)
        (inst name="VDDP7"      place_status=placed)
        (inst name="GNDP7"      place_status=placed)

        (inst name="VDDC8"      place_status=placed)
        (inst name="GNDC8"      place_status=placed)
        (inst name="VDDP8"      place_status=placed)
        (inst name="GNDP8"      place_status=placed)
    )

    (right
        (inst name="VDDC9"      place_status=placed)
        (inst name="GNDC9"      place_status=placed)
        (inst name="VDDP9"      place_status=placed)
        (inst name="GNDP9"      place_status=placed)

        ; ---- worst_delay[7:0]  ----
        (inst name="O_W_DELAY0" place_status=placed)
        (inst name="O_W_DELAY1" place_status=placed)
        (inst name="O_W_DELAY2" place_status=placed)
        (inst name="O_W_DELAY3" place_status=placed)
        (inst name="O_W_DELAY4" place_status=placed)
        (inst name="O_W_DELAY5" place_status=placed)
        (inst name="O_W_DELAY6" place_status=placed)
        (inst name="O_W_DELAY7" place_status=placed)

        (inst name="VDDC10"     place_status=placed)
        (inst name="GNDC10"     place_status=placed)
        (inst name="VDDP10"     place_status=placed)
        (inst name="GNDP10"     place_status=placed)

        (inst name="VDDC11"     place_status=placed)
        (inst name="GNDC11"     place_status=placed)
        (inst name="VDDP11"     place_status=placed)
        (inst name="GNDP11"     place_status=placed)
    )

    (topright
        (inst name="topright"   cell="CORNERD")
    )
    (topleft
        (inst name="topleft"    cell="CORNERD")
    )
    (bottomright
        (inst name="bottomright" cell="CORNERD")
    )
    (bottomleft
        (inst name="bottomleft"  cell="CORNERD")
    )
)
