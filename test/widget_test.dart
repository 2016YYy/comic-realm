import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comic_realm/models/source.dart';
import 'package:comic_realm/core/rule_parser.dart';
import 'package:comic_realm/core/json_path.dart';
import 'package:comic_realm/services/source_service.dart';

/// 验证图源规则解析（兼容 开源阅读 legado / 异次元 的 JSON 格式）。
/// 该测试为纯 Dart 逻辑，不依赖 Hive / path_provider 等原生插件。
void main() {
  group('ComicSource.fromJson', () {
    test('解析 legado / 异次元 图源 JSON 字段', () {
      final source = ComicSource.fromJson({
        'bookSourceName': 'MYCOMIC 漫画',
        'bookSourceUrl': 'https://mycomic.com',
        'bookSourceGroup': '漫画',
        'ruleSearchUrl': 'https://mycomic.com/search?q=searchKey',
        'ruleSearchList': '.comic-item',
        'ruleSearchName': 'h3@text',
        'ruleChapterList': '.chapter-list@li',
        'enable': true,
      });

      expect(source.bookSourceName, 'MYCOMIC 漫画');
      expect(source.bookSourceUrl, 'https://mycomic.com');
      expect(source.ruleSearchList, '.comic-item');
      expect(source.enable, isTrue);
    });

    test('缺失字段使用默认值', () {
      final source = ComicSource.fromJson({'bookSourceUrl': 'https://example.com'});

      expect(source.ruleCoverUrl, '');
      expect(source.ruleChapterName, '');
      expect(source.bookSourceType, '漫画');
      expect(source.weight, 0);
    });
  });

  group('ComicSource.findCategories', () {
    test('按「标题::url」解析发现页分类', () {
      final source = ComicSource.fromJson({
        'ruleFindUrl':
            '最新更新::https://mycomic.com/\n热门推荐::https://mycomic.com/hot',
      });

      final categories = source.findCategories;
      expect(categories.length, 2);
      expect(categories.first.title, '最新更新');
      expect(categories.first.url, 'https://mycomic.com/');
      expect(categories.last.title, '热门推荐');
      expect(categories.last.url, 'https://mycomic.com/hot');
    });

    test('空规则返回空列表', () {
      final source = ComicSource.fromJson({});
      expect(source.findCategories, isEmpty);
    });
  });

  group('ComicSource.fromJson（legado 嵌套规则）', () {
    test('兼容 ruleSearch / ruleBookInfo / ruleToc / ruleContent 嵌套结构', () {
      final source = ComicSource.fromJson({
        'bookSourceName': '嵌套源',
        'bookSourceUrl': 'https://nested.com',
        'searchUrl': 'https://nested.com/search?kw=searchKey',
        'ruleSearch': {'bookList': '.result li', 'name': 'h4@text', 'bookUrl': 'a@href'},
        'ruleBookInfo': {'name': 'h1@text', 'coverUrl': '.cover@src'},
        'ruleToc': {'chapterList': '#list a', 'chapterName': '@text', 'chapterUrl': '@href'},
        'ruleContent': {'content': '#imgbox img@src'},
      });

      expect(source.ruleSearchUrl, 'https://nested.com/search?kw=searchKey');
      expect(source.ruleSearchList, '.result li');
      expect(source.ruleSearchName, 'h4@text');
      expect(source.ruleSearchNoteUrl, 'a@href');
      expect(source.ruleBookName, 'h1@text');
      expect(source.ruleCoverUrl, '.cover@src');
      expect(source.ruleChapterList, '#list a');
      expect(source.ruleChapterName, '@text');
      expect(source.ruleContentUrl, '@href');
      expect(source.ruleBookContent, '#imgbox img@src');
    });
  });

  group('RuleParser.parse（异次元 / legado 语法）', () {
    test('class./tag. 前缀选择器', () {
      final r1 = RuleParser.parse('class.card');
      expect(r1.steps.length, 1);
      expect(r1.steps.first.cssSelector, '.card');
      expect(r1.attr, isNull);

      final r2 = RuleParser.parse('tag.h3@text');
      expect(r2.steps.first.cssSelector, 'h3');
      expect(r2.attr, 'text');

      final r3 = RuleParser.parse('tag.img@src');
      expect(r3.steps.first.cssSelector, 'img');
      expect(r3.attr, 'src');
    });

    test('链式选择器 class.reader-images@tag.img@src', () {
      final r = RuleParser.parse('class.reader-images@tag.img@src');
      expect(r.steps.length, 2);
      expect(r.steps[0].cssSelector, '.reader-images');
      expect(r.steps[1].cssSelector, 'img');
      expect(r.attr, 'src');
    });

    test('JSONPath 规则', () {
      final r = RuleParser.parse(r'$.name');
      expect(r.steps.first.jsonPath, r'$.name');
    });

    test('XPath 转换为 CSS', () {
      final r = RuleParser.parse('//div[@class="box"]/text()');
      expect(r.steps.first.cssSelector, 'div[class="box"]');
      expect(r.attr, 'text');
    });

    test('@js 规则与 @Header', () {
      final r = RuleParser.parse('@js:(function(r){return r;})(result)');
      expect(r.steps, isEmpty);
      expect(r.jsCode, isNotNull);

      final (url, headers) = RuleParser.splitHeader('https://x.com/s@Header:{Referer:https://x.com}');
      expect(url, 'https://x.com/s');
      expect(headers['Referer'], 'https://x.com');
    });

    test('## 结果替换', () {
      final r = RuleParser.parse('class.name@text##\\s+##');
      expect(r.steps.first.cssSelector, '.name');
      expect(r.attr, 'text');
      expect(r.replaceFrom, r'\s+');
    });
  });

  group('JsonPathEngine.query', () {
    final data = {
      'items': [
        {'id': 1, 'title': 'A'},
        {'id': 2, 'title': 'B'},
      ],
      'meta': {'count': 2},
    };

    test(r'$.items 与 $.[*]', () {
      expect(JsonPathEngine.query(data, r'$.items').length, 1);
      expect(JsonPathEngine.query(data, r'$.[*]').length, 2);
    });

    test(r'$.items[*].title 链式取值', () {
      final titles = JsonPathEngine.query(data, r'$.items[*].title');
      expect(titles, ['A', 'B']);
    });

    test(r'$..id 递归查找', () {
      expect(JsonPathEngine.query(data, r'$..id'), [1, 2]);
    });

    test(r'$.items[0].id 数组下标', () {
      expect(JsonPathEngine.query(data, r'$.items[0].id'), [1]);
    });
  });

  group('SourceService.decodePayload（压缩 / Base64 载荷）', () {
    final service = SourceService();
    final jsonText = jsonEncode([
      {'bookSourceName': '测试源', 'bookSourceUrl': 'https://t.com'}
    ]);

    test('明文 JSON', () {
      expect(service.decodePayload(jsonText), jsonText);
    });

    test('Base64 编码的 JSON', () {
      final payload = base64.encode(utf8.encode(jsonText));
      expect(service.decodePayload(payload), jsonText);
    });

    test('Base64 + zlib 压缩的 JSON', () {
      final compressed = ZLibCodec().encode(utf8.encode(jsonText));
      final payload = base64.encode(compressed);
      expect(service.decodePayload(payload), jsonText);
    });

    test('Base64 + gzip 压缩的 JSON', () {
      final compressed = GZipCodec().encode(utf8.encode(jsonText));
      final payload = base64.encode(compressed);
      expect(service.decodePayload(payload), jsonText);
    });

    test('URL-safe Base64（无填充）', () {
      final payload = base64Url
          .encode(utf8.encode(jsonText))
          .replaceAll('=', '');
      expect(service.decodePayload(payload), jsonText);
    });

    test('无法识别的载荷返回 null', () {
      expect(service.decodePayload('这不是图源内容'), isNull);
    });
  });
}
