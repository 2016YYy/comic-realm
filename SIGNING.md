# 发布签名配置

Android 发布包的签名信息**不再放进仓库**（历史版本曾把 keystore 与口令直接提交，已造成公开可复用的问题）。
现在统一通过 **GitHub Secrets** 在 CI 注入，本地则用未入库的 `android/key.properties` 或环境变量。

---

## 一、CI：配置 GitHub Secrets

进入仓库 **Settings → Secrets and variables → Actions → New repository secret**，
按下表创建 5 个 Secret：

| Secret 名 | 内容 | 说明 |
|---|---|---|
| `COMICREALM_KEYSTORE_BASE64` | keystore 文件的 base64 | 用下面的命令生成，**单行、无换行** |
| `COMICREALM_STORE_FILE` | `release-keystore.jks` | 相对 `android/app/` 的文件名 |
| `COMICREALM_STORE_PASSWORD` | keystore 口令 | |
| `COMIC_REALM_KEY_ALIAS` | 别名 `comicrealm` | |
| `COMIC_REALM_KEY_PASSWORD` | 密钥口令 | |

### 生成 keystore 的 base64

keystore 文件在桌面密钥库 `C:\Users\...\Desktop\密钥库\漫画\keys-package\release-keystore.jks`：

```powershell
# PowerShell：输出单行 base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\笨熊四呆呆\Desktop\密钥库\漫画\keys-package\release-keystore.jks"))
```

```bash
# Git Bash / WSL
base64 -w0 /c/Users/笨熊四呆呆/Desktop/密钥库/漫画/keys-package/release-keystore.jks
```

> [!IMPORTANT]
> base64 字符串**不能含换行**，否则 `base64 -d` 会失败。把整串原样粘进 Secret 的值里。

### Secret 配好后 CI 的行为

`.github/workflows/build.yml` 的 `build-android` 会：

1. 校验 4 个签名变量是否齐全，**缺一个就直接失败**；
2. 把 `COMICREALM_KEYSTORE_BASE64` 解出 `android/app/release-keystore.jks`；
3. 构建后用 `apksigner verify --print-certs` 打印证书 DN，便于人工确认；
4. 四个变量里任意缺失时**不会**静默回退到 debug 签名，避免再次出现签名分裂。

---

## 二、本地开发：`android/key.properties`

本地自己打包时，在 `comic-realm/android/key.properties` 写入（该文件已被 `.gitignore` 忽略，不会入库）：

```properties
storeFile=release-keystore.jks
storePassword=comicrealm2026
keyAlias=comicrealm
keyPassword=comicrealm2026
```

并把 keystore 放到 `comic-realm/android/app/release-keystore.jks`。
之后 `flutter build apk --release` 会自动带上正式签名。

仓库里带了一份模板 [`android/key.properties.example`](android/key.properties.example)，可以直接复制后改值：

```powershell
cd comic-realm/android
cp key.properties.example key.properties
# 编辑 key.properties 填入真实口令
# 从桌面密钥库复制 keystore 到 app 目录
Copy-Item "C:\Users\笨熊四呆呆\Desktop\密钥库\漫画\keys-package\release-keystore.jks" app\
```

也可改用环境变量（优先级高于 `key.properties`）：

```powershell
$env:COMICREALM_STORE_FILE = "release-keystore.jks"
$env:COMICREALM_STORE_PASSWORD = "comicrealm2026"
$env:COMIC_REALM_KEY_ALIAS = "comicrealm"
$env:COMIC_REALM_KEY_PASSWORD = "comicrealm2026"
```

---

## 三、当前签名证书指纹（校验用）

| 项 | 值 |
|---|---|
| Key Alias | `comicrealm` |
| Keystore 类型 | PKCS12 |
| 算法 | SHA384withRSA / 2048-bit |
| 有效期 | 2026-10-15 ~ 2054-03-02 |
| Subject | `CN=ComicRealm, OU=Dev, O=ComicRealm, L=Shanghai, ST=Shanghai, C=CN` |
| SHA-1 | `3B:F2:48:07:EB:01:F0:EB:54:A1:5A:02:8C:63:2A:98:B0:E4:BB:DB` |
| SHA-256 | `31:13:BE:CE:E0:2D:74:ED:04:78:F9:49:4D:7E:06:72:8B:EE:4E:20:0E:37:44:41:10:05:C1:DA:05:0D:66:A8` |

本地核对 keystore 是不是同一份：

```powershell
keytool -list -v -keystore android/app/release-keystore.jks -storepass comicrealm2026
# 看 SHA1 / SHA256 是否与上表一致
```

---

## 四、已知历史遗留问题

> [!IMPORTANT]
> **1.0.0 ~ 1.0.3 的发布 APK 使用 debug 签名**（详见 CHANGELOG 1.0.4 条目），
> 从这三个版本升级到 1.0.4 及以上**必须先卸载旧版本**，否则会因签名冲突安装失败。
> 1.0.4 起的版本可正常覆盖升级，签名与本文件所述证书一致。
>
> 另外，keystore 曾以明文形式提交在公开仓库中（v1.0.4 ~ v1.8.1 的历史提交里都有）。
> **虽然本次已把它从当前版本索引中移除，但历史提交中的副本无法真正收回。**
> 若在意，建议后续换发新证书，并配合一次版本号大跨度升级（例如 2.0.0）。
>
> **v1.8.0 与 v1.6.1 的 CI 构建失败**，Release 产物不完整（详见各 Release 内的警告块）。
> v1.8.1 起 Android 构建恢复正常。
