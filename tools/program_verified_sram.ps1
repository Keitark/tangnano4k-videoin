param([Parameter(Mandatory=$true)][string]$BuildDirectory,
      [Parameter(Mandatory=$true)][string]$ExpectedHash,
      [Parameter(Mandatory=$true)][string]$EvidenceLog)
$ErrorActionPreference='Stop'
# Programmer resolves its --fsFile argument from its own working directory.
# Validate and pass an absolute path so gate checks and the write use one file.
$BuildDirectory=(Resolve-Path -LiteralPath $BuildDirectory).ProviderPath
$programmer=Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/vendor/sipeed_programmer_1.9.11.02_build2518/programmer1.9.11.02(build2518).Win64/Programmer/bin/programmer_cli.exe'
$imagePath=Join-Path $BuildDirectory 'impl/pnr/project.fs'
$rpt=Get-Content (Join-Path $BuildDirectory 'impl/pnr/project.rpt.txt') -Raw
$timing=Get-Content (Join-Path $BuildDirectory 'impl/pnr/project_tr_content.html') -Raw
Start-Transcript -Path $EvidenceLog -Force | Out-Null
try {
    Write-Output 'Sipeed Programmer 1.9.11.02 build 2518; SRAM only; JTAG 2.5MHz'
    $programmerHash=(Get-FileHash $programmer).Hash
    if($programmerHash -ne '0CBB56027B0DED80F92895C979A9B6D727BBC3E7CF000366B8EB07DA71876DD1'){throw 'Programmer hash mismatch'}
    $imageHash=(Get-FileHash $imagePath).Hash
    if($imageHash -ne $ExpectedHash){throw 'Image hash mismatch'}
    Write-Output "programmer_sha256=$programmerHash image_sha256=$imageHash"
    if($rpt -notmatch '<Part Number>: GW1NSR-LV4CQN48PC6/I5'){throw 'Wrong target grade'}
    foreach($check in @('Setup','Hold')) {
        if($timing -notmatch "Numbers of $check Violated Endpoints</td>\s*<td>0</td>"){throw "$check timing gate failed"}
    }
    $dev=Get-PnpDevice -PresentOnly
    $required=@(
        @{Name='USB Serial Converter A'; Id='^USB\\VID_0403&PID_6010&MI_00\\'; Inf='oem69.inf'},
        @{Name='USB Serial Converter B'; Id='^USB\\VID_0403&PID_6010&MI_01\\'; Inf='oem69.inf'},
        @{Name='USB Serial Port (COM8)'; Id='^FTDIBUS\\VID_0403\+PID_6010\+FACTORYAIOT_PRO&2\\'; Inf='oem96.inf'}
    )
    $drivers=Get-CimInstance Win32_PnPSignedDriver
    foreach($spec in $required) {
        $d=@($dev | Where-Object {$_.FriendlyName -eq $spec.Name -and $_.InstanceId -match $spec.Id})
        if($d.Count -ne 1 -or $d[0].Status -ne 'OK'){throw "Device gate failed: $($spec.Name)"}
        $driver=@($drivers | Where-Object {$_.DeviceID -eq $d[0].InstanceId})
        if($driver.Count -ne 1 -or $driver[0].InfName -ne $spec.Inf -or $driver[0].DriverVersion -ne '2.12.36.20'){throw 'Driver gate failed'}
        Write-Output "$($spec.Name): $($d[0].InstanceId) $($driver[0].InfName) $($driver[0].DriverVersion) OK"
    }
    if((Get-ScheduledTask -TaskName UsbMonitor).State -ne 'Disabled'){throw 'UsbMonitor is not disabled'}
    $owners=tasklist.exe /m ftd2xx.dll
    if($LASTEXITCODE -ne 0 -or ($owners -match '\.exe\s')){throw "FTDI channel may be owned: $owners"}
    Write-Output 'UsbMonitor Disabled; no ftd2xx.dll process owners'
    $cables=& $programmer --scan-cables F
    $cables | Write-Output
    if($LASTEXITCODE -ne 0 -or ($cables -join ' ') -notmatch 'USB Debugger A/0/'){throw 'Cable discovery failed'}
    $scan=& $programmer --cable-index 4 --channel 0 --frequency 2.5MHz --scan
    $scan | Write-Output
    if($LASTEXITCODE -ne 0 -or ($scan -join ' ') -notmatch '0x0100981B' -or ($scan -join ' ') -notmatch '1 device\(s\) found'){throw 'JTAG identity gate failed'}
    & $programmer --cable-index 4 --channel 0 --frequency 2.5MHz --device GW1NSR-4C --operation_index 16 --fsFile $imagePath 2>&1 |
        Where-Object {$_ -notmatch '^Programming\.\.'}
    if($LASTEXITCODE -ne 0){throw 'SRAM programming failed'}
} finally {
    Stop-Transcript | Out-Null
}
