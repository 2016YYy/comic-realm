import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/database.dart';
import '../core/http_client.dart';
import '../core/source_engine.dart';
import '../models/comic.dart';
import '../models/download.dart';
import '../models/source.dart';

class DownloadService extends ChangeNotifier {
  final SourceEngine _engine = SourceEngine();
  final HttpClient _http = HttpClient();

  List<DownloadTask> get tasks => AppDatabase.downloads.values.toList()
    ..sort((a, b) => b.createTime.compareTo(a.createTime));

  /// 创建下载任务并执行
  Future<DownloadTask> downloadChapter({
    required ComicSource source,
    required Comic comic,
    required Chapter chapter,
  }) async {
    final taskId = '${source.bookSourceUrl}_${chapter.url}';
    // 是否已存在
    if (AppDatabase.downloads.containsKey(taskId)) {
      final existing = AppDatabase.downloads.get(taskId)!;
      if (existing.statusEnum == DownloadStatus.completed) {
        return existing;
      }
    }

    final task = DownloadTask(
      taskId: taskId,
      comicName: comic.name,
      chapterName: chapter.name,
      chapterUrl: chapter.url,
      sourceUrl: source.bookSourceUrl,
      sourceName: source.bookSourceName,
      coverUrl: comic.coverUrl,
      status: DownloadStatus.downloading.index,
    );
    await AppDatabase.downloads.put(taskId, task);
    notifyListeners();

    try {
      if (source.isNovel) {
        // 小说源：下载文本内容保存为 .txt
        final text = await _engine.getContentText(source, chapter, comic);
        task.totalPages = 1;
        await task.save();

        final dir = await _getChapterDir(comic.name, chapter.name);
        final filePath = p.join(dir.path, 'content.txt');
        await File(filePath).writeAsString(text, encoding: utf8);
        task.downloadedPages = 1;
        task.savePath = dir.path;
        task.statusEnum = text.isNotEmpty ? DownloadStatus.completed : DownloadStatus.failed;
        await task.save();
      } else {
        // 漫画源：下载图片
        final images = await _engine.getContent(source, chapter, comic);
        task.totalPages = images.length;
        await task.save();

        final dir = await _getChapterDir(comic.name, chapter.name);
        var downloaded = 0;
        for (var i = 0; i < images.length; i++) {
          final url = images[i];
          final ext = p.extension(Uri.parse(url).path).isNotEmpty
              ? p.extension(Uri.parse(url).path)
              : '.jpg';
          final fileName = '${i.toString().padLeft(4, '0')}$ext';
          final filePath = p.join(dir.path, fileName);
          try {
            await _http.download(url, filePath, userAgent: source.httpUserAgent);
            downloaded++;
            task.downloadedPages = downloaded;
            await task.save();
            notifyListeners();
          } catch (e) {
            // 单页失败不中断
          }
        }
        task.savePath = dir.path;
        task.statusEnum = downloaded > 0 ? DownloadStatus.completed : DownloadStatus.failed;
        await task.save();
      }
    } catch (e) {
      task.statusEnum = DownloadStatus.failed;
      await task.save();
    }
    notifyListeners();
    return task;
  }

  Future<Directory> _getChapterDir(String comic, String chapter) async {
    final base = await getApplicationSupportDirectory();
    final safeComic = _safe(comic);
    final safeChapter = _safe(chapter);
    final dir = Directory(p.join(base.path, 'downloads', safeComic, safeChapter));
    await dir.create(recursive: true);
    return dir;
  }

  String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');

  Future<void> deleteTask(DownloadTask task) async {
    if (task.savePath.isNotEmpty) {
      final dir = Directory(task.savePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    await AppDatabase.downloads.delete(task.taskId);
    notifyListeners();
  }

  /// 获取已下载章节的本地图片路径列表
  Future<List<String>> getLocalImages(DownloadTask task) async {
    if (task.savePath.isEmpty) return [];
    final dir = Directory(task.savePath);
    if (!await dir.exists()) return [];
    final files = await dir.list().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.whereType<File>().map((f) => f.path).toList();
  }
}
