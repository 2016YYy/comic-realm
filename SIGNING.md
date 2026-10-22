# 发布签名配置

Android 发布包的签名信息**不再放进仓库**。现在统一通过 **GitHub Secrets** 在 CI 注入，本地则用未入库的 `android/key.properties` 或环境变量。

> [!IMPORTANT]
> **2026-10-22 已换发第 2 代签名证书。** 旧证书（v1.0.4 ~ v1.9.0 使用）因 keystore 与口令在公开仓库暴露 16 个版本，已作废。
> 新证书从 **v2.0.0** 起使用，与旧证书**不兼容**——老用户升级必须先卸载旧版。详见第四节。

---

## 一、CI：配置 GitHub Secrets

进入仓库 **Settings → Secrets and variables → Actions → New repository secret**，按下表创建 5 个 Secret：

| Secret 名 | 内容 | 说明 |
|---|---|---|
| `COMICREALM_KEYSTORE_BASE64` | keystore 文件的 base64 | 单行、无换行 |
| `COMICREALM_STORE_FILE` | `comic-realm-release-2026.jks` | 相对 `android/app/` 的文件名 |
| `COMICREALM_STORE_PASSWORD` | keystore 口令 | 见本地 `keys-package/签名信息.txt` |
| `COMIC_REALM_KEY_ALIAS` | `comicrealm` | |
| `COMIC_REALM_KEY_PASSWORD` | 密钥口令 | 与 storePassword 相同 |

### 生成 keystore 的 base64

keystore 本地保存于 `comic-realm/keys-package/comic-realm-release-2026.jks`（该目录已被 `.gitignore` 忽略）：

```powershell
# PowerShell：输出单行 base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("comic-realm\keys-package\comic-realm-release-2026.jks"))
```

```bash
# Git Bash / WSL
base64 -w0 comic-realm/keys-package/comic-realm-release-2026.jks
```

> [!IMPORTANT]
> base64 字符串**不能含换行**，否则 `base64 -d` 会失败。把整串原样粘进 Secret 的值里。

### Secret 配好后 CI 的行为

`.github/workflows/build.yml` 的 `build-android` 会：

1. 先跑 `secret-scan` 关卡，发现敏感信息直接终止；
2. 校验 4 个签名变量是否齐全，**缺一个就直接失败**；
3. 把 `COMICREALM_KEYSTORE_BASE64` 解出 `android/app/comic-realm-release-2026.jks`；
4. 构建后用 `apksigner verify --print-certs` 打印证书 DN 与指纹，便于人工确认；
5. 任意变量缺失时**不会**静默回退到 debug 签名，避免签名分裂。

---

## 二、本地开发：`android/key.properties`

在 `comic-realm/android/key.properties` 写入（该文件已被 `.gitignore` 忽略）：

```properties
storeFile=comic-realm-release-2026.jks
storePassword=<见 keys-package/签名信息.txt>
keyAlias=comicrealm
keyPassword=<同上>
```

并把 keystore 复制到 `comic-realm/android/app/comic-realm-release-2026.jks`：

```powershell
cd comic-realm/android
Copy-Item key.properties.example key.properties
# 编辑 key.properties 填入真实口令
Copy-Item ..\keys-package\comic-realm-release-2026.jks app\
```

也可改用环境变量（优先级高于 `key.properties`）：

```powershell
$env:COMICREALM_STORE_FILE = "comic-realm-release-2026.jks"
$env:COMICREALM_STORE_PASSWORD = "<口令>"
$env:COMIC_REALM_KEY_ALIAS = "comicrealm"
$env:COMIC_REALM_KEY_PASSWORD = "<口令>"
```

> 口令**不写进仓库任何文件**。明文只保存在本地 `keys-package/签名信息.txt`（gitignore）与 GitHub Secrets 里。

---

## 三、当前签名证书指纹（校验用）

### 第 2 代（v2.0.0 起，当前）

| 项 | 值 |
|---|---|
| Key Alias | `comicrealm` |
| Keystore 类型 | JKS |
| 算法 | SHA256withRSA / 2048-bit |
| 有效期 | 10000 天 |
| Subject | `CN=ComicRealm, OU=Dev, O=ComicRealm, L=Shanghai, ST=Shanghai, C=CN` |
| SHA-1 | `E4:8F:25:13:59:C9:8D:93:80:98:F8:F5:1E:9F:1E:CB:6C:03:3E:7E` |
| SHA-256 | `FD:FB:16:F1:7F:16:CE:4F:DD:30:03:7B:25:2C:6D:E4:44:18:13:7F:15:6B:A9:77:29:4B:31:33:1A:2E:8C:BC` |

### 第 1 代（v1.0.4 ~ v1.9.0，已作废）

| 项 | 值 |
|---|---|
| SHA-1 | `3B:F2:48:07:EB:01:F0:EB:54:A1:5A:02:8C:63:2A:98:B0:E4:BB:DB` |
| SHA-256 | `31:13:BE:CE:E0:2D:74:ED:04:78:F9:49:4D:7E:06:72:8B:EE:4E:20:0E:37:44:41:10:05:C1:DA:05:0D:66:A8` |

本地核对 keystore：

```powershell
keytool -list -v -keystore comic-realm-release-2026.jks -storepass <口令>
# 看 SHA1 / SHA256 是否与上表一致
```

核对已发布 APK：

```bash
apksigner verify --print-certs ComicRealm-v2.0.0-arm64-v8a.apk
```

---

## 四、证书换发记录与影响

### 为什么换

第 1 代 keystore（`release-keystore.jks`）与明文口令曾在公开仓库 **v1.0.4 ~ v1.8.1 共 16 个版本**中暴露，
任何人都可获取该文件并签发与官方同签名的 APK。历史提交无法真正收回，因此决定换发。

完整审计见 [`docs/SECURITY-AUDIT.md`](docs/SECURITY-AUDIT.md)。

### 换发带来的破坏性变更

> [!WARNING]
> 新旧证书签名不同，Android 会视为**两个不同的应用**。
> 从 v1.9.0 及更早版本升级到 **v2.0.0** 时：
>
> 1. 会提示「应用未安装」或「签名冲突」；
> 2. **必须先卸载旧版本**再安装新版本；
> 3. 卸载会清除应用本地数据（登录状态、阅读记录、下载缓存等）。

这是换证书的必然代价，无法规避。

### 时间线

| 时间 | 事件 |
|---|---|
| 2026-10-15 | 第 1 代证书启用（v1.0.4） |
| 2026-10-22 | 发现 16 个版本泄露 keystore + 口令，决定换发 |
| 2026-10-22 | 生成第 2 代证书，更新 GitHub Secrets |
| 2026-10-22 | v2.0.0 起使用第 2 代证书 |

---

## 五、历史遗留问题（已归档）

> **1.0.0 ~ 1.0.3 的发布 APK 使用 debug 签名**（详见 CHANGELOG 1.0.4 条目）。
> 这些版本的签名与任何正式证书都不兼容，已于 2026-10-17 用 `resign_tag` 重建替换。
>
> **v1.8.0 与 v1.6.1 的 CI 构建失败**，Release 产物不完整（详见各 Release 内的警告块）；
> v1.8.1 起 Android 构建恢复正常。
>
> **第 1 代 keystore 已作废**，但 v1.0.4 ~ v1.9.0 的已发布 APK 仍使用它签名——
> 这些老 APK 与 v2.0.0+ 无法互相覆盖升级。