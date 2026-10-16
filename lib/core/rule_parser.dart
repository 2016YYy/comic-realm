import 'dart:convert';

/// 图源规则解析器：把 legado / 异次元 的规则字符串拆解成可执行的选择器步骤。
///
/// 支持的语法：
///   class.xxx / id.xxx / tag.xxx / text.xxx   前缀式 CSS
///   .xxx / #xxx / div a                        原生 CSS
///   //div[@class="x"]/text()                    基础 XPath（自动转 CSS）
///   $.items / $.a[*].b                          JSONPath
///   @css:xxx / @json:$.xxx                      显式前缀
///   tag.a.0 / tag.h4.0                          末尾 .N 索引
///   @text / @href / @src / @data-src …          属性
///   @js:code                                    内嵌 JS
///   @Header:{Referer:host}                      单规则请求头
///   规则##正则##替换                             结果替换
class RuleParser {
  /// URL 类属性：抽取后需转成绝对地址。
  static const Set<String> urlAttrs = {
    'href', 'src', 'data-src', 'data-original', 'data-lazy-src', 'data-lazyload',
    'data-bg', 'data-srcset', 'srcset', 'poster', 'data-url', 'data-echo',
    'data-cfsrc', 'data-img', 'data-original-src',
  };

  static ParsedRule parse(String raw) {
    var rule = raw.trim();
    final headers = <String, String>{};

    // 1. @Header:{...}
    final hdIdx = _indexOfIgnoreCase(rule, '@header:');
    if (hdIdx >= 0) {
      final braceStart = rule.indexOf('{', hdIdx);
      if (braceStart >= 0) {
        final braceEnd = _matchBracket(rule, braceStart, '{', '}');
        if (braceEnd > braceStart) {
          headers.addAll(_parseHeader(rule.substring(braceStart + 1, braceEnd)));
          rule = (rule.substring(0, hdIdx) + rule.substring(braceEnd + 1)).trim();
        }
      }
    }
    // 2. @js:（其后全部为脚本）
    String? js;
    final jsIdx = rule.indexOf('@js:');
    if (jsIdx >= 0) {
      js = rule.substring(jsIdx + 4);
      rule = rule.substring(0, jsIdx);
    }

    // 3. ## 替换：规则##正则##替换内容
    String? from;
    String? to;
    final hashIdx = rule.indexOf('##');
    if (hashIdx >= 0) {
      final parts = rule.split('##');
      if (parts.length >= 3) {
        rule = parts[0];
        from = parts[1];
        to = parts.sublist(2).join('##');
      } else if (parts.length == 2) {
        rule = parts[0];
        from = parts[1];
        to = '';
      }
    }

    // 4. 按 @ 切分（括号 / 引号内的 @ 不切）
    final tokens = _splitTop(rule.trim(), '@');

    final steps = <RuleStep>[];
    String? attr;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i].trim();
      if (t.isEmpty) continue;

      if (i > 0 && attr == null && !_looksLikeSelector(t)) {
        attr = t.toLowerCase();
        continue;
      }

      final step = _buildStep(t);
      if (step != null) {
        steps.add(step);
        if (attr == null && step.xpathAttr != null) attr = step.xpathAttr;
      }
    }

    return ParsedRule(
      steps: steps,
      attr: attr,
      jsCode: js,
      headers: headers,
      replaceFrom: from,
      replaceTo: to,
    );
  }

  /// 仅剥离 `@Header:{...}`，返回剩余规则文本与请求头（用于 URL 型规则）。
  static (String, Map<String, String>) splitHeader(String raw) {
    var rule = raw.trim();
    final headers = <String, String>{};
    final hdIdx = _indexOfIgnoreCase(rule, '@header:');
    if (hdIdx >= 0) {
      final braceStart = rule.indexOf('{', hdIdx);
      if (braceStart >= 0) {
        final braceEnd = _matchBracket(rule, braceStart, '{', '}');
        if (braceEnd > braceStart) {
          headers.addAll(_parseHeader(rule.substring(braceStart + 1, braceEnd)));
          rule = (rule.substring(0, hdIdx) + rule.substring(braceEnd + 1)).trim();
        }
      }
    }
    return (rule, headers);
  }

  /// 已知属性名集合：用于区分「标签选择器」与「属性抽取」。
  /// 例如 `li` 是标签选择器，`href` 是属性。
  static const Set<String> _attrNames = {
    'text', 'textnodes', 'owntext', 'html', 'innerhtml', 'outerhtml',
    'href', 'src', 'class', 'id', 'title', 'alt', 'style', 'name',
    'value', 'type', 'content', 'charset', 'rel', 'target', 'width',
    'height', 'action', 'method', 'placeholder', 'checked', 'disabled',
    'selected', 'readonly', 'download', 'poster', 'srcset',
  };

  /// 判断 token 是否为选择器（而非属性）。
  /// 已知属性名或 `data-*` 开头视为属性，其余视为 CSS 选择器。
  static bool _looksLikeSelector(String t) {
    final lower = t.toLowerCase().trim();
    if (lower.isEmpty) return false;
    // 选择器前缀
    if (t.startsWith('//') ||
        t.startsWith('/') ||
        t.startsWith(r'$') ||
        t.startsWith('.') ||
        t.startsWith('#') ||
        lower.startsWith('tag.') ||
        lower.startsWith('class.') ||
        lower.startsWith('id.') ||
        lower.startsWith('text.') ||
        lower.startsWith('css:') ||
        lower.startsWith('json:') ||
        lower.startsWith('jsonpath:')) {
      return true;
    }
    // data-* 属性
    if (lower.startsWith('data-')) return false;
    // 已知属性名
    if (_attrNames.contains(lower)) return false;
    // 其余视为 CSS 选择器（含标签名如 li、div、a 等）
    return true;
  }

  static RuleStep? _buildStep(String token) {
    final lower = token.toLowerCase();

    if (lower.startsWith('css:')) {
      final sel = token.substring(4).trim();
      final (css, index) = _stripIndex(sel);
      return RuleStep(cssSelector: css, index: index);
    }

    if (lower.startsWith('json:')) {
      return RuleStep(jsonPath: token.substring(5).trim());
    }
    if (lower.startsWith('jsonpath:')) {
      return RuleStep(jsonPath: token.substring(9).trim());
    }

    if (token.startsWith(r'$')) {
      return RuleStep(jsonPath: token);
    }

    if (token.startsWith('//') || token.startsWith('/')) {
      return _translateXPath(token);
    }

    String css;
    if (lower.startsWith('tag.')) {
      css = token.substring(4).trim();
    } else if (lower.startsWith('class.')) {
      css = '.${token.substring(6).trim()}';
    } else if (lower.startsWith('id.')) {
      css = '#${token.substring(3).trim()}';
    } else if (lower.startsWith('text.')) {
      return RuleStep(textMatch: token.substring(5).trim());
    } else {
      css = token;
    }

    final (sel, index) = _stripIndex(css);
    return RuleStep(cssSelector: sel, index: index);
  }

  /// 拆出末尾的 `.N` 索引，例如 tag`h4.0` -> (`h4`, 0)
  static (String, int?) _stripIndex(String sel) {
    final m = RegExp(r'^(.*?)\.(\d+)$').firstMatch(sel);
    if (m != null && m.group(1)!.trim().isNotEmpty) {
      return (m.group(1)!, int.parse(m.group(2)!));
    }
    return (sel, null);
  }

  /// 基础 XPath -> CSS 转换，覆盖常见写法。
  static RuleStep? _translateXPath(String xpath) {
    var s = xpath.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }

    String? attr;

    final textM = RegExp(r'/text\(\)\s*$').firstMatch(s);
    if (textM != null) {
      attr = 'text';
      s = s.substring(0, textM.start);
    } else {
      final atM = RegExp(r'/@([A-Za-z0-9_\-]+)\s*$').firstMatch(s);
      if (atM != null) {
        attr = atM.group(1)!;
        s = s.substring(0, atM.start);
      }
    }

    if (s.startsWith('//')) {
      s = s.substring(2);
    } else if (s.startsWith('/')) {
      s = s.substring(1);
    }

    final parts = _splitTop(s, '/');
    var last = parts.isNotEmpty ? parts.last.trim() : s;
    if (last.isEmpty) last = '*';

    int? index;
    var css = last;

    // [@attr="value"] -> [attr="value"]
    final predM = RegExp(r'''^(.*?)\[@([A-Za-z0-9_\-]+)\s*=\s*(['"])(.*?)\3\]\s*$''')
        .firstMatch(last);
    final numM = RegExp(r'^(.*?)\[(\d+)\]\s*$').firstMatch(last);

    if (predM != null) {
      css = '${predM.group(1)!}[${predM.group(2)!}="${predM.group(4)!}"]';
    } else if (numM != null) {
      css = numM.group(1)!;
      index = int.parse(numM.group(2)!) - 1;
    }

    css = css.trim();
    if (css.isEmpty) css = '*';
    return RuleStep(cssSelector: css, index: index, xpathAttr: attr);
  }

  // ---------------- 工具方法 ----------------

  /// 按分隔符切分，忽略括号 / 引号内部的字符。
  static List<String> _splitTop(String s, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    String? quote;

    for (var i = 0; i < s.length; i++) {
      final c = s[i];
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
      if (depth == 0 && s.startsWith(sep, i)) {
        out.add(buf.toString());
        buf.clear();
        i += sep.length - 1;
        continue;
      }
      buf.write(c);
    }
    out.add(buf.toString());
    return out;
  }

  static int _indexOfIgnoreCase(String s, String sub) {
    return s.toLowerCase().indexOf(sub.toLowerCase());
  }

  /// 返回与 open 匹配的闭括号下标；找不到返回 -1。
  static int _matchBracket(String s, int openIdx, String open, String close) {
    var depth = 0;
    String? quote;
    for (var i = openIdx; i < s.length; i++) {
      final c = s[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '\'' || c == '"') {
        quote = c;
        continue;
      }
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 解析 `{Referer:host, User-Agent:xxx}` 形式（允许未加引号）。
  static Map<String, String> _parseHeader(String inner) {
    final map = <String, String>{};

    // 优先尝试标准 JSON（补引号后）
    try {
      final fixed = inner.replaceAllMapped(
        RegExp(r'([{,]\s*)([A-Za-z0-9_\-]+)(\s*:)'),
        (m) => '${m[1]}"${m[2]}"${m[3]}',
      );
      final decoded = jsonDecode('{$fixed}');
      if (decoded is Map) {
        decoded.forEach((k, v) => map[k.toString()] = v.toString());
        return map;
      }
    } catch (_) {
      // 忽略，走正则兜底
    }

    for (final m in RegExp(r'([A-Za-z0-9_\-]+)\s*:\s*([^,}]+)').allMatches(inner)) {
      map[m.group(1)!] =
          m.group(2)!.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
    }
    return map;
  }
}

/// 规则中的一个选择器步骤。
class RuleStep {
  final String? cssSelector;
  final String? jsonPath;
  final String? textMatch;
  final int? index;
  final String? xpathAttr;

  const RuleStep({
    this.cssSelector,
    this.jsonPath,
    this.textMatch,
    this.index,
    this.xpathAttr,
  });
}

/// 解析后的规则。
class ParsedRule {
  final List<RuleStep> steps;
  final String? attr;
  final String? jsCode;
  final Map<String, String> headers;
  final String? replaceFrom;
  final String? replaceTo;

  const ParsedRule({
    required this.steps,
    this.attr,
    this.jsCode,
    this.headers = const {},
    this.replaceFrom,
    this.replaceTo,
  });

  bool get isEmpty => steps.isEmpty && (jsCode == null || jsCode!.isEmpty);
}
