import 'dart:io';

import 'package:flutter/services.dart';

/// 通过原生 CookieManager 读取指定 URL 的全部 Cookie（含 HttpOnly）。
///
/// WebView 通过 JavaScript `document.cookie` 无法读取 HttpOnly Cookie，
/// 而图源站点的反爬验证 Cookie 正是 HttpOnly，因此必须走原生接口。
class NativeCookieManager {
  static const MethodChannel _channel =
      MethodChannel('comic_realm/cookies');

  /// 获取 [url] 下的全部 Cookie，返回「name=value」列表。
  /// 不支持的平台返回空列表。
  static Future<List<Cookie>> getCookies(String url) async {
    if (!Platform.isAndroid && !Platform.isIOS) return [];
    try {
      final result = await _channel.invokeMethod<List>(
        'getCookies',
        {'url': url},
      );
      if (result == null) return [];
      return result
          .whereType<String>()
          .where((c) => c.contains('='))
          .map((c) {
        final idx = c.indexOf('=');
        return Cookie(c.substring(0, idx), c.substring(idx + 1));
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
