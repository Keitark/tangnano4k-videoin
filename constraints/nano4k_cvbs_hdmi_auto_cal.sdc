create_clock -name clk_27m -period 37.037 -waveform {0 18.518} [get_ports {clk_27m}]

# First stages of explicit asynchronous status synchronizers into HDMI pixels.
set_false_path -to [get_pins {hdmi/level_meta_*_s0/D}]
set_false_path -to [get_pins {hdmi/activity_meta_s0/D hdmi/lock_meta_s0/D hdmi/low_meta_s0/D}]
set_false_path -to [get_pins {hdmi/reference_meta_*_s0/D}]
set_false_path -to [get_pins {hdmi/threshold_meta_*_s0/D}]

# First stage of the pixel-reset to 126 MHz OSER10 reset synchronizer.
set_false_path -to [get_pins {serializer_reset_pipe_0_s0/D}]
