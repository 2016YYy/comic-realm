# tools/bin

存放本地开发用的外部可执行文件，**二进制不入库**（见 `.gitignore`）。

## gitleaks

敏感信息扫描工具，由 `scripts/secret-scan.ps1` / `scripts/secret-scan.sh` 调用。

### 获取方式

Windows：

```powershell
$ver = "8.30.1"
Invoke-WebRequest "https://github.com/gitleaks/gitleaks/releases/download/v$ver/gitleaks_${ver}_windows_x64.zip" -OutFile gitleaks.zip
Expand-Archive gitleaks.zip -DestinationPath tools/bin -Force
```

Linux / macOS：

```bash
curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz | tar -xz -C tools/bin gitleaks
```

也可以用系统包管理器：`brew install gitleaks` / `sudo apt install gitleaks` / `winget install gitleaks`，
脚本会优先找 `tools/bin`，找不到再回退到 PATH。

## 为什么不入库

可执行文件约 21MB，且平台相关（Windows/Linux/macOS 不同），不适合进 Git。
CI 每次构建时自行下载（见 `.github/workflows/secret-scan.yml`）。