create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]

# Explicit two-register synchronizers terminate every decoder-to-HDMI status
# crossing. Constrain only the first-stage D pins; all functional logic remains
# timed in its source or destination domain.
set_false_path -to [get_pins {hdmi/line_toggle_meta_s0/D hdmi/bank_meta_s0/D hdmi/lock_meta_s0/D}]

# Stable, line-rate HPLL diagnostic buses cross only for on-screen telemetry.
# Constrain their first-stage synchronizer D pins; the second stages remain
# normally timed in the HDMI pixel domain.
set_false_path -to [get_pins {hdmi/phase_error_meta_8_s0/D hdmi/phase_error_meta_7_s0/D hdmi/phase_error_meta_6_s0/D hdmi/phase_error_meta_5_s0/D hdmi/phase_error_meta_4_s0/D hdmi/phase_error_meta_3_s0/D hdmi/phase_error_meta_2_s0/D hdmi/phase_error_meta_1_s0/D hdmi/phase_error_meta_0_s0/D hdmi/period_meta_5_s0/D hdmi/period_meta_4_s0/D hdmi/period_meta_3_s0/D hdmi/period_meta_2_s0/D hdmi/period_meta_1_s0/D hdmi/period_meta_0_s0/D}]
set_false_path -to [get_pins {hdmi/sync_width_meta_7_s0/D hdmi/sync_width_meta_6_s0/D hdmi/sync_width_meta_5_s0/D hdmi/sync_width_meta_4_s0/D hdmi/sync_width_meta_3_s0/D hdmi/sync_width_meta_2_s0/D hdmi/sync_width_meta_1_s0/D hdmi/sync_width_meta_0_s0/D}]
set_false_path -to [get_pins {hdmi/black_level_meta_7_s0/D hdmi/black_level_meta_6_s0/D hdmi/black_level_meta_5_s0/D hdmi/black_level_meta_4_s0/D hdmi/black_level_meta_3_s0/D hdmi/black_level_meta_2_s0/D hdmi/black_level_meta_1_s0/D hdmi/black_level_meta_0_s0/D hdmi/luma_level_meta_7_s0/D hdmi/luma_level_meta_6_s0/D hdmi/luma_level_meta_5_s0/D hdmi/luma_level_meta_4_s0/D hdmi/luma_level_meta_3_s0/D hdmi/luma_level_meta_2_s0/D hdmi/luma_level_meta_1_s0/D hdmi/luma_level_meta_0_s0/D}]

# First stage of the qualified-sync crossing from the 108 MHz ADC domain into
# the 13.5 MHz sample domain. The following stage remains normally timed.
set_false_path -to [get_pins {sync_meta_s0/D}]

# The serializer reset is asynchronously asserted but released by an
# eight-stage pipeline clocked by the serializer clock itself. The OSER10 hard
# macro recovery check does not recognize that synchronous deassertion chain.
set_false_path -to [get_pins {hdmi/serializers[0]/RESET hdmi/serializers[1]/RESET hdmi/serializers[2]/RESET}]
