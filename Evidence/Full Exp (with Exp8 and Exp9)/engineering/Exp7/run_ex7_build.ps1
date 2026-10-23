$vivado = 'D:\Vivado\2018.3\bin\vivado.bat'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $projectRoot 'vivado_ex7\run_ex7_build.log'
& $vivado -mode batch -source (Join-Path $projectRoot 'run_ex7_build.tcl') -log $log -journal (Join-Path $projectRoot 'vivado_ex7\run_ex7_build.jou')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
