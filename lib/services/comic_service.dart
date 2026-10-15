import 'package:flutter/foundation.dart';
import '../core/database.dart';
import '../core/source_engine.dart';
import '../models/comic.dart';
import '../models/source.dart';

/// 搜索聚合结果：包含成功结果与逐图源的失败信息，便于定位问题。
class SearchOutcome {
  final List<Comic> comics;
  final List<SourceError> errors;

  SearchOutcome(this.comics, this.errors);

  bool get hasErrors => errors.isNotEmpty;
}

class SourceError {
  final String sourceName;
  final String message;
  SourceError(this.sourceName, this.message);
}

class ComicService extends ChangeNotifier {
  final SourceEngine engine = SourceEngine();

  ComicService();

  List<ComicSource> get _enabledSources =>
      AppDatabase.sources.values.where((s) => s.enable).toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));

  /// 跨所有已启用图源搜索，返回结果与错误明细
  Future<SearchOutcome> searchAllWithErrors(String keyword, {int page = 1}) async {
    final sources = _enabledSources;
    final results = <Comic>[];
    final errors = <SourceError>[];
    for (final source in sources) {
      try {
        final list = await engine.search(source, keyword, page: page);
        results.addAll(list);
      } catch (e) {
        errors.add(SourceError(source.bookSourceName, friendlyError(e)));
      }
    }
    return SearchOutcome(results, errors);
  }

  /// 兼容旧调用
  Future<List<Comic>> searchAll(String keyword, {int page = 1}) async {
    final outcome = await searchAllWithErrors(keyword, page: page);
    return outcome.comics;
  }

  Future<List<Comic>> searchBySource(ComicSource source, String keyword, {int page = 1}) {
    return engine.search(source, keyword, page: page);
  }

  /// 按图源分类（发现页）获取漫画列表
  Future<List<Comic>> categoryComics(ComicSource source, String urlTemplate, {int page = 1}) {
    return engine.category(source, urlTemplate, page: page);
  }

  Future<Comic> getDetail(ComicSource source, Comic comic) {
    return engine.getDetail(source, comic);
  }

  Future<List<Chapter>> getChapters(ComicSource source, Comic comic) {
    return engine.getChapters(source, comic);
  }

  Future<List<String>> getContent(ComicSource source, Chapter chapter, Comic comic) {
    return engine.getContent(source, chapter, comic);
  }

  /// 获取小说章节文本（文本源专用）。
  Future<String> getContentText(ComicSource source, Chapter chapter, Comic comic) {
    return engine.getContentText(source, chapter, comic);
  }

  /// 收藏
  Future<void> addFavorite(Comic comic) async {
    comic.isFavorite = true;
    await AppDatabase.favorites.put(comic.noteUrl, comic);
    notifyListeners();
  }

  Future<void> removeFavorite(Comic comic) async {
    await AppDatabase.favorites.delete(comic.noteUrl);
    notifyListeners();
  }

  bool isFavorite(String noteUrl) => AppDatabase.favorites.containsKey(noteUrl);

  /// 触发一次刷新（例如书库下拉刷新）
  void reload() => notifyListeners();

  List<Comic> get favorites => AppDatabase.favorites.values.toList();

  /// 将网络/解析异常转换为用户可读的中文提示。
  static String friendlyError(Object e) {
    final msg = e.toString();

    // DNS 解析失败
    if (msg.contains('Failed host lookup') || msg.contains('SocketException')) {
      final hostMatch = RegExp(r"'([^']+)'").firstMatch(msg);
      final host = hostMatch?.group(1) ?? '目标网站';
      return '无法连接到 $host（域名解析失败，该源站可能已失效）';
    }

    // 连接超时
    if (msg.contains('connectionTimeout') || msg.contains('Connection timed out')) {
      return '连接超时，请检查网络或稍后重试';
    }

    // 接收超时
    if (msg.contains('receiveTimeout') || msg.contains('Receive timeout')) {
      return '响应超时，源站可能响应过慢';
    }

    // 连接被拒绝
    if (msg.contains('Connection refused') || msg.contains('connectionError')) {
      return '连接被拒绝，该源站可能已下线';
    }

    // HTTP 错误状态码
    final statusMatch = RegExp(r'StatusCode:\s*(\d+)').firstMatch(msg);
    if (statusMatch != null) {
      final code = statusMatch.group(1);
      return '源站返回 HTTP $code 错误';
    }

    // 404
    if (msg.contains('404')) {
      return '页面未找到（404），该源站结构可能已变更';
    }

    // 去掉前缀并截断
    var clean = msg.replaceFirst(RegExp(r'Exception:|DioException\s*\[[^\]]*\]:?\s*'), '');
    clean = clean.replaceFirst(RegExp(r'^Error:\s*'), '');
    if (clean.length > 120) clean = '${clean.substring(0, 120)}…';
    return clean.isEmpty ? '未知错误' : clean;
  }
}
