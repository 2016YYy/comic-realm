import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:charset/charset.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 全局 HTTP 客户端，自动管理 Cookie、UA，并支持图源自定义 UA。
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;
  HttpClient._internal();

  late Dio _dio;
  PersistCookieJar? _cookieJar;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final cookiePath = p.join(dir.path, 'cookies');
    await Directory(cookiePath).create(recursive: true);
    _cookieJar = PersistCookieJar(storage: FileStorage(cookiePath));

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    ));
    _dio.interceptors.add(CookieManager(_cookieJar!));
  }

  Dio get dio => _dio;

  PersistCookieJar get cookieJar => _cookieJar!;

  /// 发起 GET 请求，支持自定义 UA 和 Header。
  ///
  /// 自动根据响应头 / 页面 `<meta charset>` 判断编码（UTF-8 / GBK / GB2312），
  /// 避免中文源页面出现乱码导致规则匹配失败。
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    final h = <String, String>{};
    if (userAgent != null && userAgent.isNotEmpty) {
      h['User-Agent'] = userAgent;
    }
    if (headers != null) h.addAll(headers);
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(headers: h, responseType: ResponseType.bytes),
    );
    final bytes = resp.data ?? <int>[];
    final contentType = resp.headers.value('content-type') ?? '';
    return decodeBytes(bytes, contentType);
  }

  /// 按 charset 解码字节流。
  String decodeBytes(List<int> bytes, String contentType) {
    if (bytes.isEmpty) return '';
    var charset = _charsetFromContentType(contentType);
    charset ??= _sniffCharset(bytes) ?? 'utf-8';
    charset = charset.toLowerCase();
    if (charset.contains('gbk') ||
        charset.contains('gb2312') ||
        charset.contains('gb18030')) {
      try {
        return gbk.decode(bytes, allowMalformed: true);
      } catch (_) {
        // 落到 UTF-8 容错解码
      }
    }
    if (charset.contains('big5')) {
      // 无内置 Big5，退化为 UTF-8 容错
      return utf8.decode(bytes, allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _charsetFromContentType(String contentType) {
    final m = RegExp(r'charset\s*=\s*["\x27]?([\w\-]+)')
        .firstMatch(contentType.toLowerCase());
    return m?.group(1);
  }

  /// 从页面头部嗅探 charset（读取前 2KB，按 latin1 解析 ASCII 部分）。
  String? _sniffCharset(List<int> bytes) {
    final head = bytes.take(2048).toList();
    final text = latin1.decode(head, allowInvalid: true);
    final m = RegExp(r'''charset\s*=\s*["']?\s*([\w\-]+)''')
        .firstMatch(text.toLowerCase());
    return m?.group(1);
  }

  Future<List<int>> getBytes(
    String url, {
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    final h = <String, String>{};
    if (userAgent != null && userAgent.isNotEmpty) {
      h['User-Agent'] = userAgent;
    }
    if (headers != null) h.addAll(headers);
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(headers: h, responseType: ResponseType.bytes),
    );
    return resp.data ?? [];
  }

  /// 下载文件到本地路径。
  Future<void> download(String url, String savePath, {
    Map<String, String>? headers,
    String? userAgent,
    void Function(int received, int total)? onProgress,
  }) async {
    final h = <String, String>{};
    if (userAgent != null && userAgent.isNotEmpty) {
      h['User-Agent'] = userAgent;
    }
    if (headers != null) h.addAll(headers);
    await _dio.download(url, savePath,
        options: Options(headers: h, responseType: ResponseType.bytes),
        onReceiveProgress: onProgress);
  }

  /// 合并相对 URL 为绝对 URL。
  String absoluteUrl(String base, String relative) {
    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      return relative;
    }
    try {
      return Uri.parse(base).resolve(relative).toString();
    } catch (_) {
      return relative;
    }
  }
}
