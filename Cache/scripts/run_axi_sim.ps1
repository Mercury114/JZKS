param(
    [string]$VivadoBin = 'D:\Xilinx\Vivado\2018.3\bin'
)

$ErrorActionPreference = 'Stop'
$cacheDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtlDir = Join-Path $cacheDir 'rtl'
$cpuDir = Join-Path $rtlDir 'cpu'
$tbDir = Join-Path $cacheDir 'tb'
$buildDir = Join-Path $cacheDir 'build\axi'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (!(Test-Path -LiteralPath $tool)) { throw "Vivado simulator not found: $tool" }
}
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$sources = @((Get-ChildItem -LiteralPath $rtlDir -Filter '*.v').FullName) +
           @((Get-ChildItem -LiteralPath $cpuDir -Filter '*.v').FullName) +
           @((Join-Path $tbDir 'cache_axi_bridge_tb.v'),
             (Join-Path $tbDir 'mycpu_top_axi_tb.v'))

Push-Location -LiteralPath $buildDir
try {
    & $xvlog -sv -i $cpuDir @sources
    if ($LASTEXITCODE -ne 0) { throw 'AXI Verilog compilation failed' }
    foreach ($top in @('cache_axi_bridge_tb', 'mycpu_top_axi_tb')) {
        $snapshot = "${top}_sim"
        & $xelab $top -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "AXI elaboration failed: $top" }
        & $xsim $snapshot -runall
        if ($LASTEXITCODE -ne 0) { throw "AXI simulation failed: $top" }
    }
} finally {
    Pop-Location
}
