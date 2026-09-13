$ErrorActionPreference='Stop'
$repoPath=Split-Path $PSScriptRoot -Parent
$suitePath=Join-Path $repoPath 'tools/vendor/keitark-tangnano/.tools/oss-cad-suite'
$savedPath=$env:PATH
Push-Location $repoPath
try {
    $env:PATH="$suitePath/bin;$suitePath/lib;$env:PATH"
    $outPath=Join-Path $repoPath 'build/resolution_tests'
    New-Item -ItemType Directory -Force -Path $outPath | Out-Null
    $sources=@('rtl/top/nano4k_ntsc_hdmi.v','rtl/cvbs/ntsc_color_decoder.v',
        'rtl/cvbs/ntsc_field_sync.v','rtl/video/runtime_video_probe.v','rtl/video/video_status_snapshot.v',
        'rtl/hdmi/hdmi_ntsc_line_tx.v','rtl/hdmi/svo_tmds.v')
    foreach($width in @(128,160)) {
        $outFile=Join-Path $outPath "store-$width.vvp"
        & "$suitePath/bin/iverilog.exe" -g2012 -s tb_ntsc_frame_store `
            -P "tb_ntsc_frame_store.DEPTH=$($width*120*2)" -o $outFile `
            tb/tb_ntsc_frame_store.v rtl/video/ntsc_lowres_frame_store.v
        if($LASTEXITCODE -ne 0){throw 'Memory compile failed'}
        & "$suitePath/bin/vvp.exe" $outFile
        if($LASTEXITCODE -ne 0){throw 'Memory test failed'}
        foreach($test in @('tb_ntsc_field_capture','tb_hdmi_probe_handoff')) {
            $outFile=Join-Path $outPath "$test-$width.vvp"
            & "$suitePath/bin/iverilog.exe" -g2012 -i -s $test -P "$test.FRAME_WIDTH=$width" -o $outFile "tb/$test.v" @sources
            if($LASTEXITCODE -ne 0){throw "Compile failed: $test width=$width"}
            & "$suitePath/bin/vvp.exe" $outFile
            if($LASTEXITCODE -ne 0){throw "Test failed: $test width=$width"}
        }
        foreach($once in @(0,1)) {
            $outFile=Join-Path $outPath "runtime-$width-$once.vvp"
            & "$suitePath/bin/iverilog.exe" -g2012 -s tb_runtime_video_probe `
                -P "tb_runtime_video_probe.BANK_PIXELS=$($width*120)" `
                -P "tb_runtime_video_probe.CYCLE_ONCE=$once" -o $outFile `
                tb/tb_runtime_video_probe.v rtl/video/runtime_video_probe.v
            if($LASTEXITCODE -ne 0){throw 'Runtime compile failed'}
            & "$suitePath/bin/vvp.exe" $outFile
            if($LASTEXITCODE -ne 0){throw "Runtime test failed: width=$width once=$once"}
        }
    }
} finally {
    $env:PATH=$savedPath
    Pop-Location
}
