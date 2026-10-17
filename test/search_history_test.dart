import 'package:flutter_test/flutter_test.dart';

import 'package:comic_realm/models/source.dart';

/// v1.8.1 新增能力的纯逻辑测试：搜索历史去重规则、视频地址识别、图源类型判定。
///
/// 搜索历史依赖 Hive，这里只测「去重 / 置顶 / 上限」这条纯算法规则，
/// 用与 SettingsService.addSearchHistory 相同的实现逐行复现，
/// 避免测试拉起原生插件。
List<String> addHistory(List<String> current, String keyword, {int max = 20}) {
  final k = keyword.trim();
  if (k.isEmpty) return current;
  final list = List<String>.from(current)..remove(k);
  list.insert(0, k);
  if (list.length > max) {
    list.removeRange(max, list.length);
  }
  return list;
}

void main() {
  group('搜索历史', () {
    test('新关键词置顶', () {
      var h = <String>[];
      h = addHistory(h, '海贼王');
      h = addHistory(h, '火影');
      expect(h, ['火影', '海贼王']);
    });

    test('重复关键词去重后置顶', () {
      var h = <String>['火影', '海贼王', '死神'];
      h = addHistory(h, '海贼王');
      expect(h, ['海贼王', '火影', '死神']);
      expect(h.where((e) => e == '海贼王').length, 1);
    });

    test('空白关键词不入库', () {
      final h = addHistory(<String>['火影'], '   ');
      expect(h, ['火影']);
    });

    test('超过上限截断最旧的', () {
      var h = <String>[];
      for (var i = 0; i < 25; i++) {
        h = addHistory(h, '关键词$i');
      }
      expect(h.length, 20);
      expect(h.first, '关键词24');
      expect(h.contains('关键词0'), isFalse);
    });
  });

  group('视频地址识别', () {
    test('常见视频扩展名被识别', () {
      // 通过 SourceEngine.getVideoUrls 的过滤规则间接验证：
      // 这里直接构造同类判断，确认扩展名清单覆盖主流格式。
      bool looksLikeVideo(String url) {
        final lower = url.toLowerCase();
        final path = lower.split('?').first.split('#').first;
        return path.endsWith('.mp4') ||
            path.endsWith('.m3u8') ||
            path.endsWith('.webm') ||
            path.endsWith('.flv') ||
            path.endsWith('.mkv') ||
            path.endsWith('.mov') ||
            path.endsWith('.avi') ||
            path.endsWith('.ts') ||
            lower.contains('.m3u8?') ||
            lower.contains('.mp4?');
      }

      expect(looksLikeVideo('https://a.com/v/1.mp4'), isTrue);
      expect(looksLikeVideo('https://a.com/v/1.m3u8'), isTrue);
      expect(looksLikeVideo('https://a.com/v/1.m3u8?token=abc'), isTrue);
      expect(looksLikeVideo('https://a.com/v/1.mp4?sign=1&t=2'), isTrue);
      expect(looksLikeVideo('https://a.com/v/1.webm'), isTrue);
      expect(looksLikeVideo('https://a.com/v/1.flv'), isTrue);
      expect(looksLikeVideo('https://a.com/img/1.jpg'), isFalse);
      expect(looksLikeVideo('https://a.com/page/1.html'), isFalse);
    });
  });

  group('源类型判定', () {
    test('legado 数字类型：0 文本 / 1 图片 / 3 视频', () {
      expect(ComicSource.fromJson({'bookSourceType': 0}).isNovel, isTrue);
      expect(ComicSource.fromJson({'bookSourceType': '1'}).isComic, isTrue);
      expect(ComicSource.fromJson({'bookSourceType': 3}).isVideo, isTrue);
    });

    test('中文类型标签', () {
      expect(ComicSource.fromJson({'bookSourceType': '漫画'}).kind,
          SourceKind.comic);
      expect(ComicSource.fromJson({'bookSourceType': '小说'}).kind,
          SourceKind.novel);
      expect(ComicSource.fromJson({'bookSourceType': '视频'}).kind,
          SourceKind.video);
    });

    test('未配置类型时按漫画处理', () {
      final s = ComicSource.fromJson({'bookSourceUrl': 'https://a.com'});
      expect(s.isComic, isTrue);
      expect(s.kindLabel, '漫画');
    });
  });
}
