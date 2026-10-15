# 更新日志

本项目的所有重要变更都会记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.0.2] - 2026-10-15

### Added

- 图源「发现」页：选中图源即可查看它的漫画分类，逐类浏览并进入阅读
- 搜索页新增图源筛选、结果计数，以及逐图源失败原因展开显示，便于定位问题图源
- 兼容 legado（开源阅读）图源的嵌套规则结构：`ruleSearch` / `ruleBookInfo` / `ruleToc` / `ruleContent`
- 新增 JSONPath 规则求值引擎与统一的规则解析器，支持 `class./id./tag.` 前缀选择器、链式选择器、`@attr`、`@js`、`@Header` 与 `##` 替换

### Changed

- 图源导入支持明文 JSON、Base64、Base64+zlib、Base64+gzip 及 URL-safe Base64 等多种载荷
- 内置图源由占位源替换为真实可用的「包子漫画」源
- HTTP 请求按响应头与页面 `<meta charset>` 自动识别 GBK / GB2312 / UTF-8 编码
- 发布产物统一命名规范为 `ComicRealm-v<版本>-<平台>-<架构>.<扩展名>`，与 [README](README.md#发布产物命名规范) 下载表格保持一致

### Fixed

- 修复部分图源导入失败、提示「格式不对」的问题（压缩载荷无法解码）
- 修复搜索不到漫画且无任何错误提示、无法定位出错图源的问题
- 修复拼接相对地址时丢失端口的问题（`absoluteUrl`）

## [1.0.1] - 2026-10-15

### Changed

- 移除免责声明中「侵权联系开发者」相关表述
- 测试改用纯逻辑的图源解析用例，移除依赖原生插件的冒烟测试

## [1.0.0] - 2026-10-15

### Added

- 首个版本：漫境 ComicRealm 多图源漫画阅读器
- 图源导入（网络地址 / 本地文件 / 二维码）与图源管理
- 漫画搜索、详情与阅读，书库收藏与离线下载
- WebView 过 Cloudflare 验证
- 应用内更新（GitHub Releases）
- Android / iOS / Windows 三平台自动构建与发布

[Unreleased]: https://github.com/2016YYy/comic-realm/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/2016YYy/comic-realm/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/2016YYy/comic-realm/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/2016YYy/comic-realm/releases/tag/v1.0.0
