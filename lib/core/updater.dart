import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 一次可用的更新信息
class AppUpdate {
  final String version;
  final String releaseNotes;
  final bool isNewer;

  /// Release 页面地址（打不开直链时的兜底）
  final String releasePageUrl;

  /// 本机平台对应的安装包直链，可能为空
  final String downloadUrl;

  /// platform -> 文件名
  final Map<String, String> assets;

  /// platform -> 下载直链
  final Map<String, String> assetUrls;

  AppUpdate({
    required this.version,
    required this.releaseNotes,
    required this.isNewer,
    required this.releasePageUrl,
    required this.downloadUrl,
    required this.assets,
    required this.assetUrls,
  });

  /// 本机平台对应的安装包文件名
  String get fileName {
    final name = assets[platformKey];
    if (name != null && name.isNotEmpty) return name;
    return 'ComicRealm-v$version-installer';
  }

  /// 当前平台在 Release 产物里的标识
  static String get platformKey {
    if (kIsWeb) return 'other';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'other';
    }
  }

  static bool get isAndroid => platformKey == 'android';
  static bool get isIOS => platformKey == 'ios';
  static bool get isWindows => platformKey == 'windows';
}

/// 应用内更新检查器：从 GitHub Releases 拉取最新版本。
class Updater {
  final String owner;
  final String repo;
  final Dio _dio;

  Updater({required this.owner, required this.repo, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ));

  /// 查询最新 Release；失败（网络异常 / 非 200）返回 null。
  Future<AppUpdate?> checkUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;

    try {
      final resp = await _dio.get(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
        options: Options(headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'ComicRealm/$current',
        }),
      );
      if (resp.statusCode != 200) return null;
      final data = resp.data;
      if (data is! Map) return null;

      final version = stripV((data['tag_name'] ?? '').toString());
      final body = (data['body'] ?? '').toString();
      final releasePageUrl = (data['html_url'] ?? '').toString();

      final assetNames = <String, String>{};
      final assetUrls = <String, String>{};
      final assetList = data['assets'];
      if (assetList is List) {
        for (final a in assetList) {
          if (a is! Map) continue;
          final name = (a['name'] ?? '').toString();
          final url = (a['browser_download_url'] ?? '').toString();
          if (name.isEmpty || url.isEmpty) continue;
          final key = classifyAsset(name);
          if (key == null) continue;
          // Android 侧优先 arm64：绝大多数在用设备都是 64 位
          final existing = assetNames[key];
          if (key == 'android' &&
              existing != null &&
              !name.toLowerCase().contains('arm64')) {
            continue;
          }
          assetNames[key] = name;
          assetUrls[key] = url;
        }
      }

      return AppUpdate(
        version: version,
        releaseNotes: body,
        isNewer: compareVersion(version, current) > 0,
        releasePageUrl: releasePageUrl,
        downloadUrl: assetUrls[AppUpdate.platformKey] ?? '',
        assets: assetNames,
        assetUrls: assetUrls,
      );
    } catch (_) {
      return null;
    }
  }

  /// 安装包文件名 -> 平台标识
  static String? classifyAsset(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.apk')) return 'android';
    if (n.endsWith('.ipa')) return 'ios';
    if (n.endsWith('.exe') || n.endsWith('.msix') || n.endsWith('.zip')) {
      return 'windows';
    }
    if (n.endsWith('.dmg') || n.contains('macos')) return 'macos';
    if (n.endsWith('.deb') || n.endsWith('.appimage')) return 'linux';
    return null;
  }

  /// 去掉可能的前导 v，例如 v1.0.2 -> 1.0.2
  static String stripV(String tag) {
    var t = tag.trim();
    if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
    return t;
  }

  /// 比较版本号，返回 >0 表示 a 更新（支持 1.2.3 / 1.2.3-beta 之类的写法）
  static int compareVersion(String a, String b) {
    final pa = _numeric(a);
    final pb = _numeric(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  static List<int> _numeric(String version) => version
      .split('.')
      .map((e) => int.tryParse(RegExp(r'^\d+').firstMatch(e)?.group(0) ?? '') ?? 0)
      .toList();
}
