param([string]$TopSource = 'rtl/top/nano4k_ntsc_hdmi.v',
      [string]$Label = 'current')
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path $PSScriptRoot -Parent
Push-Location $repoPath
$originalPath = $env:PATH
try {
    $suitePath = Join-Path $repoPath 'tools/vendor/keitark-tangnano/.tools/oss-cad-suite'
    $env:PATH = "$suitePath/bin;$suitePath/lib;$env:PATH"
    $testPath = Join-Path $repoPath 'build/recovery_hpll'
    New-Item -ItemType Directory -Force -Path $testPath | Out-Null
    $simPath = Join-Path $testPath "$Label.vvp"
    # Ignore unrelated unelaborated board primitives; see testbench scope.
    & "$suitePath/bin/iverilog.exe" -g2012 -i -s tb_ntsc_hpll -o $simPath `
        tb/tb_ntsc_hpll.v $TopSource rtl/cvbs/ntsc_color_decoder.v
    if ($LASTEXITCODE -ne 0) { throw 'HPLL test compilation failed' }
    & "$suitePath/bin/vvp.exe" $simPath 2>&1 |
        Tee-Object -FilePath (Join-Path $testPath "$Label.log")
    if ($LASTEXITCODE -ne 0) { throw 'HPLL regression failed; see log' }
} finally {
    $env:PATH = $originalPath
    Pop-Location
}
