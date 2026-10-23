param(
    [ValidateSet('Exp8', 'Exp9')]
    [string]$Experiment = 'Exp8',
    [string]$OutputPath = ''
)

$base = Split-Path $PSScriptRoot -Parent
$partsPath = Join-Path $base ("waveforms\{0}\tb_top_behav.wdb.part*" -f $Experiment)
$parts = Get-ChildItem -Path $partsPath -File | Sort-Object Name
if ($parts.Count -eq 0) {
    throw "No waveform chunks found for $Experiment"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $base ("tb_top_behav_{0}.wdb" -f $Experiment.ToLower())
}

$output = [System.IO.File]::Create($OutputPath)
try {
    foreach ($part in $parts) {
        $input = [System.IO.File]::OpenRead($part.FullName)
        try {
            $input.CopyTo($output)
        } finally {
            $input.Dispose()
        }
    }
} finally {
    $output.Dispose()
}

Write-Output ("Restored {0} from {1} chunks: {2}" -f $Experiment, $parts.Count, $OutputPath)
