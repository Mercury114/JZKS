$vivado = 'D:\Vivado\2018.3\bin\vivado.bat'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $projectRoot 'local_gettrace_ex7\run_reference_ex7.log'
& $vivado -mode batch -source (Join-Path $projectRoot 'setup_reference_ex7.tcl') -log $log -journal (Join-Path $projectRoot 'local_gettrace_ex7\run_reference_ex7.jou')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
