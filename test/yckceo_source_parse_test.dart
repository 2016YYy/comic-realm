import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_realm/models/source.dart';

void main() {
  group('yckceo 源解析验证', () {
    late List<dynamic> comicSources;
    late List<dynamic> bookSources;

    setUpAll(() async {
      // 下载图源（base64+zlib）
      final comicResp = await _download(
          'https://www.yckceo.com/yiciyuan/tuyuans/json/id/50.json');
      final comicB64 = utf8.decode(comicResp).trim();
      final comicDecoded = base64.decode(comicB64);
      final comicDecompressed = zlib.decode(comicDecoded);
      comicSources = jsonDecode(utf8.decode(comicDecompressed)) as List;

      // 下载书源（纯 JSON）
      final bookResp = await _download(
          'https://www.yckceo.com/yuedu/shuyuans/json/id/293.json');
      bookSources = jsonDecode(utf8.decode(bookResp)) as List;
    });

    test('图源：能解析出 bookSourceType=漫画 且搜索规则非空', () {
      var count = 0;
      for (final s in comicSources) {
        final src = ComicSource.fromJson(Map<String, dynamic>.from(s as Map));
        if (src.isComic && src.ruleSearchList.isNotEmpty) {
          count++;
        }
      }
      print('有效图源数: $count / ${comicSources.length}');
      expect(count, greaterThan(0));
    });

    test('书源：能解析字符串字典字面量规则（legado 格式）', () {
      var count = 0;
      for (final s in bookSources) {
        final src = ComicSource.fromJson(Map<String, dynamic>.from(s as Map));
        // legado 书源使用 ruleSearch 字符串字典 + searchUrl
        if (src.ruleSearchUrl.isNotEmpty && src.ruleSearchList.isNotEmpty) {
          count++;
        }
      }
      print('有效书源数: $count / ${bookSources.length}');
      expect(count, greaterThan(0));
    });

    test('书源：isNovel 判断正确（bookSourceType=0）', () {
      var novelCount = 0;
      for (final s in bookSources) {
        final src = ComicSource.fromJson(Map<String, dynamic>.from(s as Map));
        if (src.isNovel) novelCount++;
      }
      print('小说源数: $novelCount / ${bookSources.length}');
      expect(novelCount, greaterThan(0));
    });

    test('书源：exploreUrl 能转换为 标题::url 格式', () {
      var withExplore = 0;
      for (final s in bookSources) {
        final src = ComicSource.fromJson(Map<String, dynamic>.from(s as Map));
        if (src.ruleFindUrl.isNotEmpty && src.ruleFindUrl.contains('::')) {
          withExplore++;
        }
      }
      print('有发现页的书源数: $withExplore');
      expect(withExplore, greaterThan(0));
    });
  });
}

Future<List<int>> _download(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0 Safari/537.36');
    final resp = await req.close();
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    client.close();
  }
}
