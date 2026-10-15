<div align="center">

# 漫境 ComicRealm

**一款支持多图源的开源漫画阅读器**

![Flutter](https://img.shields.io/badge/Flutter-3.29.3-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Windows-lightgrey)

一个纯净、自由、可扩展的漫画阅读工具，支持自定义图源导入，让你在任何设备上都能顺畅阅读喜爱的漫画。

</div>

---

## ✨ 功能特性

### 📚 核心功能
- **多图源支持** — 兼容开源阅读(legado) / 异次元 的图源 JSON 规则格式，一套规则解析全站漫画
- **内置 MYCOMIC 图源** — 开箱即用，也可随时添加第三方图源
- **漫画搜索 / 详情 / 阅读** — 完整的浏览与阅读体验，支持上下滑动翻页
- **本地下载** — 一键下载章节到本地，离线也能看
- **书库收藏** — 收藏喜爱的漫画，随时续读

### 🔌 图源导入（三种方式）
| 方式 | 说明 |
|------|------|
| 🌐 **网络地址** | 输入图源 JSON 的 URL 直接导入（如图源站分享链接） |
| 📁 **本地文件** | 选择本地 `.json` / `.txt` 图源文件导入 |
| 📷 **二维码** | 扫描图源二维码快速导入 |

图源规则格式参考：[异次元图源站](https://www.yckceo.com/yiciyuan/tuyuan/index.html)

### 🛡️ Cloudflare 适配
- 部分图源站受 Cloudflare 防护，内置「WebView 过验证」功能，手动通过验证后自动同步 Cookie

### 🔄 应用内更新
- 自动检测 GitHub Releases 最新版本，发现新版本时弹窗提示，一键跳转下载
- 支持 Android (.apk)、iOS (.ipa)、Windows (.zip) 三平台分发

### 🎨 界面
- Material 3 暗色主题，护眼舒适
- 响应式布局，适配手机 / 平板 / 桌面

---

## 📦 下载安装

前往 [Releases](https://github.com/2016YYy/comic-realm/releases) 页面下载对应平台的安装包：

| 平台 | 文件 | 说明 |
|------|------|------|
| Android | `app-arm64-v8a-release.apk` | 推荐，适配绝大多数现代安卓设备 |
| Android | `app-armeabi-v7a-release.apk` | 32 位旧设备 |
| iOS | `comic-realm-ios.ipa` | 需自签或越狱安装 |
| Windows | `comic-realm-windows.zip` | 解压后运行 `comic_realm.exe` |

---

## 🚀 快速开始

### 从源码构建

环境要求：
- Flutter SDK `>= 3.19.0`
- Android Studio（Android 构建）/ Xcode（iOS 构建）/ Visual Studio（Windows 构建）

```bash
# 1. 克隆仓库
git clone https://github.com/2016YYy/comic-realm.git
cd comic-realm

# 2. 安装依赖
flutter pub get

# 3. 运行
flutter run

# 4. 构建
flutter build apk --release      # Android
flutter build ios --release      # iOS
flutter build windows --release  # Windows
```

### 添加图源

1. 打开应用 → 底部「图源」
2. 点击右上角「+」
3. 选择导入方式（网络地址 / 本地文件 / 二维码）
4. 导入成功后即可在搜索中使用该图源

---

## 🛠️ 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | [Flutter](https://flutter.dev) / Dart |
| 状态管理 | Provider |
| 网络请求 | Dio + CookieJar |
| HTML 解析 | html / csslib |
| JS 引擎 | flutter_js (QuickJS) — 执行图源规则中的解码脚本 |
| 本地存储 | Hive |
| 图片缓存 | cached_network_image |
| 二维码 | mobile_scanner |
| 持续集成 | GitHub Actions |

---

## 📁 项目结构

```
comic_realm/
├── lib/
│   ├── main.dart              # 入口
│   ├── app.dart               # 应用根组件 & 主题
│   ├── core/
│   │   ├── http_client.dart   # HTTP 客户端（Cookie / UA）
│   │   ├── source_engine.dart # 图源规则解析引擎
│   │   ├── js_runtime.dart    # JS 运行时
│   │   ├── database.dart      # Hive 数据库
│   │   └── updater.dart       # GitHub 版本更新检查
│   ├── models/                # 数据模型
│   ├── services/              # 业务服务
│   └── screens/               # 界面
├── assets/                    # 资源
├── .github/workflows/         # CI/CD
├── pubspec.yaml
└── README.md
```

---

## ⚠️ 免责声明

本软件为开源漫画阅读器，**本身不存储、不上传任何漫画内容**，仅作为用户访问第三方图源网站的解析与阅读工具。所有漫画作品的版权归原作者及图源网站所有。

- 本软件仅供个人学习交流使用，**严禁用于任何商业用途**
- 使用者应遵守所在国家或地区的法律法规
- 因使用本软件产生的一切法律责任由使用者自行承担
- 如本软件的任何内容侵犯了您的合法权益，请通过 [GitHub Issue](https://github.com/2016YYy/comic-realm/issues) 联系开发者，我们将在第一时间处理

---

## 📄 开源协议

[MIT License](LICENSE) © ComicRealm Contributors
