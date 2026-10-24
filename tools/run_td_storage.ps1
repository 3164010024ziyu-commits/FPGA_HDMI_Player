param([string]$TdRoot = 'D:/fpga', [switch]$Physical)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build/td'
$tdExe = Join-Path $TdRoot 'bin/td_commands_prompt.exe'
$tdScript = (Join-Path $PSScriptRoot 'run_td_storage.tcl').Replace('\', '/')
if (!(Test-Path -LiteralPath $tdExe)) { throw "TD executable not found: $tdExe" }
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
$sourceFiles = @(
    'rtl/storage/spi_byte_master.v', 'rtl/storage/sd_spi_reader.v',
    'rtl/storage/fat32_bmp_reader.v', 'rtl/storage/bmp_stream_decoder.v',
    'rtl/storage/storage_pipeline.v', 'rtl/storage/hx4s20c_storage_bringup.v',
    'constraints/hx4s20c_storage_bringup.adc', 'constraints/hx4s20c_storage_bringup.sdc',
    'project/td/Storage_Bringup.al', 'tools/run_td_storage.tcl',
    'tools/run_td_storage_pnr.tcl', 'tools/run_td_storage.ps1'
)
$sourceHashes = [ordered]@{}
foreach ($source in $sourceFiles) {
    $sourceHashes[$source] = (Get-FileHash -LiteralPath (Join-Path $repoRoot $source) -Algorithm SHA256).Hash.ToLower()
}
# This is a build input record, not a declaration that synthesis has passed.
$sourceHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $buildRoot 'source_hashes.json') -Encoding utf8
Push-Location -LiteralPath $buildRoot
try {
    & $tdExe $tdScript *> 'storage_build.log'
    $tdExitCode = $LASTEXITCODE
    Get-Content -LiteralPath 'storage_build.log' -Tail 16
    $tdLog = Get-Content -LiteralPath 'storage_build.log' -Raw
    if ($tdExitCode -ne 0 -or $tdLog -notmatch 'PASS_TD_SYNTHESIS' -or $tdLog -match 'RUN-\d+ ERROR:') {
        throw "TD synthesis failed. See $buildRoot/storage_build.log"
    }
    Write-Host "PASS TD synthesis. Reports: $buildRoot/storage/"
    if ($Physical) {
        $pnrScript = (Join-Path $PSScriptRoot 'run_td_storage_pnr.tcl').Replace('\', '/')
        & $tdExe $pnrScript *> 'storage_pnr.log'
        $pnrExitCode = $LASTEXITCODE
        Get-Content -LiteralPath 'storage_pnr.log' -Tail 16
        $pnrLog = Get-Content -LiteralPath 'storage_pnr.log' -Raw
        if ($pnrExitCode -ne 0 -or $pnrLog -notmatch 'PASS_TD_PNR:' -or $pnrLog -match 'RUN-\d+ ERROR:') {
            throw "TD physical build failed. See $buildRoot/storage_pnr.log"
        }
        Write-Host "PASS TD place/route and candidate bitstream. Reports: $buildRoot/storage/"
    }
    foreach ($source in $sourceFiles) {
        if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $source) -Algorithm SHA256).Hash.ToLower() -ne $sourceHashes[$source]) {
            throw "Source changed during build: $source. Rebuild before publishing results."
        }
    }
    if ($Physical) {
        $sourceHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $buildRoot 'physical_source_hashes.json') -Encoding utf8
    }
} finally {
    Pop-Location
}
