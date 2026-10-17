#!/usr/bin/env bash
#
# 生成 GitHub Release 正文：版本说明取自 CHANGELOG.md，下载表格取自该 Release 的真实产物。
# Release 尚未创建（例如刚打完标签、产物还没上传）时，下载表格回退到产物命名约定。
#
# 样式对齐 melodyflow：标题行 = 「应用名 vX.Y.Z - 一句话概括」，正文使用带表情的二级小标题。
# CHANGELOG 中版本小节的首行若为 `> 一句话概括`，会被提取为副标题。
#
# 用法：scripts/release-notes.sh <tag>      # 正文写到 stdout
# 依赖：gh（需 GH_TOKEN）、git 标签、仓库根目录下的 CHANGELOG.md

set -euo pipefail

APP="ComicRealm"
PROJECT="漫境 ComicRealm"
REPO="${GITHUB_REPOSITORY:?需要 GITHUB_REPOSITORY 环境变量}"
TAG="${1:?用法: release-notes.sh <tag>}"
VERSION="${TAG#v}"

# 从 CHANGELOG.md 抽取该版本小节（不含 "## [x.y.z]" 标题行，也不含底部的链接定义）
section=$(awk -v ver="$VERSION" '
  $0 ~ "^## \\[" ver "\\]" { found = 1; next }
  found && (/^## \[/ || /^\[[^]]+\]:/) { exit }
  found { print }
' CHANGELOG.md)

if [ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
  echo "CHANGELOG.md 中找不到 ${VERSION} 的小节" >&2
  exit 1
fi

# 提取可选副标题：小节第一条非空行若以 "> " 开头
subtitle=$(printf '%s\n' "$section" | awk '
  /^[[:space:]]*$/ { next }
  /^> / { sub(/^> /, ""); print; exit }
  { exit }
')

# 存在副标题时，从正文中剔除该行
if [ -n "$subtitle" ]; then
  section=$(printf '%s\n' "$section" | awk '
    !skipped && /^[[:space:]]*$/ { next }
    !skipped && /^> / { skipped = 1; next }
    { skipped = 1; print }
  ')
fi

# 规整小节首尾空白：去掉开头空行与结尾多余空行，
# 避免与下方固定的 echo 空行叠加成连续空行。
section=$(printf '%s\n' "$section" | awk '
  { lines[NR] = $0 }
  END {
    start = 1
    while (start <= NR && lines[start] ~ /^[[:space:]]*$/) start++
    end = NR
    while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
    for (i = start; i <= end; i++) print lines[i]
  }
')

# 产物文件名 -> 「平台|说明」
asset_info() {
  case "$1" in
    *arm64*)   echo 'Android|推荐，适配大多数现代设备' ;;
    *armeabi*) echo 'Android|32 位老旧设备' ;;
    *x86*)     echo 'Android|模拟器 / x86 设备' ;;
    *.ipa)     echo 'iOS|免签名包，需自签安装' ;;
    *windows*) echo 'Windows|解压即用' ;;
    *.apk)     echo 'Android|未分架构通用包' ;;
    *)         echo '其他|' ;;
  esac
}

# 上一个版本，用于生成 compare 链接
prev=""
found=false
while IFS= read -r t; do
  if [ "$found" = true ]; then
    prev="$t"
    break
  fi
  if [ "$t" = "$TAG" ]; then
    found=true
  fi
done < <(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$')

# 该 Release 的真实产物；Release 不存在时为空
assets=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || true)

# 标题行：应用名 + 版本（+ 副标题）
if [ -n "$subtitle" ]; then
  echo "## ${PROJECT} ${TAG} - ${subtitle}"
else
  echo "## ${PROJECT} ${TAG}"
fi
echo
printf '%s\n' "$section"
echo
echo "### 📦 下载"
echo
echo "| 平台 | 安装包 | 说明 |"
echo "| --- | --- | --- |"
if [ -n "$assets" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    info=$(asset_info "$name")
    echo "| ${info%%|*} | \`${name}\` | ${info#*|} |"
  done <<< "$assets"
else
  echo "| Android | \`${APP}-${TAG}-android-arm64-v8a.apk\` | 推荐，适配大多数现代设备 |"
  echo "| Android | \`${APP}-${TAG}-android-armeabi-v7a.apk\` | 32 位老旧设备 |"
  echo "| Android | \`${APP}-${TAG}-android-x86_64.apk\` | 模拟器 / x86 设备 |"
  echo "| Windows | \`${APP}-${TAG}-windows-x64.zip\` | 解压即用 |"
  echo "| iOS | \`${APP}-${TAG}-ios-unsigned.ipa\` | 免签名包，需自签安装 |"
fi
echo
echo "首次使用请在「图源」页导入图源；应用内「设置 → 检查更新」可一键升级。"
if [ -n "$prev" ]; then
  echo
  echo "**完整更新日志**：[\`${prev}...${TAG}\`](https://github.com/${REPO}/compare/${prev}...${TAG})"
fi
