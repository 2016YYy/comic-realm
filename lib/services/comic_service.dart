import 'package:flutter/foundation.dart';
import '../core/database.dart';
import '../core/source_engine.dart';
import '../models/comic.dart';
import '../models/source.dart';
import 'source_service.dart';

class ComicService extends ChangeNotifier {
  final SourceEngine engine = SourceEngine();

  ComicService();

  /// 跨所有已启用图源搜索
  Future<List<Comic>> searchAll(String keyword, {int page = 1}) async {
    final sources = SourceService().enabledSources;
    final results = <Comic>[];
    for (final source in sources) {
      try {
        final list = await engine.search(source, keyword, page: page);
        results.addAll(list);
      } catch (_) {}
    }
    return results;
  }

  Future<List<Comic>> searchBySource(ComicSource source, String keyword, {int page = 1}) {
    return engine.search(source, keyword, page: page);
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

  List<Comic> get favorites => AppDatabase.favorites.values.toList();
}
