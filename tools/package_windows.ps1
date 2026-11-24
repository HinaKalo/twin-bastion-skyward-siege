param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Tag
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$bundle = Join-Path $dist "Twin-Bastion-Skyward-Siege-$Tag-win-x64.zip"
$metadata = @(
    (Join-Path $dist 'TwinBastionTD.exe')
    (Join-Path $root 'LICENSE')
    (Join-Path $root 'THIRD_PARTY_NOTICES.md')
    (Join-Path $root 'licenses/Godot-LICENSE.txt')
    (Join-Path $root 'licenses/Godot-COPYRIGHT.txt')
)
Compress-Archive -LiteralPath $metadata -DestinationPath $bundle -CompressionLevel Optimal -Force
$digest = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $(Split-Path $bundle -Leaf)" | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
Write-Output $bundle
