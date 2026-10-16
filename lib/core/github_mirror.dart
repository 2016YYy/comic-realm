import 'dart:async';

import 'package:dio/dio.dart';

/// GitHub 加速镜像工具。
///
/// 国内直连 github.com 下载 Release 安装包经常非常慢，甚至长时间卡住，
/// 这里把原始直链重写到若干公共加速镜像上，并在下载前做一次并发测速，
/// 自动选用最快可用的镜像；下载中途失败还能按顺序回退到下一个候选。
class GithubMirror {
  GithubMirror._();

  /// 公共加速前缀（形如 `https://xxx/`，后接完整 github 地址）。
  ///
  /// 这些是常见的 GitHub 反向代理，对 Release 资源与 API 都能加速。
  /// 若某个镜像失效，测速与回退机制会自动跳过它。
  static const List<String> prefixes = [
    'https://ghfast.top/',
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
    'https://github.moeyy.xyz/',
    'https://gh.llkk.cc/',
  ];

  /// 是否为可被加速的 GitHub 地址。
  static bool isGithubUrl(String url) {
    final u = url.trim().toLowerCase();
    return u.startsWith('https://github.com/') ||
        u.startsWith('https://raw.githubusercontent.com/') ||
        u.startsWith('https://objects.githubusercontent.com/') ||
        u.startsWith('https://codeload.github.com/') ||
        u.startsWith('https://api.github.com/');
  }

  /// 把原始地址套到镜像前缀后面。
  static String rewrite(String url, String prefix) {
    final p = prefix.endsWith('/') ? prefix : '$prefix/';
    return '$p$url';
  }

  /// 生成候选地址列表：[直连, ...镜像]。非 GitHub 地址原样返回。
  static List<String> candidates(String url, {bool directFirst = true}) {
    if (!isGithubUrl(url)) return [url];
    final list = <String>[];
    if (directFirst) list.add(url);
    for (final p in prefixes) {
      list.add(rewrite(url, p));
    }
    if (!directFirst) list.add(url);
    return list;
  }

  /// 并发探测各候选地址，返回响应最快的可用地址；全部失败返回 null。
  static Future<String?> pickFastest(
    List<String> urls, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (urls.isEmpty) return null;
    if (urls.length == 1) {
      return await _probe(urls.first, timeout) ? urls.first : null;
    }
    final completer = Completer<String?>();
    var pending = urls.length;
    for (final u in urls) {
      unawaited(_probe(u, timeout).then((ok) {
        if (ok && !completer.isCompleted) completer.complete(u);
        if (--pending == 0 && !completer.isCompleted) completer.complete(null);
      }));
    }
    return completer.future;
  }

  /// 探测单个地址是否可用（HEAD + `Range: bytes=0-0`，跟随重定向，短超时）。
  static Future<bool> _probe(String url, Duration timeout) async {
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      followRedirects: true,
    ));
    try {
      final resp = await dio.head(
        url,
        options: Options(
          headers: const {'Range': 'bytes=0-0'},
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      return resp.statusCode != null && resp.statusCode! < 400;
    } catch (_) {
      return false;
    } finally {
      dio.close(force: true);
    }
  }
}
