import 'dart:convert';
import '../core/database.dart';
import '../models/comic.dart';
import '../models/source.dart';
import 'history_service.dart';

/// 恢复结果统计，用于给用户明确反馈
class RestoreSummary {
  final int sources;
  final int favorites;
  final int history;
  final bool settings;

  const RestoreSummary({
    this.sources = 0,
    this.favorites = 0,
    this.history = 0,
    this.settings = false,
  });

  @override
  String toString() =>
      '图源 $sources 个 · 收藏 $favorites 本 · 历史 $history 条${settings ? ' · 偏好设置已恢复' : ''}';
}

/// 数据备份与恢复：把图源、收藏、阅读历史与偏好设置导出为单个 JSON 文件。
///
/// 不含已下载的图片文件本身（体积过大），恢复后重新下载即可。
class BackupService {
  static const String format = 'comic-realm-backup';
  static const int formatVersion = 1;

  /// 生成备份 JSON 文本
  String buildBackupJson({required String appVersion}) {
    final sources = AppDatabase.sources.values.map((s) => s.toJson()).toList();
    final favorites = AppDatabase.favorites.values.map((c) => c.toJson()).toList();
    final history = HistoryService()
        .entries
        .map((e) => e.toMap())
        .toList();
    final settings = <String, Object?>{};
    final box = AppDatabase.settings;
    for (final key in box.keys) {
      if (key == 'readHistory') continue; // 历史单独导出
      final value = box.get(key);
      if (value is num || value is String || value is bool) {
        settings[key.toString()] = value;
      }
    }

    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'formatVersion': formatVersion,
      'app': '漫境 ComicRealm',
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'sources': sources,
      'favorites': favorites,
      'history': history,
      'settings': settings,
    });
  }

  String suggestedFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'comic-realm-backup-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.json';
  }

  /// 解析并恢复备份。格式不识别时抛 [FormatException]。
  Future<RestoreSummary> restore(String raw) async {
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (e) {
      throw FormatException('备份文件不是合法 JSON：$e');
    }
    if (data is! Map || data['format'] != format) {
      throw const FormatException('不是漫境 ComicRealm 的备份文件');
    }

    var sourceCount = 0;
    var favoriteCount = 0;
    var historyCount = 0;
    var settingsRestored = false;

    final sources = data['sources'];
    if (sources is List) {
      for (final item in sources) {
        if (item is! Map) continue;
        final source = ComicSource.fromJson(Map<String, dynamic>.from(item));
        if (source.bookSourceUrl.isEmpty) continue;
        await AppDatabase.sources.put(source.bookSourceUrl, source);
        sourceCount++;
      }
    }

    final favorites = data['favorites'];
    if (favorites is List) {
      for (final item in favorites) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final comic = Comic(
          name: (map['name'] ?? '').toString(),
          author: (map['author'] ?? '').toString(),
          coverUrl: (map['coverUrl'] ?? '').toString(),
          introduce: (map['introduce'] ?? '').toString(),
          kind: (map['kind'] ?? '').toString(),
          lastChapter: (map['lastChapter'] ?? '').toString(),
          noteUrl: (map['noteUrl'] ?? '').toString(),
          sourceUrl: (map['sourceUrl'] ?? '').toString(),
          sourceName: (map['sourceName'] ?? '').toString(),
          isFavorite: true,
        );
        if (comic.noteUrl.isEmpty) continue;
        await AppDatabase.favorites.put(comic.noteUrl, comic);
        favoriteCount++;
      }
    }

    final history = data['history'];
    if (history is List) {
      final box = AppDatabase.settings;
      final existing = HistoryService().entries.map((e) => e.toMap()).toList();
      final merged = <Map<String, Object?>>[
        ...existing,
        ...history.whereType<Map>().map((m) => ReadHistoryEntry.fromMap(m).toMap()),
      ];
      // 同 noteUrl 去重，保留先出现的（本地已有的优先）
      final seen = <String>{};
      final deduped = <Map<String, Object?>>[];
      for (final m in merged) {
        final key = (m['noteUrl'] ?? '').toString();
        if (key.isEmpty || seen.add(key)) deduped.add(m);
      }
      await box.put('readHistory', deduped);
      historyCount = deduped.length;
    }

    final settings = data['settings'];
    if (settings is Map) {
      final box = AppDatabase.settings;
      for (final entry in settings.entries) {
        final value = entry.value;
        if (value is num || value is String || value is bool) {
          await box.put(entry.key.toString(), value);
        }
      }
      settingsRestored = true;
    }

    return RestoreSummary(
      sources: sourceCount,
      favorites: favoriteCount,
      history: historyCount,
      settings: settingsRestored,
    );
  }
}
