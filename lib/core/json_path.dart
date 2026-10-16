/// 迷你 JSONPath 求值器，用于解析图源规则中以 `$` 开头（或 JSON 响应下不带
/// 前缀）的 JSON 表达式。
///
/// 对齐 legado / 异次元 使用的 Jayway JsonPath 语义，覆盖图源常见写法：
///   $.items / data.items            取键（可不带 `$`）
///   $.[*] / $[*] / $.*              取数组或对象的全部值
///   $.a[*].b / $.a.b[0]             链式取值 / 下标（支持负数）
///   $..id / $..*                    递归查找某键 / 递归取全部
///   $['a']['b'] / $['a','b']        方括号键 / 多键合并
///   $.list[0:2] / [-1:]             数组切片（含负索引）
///   $.list[?(@.k == 'v')]           过滤器（支持 == != > >= < <= =~ 及 && || !）
///   $.list.length() / first() / last()  常用函数
class JsonPathEngine {
  static final RegExp _identRe =
      RegExp(r'[A-Za-z0-9_\-\u4e00-\u9fa5]+');

  /// 查询并返回所有命中的节点（结果可能为空数组）。
  static List<dynamic> query(dynamic root, String path) {
    var p = path.trim();
    if (p.startsWith(r'$')) p = p.substring(1);

    var current = <dynamic>[root];
    var i = 0;

    while (i < p.length && current.isNotEmpty) {
      final c = p[i];

      if (c == '.') {
        final hasNext = i + 1 < p.length;
        if (hasNext && p[i + 1] == '.') {
          // 递归下降 ..
          i += 2;
          if (i < p.length && p[i] == '*') {
            i++;
            current = _recursiveAll(current);
          } else {
            final key = _readIdent(p, i);
            i += key.length;
            if (key.isNotEmpty) current = _recursiveKey(current, key);
          }
          continue;
        }
        if (hasNext && p[i + 1] == '[') {
          i++; // 跳过点号，交给 '[' 分支处理
          continue;
        }
        i++;
        if (i < p.length && p[i] == '*') {
          i++;
          current = _valuesOf(current);
          continue;
        }
        current = _consumeNameOrCall(p, i, current, (next) => i = next);
      } else if (c == '[') {
        final end = _findBracketEnd(p, i);
        if (end < 0) break;
        final inner = p.substring(i + 1, end).trim();
        i = end + 1;
        current = _applyBracket(current, inner);
      } else if (c == '*') {
        i++;
        current = _valuesOf(current);
      } else {
        current = _consumeNameOrCall(p, i, current, (next) => i = next);
      }
    }
    return current;
  }

  /// 读取一个标识符（可能是普通键，也可能是函数调用 `name(args)`）。
  static List<dynamic> _consumeNameOrCall(
    String p,
    int start,
    List<dynamic> current,
    void Function(int) setIndex,
  ) {
    final key = _readIdent(p, start);
    if (key.isEmpty) {
      setIndex(start + 1);
      return current;
    }
    var i = start + key.length;
    if (i < p.length && p[i] == '(') {
      final end = _findParenEnd(p, i);
      final args = end > i ? p.substring(i + 1, end) : '';
      setIndex(end < 0 ? p.length : end + 1);
      return _applyFunction(current, key, args);
    }
    setIndex(i);
    return _pluckKey(current, key);
  }

  static String _readIdent(String s, int start) {
    final m = _identRe.matchAsPrefix(s, start);
    return m?.group(0) ?? '';
  }

  // -------------------- 括号处理 --------------------

  static List<dynamic> _applyBracket(List<dynamic> current, String inner) {
    if (inner.isEmpty) return current;
    if (inner == '*') return _valuesOf(current);

    // 过滤器 ?(...)
    if (inner.startsWith('?(')) {
      var expr = inner.substring(2);
      if (expr.endsWith(')')) expr = expr.substring(0, expr.length - 1);
      return _filterByExpr(current, expr);
    }

    // 引号键：单个或多个 ['a','b']
    if (inner.startsWith("'") || inner.startsWith('"')) {
      final keys = _splitTop(inner, ',');
      if (keys.length == 1) return _pluckKey(current, _unquote(keys.first));
      final out = <dynamic>[];
      for (final k in keys) {
        out.addAll(_pluckKey(current, _unquote(k)));
      }
      return out;
    }

    // 切片 start:end[:step]
    if (inner.contains(':') && !_hasQuote(inner)) {
      return _applySlice(current, inner);
    }

    // 数字下标（含负数）
    final n = int.tryParse(inner);
    if (n != null) return _applyIndexAll(current, n);

    // 裸键
    return _pluckKey(current, inner);
  }

  static List<dynamic> _applyIndexAll(List<dynamic> nodes, int idx) {
    final out = <dynamic>[];
    for (final n in nodes) {
      if (n is List) {
        final real = idx < 0 ? n.length + idx : idx;
        if (real >= 0 && real < n.length) out.add(n[real]);
      } else if (n is String && idx >= 0 && idx < n.length) {
        out.add(n[idx]);
      }
    }
    return out;
  }

  static List<dynamic> _applySlice(List<dynamic> nodes, String inner) {
    final parts = inner.split(':');
    final start =
        parts.isNotEmpty && parts[0].trim().isNotEmpty ? int.tryParse(parts[0].trim()) : null;
    final end =
        parts.length > 1 && parts[1].trim().isNotEmpty ? int.tryParse(parts[1].trim()) : null;
    var step =
        parts.length > 2 && parts[2].trim().isNotEmpty ? int.tryParse(parts[2].trim()) : null;
    if (step == null || step == 0) step = 1;

    final out = <dynamic>[];
    for (final n in nodes) {
      if (n is! List) continue;
      final len = n.length;
      var s = start ?? (step > 0 ? 0 : len - 1);
      var e = end ?? (step > 0 ? len : -1);
      if (s < 0) s += len;
      if (e < 0 && end != null) e += len;
      if (step > 0) {
        if (s < 0) s = 0;
        if (e > len) e = len;
        for (var k = s; k < e; k += step) {
          if (k >= 0 && k < len) out.add(n[k]);
        }
      } else {
        if (s > len - 1) s = len - 1;
        for (var k = s; k > e; k += step) {
          if (k >= 0 && k < len) out.add(n[k]);
        }
      }
    }
    return out;
  }

  static List<dynamic> _applyFunction(
    List<dynamic> nodes,
    String name,
    String args,
  ) {
    switch (name.toLowerCase()) {
      case 'length':
      case 'size':
        return nodes.map((n) {
          if (n is List) return n.length;
          if (n is String) return n.length;
          if (n is Map) return n.length;
          return 0;
        }).toList();
      case 'first':
        return nodes.isEmpty ? const [] : [nodes.first];
      case 'last':
        return nodes.isEmpty ? const [] : [nodes.last];
      default:
        // 未支持的其他函数：原样返回，交给后续步骤 / @js 处理
        return nodes;
    }
  }

  static List<dynamic> _pluckKey(List<dynamic> nodes, String key) {
    final out = <dynamic>[];
    for (final n in nodes) {
      if (n is Map) {
        if (n.containsKey(key)) out.add(n[key]);
      } else if (n is List) {
        for (final e in n) {
          if (e is Map && e.containsKey(key)) out.add(e[key]);
        }
      }
    }
    return out;
  }

  static List<dynamic> _valuesOf(List<dynamic> nodes) {
    final out = <dynamic>[];
    for (final n in nodes) {
      if (n is Map) {
        out.addAll(n.values);
      } else if (n is List) {
        out.addAll(n);
      }
    }
    return out;
  }

  // -------------------- 过滤器 --------------------

  static List<dynamic> _filterByExpr(List<dynamic> nodes, String expr) {
    // 先展平：将嵌套列表展开为元素列表（类似 [*] 的行为）
    final flattened = <dynamic>[];
    for (final n in nodes) {
      if (n is List) {
        flattened.addAll(n);
      } else {
        flattened.add(n);
      }
    }
    final e = expr.trim();
    if (e.isEmpty) return flattened;
    return flattened.where((n) => _evalFilter(n, e)).toList();
  }

  static bool _evalFilter(dynamic node, String expr) {
    var e = expr.trim();
    if (e.isEmpty) return false;

    // 去掉最外层括号
    if (_hasOuterParens(e)) {
      e = e.substring(1, e.length - 1).trim();
    }

    // 逻辑或 ||
    final ors = _splitTop(e, '||');
    if (ors.length > 1) return ors.any((s) => _evalFilter(node, s));

    // 逻辑与 &&
    final ands = _splitTop(e, '&&');
    if (ands.length > 1) return ands.every((s) => _evalFilter(node, s));

    if (e.startsWith('!') && !e.startsWith('!=')) {
      return !_evalFilter(node, e.substring(1));
    }

    final cmp = _findComparison(e);
    if (cmp != null) {
      final l = _operand(node, cmp.$1);
      final r = _operand(node, cmp.$2);
      switch (cmp.$3) {
        case '==':
          return _looseEq(l, r);
        case '!=':
          return !_looseEq(l, r);
        case '>':
          return _num(l) != null && _num(r) != null && _num(l)! > _num(r)!;
        case '>=':
          return _num(l) != null && _num(r) != null && _num(l)! >= _num(r)!;
        case '<':
          return _num(l) != null && _num(r) != null && _num(l)! < _num(r)!;
        case '<=':
          return _num(l) != null && _num(r) != null && _num(l)! <= _num(r)!;
        case '=~':
          return _regex(r).hasMatch(l == null ? '' : l.toString());
      }
    }

    // 存在性判断
    final v = _operand(node, e);
    return v != null && v.toString().isNotEmpty;
  }

  static dynamic _operand(dynamic node, String token) {
    final t = token.trim();
    if (t.startsWith('@')) {
      var path = t.substring(1);
      if (path.startsWith('.')) path = path.substring(1);
      if (path.isEmpty) return node;
      final res = query(node, path);
      return res.isEmpty ? null : res.first;
    }
    if (_isQuoted(t)) return _unquote(t);
    if (t == 'true') return true;
    if (t == 'false') return false;
    if (t == 'null') return null;
    final n = num.tryParse(t);
    if (n != null) return n;
    return t;
  }

  /// 查找顶层比较运算符，返回 (左, 右, 运算符)。
  static (String, String, String)? _findComparison(String e) {
    const ops = ['==', '!=', '>=', '<=', '=~', '>', '<'];
    String? quote;
    var depth = 0;
    for (var i = 0; i < e.length; i++) {
      final c = e[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '\'' || c == '"') {
        quote = c;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth++;
        continue;
      }
      if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) depth--;
        continue;
      }
      if (depth != 0) continue;
      for (final op in ops) {
        if (e.startsWith(op, i)) {
          return (e.substring(0, i).trim(), e.substring(i + op.length).trim(), op);
        }
      }
    }
    return null;
  }

  static bool _looseEq(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    final na = _num(a);
    final nb = _num(b);
    if (na != null && nb != null) return na == nb;
    return a.toString() == b.toString();
  }

  static num? _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  static RegExp _regex(dynamic r) {
    final s = r?.toString() ?? '';
    if (s.length >= 2 && s.startsWith('/') && s.endsWith('/')) {
      try {
        return RegExp(s.substring(1, s.length - 1));
      } catch (_) {}
    }
    try {
      return RegExp(RegExp.escape(s));
    } catch (_) {
      return RegExp(r'$^');
    }
  }

  // -------------------- 递归 --------------------

  static List<dynamic> _recursiveKey(List<dynamic> nodes, String key) {
    final out = <dynamic>[];
    void walk(dynamic n) {
      if (n is Map) {
        n.forEach((k, v) {
          if (k == key) out.add(v);
          walk(v);
        });
      } else if (n is List) {
        for (final e in n) {
          walk(e);
        }
      }
    }

    for (final n in nodes) {
      walk(n);
    }
    return out;
  }

  static List<dynamic> _recursiveAll(List<dynamic> nodes) {
    final out = <dynamic>[];
    void walk(dynamic n) {
      if (n is Map) {
        n.forEach((k, v) {
          out.add(v);
          walk(v);
        });
      } else if (n is List) {
        for (final e in n) {
          out.add(e);
          walk(e);
        }
      }
    }

    for (final n in nodes) {
      walk(n);
    }
    return out;
  }

  // -------------------- 工具 --------------------

  /// 返回与 openIdx 处的 `[` 匹配的 `]` 下标；找不到返回 -1。
  static int _findBracketEnd(String s, int openIdx) {
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
      if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 返回与 openIdx 处的 `(` 匹配的 `)` 下标；找不到返回 -1。
  static int _findParenEnd(String s, int openIdx) {
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
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 按分隔符切分，忽略引号 / 各类括号内部的分隔符。
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
    return out.map((e) => e.trim()).toList();
  }

  static bool _hasOuterParens(String e) {
    if (!(e.startsWith('(') && e.endsWith(')'))) return false;
    var depth = 0;
    String? quote;
    for (var i = 0; i < e.length; i++) {
      final c = e[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '\'' || c == '"') {
        quote = c;
        continue;
      }
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return i == e.length - 1;
      }
    }
    return false;
  }

  static bool _hasQuote(String s) => s.contains("'") || s.contains('"');

  static bool _isQuoted(String t) =>
      t.length >= 2 &&
      ((t.startsWith("'") && t.endsWith("'")) ||
          (t.startsWith('"') && t.endsWith('"')));

  static String _unquote(String t) {
    final s = t.trim();
    if (s.length >= 2 && _isQuoted(s)) return s.substring(1, s.length - 1);
    return s;
  }
}
