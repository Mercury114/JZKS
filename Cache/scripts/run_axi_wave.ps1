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

    foreach ($case in @(
        @{ Top = 'cache_axi_bridge_tb'; Tcl = 'axi_bridge_wave.tcl'; VcdTcl = 'axi_bridge_vcd.tcl'; Pass = 'PASS cache_axi_bridge:' },
        @{ Top = 'mycpu_top_axi_tb'; Tcl = 'axi_cpu_wave.tcl'; VcdTcl = 'axi_cpu_vcd.tcl'; Pass = 'PASS AXI five-stage CPU/cache/MMIO:' }
    )) {
        $top = $case.Top
        $snapshot = "${top}_wave_sim"
        $wdb = "${top}.wdb"
        $wcfg = "${top}.wcfg"
        $log = "${top}_wave.log"

        # XSim parses a Tcl batch path as Tcl text; Windows backslashes are escapes.
        $tclPath = (Join-Path $PSScriptRoot $case.Tcl).Replace('\', '/')
        if (Test-Path -LiteralPath $wcfg) { Remove-Item -LiteralPath $wcfg -Force }

        & $xelab $top -debug typical -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "AXI wave elaboration failed: $top" }

        $simOutput = & $xsim $snapshot -wdb $wdb -tclbatch $tclPath 2>&1
        $simOutput | Set-Content -LiteralPath $log -Encoding UTF8
        $simOutput | Write-Output
        if ($LASTEXITCODE -ne 0 -or
            ($simOutput -join "`n") -match 'ERROR:|FATAL_ERROR:|\$fatal' -or
            -not ($simOutput -join "`n").Contains($case.Pass)) {
            throw "AXI wave simulation failed: $top (see $buildDir\$log)"
        }
        foreach ($file in @($wdb, $wcfg)) {
            if (!(Test-Path -LiteralPath $file)) { throw "Missing waveform file: $buildDir\$file" }
        }
        $vcd = "${top}.vcd"
        $vcdLog = "${top}_vcd.log"
        $vcdTclPath = (Join-Path $PSScriptRoot $case.VcdTcl).Replace('\', '/')
        if (Test-Path -LiteralPath $vcd) { Remove-Item -LiteralPath $vcd -Force }
        $vcdOutput = & $xsim $snapshot -tclbatch $vcdTclPath 2>&1
        $vcdOutput | Set-Content -LiteralPath $vcdLog -Encoding UTF8
        $vcdOutput | Write-Output
        if ($LASTEXITCODE -ne 0 -or
            ($vcdOutput -join "`n") -match 'ERROR:|FATAL_ERROR:|\$fatal' -or
            -not ($vcdOutput -join "`n").Contains($case.Pass) -or
            -not (Test-Path -LiteralPath $vcd)) {
            throw "AXI VCD export failed: $top (see $buildDir\$vcdLog)"
        }
        Write-Output "WAVE $top : $buildDir\$wdb and $buildDir\$wcfg"
    }
} finally {
    Pop-Location
}
