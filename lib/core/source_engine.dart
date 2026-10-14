import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/source.dart';
import '../models/comic.dart';
import 'http_client.dart';
import 'js_runtime.dart';

/// 图源规则引擎：根据 ComicSource 中的 CSS 选择器规则解析网页。
class SourceEngine {
  final HttpClient _http = HttpClient();
  final JsRuntime _js = JsRuntime();

  /// 搜索漫画
  Future<List<Comic>> search(ComicSource source, String keyword, {int page = 1}) async {
    var url = source.ruleSearchUrl.replaceAll('searchKey', Uri.encodeComponent(keyword));
    url = url.replaceAll('searchPage', page.toString());
    final html = await _http.getString(url, userAgent: source.httpUserAgent);
    final doc = html_parser.parse(html);
    final items = _selectList(doc, source.ruleSearchList);
    final comics = <Comic>[];
    for (final el in items) {
      comics.add(Comic(
        name: _selectText(el, source.ruleSearchName),
        author: _selectText(el, source.ruleSearchAuthor),
        coverUrl: _selectAttr(el, source.ruleSearchCoverUrl, url),
        noteUrl: _selectAttr(el, source.ruleSearchNoteUrl, url),
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName,
      ));
    }
    return comics;
  }

  /// 获取漫画详情
  Future<Comic> getDetail(ComicSource source, Comic comic) async {
    final html = await _http.getString(comic.noteUrl, userAgent: source.httpUserAgent);
    final doc = html_parser.parse(html);
    comic.name = _selectText(doc, source.ruleBookName).ifEmpty(comic.name);
    comic.author = _selectText(doc, source.ruleBookAuthor).ifEmpty(comic.author);
    comic.coverUrl = _selectAttr(doc, source.ruleCoverUrl, comic.noteUrl).ifEmpty(comic.coverUrl);
    comic.introduce = _selectText(doc, source.ruleIntroduce);
    comic.kind = _selectText(doc, source.ruleBookKind);
    return comic;
  }

  /// 获取章节列表
  Future<List<Chapter>> getChapters(ComicSource source, Comic comic) async {
    final html = await _http.getString(comic.noteUrl, userAgent: source.httpUserAgent);
    final doc = html_parser.parse(html);
    var rule = source.ruleChapterList;
    var reverse = false;
    if (rule.startsWith('-')) {
      reverse = true;
      rule = rule.substring(1);
    }
    final items = _selectList(doc, rule);
    var chapters = <Chapter>[];
    for (var i = 0; i < items.length; i++) {
      final el = items[i];
      chapters.add(Chapter(
        name: _selectText(el, source.ruleChapterName),
        url: _selectAttr(el, source.ruleContentUrl, comic.noteUrl),
        index: i,
      ));
    }
    if (reverse) chapters = chapters.reversed.toList();
    return chapters;
  }

  /// 获取章节图片 URL 列表
  Future<List<String>> getContent(ComicSource source, Chapter chapter, Comic comic) async {
    final html = await _http.getString(chapter.url, userAgent: source.httpUserAgent);
    final rule = source.ruleBookContent;

    // @js: 形式：执行 JS 解码脚本
    if (rule.startsWith('@js:')) {
      final jsPart = rule.substring(4);
      var jsCode = jsPart;
      final headerIdx = jsPart.indexOf('@Header:');
      if (headerIdx >= 0) {
        jsCode = jsPart.substring(0, headerIdx);
      }
      final result = await _js.evalWith('($jsCode)', {'result': html});
      return _parseJsResult(result);
    }

    // 普通 CSS 选择器
    final doc = html_parser.parse(html);
    final items = _selectList(doc, rule);
    final urls = <String>[];
    for (final el in items) {
      // 尝试 data-src, src, data-original 等属性
      var u = el.attributes['data-src'] ??
          el.attributes['data-original'] ??
          el.attributes['src'] ??
          el.attributes['data-lazy-src'] ??
          '';
      if (u.isNotEmpty) {
        urls.add(_http.absoluteUrl(chapter.url, u));
      }
    }
    return urls;
  }

  /// 解析 JS 返回结果（可能是数组字面量或逗号分隔字符串）
  List<String> _parseJsResult(String raw) {
    raw = raw.trim();
    if (raw.startsWith('[') && raw.endsWith(']')) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          return list.map((e) => e.toString()).toList();
        }
      } catch (_) {
        final inner = raw.substring(1, raw.length - 1);
        return inner.split(',').map((s) => s.trim().replaceAll('"', '')).where((s) => s.isNotEmpty).toList();
      }
    }
    // 逗号分隔
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// 解析 CSS 选择器列表，支持简单的 class / id / tag / 属性选择器
  List<Element> _selectList(dynamic root, String selector) {
    if (selector.isEmpty) return [];
    if (root is! Element && root is! Document) {
      return [];
    }
    try {
      return root.querySelectorAll(selector);
    } catch (_) {
      return [];
    }
  }

  /// 解析 text 规则：selector@text
  String _selectText(dynamic root, String rule) {
    if (rule.isEmpty) return '';
    final parts = rule.split('@');
    final selector = parts[0];
    final attr = parts.length > 1 ? parts[1] : 'text';
    if (selector.isEmpty) {
      if (root is Element) {
        return attr == 'text' ? root.text.trim() : (root.attributes[attr] ?? '');
      }
      return '';
    }
    try {
      final el = root.querySelector(selector);
      if (el == null) return '';
      if (attr == 'text' || attr == 'textNodes') {
        return el.text.trim();
      }
      return el.attributes[attr] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 解析属性规则：selector@attr
  String _selectAttr(dynamic root, String rule, String baseUrl) {
    if (rule.isEmpty) return '';
    final parts = rule.split('@');
    final selector = parts[0];
    final attr = parts.length > 1 ? parts[1] : 'href';
    Element? el;
    if (selector.isNotEmpty) {
      try {
        el = root.querySelector(selector);
      } catch (_) {
        return '';
      }
    } else if (root is Element) {
      el = root;
    }
    if (el == null) return '';
    var val = el.attributes[attr] ?? '';
    if (val.isNotEmpty) {
      val = _http.absoluteUrl(baseUrl, val);
    }
    return val;
  }
}

extension _StringExt on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
