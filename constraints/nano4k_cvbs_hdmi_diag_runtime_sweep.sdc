create_clock -name clk_27m -period 37.037 -waveform {0 18.518} [get_ports {clk_27m}]

# First stages of explicit asynchronous status synchronizers into HDMI pixels.
# reconstructed_level can saturate to 255, so bits 1..7 all remain live even
# with LEVEL_SHIFT=2. Bit 0 is optimized away by this diagnostic datapath.
set_false_path -to [get_pins {hdmi/level_meta_1_s0/D hdmi/level_meta_2_s0/D hdmi/level_meta_3_s0/D hdmi/level_meta_4_s0/D hdmi/level_meta_5_s0/D hdmi/level_meta_6_s0/D hdmi/level_meta_7_s0/D hdmi/activity_meta_s0/D hdmi/lock_meta_s0/D hdmi/low_meta_s0/D}]
set_false_path -to [get_pins {hdmi/reference_meta_*_s0/D}]

# First stage of the pixel-reset to 126 MHz OSER10 reset synchronizer.
set_false_path -to [get_pins {serializer_reset_pipe_0_s0/D}]
