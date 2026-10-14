import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
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
    final resp = await _dio.get<String>(url, options: Options(headers: h));
    return resp.data ?? '';
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
    final baseUri = Uri.parse(base);
    if (relative.startsWith('//')) {
      return '${baseUri.scheme}:$relative';
    }
    if (relative.startsWith('/')) {
      return '${baseUri.scheme}://${baseUri.host}$relative';
    }
    final basePath = base.substring(0, base.lastIndexOf('/') + 1);
    return basePath + relative;
  }
}
