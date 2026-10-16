import 'dart:convert';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/database.dart';
import '../core/http_client.dart';
import '../core/source_engine.dart';
import '../models/source.dart';
import 'comic_service.dart';

/// 单图源检测结果。
class DetectResult {
  /// 图源是否仍然有效（网络可达）。
  final bool valid;

  /// 失效时的友好错误信息。
  final String? error;

  /// 是否成功自动更新了规则。
  final bool updated;

  DetectResult({required this.valid, this.error, this.updated = false});
}

/// 批量检测汇总。
class DetectSummary {
  final int total;
  final int valid;
  final int deleted;
  final int updated;
  final List<DetectFailure> failures;

  DetectSummary({
    required this.total,
    required this.valid,
    required this.deleted,
    required this.updated,
    required this.failures,
  });
}

class DetectFailure {
  final String sourceName;
  final String error;
  DetectFailure(this.sourceName, this.error);
}

class SourceService extends ChangeNotifier {
  final SourceEngine engine = SourceEngine();

  List<ComicSource> get allSources => AppDatabase.sources.values.toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));

  List<ComicSource> get enabledSources =>
      allSources.where((s) => s.enable).toList();

  /// 从 JSON 字符串导入图源（支持单个对象、数组、Base64 / zlib / gzip 压缩载荷）
  Future<List<ComicSource>> importFromJson(String raw) async {
    final text = decodePayload(raw);
    if (text == null) {
      throw const FormatException(
          '图源格式无法识别：既不是合法 JSON，也不是受支持的 Base64 / zlib / gzip 载荷');
    }
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (e) {
      throw FormatException('图源 JSON 解析失败：$e');
    }
    // 兼容 { "bookSources": [...] } 之类的包裹结构
    if (data is Map && data['bookSources'] is List) {
      data = data['bookSources'];
    }
    final list = data is List ? data : [data];
    final imported = <ComicSource>[];
    for (final item in list) {
      if (item is! Map) continue;
      final source = ComicSource.fromJson(Map<String, dynamic>.from(item));
      if (source.bookSourceUrl.isEmpty || source.bookSourceName.isEmpty) {
        continue;
      }
      await AppDatabase.sources.put(source.bookSourceUrl, source);
      imported.add(source);
    }
    if (imported.isEmpty) {
      throw const FormatException('未解析到有效图源（缺少 bookSourceUrl / bookSourceName）');
    }
    notifyListeners();
    return imported;
  }

  /// 从网络地址导入图源
  Future<List<ComicSource>> importFromUrl(String url) async {
    final bytes = await _downloadBytes(url);
    return importFromBytes(bytes);
  }

  /// 从本地文件导入图源
  Future<List<ComicSource>> importFromFile(String path) async {
    final bytes = await io.File(path).readAsBytes();
    return importFromBytes(bytes);
  }

  /// 从字节流导入（自动识别 UTF-8 文本 / zlib / gzip / Base64 载荷）
  Future<List<ComicSource>> importFromBytes(List<int> bytes) async {
    if (bytes.isEmpty) throw const FormatException('图源内容为空');

    // 1. 二进制压缩载荷（zlib / gzip）
    final decompressed = _tryDecompress(bytes);
    if (decompressed != null) {
      return importFromJson(utf8.decode(decompressed, allowMalformed: true));
    }

    // 2. 文本载荷（明文 JSON 或 Base64）
    final text = utf8.decode(bytes, allowMalformed: true);
    return importFromJson(text);
  }

  /// 导出图源为 JSON 字符串（支持单个或全部）。
  String exportSourcesToJson(List<ComicSource> sources) {
    final list = sources.map((s) => s.toJson()).toList();
    return jsonEncode(list);
  }

  /// 导出图源到本地文件，返回文件路径。
  Future<String> exportSourcesToFile(List<ComicSource> sources) async {
    final json = exportSourcesToJson(sources);
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final file = io.File('${dir.path}/comic_realm_sources_$stamp.json');
    await file.writeAsString(json);
    return file.path;
  }

  /// 解码文本载荷，返回 JSON 文本；无法识别时返回 null。
  @visibleForTesting
  String? decodePayload(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // 已经是 JSON
    if (_looksLikeJson(s)) return s;

    // Base64 -> 文本 / 压缩
    final bytes = _tryBase64(s);
    if (bytes != null) {
      final decompressed = _tryDecompress(bytes);
      if (decompressed != null) {
        final t = utf8.decode(decompressed, allowMalformed: true).trim();
        if (_looksLikeJson(t)) return t;
      }
      final t = utf8.decode(bytes, allowMalformed: true).trim();
      if (_looksLikeJson(t)) return t;
      // 有些站点会先 base64 再 zlib 再 base64，做一次二次尝试
      final nested = _tryBase64(t);
      if (nested != null) {
        final d = _tryDecompress(nested);
        if (d != null) {
          final t2 = utf8.decode(d, allowMalformed: true).trim();
          if (_looksLikeJson(t2)) return t2;
        }
      }
    }

    // 去 BOM / 前后杂字符后再判断一次
    final cleaned = s.replaceFirst('\uFEFF', '').trim();
    if (_looksLikeJson(cleaned)) return cleaned;

    return null;
  }

  bool _looksLikeJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// 尝试 Base64（标准 / URL-safe / 缺省补位）解码，失败返回 null。
  List<int>? _tryBase64(String s) {
    var t = s.replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return null;
    // 去除常见 data-uri 前缀
    final commaIdx = t.indexOf(',');
    if (t.startsWith('data:') && commaIdx > 0) {
      t = t.substring(commaIdx + 1);
    }
    t = t.replaceAll('-', '+').replaceAll('_', '/');
    final pad = t.length % 4;
    if (pad == 1) return null;
    if (pad == 2) t += '==';
    if (pad == 3) t += '=';
    try {
      return base64.decode(t);
    } catch (_) {
      return null;
    }
  }

  /// 尝试 zlib / 原始 deflate / gzip 解压，失败返回 null。
  List<int>? _tryDecompress(List<int> bytes) {
    if (bytes.length < 2) return null;
    // zlib 头：0x78
    if (bytes[0] == 0x78) {
      try {
        return io.ZLibCodec().decode(bytes);
      } catch (_) {}
      try {
        return io.ZLibCodec(raw: true).decode(bytes);
      } catch (_) {}
    }
    // gzip 头：0x1f 0x8b
    if (bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        return io.GZipCodec().decode(bytes);
      } catch (_) {}
    }
    // 兜底：原始 deflate
    try {
      return io.ZLibCodec(raw: true).decode(bytes);
    } catch (_) {}
    try {
      return io.ZLibCodec().decode(bytes);
    } catch (_) {}
    return null;
  }

  Future<List<int>> _downloadBytes(String url) async {
    final client = io.HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(io.HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36');
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw io.HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close();
    }
  }

  Future<void> removeSource(ComicSource source) async {
    await AppDatabase.sources.delete(source.bookSourceUrl);
    notifyListeners();
  }

  /// 触发一次刷新（例如恢复备份后）
  void reload() => notifyListeners();

  Future<void> toggleSource(ComicSource source) async {
    source.enable = !source.enable;
    await source.save();
    notifyListeners();
  }

  // -------------------- 图源有效性检测 --------------------

  /// 判断异常是否为网络级错误（说明源站不可达）。
  static bool isNetworkError(Object e) {
    final msg = e.toString();
    return msg.contains('Failed host lookup') ||
        msg.contains('SocketException') ||
        msg.contains('Connection timed out') ||
        msg.contains('Connection refused') ||
        msg.contains('connectionTimeout') ||
        msg.contains('receiveTimeout') ||
        msg.contains('connectionError');
  }

  /// 检测单个图源是否有效。
  ///
  /// - 若源站不可达（DNS / 连接拒绝 / 超时），返回 `valid: false`
  /// - 若可达，尝试从 [ComicSource.bookSourceUrl] 重新下载规则并更新
  ///   （仅当该地址返回合法图源 JSON 时才更新），返回 `valid: true, updated: true/false`
  Future<DetectResult> detectSource(ComicSource source) async {
    final dio = HttpClient().dio;
    // 用较短超时快速检测源站是否可达
    try {
      await dio.getUri(
        Uri.parse(source.bookSourceUrl),
        options: dioOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      );
    } catch (e) {
      if (isNetworkError(e)) {
        return DetectResult(valid: false, error: ComicService.friendlyError(e));
      }
      // 非网络级错误（如 4xx/5xx），源站仍在运行，视为有效
    }

    // 源站可达，尝试自动更新规则
    final updated = await _tryUpdateSource(source);
    return DetectResult(valid: true, updated: updated);
  }

  /// 检测并处理单个图源：失效则删除，有效则更新。
  ///
  /// 返回检测结果，调用方可据此提示用户。
  Future<DetectResult> detectAndHandle(ComicSource source) async {
    final result = await detectSource(source);
    if (!result.valid) {
      await removeSource(source);
    }
    return result;
  }

  /// 批量检测所有图源：失效自动删除，有效自动更新。
  ///
  /// 返回汇总信息（含被删除 / 更新的数量与失败详情）。
  Future<DetectSummary> detectAndCleanAll() async {
    final sources = allSources;
    var valid = 0;
    var deleted = 0;
    var updated = 0;
    final failures = <DetectFailure>[];

    for (final source in sources) {
      final result = await detectSource(source);
      if (result.valid) {
        valid++;
        if (result.updated) updated++;
      } else {
        deleted++;
        failures.add(DetectFailure(source.bookSourceName, result.error ?? '未知错误'));
        await AppDatabase.sources.delete(source.bookSourceUrl);
      }
    }
    notifyListeners();
    return DetectSummary(
      total: sources.length,
      valid: valid,
      deleted: deleted,
      updated: updated,
      failures: failures,
    );
  }

  /// 尝试从 [ComicSource.bookSourceUrl] 重新下载并更新图源规则。
  ///
  /// 仅当该地址返回合法的图源 JSON（单个对象或数组）时更新成功。
  Future<bool> _tryUpdateSource(ComicSource source) async {
    final url = source.bookSourceUrl;
    if (url.isEmpty) return false;
    // 仅对看起来像 JSON 地址的 URL 尝试更新，避免对普通首页误判
    if (!_looksLikeJsonUrl(url)) return false;

    try {
      final bytes = await _downloadBytes(url);
      final text = utf8.decode(bytes, allowMalformed: true);
      dynamic data;
      try {
        data = jsonDecode(text);
      } catch (_) {
        return false;
      }
      // 兼容 { "bookSources": [...] } 包裹
      if (data is Map && data['bookSources'] is List) {
        data = data['bookSources'];
      }
      final list = data is List ? data : [data];
      for (final item in list) {
        if (item is! Map) continue;
        final fresh = ComicSource.fromJson(Map<String, dynamic>.from(item));
        // 只更新 bookSourceUrl 匹配的同一条源
        if (fresh.bookSourceUrl == source.bookSourceUrl &&
            fresh.bookSourceName.isNotEmpty) {
          await AppDatabase.sources.put(source.bookSourceUrl, fresh);
          return true;
        }
      }
    } catch (_) {
      // 更新失败不影响检测结果
    }
    return false;
  }

  bool _looksLikeJsonUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.json') ||
        lower.contains('.json?') ||
        lower.contains('/json/') ||
        lower.contains('api');
  }

  Options dioOptions({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    bool Function(int?)? validateStatus,
  }) {
    return Options(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      validateStatus: validateStatus,
    );
  }

  /// 内置图源初始化。
  ///
  /// v1.1.0 起不再内置任何图源，所有图源均由用户自行导入
  /// （兼容开源阅读 / 异次元 JSON 格式）。
  Future<void> loadBuiltInSources() async {
    // 保留此方法以兼容旧调用，但不再注入默认图源。
    notifyListeners();
  }
}
