$ErrorActionPreference = 'Stop'

function Split-Binary([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $chunkSize = 90000000L
    $input = [System.IO.File]::OpenRead($Source)
    try {
        $buffer = New-Object byte[] (4MB)
        $part = 1
        while ($input.Position -lt $input.Length) {
            $name = Join-Path $Destination ("tb_top_behav.wdb.part{0:D2}" -f $part)
            $output = [System.IO.File]::Create($name)
            $remaining = [Math]::Min($chunkSize, $input.Length - $input.Position)
            try {
                while ($remaining -gt 0) {
                    $want = [int][Math]::Min($buffer.Length, $remaining)
                    $read = $input.Read($buffer, 0, $want)
                    if ($read -le 0) { break }
                    $output.Write($buffer, 0, $read)
                    $remaining -= $read
                }
            } finally {
                $output.Dispose()
            }
            $part++
        }
    } finally {
        $input.Dispose()
    }
}

$base = Join-Path $PSScriptRoot 'Full Exp (with Exp8 and Exp9)'
Split-Binary (Join-Path $base 'engineering\Exp8\waveform\tb_top_behav.wdb') (Join-Path $base 'waveforms\Exp8')
Split-Binary (Join-Path $base 'engineering\Exp9\waveform\tb_top_behav.wdb') (Join-Path $base 'waveforms\Exp9')
foreach ($exp in @('Exp8', 'Exp9')) {
    $direct = Join-Path $base ("engineering\{0}\waveform\tb_top_behav.wdb" -f $exp)
    if (Test-Path $direct) { Remove-Item $direct -Force }
}
Write-Output 'WDB split complete.'
