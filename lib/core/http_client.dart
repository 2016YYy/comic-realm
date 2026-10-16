import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:charset/charset.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'native_cookie_manager.dart';

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

  // -------------------- Gatekeeper PoW 自动过验证 --------------------

  static const _gkPowPrefix = 'gatekeeper-pow-v1:';

  /// 判断响应是否为 Gatekeeper 挑战（两种形态）：
  /// 1. 403 + JSON `{"challenge_url":"...","error":"challenge_required"}`
  /// 2. 浏览器验证 HTML（含 challengeId / gatekeeper-pow），状态码可能是 200 或 403
  bool _isGatekeeperChallenge(Response resp) {
    final text = _respText(resp);
    if (text == null) return false;
    if (text.contains('challenge_required')) return true;
    // HTML 挑战页特征：同时包含 challengeId 与 gatekeeper
    if (text.contains('challengeId') && text.contains('gatekeeper')) {
      return true;
    }
    return false;
  }

  String? _respText(Response resp) {
    final data = resp.data;
    if (data is List<int>) {
      try {
        return utf8.decode(data, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    if (data is String) return data;
    return null;
  }

  /// 从 challenge HTML 中解析参数。
  _GkParams? _parseGkParams(String html) {
    final cid = RegExp(r'challengeId\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);
    final ticket = RegExp(r'ticket\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);
    final diffStr =
        RegExp(r'difficultyBits\s*:\s*(\d+)').firstMatch(html)?.group(1);
    final verifyPath =
        RegExp(r'verifyUrl\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);
    if (cid == null || ticket == null || diffStr == null) return null;
    return _GkParams(
      challengeId: cid,
      ticket: ticket,
      difficulty: int.tryParse(diffStr) ?? 16,
      verifyPath: verifyPath ?? '/__gatekeeper_challenge/verify',
    );
  }

  /// 解 Gatekeeper PoW：找到 nonce 使 SHA-256(_gkPowPrefix + challengeId + ':' + nonce)
  /// 的前 [difficultyBits] 位为 0。
  String _solvePow(String challengeId, int difficultyBits) {
    final prefixBytes = utf8.encode('$_gkPowPrefix$challengeId:');
    final fullByteCount = difficultyBits ~/ 8;
    final remBits = difficultyBits % 8;
    var nonce = 0;
    while (true) {
      final msg = [...prefixBytes, ...utf8.encode(nonce.toString())];
      final h = sha256.convert(msg).bytes;
      var ok = true;
      for (var i = 0; i < fullByteCount; i++) {
        if (h[i] != 0) {
          ok = false;
          break;
        }
      }
      if (ok && remBits > 0) {
        final mask = (0xFF << (8 - remBits)) & 0xFF;
        if ((h[fullByteCount] & mask) != 0) ok = false;
      }
      if (ok) return nonce.toString();
      nonce++;
    }
  }

  /// 处理 Gatekeeper 挑战：优先走原生求解器（复用 TLS 会话），失败后回退到 Dart 求解。
  ///
  /// 关键点：`__Host-gk_browser_*` 绑定 cookie 必须与 verify 请求处于同一 TLS 会话，
  /// 否则服务端返回 `binding_mismatch`。dart:io HttpClient 不复用 HTTPS 连接，
  /// 因此移动端优先使用原生 HTTP 栈（Android HttpURLConnection / iOS URLSession）。
  Future<void> _solveGatekeeperChallenge(String requestUrl) async {
    try {
      // 1. 优先调用原生求解器（Android / iOS）
      final clearanceRaw = await NativeCookieManager.solveGatekeeper(requestUrl);
      if (clearanceRaw != null && clearanceRaw.isNotEmpty) {
        final uri = Uri.parse(requestUrl);
        for (final sc in clearanceRaw) {
          try {
            final cookie = io.Cookie.fromSetCookieValue(sc);
            await _cookieJar?.saveFromResponse(uri, [cookie]);
          } catch (_) {}
        }
        return;
      }

      // 2. 回退：Dart 端求解（桌面端 / 原生不可用时；可能因 TLS 会话绑定失败）
      await _solveGatekeeperChallengeDart(requestUrl);
    } catch (e) {
      // 静默失败，由调用方根据重试结果决定是否提示用户手动过验证
    }
  }

  /// Dart 端 Gatekeeper PoW 求解（桌面端回退方案）。
  Future<void> _solveGatekeeperChallengeDart(String requestUrl) async {
    final uri = Uri.parse(requestUrl);
    final startUrl =
        '${uri.scheme}://${uri.host}/__gatekeeper_challenge/start?return=%2F';
    final startUri = Uri.parse(startUrl);
    final ua = _dio.options.headers['User-Agent']?.toString() ??
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36';

    // 专用 dio：不挂 CookieManager，避免其覆盖手动 Cookie 头
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'User-Agent': ua},
    ));

    // 1. 拉取 challenge start 页，获取绑定 cookie + 挑战参数
    final resp1 = await dio.get<String>(
      startUrl,
      options: Options(
        headers: {
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
        validateStatus: (_) => true,
      ),
    );

    final browserCookies = <String, String>{};
    final setCookies1 = resp1.headers['set-cookie'] ?? [];
    for (final sc in setCookies1) {
      try {
        final c = io.Cookie.fromSetCookieValue(sc);
        browserCookies[c.name] = c.value;
      } catch (_) {}
    }

    final html = resp1.data ?? '';
    final params = _parseGkParams(html);
    if (params == null) return;

    // 2. 解 PoW
    final nonce = _solvePow(params.challengeId, params.difficulty);

    // 3. POST verify，手动附带绑定 cookie
    final verifyUrl = startUri.resolve(params.verifyPath).toString();
    final verifyUri = Uri.parse(verifyUrl);
    final cookieHeader =
        browserCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    final resp2 = await dio.post(
      verifyUrl,
      data: jsonEncode({
        'challenge_id': params.challengeId,
        'ticket': params.ticket,
        'nonce': nonce,
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Origin': '${uri.scheme}://${uri.host}',
          'Referer': startUrl,
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        },
        validateStatus: (_) => true,
      ),
    );

    // 4. 将 verify 响应的 clearance cookie 存入共享 CookieJar
    final setCookies2 = resp2.headers['set-cookie'] ?? [];
    for (final sc in setCookies2) {
      try {
        final cookie = io.Cookie.fromSetCookieValue(sc);
        await _cookieJar?.saveFromResponse(verifyUri, [cookie]);
      } catch (_) {}
    }
  }

  /// 带 Gatekeeper 重试的请求包装。
  ///
  /// 注意：章节页会从 cn.bzmgcn.com 302 跳转到 cn.cnbzmg.com，两个域名
  /// 各自需要独立的 Gatekeeper 验证。因此使用 [Response.realUri]（跳转后
  /// 的最终地址）来确定求解目标域名，并允许多次重试以应对跨域挑战。
  Future<Response<List<int>>> _getWithRetry(
    String url, {
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    // 先校验地址，避免把相对 / 空地址交给 Dio 触发
    // 「Invalid argument(s): No host specified in URI」这类底层报错。
    if (!isHttpUrl(url)) {
      throw Exception(
          '无效的请求地址（缺少主机名）：${url.trim().isEmpty ? '(空地址)' : url.trim()}');
    }
    final h = <String, String>{};
    if (userAgent != null && userAgent.isNotEmpty) {
      h['User-Agent'] = userAgent;
    }
    if (headers != null) h.addAll(headers);

    // validateStatus 接受所有状态码，以便检测 403 challenge 响应。
    final opts = Options(
      headers: h,
      responseType: ResponseType.bytes,
      validateStatus: (_) => true,
    );

    // 瞬时网络错误（Connection reset / 超时）自动退避重试。
    var resp = await _getWithTransientRetry(url, opts);
    // 最多重试 3 次，应对跨域跳转后连续触发的 Gatekeeper 挑战。
    for (var i = 0; i < 3 && _isGatekeeperChallenge(resp); i++) {
      // 使用跳转后的真实地址求解，确保原生求解器命中正确的域名。
      final target = resp.realUri.toString();
      await _solveGatekeeperChallenge(target);
      resp = await _getWithTransientRetry(url, opts);
    }
    return resp;
  }

  /// 对「连接被重置 / 连接超时 / 临时不可达」等瞬时错误做有限次退避重试。
  Future<Response<List<int>>> _getWithTransientRetry(
    String url,
    Options opts,
  ) async {
    const maxRetries = 2;
    var attempt = 0;
    while (true) {
      try {
        return await _dio.get<List<int>>(url, options: opts);
      } on DioException catch (e) {
        if (attempt < maxRetries && _isTransientError(e)) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 判断是否为可重试的瞬时网络错误。
  bool _isTransientError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        break;
    }
    final msg = e.message ?? '';
    return msg.contains('Connection reset') ||
        msg.contains('SocketException') ||
        msg.contains('timed out') ||
        msg.contains('Connection closed') ||
        msg.contains('Connection aborted');
  }

  /// 判断字符串是否为带主机名的 http(s) 地址。
  static bool isHttpUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// 发起 GET 请求，支持自定义 UA 和 Header。
  ///
  /// 自动根据响应头 / 页面 `<meta charset>` 判断编码（UTF-8 / GBK / GB2312），
  /// 避免中文源页面出现乱码导致规则匹配失败。
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    final resp = await _getWithRetry(url, headers: headers, userAgent: userAgent);
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
    final resp = await _getWithRetry(url, headers: headers, userAgent: userAgent);
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

/// Gatekeeper 挑战参数。
class _GkParams {
  final String challengeId;
  final String ticket;
  final int difficulty;
  final String verifyPath;

  _GkParams({
    required this.challengeId,
    required this.ticket,
    required this.difficulty,
    required this.verifyPath,
  });
}
