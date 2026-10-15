import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/database.dart';
import '../core/source_engine.dart';
import '../models/source.dart';

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
    final bytes = await File(path).readAsBytes();
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
        return ZLibCodec().decode(bytes);
      } catch (_) {}
      try {
        return ZLibCodec(raw: true).decode(bytes);
      } catch (_) {}
    }
    // gzip 头：0x1f 0x8b
    if (bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        return GZipCodec().decode(bytes);
      } catch (_) {}
    }
    // 兜底：原始 deflate
    try {
      return ZLibCodec(raw: true).decode(bytes);
    } catch (_) {}
    try {
      return ZLibCodec().decode(bytes);
    } catch (_) {}
    return null;
  }

  Future<List<int>> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36');
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
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

  /// 内置图源初始化。
  ///
  /// v1.1.0 起不再内置任何图源，所有图源均由用户自行导入
  /// （兼容开源阅读 / 异次元 JSON 格式）。
  Future<void> loadBuiltInSources() async {
    // 保留此方法以兼容旧调用，但不再注入默认图源。
    notifyListeners();
  }
}
