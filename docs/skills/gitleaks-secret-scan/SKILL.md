---
name: gitleaks-secret-scan
description: 用 gitleaks 扫描 Git 仓库中的密码、Token、API Key 等敏感信息。发布、打标签、提交构建版本之前必须执行。适用于 comic-realm 等项目以及任意 Git 仓库的泄露排查。
whenToUse: 在准备提交、打版本标签、构建发布包之前；或需要排查仓库历史是否泄露凭证时。
---

# Gitleaks 敏感信息扫描

## 何时必须执行

**在以下动作之前，务必先跑一次扫描并确认无泄露：**

1. 打版本标签（`git tag vX.Y.Z`）
2. 推送触发 CI 构建（Build & Release）
3. 提交涉及签名、密钥、CI 配置的改动
4. 发布 Release 前

有任何命中（exit code 1）就**不要继续**，先处理泄露再发版。

## 一、安装 gitleaks

### 项目内安装（推荐）

本仓库把可执行文件放在 `tools/bin/gitleaks.exe`（Windows）或 `tools/bin/gitleaks`（Linux/macOS）。
二进制不入库，克隆后按下面方式获取：

```powershell
# Windows
$ver = "8.30.1"
Invoke-WebRequest -Uri "https://github.com/gitleaks/gitleaks/releases/download/v$ver/gitleaks_${ver}_windows_x64.zip" -OutFile gitleaks.zip
Expand-Archive gitleaks.zip -DestinationPath tools/bin -Force
```

```bash
# Linux / macOS
curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz" | tar -xz -C tools/bin gitleaks
```

### 系统级安装

```bash
brew install gitleaks            # macOS
sudo apt install gitleaks        # Debian/Ubuntu
docker pull zricethezav/gitleaks # Docker 通用
```

## 二、扫描命令

### 1. 扫描工作区（不含历史，最快）

```bash
gitleaks dir . -v
```

### 2. 扫描完整 Git 历史（发版前用这个）

```bash
gitleaks git . -v
```

### 3. 生成 JSON 报告

```bash
gitleaks git . --report-path gitleaks-report.json --report-format json --redact
```

## 三、退出码含义

| 退出码 | 含义 | 处理 |
|---|---|---|
| 0 | 未发现泄露 | 可以继续 |
| 1 | **发现泄露** | **停止发版**，先处理 |
| 其他 | 配置或运行错误 | 检查 config 与路径 |

## 四、项目封装脚本

本仓库提供 `scripts/secret-scan.ps1`（Windows）与 `scripts/secret-scan.sh`（Linux/macOS）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/secret-scan.ps1
```

```bash
bash scripts/secret-scan.sh
```

## 五、接入 CI（自动拦截）

`.github/workflows/secret-scan.yml` 在 push / PR 时自动扫描；
`build.yml` 在打标签构建前也会先扫描，**有泄露则构建失败**。

## 六、忽略与白名单

- **单行忽略**：代码行尾加 `# gitleaks:allow`
- **自定义忽略**：编辑 `.gitleaks.toml` 的 `[allowlist]` 段
- **按指纹忽略**：把输出的 `Fingerprint` 写进 `.gitleaksignore`（每行一个）

> [!WARNING]
> 白名单只用于「已确认并公开披露、且无法实际修复」的历史项。
> **不要**为了方便把真实凭证加进白名单，那等于没扫。

## 七、发现泄露后的处置

1. **立即轮换**：作废凭证（改密码、吊销 Token、重新生成密钥）
2. **清理历史**（可选）：`git filter-repo` 或 BFG 重写历史并强推（会改变所有 commit hash）
3. **记录**：在 CHANGELOG 或 SECURITY 文档写明发现时间、影响范围、处置方式
4. **复查**：重跑扫描确认干净

> 凭证一旦推送到公开仓库，就应视为**已泄露**。清理历史只能降低扩散，不能挽回曝光。

## 八、常见问题

**Q: 扫描很慢？** 只扫工作区用 `gitleaks dir .`；扫历史才用 `detect`。

**Q: 误报太多？** 在 `.gitleaks.toml` 里加精确的 `regexes` / `paths` 白名单，不要直接关规则。

**Q: keystore 等二进制扫不到？** gitleaks 只扫文本。二进制凭证（.jks/.keystore/.p12）靠 `.gitignore` 与 CI 校验拦截，本仓库已在 `android/.gitignore` 忽略所有 `*.jks`。

> [!IMPORTANT]
> **两个必须知道的坑（已在 2026-10-22 实际踩到并修正）**
>
> 1. **配置文件名必须是 `.gitleaks.toml`（带点）**。gitleaks 只自动识别这个带点的名字；
>    命名成 `gitleaks.toml` 不会被加载，裸跑会退回内置默认规则，而内置规则**没有 Android 签名口令这一类**，
>    结果就是「报告 0 泄露」的假阴性。本项目已改用 `.gitleaks.toml`。
> 2. **gitleaks 8.30 起已移除 `detect` / `protect` 命令**，只剩 `dir` 与 `git`。
>    旧写法 `gitleaks detect --source .` 会直接报错；查暂存区用 `gitleaks git --staged`。