$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = $PSScriptRoot
$DistDir = Join-Path $Root "dist"
$OutExe = Join-Path $DistDir "TwinBastionTD.exe"

if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
}

Write-Host "`n>>> 正在刷新 Twin Bastion TD 资源索引..." -ForegroundColor Cyan
& godot --headless --path $Root --import | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> 正在导出独立 Windows 可执行程序: $OutExe" -ForegroundColor Cyan
& godot --headless --path $Root --export-release "Windows Desktop" $OutExe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Path $OutExe) {
    $sizeMB = [math]::Round((Get-Item $OutExe).Length / 1MB, 2)
    Write-Host "`n[OK] 导出成功！文件路径: $OutExe ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host "`n[FAIL] 导出失败，未找到: $OutExe" -ForegroundColor Red
    exit 1
}
