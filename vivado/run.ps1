param(
    [ValidateSet('create', 'simulate', 'simulate_hw', 'fifo', 'stopwatch', 'stopwatch_hw', 'irq', 'irq_hw', 'bitstream')]
    [string]$Mode = 'create',
    [string]$Vivado = 'D:\Xilinx\Vivado\2018.3\bin\vivado.bat',
    [ValidateSet('auto', 'uart', 'ex9')]
    [string]$Firmware = 'auto',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Vivado)) { throw "Vivado not found: $Vivado" }
if ($Firmware -eq 'auto') {
    $Firmware = if ($Mode -in @('create','bitstream')) { 'ex9' } else { 'uart' }
}
if ($Firmware -eq 'uart') {
    & $Python (Join-Path $PSScriptRoot '..\innovation_uart\sw\prepare_images.py')
    if ($LASTEXITCODE -ne 0) { throw 'UART image preparation failed' }
}
Push-Location -LiteralPath $PSScriptRoot
try {
    & $Vivado -mode batch -nojournal -log "console_$Mode.log" -source 'run.tcl' -tclargs $Mode $Firmware
    if ($LASTEXITCODE -ne 0) { throw "Vivado $Mode failed; inspect console_$Mode.log" }
} finally { Pop-Location }
