$vivado = 'D:\Vivado\2018.3\bin\vivado.bat'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $projectRoot 'vivado_ex7\setup_vivado_ex7.log'
& $vivado -mode batch -source (Join-Path $projectRoot 'setup_vivado_ex7.tcl') -log $log -journal (Join-Path $projectRoot 'vivado_ex7\setup_vivado_ex7.jou')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
