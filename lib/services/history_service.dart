import 'package:flutter/foundation.dart';
import '../core/database.dart';
import '../models/comic.dart';

/// 一条阅读历史记录。用 Map 存在 Hive 的 `settings` box 里，
/// 避免为了一个新模型再动一次 Hive adapter 代码生成。
class ReadHistoryEntry {
  final String noteUrl;
  final String comicName;
  final String coverUrl;
  final String sourceUrl;
  final String sourceName;
  final String chapterName;
  final int chapterIndex;
  final DateTime readAt;

  ReadHistoryEntry({
    required this.noteUrl,
    this.comicName = '',
    this.coverUrl = '',
    this.sourceUrl = '',
    this.sourceName = '',
    this.chapterName = '',
    this.chapterIndex = 0,
    required this.readAt,
  });

  Map<String, Object?> toMap() => {
        'noteUrl': noteUrl,
        'comicName': comicName,
        'coverUrl': coverUrl,
        'sourceUrl': sourceUrl,
        'sourceName': sourceName,
        'chapterName': chapterName,
        'chapterIndex': chapterIndex,
        'readAt': readAt.millisecondsSinceEpoch,
      };

  static ReadHistoryEntry fromMap(Map<dynamic, dynamic> map) => ReadHistoryEntry(
        noteUrl: (map['noteUrl'] ?? '').toString(),
        comicName: (map['comicName'] ?? '').toString(),
        coverUrl: (map['coverUrl'] ?? '').toString(),
        sourceUrl: (map['sourceUrl'] ?? '').toString(),
        sourceName: (map['sourceName'] ?? '').toString(),
        chapterName: (map['chapterName'] ?? '').toString(),
        chapterIndex: (map['chapterIndex'] as num?)?.toInt() ?? 0,
        readAt: DateTime.fromMillisecondsSinceEpoch(
          (map['readAt'] as num?)?.toInt() ?? 0,
        ),
      );

  Comic toComic() => Comic(
        name: comicName,
        coverUrl: coverUrl,
        noteUrl: noteUrl,
        sourceUrl: sourceUrl,
        sourceName: sourceName,
      );
}

/// 浏览 / 阅读历史：记录读过哪一本、读到哪一章、什么时候读的。
class HistoryService extends ChangeNotifier {
  static const _key = 'readHistory';
  static const int _maxEntries = 300;

  List<ReadHistoryEntry> get entries {
    final raw = AppDatabase.settings.get(_key);
    if (raw is! List) return [];
    final list = <ReadHistoryEntry>[];
    for (final item in raw) {
      if (item is Map) {
        list.add(ReadHistoryEntry.fromMap(item));
      }
    }
    list.sort((a, b) => b.readAt.compareTo(a.readAt));
    return list;
  }

  bool get isEmpty => entries.isEmpty;

  ReadHistoryEntry? entryFor(String noteUrl) {
    for (final e in entries) {
      if (e.noteUrl == noteUrl) return e;
    }
    return null;
  }

  /// 记录 / 更新一条历史（同一本只保留最新一条）
  Future<void> record({
    required Comic comic,
    required String chapterName,
    int chapterIndex = 0,
  }) async {
    if (comic.noteUrl.isEmpty) return;
    final all = entries.where((e) => e.noteUrl != comic.noteUrl).toList();
    all.insert(
      0,
      ReadHistoryEntry(
        noteUrl: comic.noteUrl,
        comicName: comic.name,
        coverUrl: comic.coverUrl,
        sourceUrl: comic.sourceUrl,
        sourceName: comic.sourceName,
        chapterName: chapterName,
        chapterIndex: chapterIndex,
        readAt: DateTime.now(),
      ),
    );
    await _save(all.take(_maxEntries).toList());
  }

  Future<void> remove(String noteUrl) async {
    await _save(entries.where((e) => e.noteUrl != noteUrl).toList());
  }

  Future<void> clear() async {
    await _save(const []);
  }

  /// 触发一次刷新（例如恢复备份后）
  void reload() => notifyListeners();

  Future<void> _save(List<ReadHistoryEntry> list) async {
    await AppDatabase.settings.put(_key, list.map((e) => e.toMap()).toList());
    notifyListeners();
  }
}
