import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/source.dart';
import '../models/comic.dart';
import 'http_client.dart';
import 'js_runtime.dart';
import 'rule_parser.dart';
import 'json_path.dart';

/// 规则执行环境：提供 @js 脚本所需的上下文变量。
class EvalEnv {
  final String raw;
  final String baseUrl;
  final String key;
  final int page;

  EvalEnv({
    required this.raw,
    required this.baseUrl,
    this.key = '',
    this.page = 1,
  });
}

/// 图源规则引擎：解析并执行 legado / 异次元 图源规则。
///
/// 支持规则语法见 [RuleParser]；JSON 规则由 [JsonPathEngine] 求值。
class SourceEngine {
  final HttpClient _http = HttpClient();
  final JsRuntime _js = JsRuntime();

  // -------------------- 对外接口 --------------------

  /// 搜索漫画
  Future<List<Comic>> search(ComicSource source, String keyword, {int page = 1}) async {
    if (source.ruleSearchUrl.trim().isEmpty) {
      throw Exception('该图源未配置搜索规则');
    }
    final (_, headers) = RuleParser.splitHeader(source.ruleSearchUrl);
    final url = buildUrl(source.ruleSearchUrl, keyword, page);
    final html = await _http.getString(url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    return _parseComicList(source, html, url, key: keyword, page: page);
  }

  /// 分类 / 发现页漫画列表
  Future<List<Comic>> category(ComicSource source, String urlTemplate, {int page = 1}) async {
    final (_, headers) = RuleParser.splitHeader(urlTemplate);
    final url = buildUrl(urlTemplate, '', page);
    final html = await _http.getString(url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    return _parseComicList(source, html, url, key: '', page: page);
  }

  /// 获取漫画详情
  Future<Comic> getDetail(ComicSource source, Comic comic) async {
    final (_, headers) = RuleParser.splitHeader(comic.noteUrl);
    final html = await _http.getString(comic.noteUrl,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: comic.noteUrl);

    comic.name = _ifEmpty(
        await _evalString(source.ruleBookName, ctx, env), comic.name);
    comic.author = _ifEmpty(
        await _evalString(source.ruleBookAuthor, ctx, env), comic.author);
    comic.coverUrl = _ifEmpty(
        await _evalString(source.ruleCoverUrl, ctx, env), comic.coverUrl);
    comic.introduce = _ifEmpty(
        await _evalString(source.ruleIntroduce, ctx, env), comic.introduce);
    comic.kind = _ifEmpty(
        await _evalString(source.ruleBookKind, ctx, env), comic.kind);
    return comic;
  }

  /// 获取章节列表
  Future<List<Chapter>> getChapters(ComicSource source, Comic comic) async {
    var ruleStr = source.ruleChapterList;
    var reverse = false;
    final trimmed = ruleStr.trimLeft();
    if (trimmed.startsWith('-')) {
      reverse = true;
      ruleStr = trimmed.substring(1);
    }
    if (ruleStr.trim().isEmpty) return [];

    // 章节列表请求 URL：优先使用 ruleChapterUrl（支持 thisPage / @js），否则用详情页 URL
    final chapterUrl = await _resolveChapterUrl(source, comic.noteUrl);
    final (_, headers) = RuleParser.splitHeader(chapterUrl);
    final html = await _http.getString(chapterUrl,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: chapterUrl);

    final parsed = RuleParser.parse(ruleStr);
    final items = await _runParsed(parsed, ctx, env);

    var chapters = <Chapter>[];
    for (final item in items) {
      final name = await _evalString(source.ruleChapterName, item, env);
      final url = await _evalString(source.ruleContentUrl, item, env);
      if (url.trim().isEmpty) continue;
      chapters.add(Chapter(name: name, url: url.trim(), index: 0));
    }
    if (reverse) chapters = chapters.reversed.toList();
    for (var i = 0; i < chapters.length; i++) {
      chapters[i].index = i;
    }
    return chapters;
  }

  /// 获取章节图片 URL 列表
  Future<List<String>> getContent(
      ComicSource source, Chapter chapter, Comic comic) async {
    final parsed = RuleParser.parse(source.ruleBookContent);
    final headers = parsed.headers;
    final html = await _http.getString(chapter.url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: chapter.url);

    final results = await _runParsed(parsed, ctx, env);
    final urls = <String>[];
    for (final r in results) {
      if (r is Element) {
        // 规则未显式指定属性时，回退到常见图片属性
        final u = r.attributes['data-src'] ??
            r.attributes['data-original'] ??
            r.attributes['data-lazy-src'] ??
            r.attributes['data-echo'] ??
            r.attributes['src'] ??
            '';
        if (u.isNotEmpty) urls.add(_http.absoluteUrl(chapter.url, u));
        continue;
      }
      final s = _stringify(r).trim();
      if (s.isEmpty) continue;
      for (final part in s.split(RegExp(r'[\n,]+'))) {
        final p = part.trim();
        if (p.isEmpty) continue;
        urls.add(_http.absoluteUrl(chapter.url, p));
      }
    }
    // 去重且保持顺序
    final seen = <String>{};
    return urls.where((u) => seen.add(u)).toList();
  }

  /// 获取小说章节文本内容（用于文本源，区别于 [getContent] 的图片列表）。
  Future<String> getContentText(
      ComicSource source, Chapter chapter, Comic comic) async {
    final parsed = RuleParser.parse(source.ruleBookContent);
    final headers = parsed.headers;
    final html = await _http.getString(chapter.url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: chapter.url);

    final results = await _runParsed(parsed, ctx, env);
    final paragraphs = <String>[];
    for (final r in results) {
      final s = _stringify(r).trim();
      if (s.isEmpty) continue;
      // 按换行拆分段落，去除空行
      for (final line in s.split(RegExp(r'\n+'))) {
        final t = line.trim();
        if (t.isNotEmpty) paragraphs.add(t);
      }
    }
    return paragraphs.join('\n\n');
  }

  /// 解析章节列表请求 URL。
  ///
  /// legado 图源的 `ruleChapterUrl` 支持：
  /// - 空：使用详情页 URL
  /// - `thisPage`：使用详情页 URL
  /// - `thisPage@js:function(baseUrl){...}(baseUrl)`：对详情页 URL 应用 JS 变换
  /// - 普通 URL：直接使用
  Future<String> _resolveChapterUrl(ComicSource source, String noteUrl) async {
    final rule = source.ruleChapterUrl.trim();
    if (rule.isEmpty) return noteUrl;

    // thisPage 关键字
    if (rule == 'thisPage') return noteUrl;

    // thisPage@js:...
    if (rule.startsWith('thisPage')) {
      final jsIdx = rule.indexOf('@js:');
      if (jsIdx > 0) {
        final jsCode = rule.substring(jsIdx + 4);
        final result = await _js.evalRule(jsCode, baseUrl: noteUrl);
        if (result.isNotEmpty && result != 'null' && result != 'undefined') {
          // 去掉 JSON 引号
          var url = result.replaceAll('"', '').replaceAll("'", '');
          if (url.startsWith('http')) return url;
        }
      }
      return noteUrl;
    }

    // 普通 URL（支持相对地址）
    if (rule.startsWith('http://') || rule.startsWith('https://')) {
      return rule;
    }
    return _http.absoluteUrl(noteUrl, rule);
  }

  // -------------------- 列表解析 --------------------

  Future<List<Comic>> _parseComicList(
    ComicSource source,
    String html,
    String baseUrl, {
    required String key,
    required int page,
  }) async {
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: baseUrl, key: key, page: page);
    final items = await _runParsed(RuleParser.parse(source.ruleSearchList), ctx, env);

    final comics = <Comic>[];
    for (final item in items) {
      final name = await _evalString(source.ruleSearchName, item, env);
      final note = await _evalString(source.ruleSearchNoteUrl, item, env);
      if (name.trim().isEmpty && note.trim().isEmpty) continue;
      final author = await _evalString(source.ruleSearchAuthor, item, env);
      final cover = await _evalString(source.ruleSearchCoverUrl, item, env);
      comics.add(Comic(
        name: name.trim(),
        author: author.trim(),
        coverUrl: cover.trim(),
        noteUrl: note.trim(),
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName,
        kind: source.bookSourceGroup,
      ));
    }
    return comics;
  }

  // -------------------- 规则执行 --------------------

  /// 执行规则并返回原始结果列表（Element / Map / String …）。
  Future<List<dynamic>> _runParsed(ParsedRule parsed, dynamic ctx, EvalEnv env) async {
    var current = <dynamic>[ctx];

    for (final step in parsed.steps) {
      current = _applyStep(step, current, env);
      if (current.isEmpty) break;
    }

    if (parsed.attr != null && current.isNotEmpty) {
      final out = <dynamic>[];
      for (final n in current) {
        final v = _extract(n, parsed.attr!, env);
        if (v != null) out.add(v);
      }
      current = out;
    }

    final js = parsed.jsCode;
    if (js != null && js.trim().isNotEmpty) {
      final arg = (parsed.steps.isEmpty && parsed.attr == null)
          ? env.raw
          : current.map(_stringify).join('\n');
      final res = await _js.evalRule(js,
          result: arg, baseUrl: env.baseUrl, key: env.key, page: env.page);
      current = _interpretJs(res);
    }

    if (parsed.replaceFrom != null) {
      RegExp? re;
      try {
        re = RegExp(parsed.replaceFrom!);
      } catch (_) {
        re = null;
      }
      if (re != null) {
        current = current
            .map((n) => _stringify(n).replaceAll(re!, parsed.replaceTo ?? ''))
            .toList();
      }
    }

    return current;
  }

  List<dynamic> _applyStep(RuleStep step, List<dynamic> current, EvalEnv env) {
    if (step.cssSelector != null) {
      final out = <dynamic>[];
      for (final n in current) {
        out.addAll(_query(n, step.cssSelector!, env));
      }
      return _applyIndex(out, step.index);
    }
    if (step.jsonPath != null) {
      final out = <dynamic>[];
      for (final n in current) {
        out.addAll(JsonPathEngine.query(n, step.jsonPath!));
      }
      return _applyIndex(out, step.index);
    }
    if (step.textMatch != null) {
      final out = <dynamic>[];
      for (final n in current) {
        if (n is Element && n.text.contains(step.textMatch!)) out.add(n);
      }
      return out.isEmpty ? current : out;
    }
    return current;
  }

  List<dynamic> _applyIndex(List<dynamic> list, int? index) {
    if (index == null) return list;
    if (index >= 0 && index < list.length) return [list[index]];
    return [];
  }

  List<Element> _query(dynamic node, String selector, EvalEnv env) {
    if (selector.trim().isEmpty) return [];
    Document? doc;
    Element? el;
    if (node is Document) {
      doc = node;
    } else if (node is Element) {
      el = node;
    } else if (node is String) {
      try {
        doc = html_parser.parse(node);
      } catch (_) {
        return [];
      }
    } else {
      return [];
    }
    try {
      if (doc != null) return doc.querySelectorAll(selector);
      if (el != null) return el.querySelectorAll(selector);
    } catch (_) {
      return [];
    }
    return [];
  }

  dynamic _extract(dynamic node, String attr, EvalEnv env) {
    final a = attr.toLowerCase();
    if (node == null) return null;

    if (a == 'text' || a == 'textnodes' || a == 'owntext') {
      if (node is Element) return node.text.trim();
      if (node is String) return node;
      return _stringify(node);
    }
    if (a == 'html' || a == 'innerhtml') {
      if (node is Element) return node.innerHtml;
      if (node is String) return node;
    }
    if (a == 'outerhtml') {
      if (node is Element) return node.outerHtml;
      if (node is String) return node;
    }

    String val = '';
    if (node is Element) {
      val = node.attributes[a] ?? '';
      // 属性名大小写在 HTML 中不敏感
      if (val.isEmpty) {
        for (final e in node.attributes.entries) {
          if (e.key.toString().toLowerCase() == a) {
            val = e.value;
            break;
          }
        }
      }
    } else if (node is Map) {
      val = (node[a] ?? node[attr])?.toString() ?? '';
    } else if (node is String) {
      return node;
    }
    if (val.isEmpty) return null;
    if (RuleParser.urlAttrs.contains(a)) {
      return _http.absoluteUrl(env.baseUrl, val);
    }
    return val;
  }

  Future<String> _evalString(String rule, dynamic ctx, EvalEnv env) async {
    if (rule.trim().isEmpty) {
      // 无规则时，若 ctx 是元素则取文本
      if (ctx is Element) return ctx.text.trim();
      if (ctx is String) return ctx;
      if (ctx is Map) return _stringify(ctx);
      return '';
    }
    final list = await _runParsed(RuleParser.parse(rule), ctx, env);
    if (list.isEmpty) return '';
    return _stringify(list.first).trim();
  }

  String _stringify(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Element) return v.text.trim();
    if (v is Document) return v.documentElement?.outerHtml ?? '';
    if (v is Map || v is List) return jsonEncode(v);
    return v.toString();
  }

  /// 自动识别响应内容类型：
  /// - 若为 JSON（以 `{` 或 `[` 开头且可解析），返回解析后的 Map/List，供 JSONPath 规则使用
  /// - 否则解析为 HTML Document，供 CSS/XPath 规则使用
  dynamic _parseContext(String raw) {
    final trimmed = raw.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        // 解析失败，回退到 HTML
      }
    }
    return html_parser.parse(raw);
  }

  List<dynamic> _interpretJs(String res) {
    final t = res.trim();
    if (t.isEmpty || t == 'undefined' || t == 'null') return [];
    try {
      final d = jsonDecode(t);
      if (d is List) return d;
      if (d is Map) return [d];
      return [d.toString()];
    } catch (_) {
      return [res];
    }
  }

  String _ifEmpty(String value, String fallback) =>
      value.trim().isEmpty ? fallback : value.trim();

  /// 构造请求 URL：替换 searchKey / searchPage 等占位符。
  static String buildUrl(String template, String keyword, int page) {
    final (noHeader, _) = RuleParser.splitHeader(template);
    var url = noHeader.trim();
    final enc = Uri.encodeComponent(keyword);
    url = url
        .replaceAll('searchKey', enc)
        .replaceAll('{{key}}', enc)
        .replaceAll('{{searchKey}}', enc)
        .replaceAll('searchPage', page.toString())
        .replaceAll('{{page}}', page.toString());
    return url.trim();
  }
}
