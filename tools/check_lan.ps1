param(
    [Parameter(Mandatory)]
    [string]$Godot,
    [int]$Port = 24635
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'tools/out'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$processes = @()

try {
    foreach ($role in @('host', 'client')) {
        $arguments = @('--headless', '--script', 'res://tests/lan_smoke.gd', '--', "role=$role", "port=$Port")
        $processes += Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $dir "lan-$role.log") -RedirectStandardError (Join-Path $dir "lan-$role.err.log")
    }
    Wait-Process -Id $processes.Id -Timeout 45
    foreach ($role in @('host', 'client')) {
        Get-Content -LiteralPath (Join-Path $dir "lan-$role.log")
        Get-Content -LiteralPath (Join-Path $dir "lan-$role.err.log")
    }
    foreach ($process in $processes) {
        if ($process.ExitCode -ne 0) { throw "LAN test process $($process.Id) returned $($process.ExitCode)" }
    }
} finally {
    foreach ($process in $processes) {
        if (!$process.HasExited) { $process.Kill() }
    }
}
