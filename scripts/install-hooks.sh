#!/usr/bin/env bash
# 安装仓库自带的 Git 钩子（提交前敏感信息扫描）
#
# 用法：bash scripts/install-hooks.sh

set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit 2>/dev/null || true

echo "✔ 已启用仓库钩子目录 .githooks"
echo "  提交前会自动执行敏感信息扫描（gitleaks protect --staged）"
echo "  临时跳过：git commit --no-verify"

# 顺便准备 gitleaks 二进制（项目内）
if [ ! -x tools/bin/gitleaks ] && [ ! -x tools/bin/gitleaks.exe ]; then
  echo
  echo "提示：tools/bin 下还没有 gitleaks。"
  echo "  Linux/macOS: curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz | tar -xz -C tools/bin gitleaks"
  echo "  Windows    : 见 SKILL 说明或运行 scripts/install-gitleaks.ps1"
fi