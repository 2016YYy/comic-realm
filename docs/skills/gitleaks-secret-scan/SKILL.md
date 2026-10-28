---
name: gitleaks-secret-scan
description: 用 gitleaks 扫描 Git 仓库中的密码、Token、API Key 等敏感信息。提交、打标签、构建发布包之前必须执行；也用于排查历史提交是否泄露凭证。
---

# Gitleaks 敏感信息扫描

## 何时必须执行

**在以下动作之前，先跑一次扫描并确认无泄露：**

1. 打版本标签（git tag vX.Y.Z）
2. 推送触发 CI 构建
3. 提交涉及签名、密钥、CI 配置的改动
4. 创建 Release 前

有任何命中（exit code 1）就**不要继续**，先处理泄露再发版。

## 一、安装 gitleaks

项目内安装（推荐）：可执行文件放 tools/bin/gitleaks.exe（Windows）或 tools/bin/gitleaks（Linux/macOS），二进制不入库。

Windows：

    $ver = "8.30.1"
    Invoke-WebRequest "https://github.com/gitleaks/gitleaks/releases/download/v$ver/gitleaks_8.30.1_windows_x64.zip" -OutFile gitleaks.zip
    Expand-Archive gitleaks.zip -DestinationPath tools/bin -Force

Linux / macOS：

    curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz | tar -xz -C tools/bin gitleaks

系统级安装：brew install gitleaks / sudo apt install gitleaks / winget install gitleaks

## 二、扫描命令（gitleaks 8.30+）

> [!IMPORTANT]
> **detect 与 protect 命令已移除**，只剩 dir 与 git。
> 旧文档里的 gitleaks detect --source . 会直接报错。

    # 扫工作区（不含历史，最快）
    gitleaks dir . -v

    # 扫完整 Git 历史（发版前用这个）
    gitleaks git . -v

    # 只扫暂存区（pre-commit 钩子用）
    gitleaks git --staged -v

    # 生成 JSON 报告
    gitleaks git . --report-path gitleaks-report.json --report-format json --redact

## 三、退出码

| 退出码 | 含义 | 处理 |
|---|---|---|
| 0 | 未发现泄露 | 可以继续 |
| 1 | 发现泄露 | 停止发版，先处理 |
| 其他 | 配置或运行错误 | 检查 config 与路径 |

> 扫描失败不等于没有泄露。配置解析错误时 gitleaks 一条都扫不了却可能返回 0，
> 务必看日志里的 no leaks found 或 leaks found: N。

## 四、配置文件名（最容易踩的坑）

> [!CAUTION]
> **配置必须叫 .gitleaks.toml（带点）**，这是 gitleaks 在仓库根目录自动识别的唯一名字。
> 命名为 gitleaks.toml（不带点）不会被加载，裸跑会退回内置默认规则。
>
> 内置规则没有 Android 签名口令这一类，结果就是「报告 0 泄露」的假阴性。
>
> 实测对照（同一份自定义规则）：
>
> | 文件名 | 裸跑 gitleaks git . | 结果 |
> |---|---|---|
> | .gitleaks.toml | 检出 storePassword 泄露 | 正确 |
> | gitleaks.toml | 报 no leaks | 漏报 |

## 五、必要的最小规则集

官方默认规则抓不到 Gradle 签名口令和通用硬编码口令，必须自己补。

注意：TOML 里包正则必须用字面量字符串（三个单引号），不能用基本字符串（三个双引号）。
三双引号会解析反斜杠转义，反斜杠加点不是合法转义序列，导致整个配置加载失败。

规则一条 android-signing-password：id 为该名，description 写 Android 签名口令明文，
secretGroup 为 2，keywords 为 storepassword 与 keypassword；
正则匹配 storePassword 或 keyPassword 后跟等号与引号包裹的值，忽略大小写，值至少 4 字符。

规则二 generic-hardcoded-password：id 为该名，secretGroup 为 2，entropy 为 2.5，
keywords 含 password、secret、token、api_key；
正则匹配 password/passwd/secret/token/api_key/apikey/access_key 后跟冒号或等号与引号包裹的值，
忽略大小写，值字符集为字母数字与 _ - ! @ # $ % ^ & * +，长度至少 8。

规则三 private-key-block：id 为该名，keywords 含 BEGIN 与 PRIVATE KEY；
正则匹配 PEM 私钥头，即三个减号 BEGIN，可选 RSA/EC/OPENSSH/PGP 加空格，再 PRIVATE KEY，再三个减号。

构建产物目录记得在 allowlist 的 paths 里排除，否则编译缓存会误报：
tools 目录下的二进制、.dart_tool、build、.gradle 四类。
正则路径分别为：(^|/)[点]dart_tool/、(^|/)build/、(^|/)[点]gradle/、(^|/)tools/bin/。

## 六、接入三层闸门

| 环节 | 机制 |
|---|---|
| 本地提交 | .githooks/pre-commit 执行 gitleaks git --staged |
| PR 与 push | .github/workflows/secret-scan.yml |
| 发版构建 | build.yml 的 secret-scan 前置 job，用 needs 依赖它 |

启用钩子（克隆后执行一次）：

    git config core.hooksPath .githooks

临时跳过钩子：git commit --no-verify（仅限确认无泄露时）。

## 七、忽略与白名单

- 单行忽略：代码行尾加井号 gitleaks:allow
- 自定义忽略：.gitleaks.toml 的 allowlist 段
- 按指纹忽略：把输出的 Fingerprint 写进 .gitleaksignore

> [!WARNING]
> 白名单只用于「已确认并公开披露、且无法实际修复」的历史项。
> 不要为了方便把真实凭证加进白名单——那等于没扫。

## 八、发现泄露后的处置

1. 立即轮换：作废凭证（改密码、吊销 Token、重新生成密钥）
2. 清理历史（可选）：git filter-repo 或 BFG 重写历史后强推
3. 记录：在 CHANGELOG 或 SECURITY 文档写明发现时间、影响范围、处置方式
4. 复查：重跑扫描确认干净

> 凭证一旦推送到公开仓库，就应视为已泄露。
> 清理历史只能降低扩散，不能挽回已曝光的副本——该轮换的必须轮换。

## 九、验证 APK 签名证书（配套环节）

换了签名证书后，要用 apksigner 确认线上包真的是新证书：

    apksigner verify --print-certs app-release.apk

> [!CAUTION]
> apksigner 输出的是「小写、无冒号」格式（如 fdfb16f1...），
> 而文档与 keytool 习惯写「大写、带冒号」（FD:FB:16:...）。
> 直接字符串比较必然不等，会把正确证书判成不符。比较前先归一化：
>
> 归一化函数写法：用 echo 输出参数，管道给 tr 删除冒号，再管道给 tr 把 A-F 转成 a-f。
> 然后比较两个归一化后的值是否相等，不等则退出码 1。

## 十、常见问题

Q: 扫描很慢？答：只扫工作区用 gitleaks dir .；扫历史才用 gitleaks git .

Q: 误报太多？答：在 .gitleaks.toml 里加精确的 regexes 或 paths 白名单，不要直接关规则。

Q: keystore 或二进制扫不到？答：gitleaks 只扫文本。二进制凭证（jks/keystore/p12）靠 .gitignore 与 CI 校验拦截。

Q: 配置报 invalid escaped character？答：用了三双引号，改成三单引号。

## 十一、案例（comic-realm 实战）

- 曾有 16 个版本（v1.0.4 到 v1.8.1）把 keystore 与明文口令提交进公开仓库；
  2026-10-22 换发第 2 代证书，v2.0.0 起启用。
- 换证书后新旧版本签名不同，Android 视为两个应用，老用户必须卸载重装。
- CI 里加了硬校验：APK 证书 SHA-256 必须等于预期值，不符则构建失败。
- 该硬校验首版因「大写带冒号 与 小写无冒号」直接比较而误判失败，归一化后修复——
  这就是第九条坑的来源。