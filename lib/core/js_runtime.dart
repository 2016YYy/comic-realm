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
    // 开启 xhr：让 JS 规则里的 java.ajax 等可以通过同步 XMLHttpRequest 发请求，
    // 从而支持 legado / 异次元 中「先取页面再解析」的 Java 扩展脚本。
    _runtime = getJavascriptRuntime(xhr: true);
    // 注入 java / Packages 兼容层（见 _javaShim）。
    try {
      _runtime!.evaluate(_javaShim);
    } catch (_) {
      // 注入失败不阻塞启动；相关规则执行时会给出明确错误
    }
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

  /// legado / 异次元 Java 扩展脚本的轻量兼容层。
  ///
  /// 在 JS 运行时的全局作用域里定义 `java`、`Packages`，覆盖漫画图源里
  /// 最常用的一批 API：同步网络请求（基于 XMLHttpRequest）、Base64 /
  /// Hex 编解码、URL 编解码、时间格式化、日志等。
  /// 需要真正 DOM 解析的 org.jsoup 不在支持范围内（在调用方拦截）。
  static const String _javaShim = r'''
var __cr_b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function __cr_b64decode(str) {
  str = String(str == null ? '' : str).replace(/[^A-Za-z0-9+/=]/g, '');
  var out = '';
  var i = 0;
  while (i < str.length) {
    var e1 = __cr_b64chars.indexOf(str.charAt(i++));
    var e2 = __cr_b64chars.indexOf(str.charAt(i++));
    var e3 = __cr_b64chars.indexOf(str.charAt(i++));
    var e4 = __cr_b64chars.indexOf(str.charAt(i++));
    if (e2 < 0) break;
    out += String.fromCharCode((e1 << 2) | (e2 >> 4));
    if (e3 >= 0 && __cr_b64chars.charAt(e3) !== '=') out += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2));
    if (e4 >= 0 && __cr_b64chars.charAt(e4) !== '=') out += String.fromCharCode(((e3 & 3) << 6) | e4);
  }
  return out;
}
function __cr_b64encode(str) {
  str = String(str == null ? '' : str);
  var out = '';
  for (var i = 0; i < str.length; i += 3) {
    var c1 = str.charCodeAt(i) & 255;
    var c2 = i + 1 < str.length ? (str.charCodeAt(i + 1) & 255) : NaN;
    var c3 = i + 2 < str.length ? (str.charCodeAt(i + 2) & 255) : NaN;
    var e1 = c1 >> 2;
    var e2 = ((c1 & 3) << 4) | (isNaN(c2) ? 0 : (c2 >> 4));
    var e3 = isNaN(c2) ? NaN : (((c2 & 15) << 2) | (isNaN(c3) ? 0 : (c3 >> 6)));
    var e4 = isNaN(c3) ? NaN : (c3 & 63);
    out += __cr_b64chars.charAt(e1);
    out += isNaN(e2) ? '=' : __cr_b64chars.charAt(e2);
    out += isNaN(e3) ? '=' : __cr_b64chars.charAt(e3);
    out += isNaN(e4) ? '=' : __cr_b64chars.charAt(e4);
  }
  return out;
}
function __cr_hexDecode(str) {
  str = String(str == null ? '' : str);
  var out = '';
  for (var i = 0; i + 1 < str.length; i += 2) {
    out += String.fromCharCode(parseInt(str.substr(i, 2), 16));
  }
  return out;
}
function __cr_hexEncode(str) {
  str = String(str == null ? '' : str);
  var out = '';
  for (var i = 0; i < str.length; i++) {
    var h = str.charCodeAt(i).toString(16);
    out += h.length === 1 ? '0' + h : h;
  }
  return out;
}
function __cr_xhr(method, url, body, headers) {
  try {
    var x = new XMLHttpRequest();
    x.open(method, String(url), false);
    try {
      x.setRequestHeader('User-Agent', 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36');
    } catch (e) {}
    if (headers) {
      for (var k in headers) {
        try { x.setRequestHeader(k, headers[k]); } catch (e) {}
      }
    }
    x.send(body == null ? null : body);
    return x.responseText == null ? '' : String(x.responseText);
  } catch (e) {
    return '';
  }
}
var java = {
  ajax: function(url) { return __cr_xhr('GET', url, null, null); },
  get: function(url, headers) { return __cr_xhr('GET', url, null, headers); },
  post: function(url, body, headers) { return __cr_xhr('POST', url, body, headers); },
  ajaxAll: function(urls) {
    var r = [];
    if (urls) { for (var i = 0; i < urls.length; i++) r.push(__cr_xhr('GET', urls[i], null, null)); }
    return r;
  },
  connect: function(u) {
    return {
      url: u,
      header: function() { return this; },
      get: function() { return __cr_xhr('GET', this.url, null, null); },
      post: function(b) { return __cr_xhr('POST', this.url, b, null); },
      getResponse: function() { return this; },
      body: function() { return this; },
      string: function() { return __cr_xhr('GET', this.url, null, null); }
    };
  },
  base64Decode: function(s) { return __cr_b64decode(s); },
  base64Encode: function(s) { return __cr_b64encode(s); },
  base64DecodeToString: function(s) { return __cr_b64decode(s); },
  hexDecode: function(s) { return __cr_hexDecode(s); },
  hexDecodeToString: function(s) { return __cr_hexDecode(s); },
  hexEncodeToString: function(s) { return __cr_hexEncode(s); },
  encodeURI: function(s) { try { return encodeURIComponent(String(s)); } catch (e) { return String(s); } },
  urlEncode: function(s) { try { return encodeURIComponent(String(s)); } catch (e) { return String(s); } },
  urlDecode: function(s) { try { return decodeURIComponent(String(s)); } catch (e) { return String(s); } },
  timeFormat: function(t) {
    try {
      var d = new Date(typeof t === 'number' ? t : Date.now());
      function p(n) { return ('0' + n).slice(-2); }
      return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
    } catch (e) { return String(t); }
  },
  log: function() {
    try { if (typeof console !== 'undefined' && console.log) { console.log.apply(console, arguments); } } catch (e) {}
  },
  toast: function() {},
  getString: function() {
    try { return String(typeof result === 'undefined' || result == null ? '' : result); } catch (e) { return ''; }
  },
  setContent: function() {
    return {
      select: function() { return { text: function() { return ''; }, html: function() { return ''; } }; },
      text: function() { return ''; },
      html: function() { return ''; }
    };
  }
};
var Packages = { java: java, org: {} };
var org = Packages.org;
''';

  void dispose() {
    _runtime?.dispose();
    _ready = false;
  }
}
