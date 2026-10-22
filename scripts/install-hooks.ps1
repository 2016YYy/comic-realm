# 安装仓库自带的 Git 钩子（提交前敏感信息扫描）
# 用法：powershell -ExecutionPolicy Bypass -File scripts/install-hooks.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

git config core.hooksPath .githooks
Write-Host "✔ 已启用仓库钩子目录 .githooks" -ForegroundColor Green
Write-Host "  提交前会自动执行敏感信息扫描（gitleaks protect --staged）"
Write-Host "  临时跳过：git commit --no-verify"

if (-not (Test-Path "tools/bin/gitleaks.exe")) {
    Write-Host ""
    Write-Host "提示：tools/bin 下还没有 gitleaks.exe" -ForegroundColor Yellow
    Write-Host "  下载：" -ForegroundColor Yellow
    Write-Host "    `$ver = ""8.30.1"""
    Write-Host "    Invoke-WebRequest ""https://github.com/gitleaks/gitleaks/releases/download/v`$ver/gitleaks_`${ver}_windows_x64.zip"" -OutFile gitleaks.zip"
    Write-Host "    Expand-Archive gitleaks.zip -DestinationPath tools/bin -Force"
}