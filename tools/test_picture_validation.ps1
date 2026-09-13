$ErrorActionPreference='Stop'
$repoPath=Split-Path $PSScriptRoot -Parent
$suitePath=Join-Path $repoPath 'tools/vendor/keitark-tangnano/.tools/oss-cad-suite'
$savedPath=$env:PATH
Push-Location $repoPath
try {
    $env:PATH="$suitePath/bin;$suitePath/lib;$env:PATH"
    $outPath=Join-Path $repoPath 'build/resolution_tests'
    New-Item -ItemType Directory -Force -Path $outPath | Out-Null
    function Test-Bench($name, $sources, $parameters=@()) {
        $outFile=Join-Path $outPath "$name-validated.vvp"
        & "$suitePath/bin/iverilog.exe" -g2012 -i -s $name @parameters -o $outFile "tb/$name.v" @sources
        if($LASTEXITCODE -ne 0){throw "Compile failed: $name"}
        & "$suitePath/bin/vvp.exe" $outFile
        if($LASTEXITCODE -ne 0){throw "Test failed: $name"}
    }
    foreach($name in @('tb_picture_validation','tb_probe_empty_frame_audit')) {
        Test-Bench $name @('rtl/video/runtime_video_probe.v')
    }
    Test-Bench 'tb_video_status_snapshot' @('rtl/video/video_status_snapshot.v')
    Test-Bench 'tb_runtime_video_probe' @('rtl/video/runtime_video_probe.v') @(
        '-P','tb_runtime_video_probe.BANK_PIXELS=9600','-P','tb_runtime_video_probe.DATA_BITS=8',
        '-P','tb_runtime_video_probe.CYCLE_ONCE=1')
    $sources=@('rtl/top/nano4k_ntsc_hdmi.v','rtl/cvbs/ntsc_color_decoder.v',
        'rtl/cvbs/ntsc_field_sync.v','rtl/video/runtime_video_probe.v',
        'rtl/video/video_status_snapshot.v','rtl/hdmi/hdmi_ntsc_line_tx.v','rtl/hdmi/svo_tmds.v')
    Test-Bench 'tb_ntsc_field_capture' $sources @('-P','tb_ntsc_field_capture.FRAME_WIDTH=80',
        '-P','tb_ntsc_field_capture.RUNTIME_PROBE=1')
    Test-Bench 'tb_color_trial' $sources
    Test-Bench 'tb_color_runtime_ab' @('rtl/cvbs/ntsc_color_decoder.v')
    foreach($clean in @(1,2,3,4)) {
        foreach($name in @('tb_ntsc_chroma_fir','tb_ntsc_clean_colors')) {
            Test-Bench $name @('rtl/cvbs/ntsc_color_decoder.v','rtl/cvbs/ntsc_chroma_fir.v') @('-P',"$name.CLEAN=$clean")
        }
    }
} finally {
    $env:PATH=$savedPath
    Pop-Location
}
