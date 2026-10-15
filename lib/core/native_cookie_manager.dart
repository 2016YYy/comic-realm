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

  /// 调用原生 Gatekeeper PoW 求解器。
  ///
  /// 原生端使用系统 HTTP 栈（Android HttpURLConnection / iOS URLSession），
  /// 其连接池会复用同一 TLS 会话，避免 dart:io HttpClient 不复用 HTTPS 连接
  /// 导致的 `binding_mismatch`。返回 verify 响应的 Set-Cookie 原始字符串列表。
  /// 不支持的平台返回 null（调用方应回退到 Dart 端求解或提示用户手动过验证）。
  static Future<List<String>?> solveGatekeeper(String url) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final result = await _channel.invokeMethod<List>(
        'solveGatekeeper',
        {'url': url},
      );
      return result?.whereType<String>().toList();
    } catch (_) {
      return null;
    }
  }
}
