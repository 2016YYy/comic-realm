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
  final Comic? comic;

  EvalEnv({
    required this.raw,
    required this.baseUrl,
    this.key = '',
    this.page = 1,
    this.comic,
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
    var url = await _buildUrl(source.ruleSearchUrl, keyword, page);
    // 搜索地址为相对路径时，以图源首页兜底解析，避免「缺少主机名」。
    url = _resolveAgainstSource(source, url);
    final html = await _http.getString(url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    return _parseComicList(source, html, url, key: keyword, page: page);
  }

  /// 分类 / 发现页漫画列表
  Future<List<Comic>> category(ComicSource source, String urlTemplate, {int page = 1}) async {
    final (_, headers) = RuleParser.splitHeader(urlTemplate);
    var url = await _buildUrl(urlTemplate, '', page);
    // 发现页 / 分类地址通常是相对路径，统一以图源首页解析为绝对地址。
    url = _resolveAgainstSource(source, url);
    final html = await _http.getString(url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    return _parseComicList(source, html, url, key: '', page: page);
  }

  /// 获取漫画详情
  Future<Comic> getDetail(ComicSource source, Comic comic) async {
    // 详情页地址为空或相对时，以图源首页兜底解析，避免「缺少主机名」。
    comic.noteUrl = _resolveAgainstSource(source, comic.noteUrl);
    _ensureHttp(comic.noteUrl, '漫画详情');
    final (_, headers) = RuleParser.splitHeader(comic.noteUrl);
    final html = await _http.getString(comic.noteUrl,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: comic.noteUrl, comic: comic);

    comic.name = _ifEmpty(
        await _evalString(source.ruleBookName, ctx, env), comic.name);
    comic.author = _ifEmpty(
        await _evalString(source.ruleBookAuthor, ctx, env), comic.author);
    final cover = await _evalString(source.ruleCoverUrl, ctx, env);
    comic.coverUrl = _ifEmpty(
        cover.isNotEmpty ? _http.absoluteUrl(comic.noteUrl, cover) : '', comic.coverUrl);
    comic.introduce = _ifEmpty(
        await _evalString(source.ruleIntroduce, ctx, env), comic.introduce);
    comic.kind = _ifEmpty(
        await _evalString(source.ruleBookKind, ctx, env), comic.kind);
    // 根据分类 / 简介文本推断连载状态（对齐 legado book.status）：
    // 含「完结」→ 2，含「连载 / 更新中」→ 1，其余保持原值。
    if (comic.status == 0) {
      final hint = '${comic.kind} ${comic.introduce}';
      if (hint.contains('完结') || hint.contains('完本') || hint.contains('已完结')) {
        comic.status = 2;
      } else if (hint.contains('连载') || hint.contains('更新中') || hint.contains('连载中')) {
        comic.status = 1;
      }
    }
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

    // 详情页地址为空或相对时，以图源首页兜底解析。
    comic.noteUrl = _resolveAgainstSource(source, comic.noteUrl);

    // 章节列表请求 URL：优先使用 ruleChapterUrl（支持 thisPage / @js），否则用详情页 URL
    final chapterUrl = await _resolveChapterUrl(source, comic.noteUrl);
    _ensureHttp(chapterUrl, '章节列表');
    final (_, headers) = RuleParser.splitHeader(chapterUrl);
    final html = await _http.getString(chapterUrl,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: chapterUrl, comic: comic);

    final items = _flattenItems(await _runRule(ruleStr, ctx, env));

    var chapters = <Chapter>[];
    for (final item in items) {
      final name = await _evalString(source.ruleChapterName, item, env);
      var rawUrl = await _evalString(source.ruleContentUrl, item, env);
      // ruleContentUrl 为空时，回退到元素的 href / Map 的 url 字段
      if (rawUrl.trim().isEmpty) {
        rawUrl = _extractUrlFromItem(item);
      }
      if (rawUrl.trim().isEmpty) continue;
      // JSON 源可能返回相对地址，统一解析为绝对 URL
      final absUrl = _http.absoluteUrl(chapterUrl, rawUrl.trim());
      chapters.add(Chapter(name: name, url: absUrl, index: 0));
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
    _ensureHttp(chapter.url, '章节内容');
    final headers = RuleParser.splitHeader(source.ruleBookContent).$2;
    final html = await _http.getString(chapter.url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: chapter.url, comic: comic);

    final results = await _runRule(source.ruleBookContent, ctx, env);
    final urls = <String>[];
    for (final r in results) {
      _collectContentUrls(r, chapter.url, urls);
    }
    // 去重且保持顺序
    final seen = <String>{};
    return urls.where((u) => seen.add(u)).toList();
  }

  /// 获取小说章节文本内容（用于文本源，区别于 [getContent] 的图片列表）。
  Future<String> getContentText(
      ComicSource source, Chapter chapter, Comic comic) async {
    _ensureHttp(chapter.url, '章节内容');
    final headers = RuleParser.splitHeader(source.ruleBookContent).$2;
    final html = await _http.getString(chapter.url,
        headers: headers.isEmpty ? null : headers, userAgent: source.httpUserAgent);
    final ctx = _parseContext(html);
    final env = EvalEnv(raw: html, baseUrl: chapter.url, comic: comic);

    final results = await _runRule(source.ruleBookContent, ctx, env);
    final paragraphs = <String>[];
    final texts = <String>[];
    for (final r in results) {
      _collectTexts(r, texts);
    }
    for (final s0 in texts) {
      final s = s0.trim();
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

  /// 将相对 / 空地址解析为绝对地址：优先用图源首页（bookSourceUrl）兜底，
  /// 再用请求的 baseUrl 兜底。避免搜索列表未配置 noteUrl 时出现
  /// 「缺少主机名」而整个章节列表加载失败。
  String _resolveAgainstSource(ComicSource source, String url, {String? base}) {
    final raw = url.trim();
    if (raw.isEmpty) {
      return source.bookSourceUrl.trim().isNotEmpty ? source.bookSourceUrl.trim() : '';
    }
    if (HttpClient.isHttpUrl(raw)) return raw;
    // 相对地址：优先用图源首页解析
    if (source.bookSourceUrl.trim().isNotEmpty) {
      final abs = _http.absoluteUrl(source.bookSourceUrl.trim(), raw);
      if (HttpClient.isHttpUrl(abs)) return abs;
    }
    if (base != null && base.trim().isNotEmpty) {
      return _http.absoluteUrl(base.trim(), raw);
    }
    return raw;
  }

  /// 校验请求地址是否可解析为带主机名的 http(s) 地址。
  ///
  /// 规则里经常出现相对地址 / 空地址（例如搜索列表未配置 noteUrl、
  /// ruleChapterUrl 为相对路径而详情页地址为空），直接交给网络层会抛出
  /// 「No host specified in URI」这种难以理解的底层错误，这里提前拦截并
  /// 给出可读提示。
  void _ensureHttp(String url, String what) {
    if (HttpClient.isHttpUrl(url)) return;
    final shown = url.trim().isEmpty ? '(空地址)' : url.trim();
    throw Exception('$what地址无效（缺少主机名）：$shown');
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
    final items = _flattenItems(await _runRule(source.ruleSearchList, ctx, env));

    final comics = <Comic>[];
    for (final item in items) {
      final name = await _evalString(source.ruleSearchName, item, env);
      final note = await _evalString(source.ruleSearchNoteUrl, item, env);
      if (name.trim().isEmpty && note.trim().isEmpty) continue;
      final author = await _evalString(source.ruleSearchAuthor, item, env);
      final cover = await _evalString(source.ruleSearchCoverUrl, item, env);
      // JSON 源可能返回相对地址，统一解析为绝对 URL
      final absNote = note.trim().isNotEmpty
          ? _http.absoluteUrl(baseUrl, note.trim())
          : '';
      final absCover = cover.trim().isNotEmpty
          ? _http.absoluteUrl(baseUrl, cover.trim())
          : '';
      comics.add(Comic(
        name: name.trim(),
        author: author.trim(),
        coverUrl: absCover,
        noteUrl: absNote,
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName,
        kind: source.bookSourceGroup,
      ));
    }
    return comics;
  }

  // -------------------- 规则执行 --------------------

  /// 执行规则（支持 `||` 回退）：依次尝试各分支，返回第一个非空结果。
  Future<List<dynamic>> _runRule(String rule, dynamic ctx, EvalEnv env) async {
    if (rule.trim().startsWith(':_H006_')) {
      throw Exception('该图源规则已加密（异次元私有格式），暂不支持');
    }
    final parts = _splitFallback(rule);
    // 响应为 JSON（Map / List）时，未显式标注的选择器按 JSONPath 解析。
    final jsonMode = ctx is Map || ctx is List;
    for (var i = 0; i < parts.length; i++) {
      final result = await _runParsed(
          RuleParser.parse(parts[i], jsonMode: jsonMode), ctx, env);
      if (result.isNotEmpty) return result;
    }
    return [];
  }

  /// 按 `||` 切分规则（忽略括号 / 引号 / `@js:` 脚本内的 `||`）。
  List<String> _splitFallback(String rule) {
    if (!rule.contains('||')) return [rule];
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    String? quote;
    var inJs = false;
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (inJs) {
        buf.write(c);
        continue;
      }
      if (quote != null) {
        buf.write(c);
        if (c == quote) quote = null;
        continue;
      }
      if (c == '\'' || c == '"') {
        quote = c;
        buf.write(c);
        continue;
      }
      if (c == '[' || c == '(' || c == '{') {
        depth++;
        buf.write(c);
        continue;
      }
      if (c == ']' || c == ')' || c == '}') {
        if (depth > 0) depth--;
        buf.write(c);
        continue;
      }
      // 检测 @js: 之后全部视为脚本
      if (rule.startsWith('@js:', i)) {
        inJs = true;
        buf.write('@js:');
        i += 3;
        continue;
      }
      if (depth == 0 && rule.startsWith('||', i)) {
        out.add(buf.toString().trim());
        buf.clear();
        i += 1;
        continue;
      }
      buf.write(c);
    }
    out.add(buf.toString().trim());
    return out.where((s) => s.isNotEmpty).toList();
  }

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
      // org.jsoup / java.ajax / base64 / Packages.java 等常见 Java 扩展 API
      // 均已由 JsRuntime 注入的 shim 提供（见 js_runtime.dart），这里直接执行。
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

  /// 从规则结果项中提取 URL（当 ruleContentUrl 为空时的回退）。
  /// HTML 元素取 href；Map 取 url/link/href 字段。
  String _extractUrlFromItem(dynamic item) {
    if (item == null) return '';
    if (item is Element) {
      return item.attributes['href'] ??
          item.attributes['data-href'] ??
          item.attributes['data-url'] ??
          '';
    }
    if (item is Map) {
      return (item['url'] ?? item['link'] ?? item['href'] ?? item['chapterUrl'] ?? '')
          .toString();
    }
    final s = item.toString().trim();
    if (s.startsWith('http') || s.startsWith('/')) return s;
    return '';
  }

  /// 展开列表型结果：JSONPath 命中数组时（如 `$.data.list`）会得到一个包裹
  /// 着数组的列表，这里展平一层，使每个元素成为一个独立条目（对齐 legado）。
  List<dynamic> _flattenItems(List<dynamic> items) {
    final out = <dynamic>[];
    for (final it in items) {
      if (it is List) {
        out.addAll(it);
      } else {
        out.add(it);
      }
    }
    return out;
  }

  /// 从规则结果项中收集图片 URL（递归展开嵌套 List）。
  void _collectContentUrls(dynamic r, String base, List<String> out) {
    if (r == null) return;
    if (r is List) {
      for (final e in r) {
        _collectContentUrls(e, base, out);
      }
      return;
    }
    if (r is Element) {
      // 规则未显式指定属性时，回退到常见图片属性（含各种懒加载写法）
      final u = r.attributes['data-src'] ??
          r.attributes['data-original'] ??
          r.attributes['data-lazy-src'] ??
          r.attributes['data-lazyload'] ??
          r.attributes['data-echo'] ??
          r.attributes['data-cfsrc'] ??
          r.attributes['data-img'] ??
          r.attributes['data-original-src'] ??
          r.attributes['data-bg'] ??
          r.attributes['data-url'] ??
          r.attributes['src'] ??
          '';
      if (u.isNotEmpty) out.add(_http.absoluteUrl(base, u));
      return;
    }
    if (r is Map) {
      // JSON 源：从常见字段提取图片 URL
      final u = (r['url'] ??
              r['src'] ??
              r['image'] ??
              r['img'] ??
              r['pic'] ??
              r['cover'] ??
              r['imageUrl'] ??
              '')
          .toString();
      if (u.isNotEmpty) out.add(_http.absoluteUrl(base, u));
      return;
    }
    final s = _stringify(r).trim();
    if (s.isEmpty) return;
    for (final part in s.split(RegExp(r'[\n,]+'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      out.add(_http.absoluteUrl(base, p));
    }
  }

  /// 从规则结果项中收集文本（递归展开嵌套 List）。
  void _collectTexts(dynamic r, List<String> out) {
    if (r == null) return;
    if (r is List) {
      for (final e in r) {
        _collectTexts(e, out);
      }
      return;
    }
    if (r is Map) {
      // JSON 源：从常见文本字段提取内容
      final s = (r['content'] ??
              r['text'] ??
              r['body'] ??
              r['chapter'] ??
              r['contentText'] ??
              r['data'] ??
              '')
          .toString();
      if (s.isNotEmpty) out.add(s);
      return;
    }
    final s = _stringify(r).trim();
    if (s.isNotEmpty) out.add(s);
  }

  Future<String> _evalString(String rule, dynamic ctx, EvalEnv env) async {
    final trimmed = rule.trim();
    // 文本模板规则：含 {if: / {/if} / [comic: / [book: 时，直接做模板处理
    // （不走选择器解析，避免把 {if:...} 当 CSS 选择器而返回空）。
    if (trimmed.contains('{if:') ||
        trimmed.contains('{/if}') ||
        trimmed.contains('[comic:') ||
        trimmed.contains('[book:')) {
      return _applyTextTemplate(trimmed, env);
    }
    if (trimmed.isEmpty) {
      // 无规则时，若 ctx 是元素则取文本
      if (ctx is Element) return ctx.text.trim();
      if (ctx is String) return ctx;
      if (ctx is Map) return _stringify(ctx);
      return '';
    }
    final list = _flattenItems(await _runRule(trimmed, ctx, env));
    if (list.isEmpty) return '';
    final result = _stringify(list.first).trim();
    // 结果文本中也可能含 {if} / [comic:] 模板片段
    if (result.contains('{if:') ||
        result.contains('{/if}') ||
        result.contains('[comic:') ||
        result.contains('[book:')) {
      return _applyTextTemplate(result, env);
    }
    return result;
  }

  /// 处理文本模板：
  ///   1. `[comic:field]` / `[book:field]` 替换为漫画对应字段值
  ///   2. `{if:条件}正文{else}否则{/if}` 按 JS 条件求值选择分支
  /// 对齐 legado 文本规则语法。
  Future<String> _applyTextTemplate(String text, EvalEnv env) async {
    var s = text;
    // 1. 替换 [comic:field] / [book:field]
    s = s.replaceAllMapped(RegExp(r'\[(?:comic|book):([^\]]+)\]'), (m) {
      return _comicFieldValue(env.comic, m.group(1)!.trim());
    });

    // 2. 处理 {if:cond}...{else}...{/if}（支持嵌套：从内向外处理）
    var changed = true;
    while (changed) {
      changed = false;
      final m = RegExp(r'\{if:([^}]+)\}([\s\S]*?)\{/if\}').firstMatch(s);
      if (m == null) break;
      final cond = m.group(1)!.trim();
      final body = m.group(2)!;
      // body 中可能含 {else}
      String ifBody = body;
      String elseBody = '';
      final elseIdx = _indexOfTopLevelElse(body);
      if (elseIdx >= 0) {
        ifBody = body.substring(0, elseIdx);
        elseBody = body.substring(elseIdx + 6); // len('{else}') == 6
      }
      final ok = await _evalCondition(cond, env);
      s = s.substring(0, m.start) + (ok ? ifBody : elseBody) + s.substring(m.end);
      changed = true;
    }
    return s;
  }

  /// 取漫画字段值（用于 [comic:field] 替换）。
  String _comicFieldValue(Comic? comic, String field) {
    if (comic == null) return '';
    switch (field.toLowerCase()) {
      case 'name':
      case 'title':
        return comic.name;
      case 'author':
        return comic.author;
      case 'cover':
      case 'coverurl':
        return comic.coverUrl;
      case 'intro':
      case 'introduce':
        return comic.introduce;
      case 'kind':
      case 'category':
        return comic.kind;
      case 'lastchapter':
        return comic.lastChapter;
      case 'noteurl':
      case 'url':
        return comic.noteUrl;
      case 'status':
        return comic.status.toString();
      case 'source':
      case 'sourcename':
        return comic.sourceName;
      default:
        return '';
    }
  }

  /// 查找 body 中顶层 {else} 的下标（忽略嵌套 {if} 内部的 {else}）。
  int _indexOfTopLevelElse(String body) {
    var depth = 0;
    for (var i = 0; i < body.length; i++) {
      if (body.startsWith('{if:', i)) {
        depth++;
        i += 3;
      } else if (body.startsWith('{/if}', i)) {
        if (depth > 0) depth--;
        i += 4;
      } else if (depth == 0 && body.startsWith('{else}', i)) {
        return i;
      }
    }
    return -1;
  }

  /// 求值 {if: 条件}：条件已替换过 [comic:field]，直接用 JS 引擎求值布尔。
  Future<bool> _evalCondition(String cond, EvalEnv env) async {
    if (cond.isEmpty) return false;
    try {
      final r = await _js.eval('!!($cond)');
      return r == 'true';
    } catch (_) {
      // 非 JS 表达式（如纯文本），按「非空即真」处理
      return cond.trim().isNotEmpty && cond != '0' && cond != 'false';
    }
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
    var trimmed = raw.trimLeft();
    // 去除可能的 BOM（U+FEFF）
    if (trimmed.startsWith('\uFEFF')) {
      trimmed = trimmed.substring(1);
    }
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

  /// 构造请求 URL：替换 searchKey / searchPage / {{page}} / {{page-N}} / <offset> 等占位符。
  static String buildUrl(String template, String keyword, int page) {
    final (noHeader, _) = RuleParser.splitHeader(template);
    var url = noHeader.trim();
    final enc = Uri.encodeComponent(keyword);

    // 关键词
    url = url
        .replaceAll('searchKey', enc)
        .replaceAll('{{key}}', enc)
        .replaceAll('{{searchKey}}', enc);

    // 页码：{{page}}、searchPage
    url = url
        .replaceAll('searchPage', page.toString())
        .replaceAll('{{page}}', page.toString());

    // 页码偏移：{{page-1}}、{{page+1}} 等
    url = url.replaceAllMapped(RegExp(r'\{\{page([+-]\d+)\}\}'), (m) {
      final offset = int.tryParse(m.group(1)!) ?? 0;
      return (page + offset).toString();
    });

    // legado 偏移列表：<0,150,300> → 第 page 项（page 从 1 开始，取第 page-1 个）
    url = url.replaceAllMapped(RegExp(r'<([^>]+)>'), (m) {
      final parts = m.group(1)!.split(',').map((e) => e.trim()).toList();
      final idx = (page - 1).clamp(0, parts.length - 1);
      return parts[idx];
    });

    return url.trim();
  }

  /// 异步构造请求 URL：在 [buildUrl] 的基础上，额外对 `{{...}}` 中的
  /// JavaScript 表达式求值（legado 支持在 URL 中写任意 JS，如
  /// `{{15*(1-1)}}`）。优先走内置简单占位符，剩余的 `{{...}}` 交由 JS 引擎。
  Future<String> _buildUrl(String template, String keyword, int page) async {
    var url = buildUrl(template, keyword, page);
    // 剩余未被静态替换的 {{...}}：可能是 JS 表达式（如 {{15*(page-1)}}）
    final jsExprRe = RegExp(r'\{\{([^{}]+)\}\}');
    if (!jsExprRe.hasMatch(url)) return url;
    try {
      url = url.replaceAllMapped(jsExprRe, (m) {
        return '__CR_EXPR_START__${m.group(1)}__CR_EXPR_END__';
      });
      final parts = url.split(RegExp(r'__CR_EXPR_START__|__CR_EXPR_END__'));
      final out = StringBuffer();
      for (var i = 0; i < parts.length; i++) {
        if (i.isOdd) {
          // 表达式片段：用 JS 求值
          final expr = parts[i].replaceAll('page', page.toString());
          final r = await _js.eval(expr);
          out.write(r);
        } else {
          out.write(parts[i]);
        }
      }
      return out.toString().trim();
    } catch (_) {
      // JS 求值失败时回退：去掉花括号保留原表达式文本
      return url.replaceAllMapped(jsExprRe, (m) => m.group(1)!);
    }
  }
}
