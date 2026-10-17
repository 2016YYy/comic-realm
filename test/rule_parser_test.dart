import 'package:flutter_test/flutter_test.dart';
import 'package:comic_realm/core/rule_parser.dart';
import 'package:comic_realm/core/json_path.dart';
import 'package:comic_realm/core/source_engine.dart';

void main() {
  group('RuleParser 标签选择器识别', () {
    test('li 等标签名应视为 CSS 选择器而非属性', () {
      final parsed = RuleParser.parse('id.js_comicSortList@li');
      // li 应被解析为 CSS 选择器步骤，而非属性
      expect(parsed.steps.length, 2);
      expect(parsed.steps[0].cssSelector, '#js_comicSortList');
      expect(parsed.steps[1].cssSelector, 'li');
      expect(parsed.attr, isNull);
    });

    test('href 应视为属性', () {
      final parsed = RuleParser.parse('class.item@a@href');
      expect(parsed.steps.length, 2);
      expect(parsed.attr, 'href');
    });

    test('data-src 应视为属性', () {
      final parsed = RuleParser.parse('class.item@tag.img@data-src');
      expect(parsed.attr, 'data-src');
    });
  });

  group('JsonPathEngine 过滤表达式', () {
    test('[?(@.Title)] 保留含 Title 键的元素', () {
      final data = {
        'list': [
          {'Title': 'A', 'id': 1},
          {'id': 2},
          {'Title': 'B', 'id': 3},
        ]
      };
      final result = JsonPathEngine.query(data, r'$.list[?(@.Title)]');
      expect(result.length, 2);
      expect(result[0]['Title'], 'A');
      expect(result[1]['Title'], 'B');
    });

    test('[?(@.type == "comic")] 按值过滤', () {
      final data = [
        {'type': 'comic', 'name': 'A'},
        {'type': 'novel', 'name': 'B'},
        {'type': 'comic', 'name': 'C'},
      ];
      final result = JsonPathEngine.query(data, r'$[?(@.type == "comic")]');
      expect(result.length, 2);
    });

    test('普通 JSONPath 仍正常工作', () {
      final data = {'data': {'chapters': [{'name': 'c1'}, {'name': 'c2'}]}};
      final result = JsonPathEngine.query(data, r'$.data.chapters[*]');
      expect(result.length, 2);
    });
  });

  group('jsonMode：JSON 响应自动按 JSONPath 解析', () {
    test(r'未带 $ 前缀的规则在 jsonMode 下解析为 JSONPath', () {
      final r = RuleParser.parse('data.list[*].name', jsonMode: true);
      expect(r.steps.first.jsonPath, 'data.list[*].name');
    });

    test(r'不带 $ 前缀的 JSONPath 也能求值', () {
      final data = {
        'data': {
          'list': [
            {'name': 'A'},
            {'name': 'B'},
          ]
        }
      };
      expect(JsonPathEngine.query(data, 'data.list[*].name'), ['A', 'B']);
    });

    test('jsonMode 下仍尊重显式 CSS 前缀', () {
      final r = RuleParser.parse('tag.li@text', jsonMode: true);
      expect(r.steps.first.cssSelector, 'li');
      expect(r.attr, 'text');
    });

    test('@json: 前缀被识别为 JSONPath', () {
      final r = RuleParser.parse(r'@json:$.data.name');
      expect(r.steps.first.jsonPath, r'$.data.name');
    });
  });

  group('buildUrl 占位符', () {
    test('{{page}} 替换', () {
      expect(SourceEngine.buildUrl('/list?page={{page}}', '', 2), '/list?page=2');
    });

    test('{{page-1}} 偏移', () {
      expect(SourceEngine.buildUrl('/list?page={{page-1}}', '', 3), '/list?page=2');
    });

    test('<0,150,300> 偏移列表', () {
      expect(SourceEngine.buildUrl('/list?offset=<0,150,300>', '', 1), '/list?offset=0');
      expect(SourceEngine.buildUrl('/list?offset=<0,150,300>', '', 2), '/list?offset=150');
      expect(SourceEngine.buildUrl('/list?offset=<0,150,300>', '', 3), '/list?offset=300');
    });
  });
}
