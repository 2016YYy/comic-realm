import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final bool isNewer;
  final Map<String, String> assets; // platform -> download url

  AppUpdate({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isNewer,
    required this.assets,
  });
}

/// 应用内更新检查器：从 GitHub Releases 拉取最新版本。
class Updater {
  final String owner;
  final String repo;
  final Dio _dio = Dio();

  Updater({required this.owner, required this.repo});

  Future<AppUpdate?> checkUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;

    try {
      final resp = await _dio.get(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      if (resp.statusCode != 200) return null;
      final data = resp.data;
      final tag = (data['tag_name'] ?? '').toString().replaceAll('v', '');
      final body = (data['body'] ?? '').toString();
      final assets = <String, String>{};
      final assetList = data['assets'] as List? ?? [];
      String? defaultUrl;
      for (final a in assetList) {
        final name = (a['name'] ?? '').toString().toLowerCase();
        final url = a['browser_download_url']?.toString() ?? '';
        if (url.isEmpty) continue;
        defaultUrl ??= url;
        if (name.endsWith('.apk') || name.contains('android')) {
          assets['android'] = url;
        } else if (name.endsWith('.ipa') || name.contains('ios')) {
          assets['ios'] = url;
        } else if (name.endsWith('.exe') || name.endsWith('.msix') || name.contains('windows')) {
          assets['windows'] = url;
        }
      }
      final isNewer = _compareVersion(tag, current) > 0;
      return AppUpdate(
        version: tag,
        downloadUrl: defaultUrl ?? '',
        releaseNotes: body,
        isNewer: isNewer,
        assets: assets,
      );
    } catch (e) {
      return null;
    }
  }

  /// 比较版本号，返回 >0 表示 a 更新。
  int _compareVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}
