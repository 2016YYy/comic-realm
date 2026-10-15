import 'package:flutter_js/flutter_js.dart';

/// 轻量 JS 运行时，用于执行图源规则中的 @js: 解码脚本。
///
/// 兼容 legado / 异次元 的 JS 规则：
///   - 脚本可访问 `result`（当前规则的文本/HTML 结果）、`baseUrl`、`key`、`page`
///   - 既可写 `return xxx;`，也可直接以表达式结尾
///   - 返回值会被 JSON 序列化，便于调用方还原字符串 / 数组 / 对象
class JsRuntime {
  static final JsRuntime _instance = JsRuntime._internal();
  factory JsRuntime() => _instance;
  JsRuntime._internal();

  JavascriptRuntime? _runtime;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _runtime = getJavascriptRuntime();
    _ready = true;
  }

  /// 执行 JS 代码并返回字符串结果。
  Future<String> eval(String code) async {
    if (!_ready) await init();
    final result = _runtime!.evaluate(code);
    return result.stringResult;
  }

  /// 在上下文中设置变量后再执行表达式。
  Future<String> evalWith(String expression, Map<String, String> vars) async {
    if (!_ready) await init();
    final sb = StringBuffer();
    vars.forEach((k, v) {
      sb.writeln('var ${_safeIdent(k)} = ${_jsString(v)};');
    });
    sb.writeln(expression);
    final result = _runtime!.evaluate(sb.toString());
    return result.stringResult;
  }

  /// 执行图源 JS 规则：注入 result/baseUrl/key/page 变量，返回 JSON 字符串。
  ///
  /// 规则脚本被包裹在 IIFE 中，因此 `return` 语句与表达式结尾两种写法都可用。
  Future<String> evalRule(
    String jsCode, {
    String result = '',
    String baseUrl = '',
    String key = '',
    int page = 1,
  }) async {
    if (!_ready) await init();
    final sb = StringBuffer();
    sb.writeln('var result = ${_jsString(result)};');
    sb.writeln('var baseUrl = ${_jsString(baseUrl)};');
    sb.writeln('var key = ${_jsString(key)};');
    sb.writeln('var page = $page;');
    sb.writeln('JSON.stringify((function(){');
    sb.writeln(jsCode);
    sb.writeln('})());');
    final res = _runtime!.evaluate(sb.toString());
    if (res.isError) {
      throw Exception('JS 规则执行失败：${res.stringResult}');
    }
    return res.stringResult;
  }

  /// 包装 JS 字符串字面量，处理引号、换行、Unicode 转义。
  static String _jsString(String v) {
    final escaped = v
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t')
        .replaceAll('\u2028', '\\u2028')
        .replaceAll('\u2029', '\\u2029');
    return '"$escaped"';
  }

  static String _safeIdent(String k) =>
      k.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '_');

  void dispose() {
    _runtime?.dispose();
    _ready = false;
  }
}
