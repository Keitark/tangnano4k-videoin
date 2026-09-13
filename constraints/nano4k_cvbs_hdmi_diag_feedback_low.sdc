create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]

set_false_path -to [get_pins {u_probe/hdmi/level_meta_1_s0/D u_probe/hdmi/level_meta_2_s0/D u_probe/hdmi/level_meta_3_s0/D u_probe/hdmi/level_meta_4_s0/D u_probe/hdmi/level_meta_5_s0/D u_probe/hdmi/level_meta_6_s0/D u_probe/hdmi/level_meta_7_s0/D u_probe/hdmi/activity_meta_s0/D u_probe/hdmi/lock_meta_s0/D u_probe/hdmi/low_meta_s0/D}]
