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
        errors.add(SourceError(source.bookSourceName, _friendlyError(e)));
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

  String _friendlyError(Object e) {
    var msg = e.toString();
    msg = msg.replaceFirst('Exception: ', '');
    if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
    return msg;
  }
}
