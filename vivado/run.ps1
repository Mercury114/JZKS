param(
    [ValidateSet('create', 'simulate', 'simulate_hw', 'fifo', 'stopwatch', 'stopwatch_hw', 'irq', 'irq_hw', 'bitstream')]
    [string]$Mode = 'create',
    [string]$Vivado = 'D:\Xilinx\Vivado\2018.3\bin\vivado.bat'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Vivado)) { throw "Vivado not found: $Vivado" }
Push-Location -LiteralPath $PSScriptRoot
try {
    & $Vivado -mode batch -nojournal -log "console_$Mode.log" -source 'run.tcl' -tclargs $Mode
    if ($LASTEXITCODE -ne 0) { throw "Vivado $Mode failed; inspect console_$Mode.log" }
} finally { Pop-Location }
