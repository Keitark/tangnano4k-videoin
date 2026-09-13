create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
# Handshaken status snapshot. Tokens cross two FFs; held_data is captured only
# after the returned ACK has crossed two pixel-clock FFs. Source retains data
# until a new request. Bound the bundle to ONE pixel period (< two periods of
# available settling); do not blanket-false-path the status data bus.
set_false_path -to [get_pins {core/status_snapshot/request_meta_s0/D core/status_snapshot/ack_meta_s0/D}]
set_max_delay -from [get_pins {core/status_snapshot/held_data*_s0/Q}] -to [get_pins {core/status_snapshot/dst_data*_s0/D}] 39.682
# Wrapper-prefixed first-stage synchronizer exceptions. Bus page metadata is
# held stable throughout publication and adopted alongside the token at vblank.
# color_meta -> color_sync is the same two-stage, single-bit status CDC as
# lock_meta -> lock_sync. Do not exempt color_sync or the decoding datapath.
set_false_path -to [get_pins {core/hdmi/line_toggle_meta_s0/D core/hdmi/bank_meta_s0/D core/hdmi/lock_meta_s0/D core/hdmi/color_meta_s0/D}]
set_false_path -to [get_pins {core/hdmi/mode_meta_0_s0/D core/hdmi/mode_meta_1_s0/D core/runtime_probe.controller/ack_meta_s0/D}]
set_false_path -to [get_pins {core/hdmi/phase_error_meta_8_s0/D core/hdmi/phase_error_meta_7_s0/D core/hdmi/phase_error_meta_6_s0/D core/hdmi/phase_error_meta_5_s0/D core/hdmi/phase_error_meta_4_s0/D core/hdmi/phase_error_meta_3_s0/D core/hdmi/phase_error_meta_2_s0/D core/hdmi/phase_error_meta_1_s0/D core/hdmi/phase_error_meta_0_s0/D core/hdmi/period_meta_5_s0/D core/hdmi/period_meta_4_s0/D core/hdmi/period_meta_3_s0/D core/hdmi/period_meta_2_s0/D core/hdmi/period_meta_1_s0/D core/hdmi/period_meta_0_s0/D}]
set_false_path -to [get_pins {core/hdmi/sync_width_meta_7_s0/D core/hdmi/sync_width_meta_6_s0/D core/hdmi/sync_width_meta_5_s0/D core/hdmi/sync_width_meta_4_s0/D core/hdmi/sync_width_meta_3_s0/D core/hdmi/sync_width_meta_2_s0/D core/hdmi/sync_width_meta_1_s0/D core/hdmi/sync_width_meta_0_s0/D}]
set_false_path -to [get_pins {core/hdmi/black_level_meta_7_s0/D core/hdmi/black_level_meta_6_s0/D core/hdmi/black_level_meta_5_s0/D core/hdmi/black_level_meta_4_s0/D core/hdmi/black_level_meta_3_s0/D core/hdmi/black_level_meta_2_s0/D core/hdmi/black_level_meta_1_s0/D core/hdmi/black_level_meta_0_s0/D core/hdmi/luma_level_meta_7_s0/D core/hdmi/luma_level_meta_6_s0/D core/hdmi/luma_level_meta_5_s0/D core/hdmi/luma_level_meta_4_s0/D core/hdmi/luma_level_meta_3_s0/D core/hdmi/luma_level_meta_2_s0/D core/hdmi/luma_level_meta_1_s0/D core/hdmi/luma_level_meta_0_s0/D}]
set_false_path -to [get_pins {core/sync_meta_s0/D}]
set_false_path -to [get_pins {core/hdmi/serializers[0]/RESET core/hdmi/serializers[1]/RESET core/hdmi/serializers[2]/RESET}]
