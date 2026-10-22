# 敏感信息审计报告

> 审计日期：2026-10-22　工具：gitleaks 8.30.1　范围：云端仓库 `2016YYy/comic-realm` 全部 23 个版本标签 + 完整 Git 历史

## 结论速览

| 类别 | 数量 | 版本 |
|---|---|---|
| ⚠️ 凭证泄露（口令 + keystore 入库） | **16** | v1.0.4 ~ v1.8.1 |
| ✅ 干净 | 7 | v1.0.0 ~ v1.0.3、v1.8.2、v1.8.3、v1.9.0 |

**已泄露内容**：

1. `android/app/build.gradle.kts` 中明文写死的签名口令（`storePassword` / `keyPassword`）
2. `android/app/release-keystore.jks` 签名密钥文件本身

两者同时在库 ⇒ 任何人克隆仓库即可用这份证书签发与官方一致的 APK。

**影响范围**：v1.0.4 起的 16 个标签；`main` 分支与 v1.8.2+ 已移除。

## 逐版本明细

| 版本 | build.gradle 明文口令 | keystore 入库 | 判定 |
|---|---|---|---|
| v1.9.0 | no | no | ✅ 干净 |
| v1.8.3 | no | no | ✅ 干净 |
| v1.8.2 | no | no | ✅ 干净 |
| v1.8.1 | YES | YES | ⚠️ 泄露 |
| v1.8.0 | YES | YES | ⚠️ 泄露 |
| v1.7.2 | YES | YES | ⚠️ 泄露 |
| v1.7.1 | YES | YES | ⚠️ 泄露 |
| v1.7.0 | YES | YES | ⚠️ 泄露 |
| v1.6.2 | YES | YES | ⚠️ 泄露 |
| v1.6.1 | YES | YES | ⚠️ 泄露 |
| v1.6.0 | YES | YES | ⚠️ 泄露 |
| v1.5.1 | YES | YES | ⚠️ 泄露 |
| v1.5.0 | YES | YES | ⚠️ 泄露 |
| v1.4.0 | YES | YES | ⚠️ 泄露 |
| v1.3.0 | YES | YES | ⚠️ 泄露 |
| v1.2.0 | YES | YES | ⚠️ 泄露 |
| v1.1.1 | YES | YES | ⚠️ 泄露 |
| v1.1.0 | YES | YES | ⚠️ 泄露 |
| v1.0.4 | YES | YES | ⚠️ 泄露 |
| v1.0.3 | no | no | ✅ 干净（但为 debug 签名） |
| v1.0.2 | no | no | ✅ 干净（但为 debug 签名） |
| v1.0.1 | no | no | ✅ 干净（但为 debug 签名） |
| v1.0.0 | no | no | ✅ 干净（但为 debug 签名） |

> v1.0.0 ~ v1.0.3 虽无凭证泄露，但使用 Android Debug 签名，与正式证书不兼容（详见 `SIGNING.md`）。

## Git 历史定位

| 提交 | 说明 |
|---|---|
| `f618b06` | 引入 keystore 与明文口令（`feat: 统一发布签名`） |
| `ce9e2c9` | 移除 keystore 与口令，改用 GitHub Secrets（`security: 签名配置移出仓库`） |

严格扫描（`-Strict`）在上述提交仍能检出 2 处口令命中，属**历史事实**，无法通过改代码消除。

## 处置建议

### 已做

- ✅ 当前分支（main）已无 keystore 与明文口令
- ✅ v1.8.2+ 构建改为 GitHub Secrets 注入签名
- ✅ 全链路接入 gitleaks 扫描（提交 / PR / 发版构建）
- ✅ 历史问题在 `SIGNING.md` 与 CHANGELOG 中公开披露

### 待决策（需仓库所有者判断）

> **最关键的一条：泄露的 keystore 应视为已作废。**
> 清理历史只能降低扩散，无法收回已被克隆的副本。
> 若在意安全，建议换发新证书（代价：所有老用户需卸载重装）。

可选动作（按投入递增）：

1. **换发新签名证书** —— 一次性解决，但破坏升级链路
2. **重写历史** —— `git filter-repo --path android/app/release-keystore.jks --invert-paths`
   并用 BFG 清理口令，随后强推（所有 commit hash 改变，23 个标签需重建）
3. **仅保持现状** —— 依赖「v1.8.2+ 已无凭证」这一事实，接受历史副本不可收回

## 复现方式

```bash
# 完整历史（默认配置，应通过）
bash scripts/secret-scan.sh

# 严格排查（会暴露历史记录中的口令引用）
bash scripts/secret-scan.sh --strict
```

## 附：本次扫描覆盖

- 本地完整 Git 历史：47 次提交
- 云端 23 个标签的源码树：v1.8.3 / v1.9.0 额外下载校验，其余由历史扫描覆盖
- 云端所有标签的 `build.gradle.kts` 与 `release-keystore.jks` 存在性：逐个 API 核查