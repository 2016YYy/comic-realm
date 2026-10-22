#!/usr/bin/env bash
# 敏感信息扫描（gitleaks 封装，Linux/macOS 版）
#
# 用途：在提交、打标签、构建发布包之前检查是否泄露密码 / Token / API Key。
# 发现泄露时退出码为 1，CI 会据此中止构建。
#
# 用法：
#   bash scripts/secret-scan.sh            # 扫工作区 + Git 历史
#   bash scripts/secret-scan.sh --dir-only # 只扫工作区（快）
#   bash scripts/secret-scan.sh --strict   # 严格规则（排查历史用）

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DIR_ONLY=0
STRICT=0
for arg in "$@"; do
  case "$arg" in
    --dir-only) DIR_ONLY=1 ;;
    --strict)   STRICT=1 ;;
  esac
done

# ── 定位 gitleaks ───────────────────────────────────────────
EXE=""
for c in "$REPO_ROOT/tools/bin/gitleaks" "$REPO_ROOT/tools/bin/gitleaks.exe"; do
  if [ -x "$c" ]; then EXE="$c"; break; fi
done
if [ -z "$EXE" ] && command -v gitleaks >/dev/null 2>&1; then
  EXE="$(command -v gitleaks)"
fi
if [ -z "$EXE" ]; then
  echo "未找到 gitleaks。安装方式：" >&2
  echo "  curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz | tar -xz -C tools/bin gitleaks" >&2
  echo "  或 brew install gitleaks / sudo apt install gitleaks" >&2
  exit 2
fi

# ── 选择配置 ───────────────────────────────────────────────
CONFIG=".gitleaks.toml"
[ "$STRICT" -eq 1 ] && CONFIG="gitleaks-strict.toml"
CFG_ARGS=()
[ -f "$CONFIG" ] && CFG_ARGS=(--config "$REPO_ROOT/$CONFIG")

SCOPE="工作区 + Git 历史"
[ "$DIR_ONLY" -eq 1 ] && SCOPE="工作区"
[ "$STRICT" -eq 1 ] && SCOPE="$SCOPE（严格规则）"

echo "gitleaks: $EXE"
echo "模式    : $SCOPE"
echo

# ── 执行 ───────────────────────────────────────────────────
if [ "$DIR_ONLY" -eq 1 ]; then
  "$EXE" dir . --redact -v "${CFG_ARGS[@]}"
  CODE=$?
else
  "$EXE" git . --redact -v "${CFG_ARGS[@]}"
  CODE=$?
fi

echo
if [ "$CODE" -eq 0 ]; then
  echo "✔ 未发现敏感信息泄露"
  exit 0
elif [ "$CODE" -eq 1 ]; then
  echo "✘ 发现敏感信息泄露，禁止发版！" >&2
  echo "处置：1) 立即轮换该凭证  2) 清理历史  3) 记录到 CHANGELOG" >&2
  exit 1
else
  echo "✘ gitleaks 运行出错（exit=$CODE）" >&2
  exit "$CODE"
fi