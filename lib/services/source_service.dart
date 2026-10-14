import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/database.dart';
import '../core/source_engine.dart';
import '../models/source.dart';

class SourceService extends ChangeNotifier {
  final SourceEngine engine = SourceEngine();

  List<ComicSource> get allSources => AppDatabase.sources.values.toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));

  List<ComicSource> get enabledSources =>
      allSources.where((s) => s.enable).toList();

  /// 从 JSON 字符串导入图源（支持单个对象或数组）
  Future<List<ComicSource>> importFromJson(String jsonStr) async {
    final imported = <ComicSource>[];
    dynamic data;
    try {
      data = jsonDecode(jsonStr);
    } catch (e) {
      throw const FormatException('图源 JSON 格式错误');
    }
    final list = data is List ? data : [data];
    for (final item in list) {
      if (item is! Map) continue;
      final source = ComicSource.fromJson(Map<String, dynamic>.from(item));
      if (source.bookSourceUrl.isEmpty || source.bookSourceName.isEmpty) continue;
      // 以 bookSourceUrl 为唯一键，重复则覆盖
      await AppDatabase.sources.put(source.bookSourceUrl, source);
      imported.add(source);
    }
    notifyListeners();
    return imported;
  }

  /// 从网络地址导入图源
  Future<List<ComicSource>> importFromUrl(String url) async {
    final file = await _downloadFile(url);
    final content = await file.readAsString();
    return importFromJson(content);
  }

  /// 从本地文件导入图源
  Future<List<ComicSource>> importFromFile(String path) async {
    final file = File(path);
    final content = await file.readAsString();
    return importFromJson(content);
  }

  Future<File> _downloadFile(String url) async {
    final dir = await getTemporaryDirectory();
    final name = p.basename(Uri.parse(url).path);
    final savePath = p.join(dir.path, name);
    // 简单下载
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final bytes = await consolidateHttpClientResponseBytes(response);
    final file = File(savePath);
    await file.writeAsBytes(bytes);
    client.close();
    return file;
  }

  Future<void> removeSource(ComicSource source) async {
    await AppDatabase.sources.delete(source.bookSourceUrl);
    notifyListeners();
  }

  Future<void> toggleSource(ComicSource source) async {
    source.enable = !source.enable;
    await source.save();
    notifyListeners();
  }

  /// 内置图源：从 assets/sources 加载并初始化
  Future<void> loadBuiltInSources() async {
    if (AppDatabase.sources.isNotEmpty) return;
    // 内置 mycomic 图源，用户也可自行导入
    final builtin = _builtInMyComicSource();
    await AppDatabase.sources.put(builtin.bookSourceUrl, builtin);
    notifyListeners();
  }

  ComicSource _builtInMyComicSource() {
    return ComicSource(
      bookSourceUrl: 'https://mycomic.com',
      bookSourceName: 'MYCOMIC 漫画',
      bookSourceGroup: '内置',
      bookSourceType: '漫画',
      httpUserAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      ruleSearchUrl: 'https://mycomic.com/search?q=searchKey',
      ruleSearchList: '.comic-item',
      ruleSearchName: '.title@text',
      ruleSearchAuthor: '.author@text',
      ruleSearchCoverUrl: 'img@src',
      ruleSearchNoteUrl: 'a@href',
      ruleBookName: 'h1@text',
      ruleCoverUrl: '.cover img@src',
      ruleBookAuthor: '.author@text',
      ruleIntroduce: '.intro@text',
      ruleChapterList: '.chapter-list a',
      ruleChapterName: '@text',
      ruleContentUrl: 'href',
      ruleBookContent: '.reader-content img@src',
      ruleFindUrl:
          '最新更新::https://mycomic.com/\n热门推荐::https://mycomic.com/hot\n日本漫画::https://mycomic.com/category/japan\n韩国漫画::https://mycomic.com/category/korea\n港台漫画::https://mycomic.com/category/hongkong\n内地漫画::https://mycomic.com/category/china',
      enable: true,
      sourceRemark: '内置图源，可能受 Cloudflare 防护，如遇访问受限请在设置中使用「WebView 过验证」获取 Cookie。',
      weight: 1000,
    );
  }
}
