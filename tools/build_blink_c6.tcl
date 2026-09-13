set repo_root [file normalize [file join [file dirname [info script]] ..]]
set build_root [file join $repo_root build blink_c6]

file mkdir $build_root
cd $build_root

set_device -name GW1NSR-4C GW1NSR-LV4CQN48PC6/I5
add_file -type verilog [file join $repo_root rtl top nano4k_blink.v]
add_file -type cst [file join $repo_root constraints nano4k_blink.cst]
add_file -type sdc [file join $repo_root constraints nano4k_blink.sdc]
set_option -synthesis_tool gowinsynthesis
set_option -top_module nano4k_blink
set_option -verilog_std v2001
set_option -use_mode_as_gpio 1
run all
