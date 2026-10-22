# comic-realm 项目约定

## 发布前必须执行敏感信息扫描

> 本文件约束：**任何 Agent 在以下动作之前，必须先运行敏感信息扫描并确认通过。**

必须在**打版本标签**、**推送触发 Build & Release**、**创建 Release** 之前执行：

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File scripts/secret-scan.ps1
```

```bash
# Linux / macOS / CI
bash scripts/secret-scan.sh
```

判定标准：

- **退出码 0** → 可以继续发版
- **退出码 1** → 发现泄露，**立即停止发版**，先按 `docs/skills/gitleaks-secret-scan/SKILL.md` 第七章处置

### 自动化保障（已配置）

| 环节 | 机制 | 位置 |
|---|---|---|
| 本地提交 | pre-commit 钩子扫描暂存内容 | `.githooks/pre-commit` |
| CI 推送/PR | 独立扫描工作流 | `.github/workflows/secret-scan.yml` |
| 发版构建 | 构建前置关卡，失败则构建不启动 | `.github/workflows/build.yml` 的 `secret-scan` job |

### 钩子安装（克隆后执行一次）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-hooks.ps1
```

```bash
bash scripts/install-hooks.sh
```

## 签名与密钥

- 签名材料**不入库**，由 GitHub Secrets 注入；配置见 `SIGNING.md`
- 严禁把 keystore、口令、Token 提交到仓库
- 历史遗留的签名问题已记录在 `SIGNING.md` 的「已知历史遗留问题」