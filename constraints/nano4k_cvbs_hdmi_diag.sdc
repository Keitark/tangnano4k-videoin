create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]

# The diagnostic values cross into the HDMI pixel domain through explicit
# two-register synchronizers. Generated clocks are not addressable when Gowin
# parses this SDC, so constrain only the D pins of the first-stage registers.
set_false_path -to [get_pins {hdmi/level_meta_*_s0/D}]
set_false_path -to [get_pins {hdmi/activity_meta_s0/D hdmi/lock_meta_s0/D hdmi/low_meta_s0/D}]
set_false_path -to [get_pins {hdmi/reference_meta_*_s0/D}]
set_false_path -to [get_pins {hdmi/threshold_meta_*_s0/D}]

# First stage of the pixel-reset to 126 MHz OSER10 reset synchronizer.
set_false_path -to [get_pins {serializer_reset_pipe_0_s0/D}]
