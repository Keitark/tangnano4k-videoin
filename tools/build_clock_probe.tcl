set_device -name GW1NSR-4C GW1NSR-LV4CQN48PC7/I6
add_file -type verilog "rtl/clock/nano4k_usb_clocks.v"
add_file -type verilog "rtl/top/nano4k_usb_clock_probe.v"
add_file -type cst "constraints/nano4k_clock_probe.cst"
add_file -type sdc "constraints/nano4k_clock_probe.sdc"
set_option -synthesis_tool gowinsynthesis
set_option -top_module nano4k_usb_clock_probe
set_option -verilog_std v2001
set_option -use_mode_as_gpio 1
set_option -place_option 2
run all
