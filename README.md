<div align="center">

# 漫境 ComicRealm

**一款支持自定义图源的跨平台开源漫画阅读器**

[![Flutter](https://img.shields.io/badge/Flutter-3.29-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/平台-Android%20%7C%20iOS%20%7C%20Windows-4c8bf5)](#-下载)
[![Release](https://img.shields.io/github/v/release/2016YYy/comic-realm?label=最新版本&color=2ea44f)](https://github.com/2016YYy/comic-realm/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/2016YYy/comic-realm/total?label=下载量&color=0969da)](https://github.com/2016YYy/comic-realm/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/2016YYy/comic-realm/analyze.yml?label=构建状态&logo=github)](https://github.com/2016YYy/comic-realm/actions)
[![License](https://img.shields.io/github/license/2016YYy/comic-realm?label=开源协议&color=3da639)](LICENSE)

一个纯净、自由、可扩展的漫画阅读工具。兼容 **legado（开源阅读）/ 异次元** 的图源规则，
支持自定义图源导入，让手机与桌面端都能顺畅阅读喜爱的漫画。

[下载](#-下载) · [功能特性](#-功能特性) · [图源导入](#-图源导入) · [更新日志](CHANGELOG.md) · [常见问题](#-常见问题)

</div>

> [!IMPORTANT]
> 本软件**不提供、不存储、不上传任何漫画内容**，仅作为访问第三方图源网站的解析与阅读工具。
> 首次使用请先[导入图源](#-图源导入)。

---

## 🧭 目录

- [简介](#-简介)
- [功能特性](#-功能特性)
- [下载](#-下载)
- [图源导入](#-图源导入)
- [从源码构建](#-从源码构建)
- [项目结构](#-项目结构)
- [技术栈](#-技术栈)
- [更新日志](#-更新日志)
- [常见问题](#-常见问题)
- [贡献](#-贡献)
- [免责声明](#-免责声明)
- [开源协议](#-开源协议)

---

## 📖 简介

**漫境 ComicRealm** 是一个基于 Flutter 开发的跨平台漫画阅读器。

市面上多数阅读器要么图源封闭、要么平台单一。漫境的目标是做一个**开放、可扩展、全平台**的阅读工具：
沿用 legado / 异次元 社区已经积累的图源规则，让你不必为换设备、换软件重新适应，一个规则即可解析全站漫画。

软件本身不含任何内容，所有漫画均来自你自行导入的图源；你可以自由增删图源、调整顺序、按需启用。

---

## ✨ 功能特性

### 📚 阅读
- **多图源聚合搜索** —— 一次搜索命中所有已启用图源，结果标注来源图源，并支持按图源筛选
- **发现页 / 分类浏览** —— 选中某个图源即可查看它的漫画分类，逐类浏览
- **漫画详情与阅读** —— 章节列表、上下滑动连续翻页
- **书库收藏** —— 收藏喜爱的漫画，随时续读
- **离线下载** —— 一键下载章节到本地，断网也能看

### 🔌 图源
- **兼容主流规则格式** —— 支持 legado（开源阅读）/ 异次元 图源 JSON 规则，含 `class./id./tag.` 前缀选择器、链式选择器、`@attr`、JSONPath、`@js` 脚本、`@Header` 请求头与 `##` 替换
- **多种导入方式** —— 网络地址 / 本地文件 / 二维码，并自动识别 Base64、zlib、gzip 等压缩载荷
- **图源管理** —— 启用 / 停用、删除
- **Cloudflare 适配** —— 内置 WebView 验证入口，手动通过验证后自动同步 Cookie

### 🎨 体验
- **应用内更新** —— 自动检测 GitHub Releases 新版本，一键跳转下载
- **Material 3 暗色主题** —— 护眼舒适
- **响应式布局** —— 适配手机 / 平板 / 桌面

---

## 📦 下载

前往 [Releases](https://github.com/2016YYy/comic-realm/releases/latest) 页面下载对应平台的安装包：

| 平台 | 安装包 | 说明 |
|------|--------|------|
| Android | `ComicRealm-v<版本>-android-arm64-v8a.apk` | **推荐**，适配绝大多数现代安卓设备 |
| Android | `ComicRealm-v<版本>-android-armeabi-v7a.apk` | 32 位老旧设备 |
| Android | `ComicRealm-v<版本>-android-x86_64.apk` | 模拟器 / x86 设备 |
| Windows | `ComicRealm-v<版本>-windows-x64.zip` | 解压后运行 `comic_realm.exe` |
| iOS | `ComicRealm-v<版本>-ios-unsigned.ipa` | 免签名包，需自行签名后安装 |

**兼容性**

| 平台 | 最低版本 | 备注 |
|------|----------|------|
| Android | 5.0 (API 21) | 三种 ABI 均已分别打包 |
| iOS | 13.0 | 分发为免签名包，需自签（AltStore / 自建证书） |
| Windows | 10 x64 | 解压即用，无需安装 |

### 发布产物命名规范

所有发布产物遵循统一命名规则，便于脚本与更新器识别：

```
<应用名>-v<语义化版本>-<平台>-<架构>.<扩展名>
```

| 片段 | 取值 | 示例 |
|------|------|------|
| 应用名 | 固定 `ComicRealm` | `ComicRealm` |
| 版本号 | 与 Git 标签一致（[语义化版本](https://semver.org/lang/zh-CN/)） | `v1.0.2` |
| 平台 | `android` / `windows` / `ios` | `android` |
| 架构 | `arm64-v8a` / `armeabi-v7a` / `x86_64` / `x64` | `arm64-v8a` |
| 扩展名 | `.apk` / `.zip` / `.ipa` | `.apk` |

完整示例：`ComicRealm-v1.0.2-android-arm64-v8a.apk`

> 版本号统一在 [`pubspec.yaml`](pubspec.yaml) 的 `version` 字段维护，Git 标签与之一致（如 `v1.0.2`）。

---

## 🔌 图源导入

漫境本身不含内容，需要你先导入图源。打开应用 → 底部 **「图源」** → 右上角 **「+」**，支持三种方式：

| 方式 | 说明 |
|------|------|
| 🌐 **网络地址** | 输入图源 JSON 的 URL 直接导入 |
| 📁 **本地文件** | 选择本地 `.json` / `.txt` 图源文件 |
| 📷 **二维码** | 扫描图源二维码导入 |

图源规则格式参考：[异次元图源站](https://www.yckceo.com/yiciyuan/tuyuan/index.html)

导入成功后：
1. 在「图源」页点击任一图源，进入**发现页**查看它的分类，逐类浏览；
2. 或到「搜索」页输入关键词，跨图源搜索漫画。

> Windows / iOS 端同样支持导入，规则格式与移动端完全一致。

---

## 🚀 从源码构建

**环境要求**

- [Flutter SDK](https://flutter.dev) `>= 3.19.0`（CI 使用 `3.29.3`）
- Android：Android Studio + JDK 17
- iOS：Xcode（仅 macOS）
- Windows：Visual Studio 2022（含「使用 C++ 的桌面开发」工作负载）

```bash
# 1. 克隆仓库
git clone https://github.com/2016YYy/comic-realm.git
cd comic-realm

# 2. 拉取依赖
flutter pub get

# 3. 运行（连接设备或启动模拟器）
flutter run

# 4. 构建发布包
flutter build apk --release --split-per-abi   # Android
flutter build windows --release               # Windows
flutter build ios --release --no-codesign     # iOS（免签名）
```

> 三平台发布包由 GitHub Actions 在推送 `v*.*.*` 标签时自动构建并发布，见
> [`.github/workflows/build.yml`](.github/workflows/build.yml)。

---

## 📁 项目结构

```
comic_realm/
├── lib/
│   ├── main.dart                    # 入口
│   ├── app.dart                     # 应用根组件 & 主题
│   ├── core/
│   │   ├── http_client.dart         # HTTP 客户端（Cookie / UA / 编码识别）
│   │   ├── source_engine.dart       # 图源规则解析引擎
│   │   ├── rule_parser.dart         # 规则语法解析
│   │   ├── json_path.dart           # JSONPath 求值
│   │   ├── js_runtime.dart          # JS 运行时（规则内脚本）
│   │   ├── database.dart            # Hive 数据库
│   │   └── updater.dart             # GitHub 版本更新检查
│   ├── models/                      # 数据模型
│   ├── services/                    # 业务服务
│   └── screens/                     # 界面
├── assets/                          # 资源
├── .github/workflows/               # CI/CD
├── pubspec.yaml
├── CHANGELOG.md
└── README.md
```

---

## 🛠️ 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | [Flutter](https://flutter.dev) / Dart |
| 状态管理 | Provider |
| 网络请求 | Dio + CookieJar |
| HTML 解析 | html / csslib |
| JS 引擎 | flutter_js (QuickJS)，执行图源规则中的解码脚本 |
| 本地存储 | Hive |
| 图片缓存 | cached_network_image |
| 二维码 | mobile_scanner |
| 持续集成 | GitHub Actions |

---

## 📝 更新日志

每个版本的**新增、变更与修复**记录在 [CHANGELOG.md](CHANGELOG.md)，遵循
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范与
[语义化版本](https://semver.org/lang/zh-CN/)。

最新版本摘要：

- **新增** 图源发现页：选中图源即可查看分类、浏览、收藏与阅读
- **修复** 图源无法导入（压缩载荷解码失败）
- **修复** 搜索无结果且无错误提示

> 发布流程：先在 `CHANGELOG.md` 中补充 `## [版本号]` 小节，再推送 `v<版本号>` 标签；
> GitHub Release 的说明会自动取自该小节（新增 / 变更 / 修复 + 下载指引），无需手写。

---

## ❓ 常见问题

<details>
<summary><b>搜索不到漫画？</b></summary>

1. 确认图源已**启用**（图源页开关为打开状态）；
2. 在搜索页展开「失败明细」，查看是哪个图源报错以及报错原因；
3. 部分图源站点需要先通过 Cloudflare 验证：设置 → **WebView 过 Cloudflare 验证**。

</details>

<details>
<summary><b>图源导入失败 / 提示格式不对？</b></summary>

漫境兼容 legado / 异次元 标准格式，并支持 Base64、zlib、gzip 压缩载荷。
请确认导入的是**图源 JSON**（而非网页链接）；仍失败时可在 Issue 中附上图源地址以便定位。

</details>

<details>
<summary><b>阅读时图片加载不出来？</b></summary>

多为图源站点限流或防盗链所致：可在设置中调整请求头 / User-Agent，或更换同内容的其它图源。

</details>

---

## 🤝 贡献

欢迎提交 Issue 与 Pull Request。提交前建议：

1. 先搜索是否已有相同 [Issue](https://github.com/2016YYy/comic-realm/issues)；
2. 运行 `flutter analyze` 与 `flutter test` 确保通过；
3. 提交信息可参考 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 风格（`feat:` / `fix:` / `docs:` …）。

---

## ⚠️ 免责声明

本软件为开源漫画阅读器，**本身不存储、不上传任何漫画内容**，仅作为用户访问第三方图源网站的解析与阅读工具。
所有漫画作品的版权归原作者及图源网站所有。

- 本软件仅供个人学习交流使用，**严禁用于任何商业用途**
- 使用者应遵守所在国家或地区的法律法规
- 因使用本软件产生的一切法律责任由使用者自行承担

---

## 📄 开源协议

[MIT License](LICENSE) © ComicRealm Contributors

## 🙏 致谢

- [legado（开源阅读）](https://github.com/gedoor/legado) —— 图源规则格式的参考与灵感来源
- [异次元](https://www.yckceo.com/yiciyuan/tuyuan/index.html) —— 图源生态与规则示例
- Flutter 及所有开源依赖的作者
