import 'package:flutter_test/flutter_test.dart';

import 'package:comic_realm/models/source.dart';

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
}
