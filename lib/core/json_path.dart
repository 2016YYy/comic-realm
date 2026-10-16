/// 迷你 JSONPath 求值器，用于解析图源规则中以 `$` 开头的 JSON 表达式。
///
/// 支持（覆盖异次元 / legado 图源常见写法）：
///   $.items              取键
///   $.[*] / $[*]         取数组或对象的全部值
///   $.a[*].b             链式取值
///   $..id                递归查找某键
///   $..*                 递归取全部
///   $.a.b[0]             数组下标
///   $['a']['b']          方括号键
class JsonPathEngine {
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
            current = _recursiveKey(current, key);
          }
        } else if (hasNext && p[i + 1] == '[') {
          i++; // 跳过点号，交给 '[' 分支处理
        } else {
          i++;
          if (i < p.length && p[i] == '*') {
            i++;
            current = _valuesOf(current);
          } else {
            final key = _readIdent(p, i);
            if (key.isEmpty) {
              i++;
            } else {
              i += key.length;
              current = _pluckKey(current, key);
            }
          }
        }
      } else if (c == '[') {
        final end = p.indexOf(']', i);
        if (end < 0) break;
        final inner = p.substring(i + 1, end).trim();
        i = end + 1;

        if (inner == '*') {
          current = _valuesOf(current);
        } else if (inner.startsWith('?(') && inner.endsWith(')')) {
          // 过滤表达式：[?(@.key)] 保留含指定键的元素
          current = _filterByExpr(current, inner.substring(2, inner.length - 1));
        } else if (inner.startsWith('"') || inner.startsWith("'")) {
          current = _pluckKey(current, inner.substring(1, inner.length - 1));
        } else if (int.tryParse(inner) != null) {
          final idx = int.parse(inner);
          current = current
              .map((e) => (e is List && idx >= 0 && idx < e.length) ? e[idx] : null)
              .where((e) => e != null)
              .toList();
        } else if (inner.isEmpty) {
          // 空下标：忽略
        } else {
          current = _pluckKey(current, inner);
        }
      } else if (c == '*') {
        i++;
        current = _valuesOf(current);
      } else {
        final key = _readIdent(p, i);
        if (key.isEmpty) {
          i++;
        } else {
          i += key.length;
          current = _pluckKey(current, key);
        }
      }
    }
    return current;
  }

  static String _readIdent(String s, int start) {
    final m = RegExp(r'^[A-Za-z0-9_\-\u4e00-\u9fa5]+').firstMatch(s.substring(start));
    return m?.group(0) ?? '';
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

  /// 过滤表达式求值：支持 `@.key`（含该键）和 `@.key == 'value'`。
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
    // 匹配 @.key == 'value' 或 @.key=="value"
    final eqM = RegExp(r"""^@\.([A-Za-z0-9_\-]+)\s*==\s*['"]([^'"]*)['"]$""").firstMatch(e);
    if (eqM != null) {
      final key = eqM.group(1)!;
      final val = eqM.group(2)!;
      return flattened.where((n) {
        if (n is! Map) return false;
        return n[key]?.toString() == val;
      }).toList();
    }
    // 匹配 @.key（含该键且值非空）
    final keyM = RegExp(r'^@\.([A-Za-z0-9_\-]+)$').firstMatch(e);
    if (keyM != null) {
      final key = keyM.group(1)!;
      return flattened.where((n) {
        if (n is! Map) return false;
        final v = n[key];
        return v != null && v.toString().isNotEmpty;
      }).toList();
    }
    // 不支持的表达式，原样返回
    return flattened;
  }

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
}
