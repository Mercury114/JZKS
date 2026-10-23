param(
    [ValidateSet('setup','ex8','ex9','build')]
    [string]$Action = 'setup'
)
$vivado = 'D:\Vivado2023\Vivado\2023.2\bin\vivado.bat'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Action -eq 'setup') {
    & $vivado -mode batch -source (Join-Path $projectRoot 'setup_project.tcl') -log (Join-Path $projectRoot 'setup.log')
} elseif ($Action -eq 'ex9') {
    & $vivado -mode batch -source (Join-Path $projectRoot 'select_test.tcl') -log (Join-Path $projectRoot "select_$Action.log") -tclargs $Action
    if ($LASTEXITCODE -eq 0) { & $vivado -mode batch -source (Join-Path $projectRoot 'run_sim.tcl') -log (Join-Path $projectRoot "sim_$Action.log") -tclargs $Action }
} else {
    & $vivado -mode batch -source (Join-Path $projectRoot 'run_build.tcl') -log (Join-Path $projectRoot 'build.log')
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
