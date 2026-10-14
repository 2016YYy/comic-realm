import 'package:flutter_js/flutter_js.dart';

/// 轻量 JS 运行时，用于执行图源规则中的 @js: 解码脚本。
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
      final escaped = v.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n');
      sb.writeln("var $k = '$escaped';");
    });
    sb.writeln(expression);
    final result = _runtime!.evaluate(sb.toString());
    return result.stringResult;
  }

  void dispose() {
    _runtime?.dispose();
    _ready = false;
  }
}
