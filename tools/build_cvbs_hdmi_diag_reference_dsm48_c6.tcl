set repo_root [file normalize [file join [file dirname [info script]] ..]]
set build_root [file join $repo_root build cvbs_hdmi_diag_reference_dsm48_c6]
file mkdir $build_root
cd $build_root

set_device -name GW1NSR-4C GW1NSR-LV4CQN48PC6/I5
add_file -type verilog [file join $repo_root rtl clock nano4k_cvbs_hdmi_clocks.v]
add_file -type verilog [file join $repo_root rtl cvbs delta_modulator_core.v]
add_file -type verilog [file join $repo_root rtl cvbs lvds_delta_adc.v]
add_file -type verilog [file join $repo_root rtl cvbs adc_activity_monitor.v]
add_file -type verilog [file join $repo_root rtl cvbs cvbs_sync_detector.v]
add_file -type verilog [file join $repo_root rtl hdmi svo_tmds.v]
add_file -type verilog [file join $repo_root rtl hdmi hdmi_diag_tx.v]
add_file -type verilog [file join $repo_root rtl top nano4k_cvbs_hdmi_diag_feedback_high.v]
add_file -type verilog [file join $repo_root rtl top nano4k_cvbs_hdmi_diag_reference_dsm48.v]
add_file -type cst [file join $repo_root constraints nano4k_cvbs_hdmi_diag.cst]
add_file -type sdc [file join $repo_root constraints nano4k_cvbs_hdmi_diag_feedback_low.sdc]

set_option -synthesis_tool gowinsynthesis
set_option -top_module nano4k_cvbs_hdmi_diag_reference_dsm48
set_option -verilog_std v2001
set_option -use_mode_as_gpio 1
set_option -place_option 2
run all
