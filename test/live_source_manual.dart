import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_realm/core/http_client.dart';
import 'package:comic_realm/core/source_engine.dart';
import 'package:comic_realm/models/source.dart';

/// 对接线上 cn.bzmgcn.com，验证 Gatekeeper PoW 自动求解 + 全链路选择器。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final tempDir = Directory.systemTemp.createTempSync('comic_realm_live');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);
    await HttpClient().init();
  });

  ComicSource baozi() => ComicSource(
        bookSourceUrl: 'https://cn.bzmgcn.com',
        bookSourceName: '包子漫画',
        bookSourceType: '漫画',
        httpUserAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        ruleSearchUrl: 'https://cn.bzmgcn.com/search?q=searchKey',
        ruleSearchList: '.comics-card',
        ruleSearchName: '.comics-card__title h3@text',
        ruleSearchAuthor: '.comics-card__info small@text',
        ruleSearchCoverUrl: '.comics-card__poster amp-img@src',
        ruleSearchNoteUrl: '.comics-card__info@href',
        ruleBookName: '.comics-detail__title@text',
        ruleCoverUrl: 'amp-img@src',
        ruleBookAuthor: '.comics-detail__author@text',
        ruleIntroduce: '.comics-detail__desc@text',
        ruleChapterList: '#chapter-items a.comics-chapters__item',
        ruleChapterName: 'span@text',
        ruleContentUrl: '@href',
        ruleBookContent: '.comic-contain amp-img@src',
        enable: true,
      );

  test('线上：搜索 -> 详情 -> 章节图片 全链路（含 PoW 与跨域跳转）', () async {
    final source = baozi();
    final engine = SourceEngine();

    print('--- 搜索 ---');
    final comics = await engine.search(source, '技');
    print('搜索结果数: ${comics.length}');
    expect(comics.isNotEmpty, true);
    print('首个: ${comics.first.name} / ${comics.first.noteUrl}');

    print('--- 详情 ---');
    final detail = await engine.getDetail(source, comics.first);
    print('标题: ${detail.name}');
    print('作者: ${detail.author}');
    expect(detail.name.isNotEmpty, true);

    print('--- 章节 ---');
    final chapters = await engine.getChapters(source, detail);
    print('章节数: ${chapters.length}');
    expect(chapters.isNotEmpty, true);

    print('--- 章节图片 ---');
    final images = await engine.getContent(source, chapters.first, detail);
    print('图片数: ${images.length}');
    print('首图: ${images.first}');
    expect(images.isNotEmpty, true);
    expect(images.first.startsWith('http'), true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
