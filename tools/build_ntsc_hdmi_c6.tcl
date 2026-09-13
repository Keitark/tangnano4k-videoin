set repo_root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(NTSC_RAW_SNAPSHOT)] && [info exists ::env(NTSC_RUNTIME_PROBE)]} {
    error "Choose only one diagnostic: NTSC_RAW_SNAPSHOT or NTSC_RUNTIME_PROBE"
}
set build_root [file join $repo_root build ntsc_hdmi_c6]
if {[info exists ::env(NTSC_BUILD_ROOT)]} {
    set build_root [file normalize $::env(NTSC_BUILD_ROOT)]
}
file mkdir $build_root
cd $build_root

set_device -name GW1NSR-4C GW1NSR-LV4CQN48PC6/I5
add_file -type verilog [file join $repo_root rtl clock nano4k_cvbs_hdmi_clocks.v]
add_file -type verilog [file join $repo_root rtl cvbs delta_modulator_core.v]
add_file -type verilog [file join $repo_root rtl cvbs lvds_delta_adc.v]
add_file -type verilog [file join $repo_root rtl cvbs adc_level_iir.v]
add_file -type verilog [file join $repo_root rtl cvbs cvbs_sync_detector.v]
add_file -type verilog [file join $repo_root rtl cvbs ntsc_field_sync.v]
add_file -type verilog [file join $repo_root rtl cvbs ntsc_color_decoder.v]
add_file -type verilog [file join $repo_root rtl cvbs ntsc_chroma_fir.v]
add_file -type verilog [file join $repo_root rtl video ntsc_line_store.v]
add_file -type verilog [file join $repo_root rtl video ntsc_lowres_frame_store.v]
add_file -type verilog [file join $repo_root rtl video runtime_video_probe.v]
add_file -type verilog [file join $repo_root rtl video video_status_snapshot.v]
add_file -type verilog [file join $repo_root rtl video ntsc_three_line_queue.v]
add_file -type verilog [file join $repo_root rtl hdmi hdmi_three_line_tx.v]
add_file -type verilog [file join $repo_root rtl hdmi svo_tmds.v]
add_file -type verilog [file join $repo_root rtl hdmi hdmi_ntsc_line_tx.v]
add_file -type verilog [file join $repo_root rtl top nano4k_ntsc_hdmi.v]
add_file -type cst [file join $repo_root constraints nano4k_ntsc_hdmi.cst]
if {[info exists ::env(NTSC_RUNTIME_PROBE)]} {
    if {[string match "line320*" $::env(NTSC_RUNTIME_PROBE)]} {
        add_file -type sdc [file join $repo_root constraints nano4k_three_line.sdc]
    } else {
        add_file -type sdc [file join $repo_root constraints nano4k_runtime_probe.sdc]
    }
} elseif {[info exists ::env(NTSC_RAW_SNAPSHOT)]} {
    add_file -type sdc [file join $repo_root constraints nano4k_raw_snapshot.sdc]
} else {
    add_file -type sdc [file join $repo_root constraints nano4k_ntsc_hdmi.sdc]
}

set_option -synthesis_tool gowinsynthesis
set_option -top_module nano4k_ntsc_hdmi
if {[info exists ::env(NTSC_RUNTIME_PROBE)]} {
    if {$::env(NTSC_RUNTIME_PROBE) == "line320_cic2"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_cic2.v]
        set_option -top_module nano4k_line320_cic2
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "line320_matrix"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_matrix.v]
        set_option -top_module nano4k_line320_matrix
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "line320_color"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_color.v]
        set_option -top_module nano4k_line320_color
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "line320_hold"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_hold.v]
        set_option -top_module nano4k_line320_hold
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "line320_smooth"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_smooth.v]
        set_option -top_module nano4k_line320_smooth
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "line320_clean"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_clean.v]
        set_option -top_module nano4k_line320_clean
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "line320"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_line320_ab.v]
        set_option -top_module nano4k_line320_ab
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "color_ab"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_color_runtime_ab.v]
        set_option -top_module nano4k_color_runtime_ab
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "color_gray"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_color_transport_gray.v]
        set_option -top_module nano4k_color_transport_gray
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "color"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_color_trial.v]
        set_option -top_module nano4k_color_trial
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "burst"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_burst_probe.v]
        set_option -top_module nano4k_burst_probe
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "160"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_runtime_160.v]
        set_option -top_module nano4k_runtime_160
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "field_view"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_runtime_field_view.v]
        set_option -top_module nano4k_runtime_field_view
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "field"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_runtime_field.v]
        set_option -top_module nano4k_runtime_field
    } elseif {$::env(NTSC_RUNTIME_PROBE) == "2"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_runtime_wide.v]
        set_option -top_module nano4k_runtime_wide
    } else {
        add_file -type verilog [file join $repo_root rtl top nano4k_runtime_probe.v]
        set_option -top_module nano4k_runtime_probe
    }
}
if {[info exists ::env(NTSC_RAW_SNAPSHOT)]} {
    if {$::env(NTSC_RAW_SNAPSHOT) == "2"} {
        add_file -type verilog [file join $repo_root rtl top nano4k_raw_pattern.v]
        set_option -top_module nano4k_raw_pattern
    } else {
        add_file -type verilog [file join $repo_root rtl top nano4k_raw_snapshot.v]
        set_option -top_module nano4k_raw_snapshot
    }
}
set_option -verilog_std v2001
set_option -use_mode_as_gpio 1
set_option -place_option 2
run all
