# 敏感信息扫描（gitleaks 封装）
#
# 用途：在提交、打标签、构建发布包之前检查是否泄露密码 / Token / API Key。
# 发现泄露时退出码为 1，调用方（CI / 发布脚本）应据此中止流程。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts/secret-scan.ps1          # 扫工作区 + 历史
#   powershell -ExecutionPolicy Bypass -File scripts/secret-scan.ps1 -DirOnly # 只扫工作区（快）

param(
    [switch]$DirOnly,
    [switch]$Strict,
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# ── 定位 gitleaks ───────────────────────────────────────────
$candidates = @(
    (Join-Path $repoRoot "tools/bin/gitleaks.exe"),
    (Join-Path $repoRoot "tools/bin/gitleaks")
)
$exe = $null
foreach ($c in $candidates) { if (Test-Path $c) { $exe = $c; break } }
if (-not $exe) {
    $cmd = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($cmd) { $exe = $cmd.Source }
}
if (-not $exe) {
    Write-Host "未找到 gitleaks。" -ForegroundColor Red
    Write-Host "请按以下任一方式安装：" -ForegroundColor Yellow
    Write-Host "  1) 下载到 tools/bin:"
    Write-Host "       `$ver = ""8.30.1"""
    Write-Host "       Invoke-WebRequest ""https://github.com/gitleaks/gitleaks/releases/download/v`$ver/gitleaks_`${ver}_windows_x64.zip"" -OutFile gitleaks.zip"
    Write-Host "       Expand-Archive gitleaks.zip -DestinationPath tools/bin -Force"
    Write-Host "  2) winget install gitleaks"
    exit 2
}

# ── 选择配置文件 ───────────────────────────────────────────
$config = if ($Strict) { "gitleaks-strict.toml" } else { ".gitleaks.toml" }
if (-not (Test-Path $config)) { $config = "" }
$configArgs = if ($config) { @("--config", (Join-Path $repoRoot $config)) } else { @() }

$reportArgs = @()
if ($ReportPath) {
    $reportArgs = @("--report-path", $ReportPath, "--report-format", "json")
}

$scopeText = if ($DirOnly) { "工作区" } else { "工作区 + Git 历史" }
if ($Strict) { $scopeText = $scopeText + "（严格规则）" }

Write-Host "gitleaks: $exe" -ForegroundColor Cyan
Write-Host ("模式    : " + $scopeText) -ForegroundColor Cyan
Write-Host ""

# ── 执行扫描 ───────────────────────────────────────────────
$scanArgs = if ($DirOnly) {
    @("dir", ".", "--redact", "-v") + $configArgs + $reportArgs
} else {
    @("git", ".", "--redact", "-v") + $configArgs + $reportArgs
}

& $exe @scanArgs
$code = $LASTEXITCODE

Write-Host ""
if ($code -eq 0) {
    Write-Host "✔ 未发现敏感信息泄露" -ForegroundColor Green
    exit 0
}
elseif ($code -eq 1) {
    Write-Host "✘ 发现敏感信息泄露，禁止发版！" -ForegroundColor Red
    Write-Host "处置：1) 立即轮换该凭证  2) 清理历史  3) 记录到 CHANGELOG" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "✘ gitleaks 运行出错（exit=$code）" -ForegroundColor Red
    exit $code
}