# 更新日志

本项目的所有重要变更都会记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.0.4] - 2026-10-15

### 修复

- 统一发布签名：修正 `build.gradle.kts` 中 `signingConfigs` 与 `buildTypes` 的声明顺序，确保 release 构建始终使用 `release-keystore.jks` 签名，后续版本升级签名一致
- 内置图源「包子漫画」恢复可用：站点启用 Gatekeeper PoW 反爬后，通过原生 HTTP 栈（Android HttpURLConnection / iOS URLSession）自动求解挑战，解决了 `dart:io HttpClient` 不复用 HTTPS 连接导致的 `binding_mismatch`
- 原生求解器同时返回 browser cookie 与 clearance cookie，保证重试请求能通过验证
- 修复跨域 Gatekeeper：章节页从 `cn.bzmgcn.com` 302 跳转到 `cn.cnbzmg.com` 后，使用响应的真实地址（`realUri`）而非原始请求地址求解挑战，确保命中正确域名；允许多次重试应对连续挑战
- 清理调试代码与临时文件

### 变更

- Gatekeeper PoW 求解逻辑下沉到原生层，Dart 端仅负责触发与保存 clearance cookie
- iOS 端通过 `HTTPCookieStorage` 自动管理验证过程中的 cookie
- 将线上集成测试从 `flutter test` 自动运行中移出（需真机 + 原生求解器），避免 CI 误报

## [1.0.3] - 2026-10-15

### 新增

- 应用内更新中心：检查更新 → 查看更新说明 → 下载 → 安装，全程在应用内完成，支持实时进度条、暂停与断点续传
- 后台下载：切到后台或锁屏都会继续下载更新包，通知栏显示实时进度，点击完成通知可直接安装
- 书架支持网格 / 紧凑 / 列表三种视图，以及按最近加入 / 最近阅读 / 标题 / 图源排序
- 新增 8 套主题种子色，以及跟随系统 / 浅色 / 深色三种主题模式
- 新增阅读历史记录与阅读进度记录（最多保留 300 条）
- 新增数据备份 / 恢复：图源、收藏、阅读历史与偏好设置可导出为单个 JSON 并一键还原

### 变更

- 重构书架 / 发现 / 下载 / 图源 / 设置五个主页面与阅读器，统一为 Material 3 主题与组件体系
- 全应用的颜色由主题种子色派生，移除页面内写死的颜色，深色模式统一为沉浸式暗色背景
- 统一漫画封面组件（`ComicCover`）与加载 / 空态 / 错误态组件（`LoadingView` / `EmptyView` / `ErrorView`）
- 设置页整合外观、阅读、更新、数据、关于等入口
- 移除已被取代的旧首页，导航统一为底部五个标签页
- 系统要求：Android 最低 6.0（API 23），iOS 最低 14.0，以满足后台下载组件的要求

### 修复

- 修复 release 包缺少 `INTERNET` 网络权限，导致正式版无法访问任何图源
- 修复应用内更新缺少 `REQUEST_INSTALL_PACKAGES` 安装权限与 APK 包可见性，下载完成后无法调起系统安装界面
- 修复后台下载通知因分组配置导致不显示单任务进度条、`{progress}` 占位符不生效的问题
- 修复 Android 13+ 下载进度通知缺少运行时通知权限的问题

## [1.0.2] - 2026-10-15

### 新增

- 图源「发现」页：选中图源即可查看它的漫画分类，逐类浏览并进入阅读
- 搜索页新增图源筛选、结果计数，以及逐图源失败原因展开显示，便于定位问题图源
- 兼容 legado（开源阅读）图源的嵌套规则结构：`ruleSearch` / `ruleBookInfo` / `ruleToc` / `ruleContent`
- 新增 JSONPath 规则求值引擎与统一的规则解析器，支持 `class./id./tag.` 前缀选择器、链式选择器、`@attr`、`@js`、`@Header` 与 `##` 替换

### 变更

- 图源导入支持明文 JSON、Base64、Base64+zlib、Base64+gzip 及 URL-safe Base64 等多种载荷
- 内置图源由占位源替换为真实可用的「包子漫画」源
- HTTP 请求按响应头与页面 `<meta charset>` 自动识别 GBK / GB2312 / UTF-8 编码
- 发布产物统一命名规范为 `ComicRealm-v<版本>-<平台>-<架构>.<扩展名>`，与 [README](README.md#发布产物命名规范) 下载表格保持一致

### 修复

- 修复部分图源导入失败、提示「格式不对」的问题（压缩载荷无法解码）
- 修复搜索不到漫画且无任何错误提示、无法定位出错图源的问题
- 修复拼接相对地址时丢失端口的问题（`absoluteUrl`）

## [1.0.1] - 2026-10-15

### 变更

- 移除免责声明中「侵权联系开发者」相关表述
- 测试改用纯逻辑的图源解析用例，移除依赖原生插件的冒烟测试

## [1.0.0] - 2026-10-15

### 新增

- 首个版本：漫境 ComicRealm 多图源漫画阅读器
- 图源导入（网络地址 / 本地文件 / 二维码）与图源管理
- 漫画搜索、详情与阅读，书库收藏与离线下载
- WebView 过 Cloudflare 验证
- 应用内更新（GitHub Releases）
- Android / iOS / Windows 三平台自动构建与发布

[Unreleased]: https://github.com/2016YYy/comic-realm/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/2016YYy/comic-realm/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/2016YYy/comic-realm/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/2016YYy/comic-realm/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/2016YYy/comic-realm/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/2016YYy/comic-realm/releases/tag/v1.0.0
