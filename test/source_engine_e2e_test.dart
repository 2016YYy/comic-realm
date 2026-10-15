import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_realm/core/http_client.dart';
import 'package:comic_realm/core/source_engine.dart';
import 'package:comic_realm/models/comic.dart';
import 'package:comic_realm/models/source.dart';

/// 端到端验证：启动本地 HTTP 服务，返回按包子漫画真实 DOM 还原的页面，
/// 完整跑通「搜索 -> 详情 -> 章节 -> 图片」链路，确认规则选择器可用。
void main() {
  late HttpServer server;
  late String base;
  final hits = <String>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test 默认会拦截网络请求，这里恢复真实网络以便访问本地服务。
    HttpOverrides.global = null;

    // HttpClient 单例依赖 path_provider，测试中 mock 该通道指向临时目录。
    final tempDir = Directory.systemTemp.createTempSync('comic_realm_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);
    await HttpClient().init();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      hits.add(req.uri.toString());
      final path = req.uri.path;
      req.response.headers.contentType = ContentType.html;
      if (path == '/search') {
        req.response.write(_searchHtml);
      } else if (path == '/list/new') {
        req.response.write(_classifyHtml);
      } else if (path == '/comic/demo') {
        req.response.write(_detailHtml);
      } else if (path == '/user/page_direct') {
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set(HttpHeaders.locationHeader, '/comic/chapter/demo/0_0.html');
      } else if (path == '/comic/chapter/demo/0_0.html') {
        req.response.write(_chapterHtml);
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  ComicSource baoziSource() => ComicSource(
        bookSourceUrl: base,
        bookSourceName: '包子漫画',
        ruleSearchUrl: '$base/search?q=searchKey',
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
        ruleBookContent: '.comic-contain__item@src',
        ruleFindUrl: '最新上架::$base/list/new',
      );

  test('搜索：能从结果页解析出漫画（名称 / 链接 / 封面）', () async {
    final engine = SourceEngine();
    final comics = await engine.search(baoziSource(), '海贼');

    expect(comics.length, 2);
    expect(comics[0].name, '海贼王');
    expect(comics[0].noteUrl, '$base/comic/demo');
    // 封面应取外层 amp-img 的真实地址，而不是内层占位图
    expect(comics[0].coverUrl, contains('cover/demo.jpg'));
    expect(comics[1].name, '海贼盛宴');
    expect(hits, contains('/search?q=%E6%B5%B7%E8%B4%BC'));
  });

  test('分类：发现页列表可解析出漫画', () async {
    final engine = SourceEngine();
    final comics = await engine.category(baoziSource(), '$base/list/new');

    expect(comics.length, 1);
    expect(comics.first.name, '围城V2');
    expect(comics.first.noteUrl, '$base/comic/demo3');
  });

  test('详情 + 章节 + 图片：全链路可用（含 302 跳转）', () async {
    final engine = SourceEngine();
    final source = baoziSource();
    final comic = Comic(name: '', noteUrl: '$base/comic/demo');

    final detail = await engine.getDetail(source, comic);
    expect(detail.name, '海贼王');
    expect(detail.author, '尾田荣一郎');
    expect(detail.introduce, contains('简介'));
    expect(detail.coverUrl, contains('cover/demo.jpg'));

    final chapters = await engine.getChapters(source, detail);
    expect(chapters.length, 2);
    expect(chapters[0].name, '第一话');
    expect(chapters[0].url, '$base/user/page_direct?comic_id=demo&section_slot=0&chapter_slot=0');

    final images = await engine.getContent(source, chapters[0], detail);
    expect(images.length, 2);
    expect(images[0], 'https://s1.bzcdn.net/fcomic/demo/0/0-abc/1.jpg');
    expect(images[1], 'https://s1.bzcdn.net/fcomic/demo/0/0-abc/2.jpg');
  });
}

const _searchHtml = '''
<div class="l-content search mt-5">
  <div class="pure-g classify-items">
    <div class="comics-card pure-u-1-2 pure-u-md-1-4">
      <a href="/comic/demo" title="海贼王" class="comics-card__poster text-decoration-none">
        <amp-img alt="海贼王" width="150" height="200" layout="responsive"
          src="https://static-tw.bzmgcn.com/cover/demo.jpg?w=285&amp;h=375&amp;q=100"
          class="i-amphtml-element i-amphtml-built">
          <img decoding="async" alt="海贼王" src="https://static-tw.bzmgcn.com/cover/default_cover.png"
               class="i-amphtml-fill-content i-amphtml-replaced-content">
        </amp-img>
      </a>
      <a href="/comic/demo" aria-label="海贼王" class="comics-card__info">
        <div class="comics-card__title text-truncate"><h3 class="text-truncate">海贼王</h3></div>
        <small class="tags text-truncate">尾田荣一郎</small>
      </a>
    </div>
    <div class="comics-card pure-u-1-2 pure-u-md-1-4">
      <a href="/comic/demo2" title="海贼盛宴" class="comics-card__poster text-decoration-none">
        <amp-img alt="海贼盛宴" width="150" height="200" layout="responsive"
          src="https://static-tw.bzmgcn.com/cover/demo2.jpg">
          <img decoding="async" src="https://static-tw.bzmgcn.com/cover/default_cover.png"
               class="i-amphtml-fill-content">
        </amp-img>
      </a>
      <a href="/comic/demo2" aria-label="海贼盛宴" class="comics-card__info">
        <div class="comics-card__title text-truncate"><h3 class="text-truncate">海贼盛宴</h3></div>
        <small class="tags text-truncate">尾田荣一郎</small>
      </a>
    </div>
  </div>
</div>
''';

const _classifyHtml = '''
<div class="index-recommend-items">
  <div class="pure-g">
    <div class="comics-card pure-u-1-3 pure-u-md-1-4">
      <a href="/comic/demo3" title="围城V2" class="comics-card__poster text-decoration-none">
        <amp-img alt="围城V2" width="150" height="200" src="https://static-tw.bzmgcn.com/cover/demo3.jpg">
          <img src="https://static-tw.bzmgcn.com/cover/default_cover.png" class="i-amphtml-fill-content">
        </amp-img>
      </a>
      <a href="/comic/demo3" class="comics-card__info">
        <div class="comics-card__title text-truncate"><h3 class="text-truncate">围城V2</h3></div>
        <small class="tags text-truncate">Marvel Comics</small>
      </a>
    </div>
  </div>
</div>
''';

const _detailHtml = '''
<div class="comics-detail">
  <h1 class="comics-detail__title">海贼王</h1>
  <h2 class="comics-detail__author">尾田荣一郎</h2>
  <p class="comics-detail__desc overflow-hidden">这里是简介文本内容</p>
  <amp-img alt="海贼王" width="180" height="240" layout="responsive"
           src="https://static-tw.bzmgcn.com/cover/demo.jpg?w=285&amp;h=375&amp;q=100"></amp-img>
  <div id="chapter-items" class="pure-g" style="margin: 0 -6px;">
    <div class="pure-u-1-1 pure-u-md-1-3 comics-chapters">
      <a href="/user/page_direct?comic_id=demo&amp;section_slot=0&amp;chapter_slot=0"
         rel="noopener" class="comics-chapters__item">
        <div style="flex: 1;"><span>第一话</span></div>
      </a>
    </div>
    <div class="pure-u-1-1 pure-u-md-1-3 comics-chapters">
      <a href="/user/page_direct?comic_id=demo&amp;section_slot=0&amp;chapter_slot=1"
         rel="noopener" class="comics-chapters__item">
        <div style="flex: 1;"><span>第二话</span></div>
      </a>
    </div>
  </div>
</div>
''';

const _chapterHtml = '''
<div>
  <amp-img id="chapter-img-0-0" width="700" height="1000"
    src="https://s1.bzcdn.net/fcomic/demo/0/0-abc/1.jpg"
    data-src="https://s1.bzcdn.net/fcomic/demo/0/0-abc/1.jpg"
    class="comic-contain__item i-amphtml-element i-amphtml-built">
    <img decoding="async" src="https://s1.bzcdn.net/fcomic/demo/0/0-abc/1.jpg"
         class="i-amphtml-fill-content i-amphtml-replaced-content">
  </amp-img>
  <amp-img id="chapter-img-0-1" width="700" height="1000"
    src="https://s1.bzcdn.net/fcomic/demo/0/0-abc/2.jpg"
    data-src="https://s1.bzcdn.net/fcomic/demo/0/0-abc/2.jpg"
    class="comic-contain__item i-amphtml-element i-amphtml-built">
    <img decoding="async" src="https://s1.bzcdn.net/fcomic/demo/0/0-abc/2.jpg"
         class="i-amphtml-fill-content i-amphtml-replaced-content">
  </amp-img>
</div>
''';
