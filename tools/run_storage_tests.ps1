param(
    [string]$SimulatorBin = '',
    [string]$PythonExe = 'python'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$previousLocation = Get-Location
function SimulatorTool([string]$name) {
    if ($SimulatorBin) { return Join-Path $SimulatorBin "$name.exe" }
    return $name
}
try {
    Set-Location -LiteralPath $repoRoot
    & $PythonExe tools/make_storage_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Vector generation failed' }
    New-Item -ItemType Directory -Force -Path build/storage | Out-Null
    if (!(Test-Path -LiteralPath build/storage/work)) {
        & (SimulatorTool 'vlib') build/storage/work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $sources = @(
        'rtl/storage/spi_byte_master.v', 'rtl/storage/sd_spi_reader.v',
        'rtl/storage/fat32_bmp_reader.v', 'rtl/storage/bmp_stream_decoder.v',
        'rtl/storage/storage_pipeline.v', 'rtl/storage/hx4s20c_storage_bringup.v',
        'tb/storage/sd_spi_card_model.sv', 'tb/storage/eg_clock_buffer_model.v',
        'tb/storage/bmp_stream_decoder_tb.sv', 'tb/storage/fat32_bmp_reader_tb.sv',
        'tb/storage/sd_spi_reader_tb.sv', 'tb/storage/storage_pipeline_tb.sv',
        'tb/storage/hx4s20c_storage_bringup_tb.sv'
    )
    $inputs = $sources + @('tools/run_storage_tests.ps1', 'tools/make_storage_vectors.py',
        'tb/storage/vectors/card.hex', 'tb/storage/vectors/image.hex')
    $hashes = [ordered]@{}
    foreach ($source in $inputs) {
        $hashes[$source] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLower()
    }
    & (SimulatorTool 'vlog') -sv -work build/storage/work @sources
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
    $tests = @('bmp_stream_decoder', 'fat32_bmp_reader', 'sd_spi_reader', 'storage_pipeline', 'hx4s20c_storage_bringup')
    foreach ($test in $tests) {
        $log = "build/storage/$test.log"
        & (SimulatorTool 'vsim') -c -lib build/storage/work "${test}_tb" -do 'run -all; quit -f' -l $log
        if ($LASTEXITCODE -ne 0) { throw "Simulation process failed: $test" }
        $result = Get-Content -LiteralPath $log -Raw
        if ($result -notmatch "PASS ${test}:" -or $result -match '\*\* (Fatal|Error):') {
            throw "Simulation assertion or watchdog failed: $test (see $log)"
        }
    }
    foreach ($source in $inputs) {
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLower() -ne $hashes[$source]) {
            throw "Simulation source changed during regression: $source"
        }
    }
    $hashes | ConvertTo-Json | Set-Content -LiteralPath build/storage/source_hashes.json -Encoding utf8
    Write-Host 'PASS all storage regressions (5 suites). Logs: build/storage/'
} finally {
    Set-Location -LiteralPath $previousLocation
}
