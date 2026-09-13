set repo_root [file normalize [file join [file dirname [info script]] ..]]

set_device -name GW1NSR-4C GW1NSR-LV4CQN48PC6/I5
add_file -type verilog [file join $repo_root rtl clock nano4k_usb_clocks.v]
add_file -type verilog [file join $repo_root rtl top nano4k_usb_clock_probe.v]
add_file -type cst [file join $repo_root constraints nano4k_clock_probe.cst]
add_file -type sdc [file join $repo_root constraints nano4k_clock_probe.sdc]
set_option -synthesis_tool gowinsynthesis
set_option -top_module nano4k_usb_clock_probe
set_option -verilog_std v2001
set_option -use_mode_as_gpio 1
set_option -place_option 2
run all
