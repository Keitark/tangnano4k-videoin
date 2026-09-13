set repo_root [file normalize [file join [file dirname [info script]] ..]]
set build_root [file join $repo_root build cvbs_sync_detector_c6]

file mkdir $build_root
cd $build_root

set_device -name GW1NSR-4C GW1NSR-LV4CQN48PC6/I5
add_file -type verilog [file join $repo_root rtl cvbs cvbs_sync_detector.v]
add_file -type sdc [file join $repo_root constraints cvbs_sync_detector.sdc]
set_option -synthesis_tool gowinsynthesis
set_option -top_module cvbs_sync_detector
set_option -verilog_std v2001

# Synthesis only: this feasibility core deliberately has no package-pin
# allocation and must not produce a programmable image.
run syn
