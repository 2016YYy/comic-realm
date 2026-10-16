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
  /// 规则脚本被包裹在 IIFE 中，因此 `return` 语句与表达式结尾两种写法都可用：
  /// 先按「带 return 的语句块」执行，若结果为 `undefined`（说明脚本本身是
  /// 一个表达式而非语句块），再按「表达式求值」重试一次。
  Future<String> evalRule(
    String jsCode, {
    String result = '',
    String baseUrl = '',
    String key = '',
    int page = 1,
  }) async {
    if (!_ready) await init();
    final vars = StringBuffer()
      ..writeln('var result = ${_jsString(result)};')
      ..writeln('var baseUrl = ${_jsString(baseUrl)};')
      ..writeln('var key = ${_jsString(key)};')
      ..writeln('var page = $page;');

    // 形式一：语句块，脚本内部自行 return
    final blockScript =
        '${vars.toString()}JSON.stringify((function(){\n$jsCode\n})());';
    final blockRes = _runtime!.evaluate(blockScript);
    if (!blockRes.isError) {
      final s = blockRes.stringResult;
      if (s != 'undefined' && s.isNotEmpty) return s;
    }

    // 形式二：纯表达式（如 `result.split('|')[0]`）
    final exprScript =
        '${vars.toString()}JSON.stringify((function(){ return (\n$jsCode\n); })());';
    final exprRes = _runtime!.evaluate(exprScript);
    if (!exprRes.isError) return exprRes.stringResult;

    // 两种形式都失败：抛出语句块形式的错误信息
    if (blockRes.isError) {
      throw Exception('JS 规则执行失败：${blockRes.stringResult}');
    }
    throw Exception('JS 规则执行失败：${exprRes.stringResult}');
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

// ===================== MD5 (RFC 1321) =====================
function __CrMd5Cycle(x, k){
  x[k] &= 0xffffffff;
}
function __CrMd5FF(a,b,c,d,x,s,ac){
  a = (a + ((b & c) | ((~b) & d)) + x + ac) & 0xffffffff;
  return ((a << s) | (a >>> (32-s))) + b & 0xffffffff;
}
function __CrMd5GG(a,b,c,d,x,s,ac){
  a = (a + ((b & d) | (c & (~d))) + x + ac) & 0xffffffff;
  return ((a << s) | (a >>> (32-s))) + b & 0xffffffff;
}
function __CrMd5HH(a,b,c,d,x,s,ac){
  a = (a + (b ^ c ^ d) + x + ac) & 0xffffffff;
  return ((a << s) | (a >>> (32-s))) + b & 0xffffffff;
}
function __CrMd5II(a,b,c,d,x,s,ac){
  a = (a + (c ^ (b | (~d))) + x + ac) & 0xffffffff;
  return ((a << s) | (a >>> (32-s))) + b & 0xffffffff;
}
function __CrMd5(str){
  str = String(str == null ? '' : str);
  // UTF-8 encode
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) { bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f)); }
    else if (c < 0xd800 || c >= 0xe000) { bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f)); }
    else { i++; c = 0x10000 + (((c & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff)); bytes.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f)); }
  }
  var len = bytes.length;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (var b = 0; b < 8; b++) bytes.push((len * 8 >>> (b * 8)) & 0xff);
  var a = 1732584193, b0 = -271733879, c = -1732584194, d = 271733878;
  for (var p = 0; p < bytes.length; p += 64) {
    var x = [];
    for (var j = 0; j < 16; j++) x[j] = bytes[p + j*4] | (bytes[p + j*4+1] << 8) | (bytes[p + j*4+2] << 16) | (bytes[p + j*4+3] << 24);
    var aa = a, bb = b0, cc = c, dd = d;
    a=__CrMd5FF(a,b0,c,d,x[0],7,-680876936); d=__CrMd5FF(d,a,b0,c,x[1],12,-389564586); c=__CrMd5FF(c,d,a,b0,x[2],17,606105819); b0=__CrMd5FF(b0,c,d,a,x[3],22,-1044525330);
    a=__CrMd5FF(a,b0,c,d,x[4],7,-176418897); d=__CrMd5FF(d,a,b0,c,x[5],12,1200080426); c=__CrMd5FF(c,d,a,b0,x[6],17,-1473231341); b0=__CrMd5FF(b0,c,d,a,x[7],22,-45705983);
    a=__CrMd5FF(a,b0,c,d,x[8],7,1770035416); d=__CrMd5FF(d,a,b0,c,x[9],12,-1958414417); c=__CrMd5FF(c,d,a,b0,x[10],17,-42063); b0=__CrMd5FF(b0,c,d,a,x[11],22,-1990404162);
    a=__CrMd5FF(a,b0,c,d,x[12],7,1804603682); d=__CrMd5FF(d,a,b0,c,x[13],12,-40341101); c=__CrMd5FF(c,d,a,b0,x[14],17,-1502002290); b0=__CrMd5FF(b0,c,d,a,x[15],22,1236535329);
    a=__CrMd5GG(a,b0,c,d,x[1],5,-165796510); d=__CrMd5GG(d,a,b0,c,x[6],9,-1069501632); c=__CrMd5GG(c,d,a,b0,x[11],14,643717713); b0=__CrMd5GG(b0,c,d,a,x[0],20,-373897302);
    a=__CrMd5GG(a,b0,c,d,x[5],5,-701558691); d=__CrMd5GG(d,a,b0,c,x[10],9,38016083); c=__CrMd5GG(c,d,a,b0,x[15],14,-660478335); b0=__CrMd5GG(b0,c,d,a,x[4],20,-405537848);
    a=__CrMd5GG(a,b0,c,d,x[9],5,568446438); d=__CrMd5GG(d,a,b0,c,x[14],9,-1019803690); c=__CrMd5GG(c,d,a,b0,x[3],14,-187363961); b0=__CrMd5GG(b0,c,d,a,x[8],20,1163531501);
    a=__CrMd5GG(a,b0,c,d,x[13],5,-1444681467); d=__CrMd5GG(d,a,b0,c,x[2],9,-51403784); c=__CrMd5GG(c,d,a,b0,x[7],14,1735328473); b0=__CrMd5GG(b0,c,d,a,x[12],20,-1926607734);
    a=__CrMd5HH(a,b0,c,d,x[5],4,-378558); d=__CrMd5HH(d,a,b0,c,x[8],11,-2022574463); c=__CrMd5HH(c,d,a,b0,x[11],16,1839030562); b0=__CrMd5HH(b0,c,d,a,x[14],23,-35309556);
    a=__CrMd5HH(a,b0,c,d,x[1],4,-1530992060); d=__CrMd5HH(d,a,b0,c,x[4],11,1272893353); c=__CrMd5HH(c,d,a,b0,x[7],16,-155497632); b0=__CrMd5HH(b0,c,d,a,x[10],23,-1094730640);
    a=__CrMd5HH(a,b0,c,d,x[13],4,681279174); d=__CrMd5HH(d,a,b0,c,x[0],11,-358537222); c=__CrMd5HH(c,d,a,b0,x[3],16,-722521979); b0=__CrMd5HH(b0,c,d,a,x[6],23,76029189);
    a=__CrMd5HH(a,b0,c,d,x[9],4,-640364487); d=__CrMd5HH(d,a,b0,c,x[12],11,-421815835); c=__CrMd5HH(c,d,a,b0,x[15],16,530742520); b0=__CrMd5HH(b0,c,d,a,x[2],23,-995338651);
    a=__CrMd5II(a,b0,c,d,x[0],6,-198630844); d=__CrMd5II(d,a,b0,c,x[7],10,1126891415); c=__CrMd5II(c,d,a,b0,x[14],15,-1416354905); b0=__CrMd5II(b0,c,d,a,x[5],21,-57434055);
    a=__CrMd5II(a,b0,c,d,x[12],6,1700485571); d=__CrMd5II(d,a,b0,c,x[3],10,-1894986606); c=__CrMd5II(c,d,a,b0,x[10],15,-1051523); b0=__CrMd5II(b0,c,d,a,x[1],21,-2054922799);
    a=__CrMd5II(a,b0,c,d,x[8],6,1873313359); d=__CrMd5II(d,a,b0,c,x[15],10,-30611744); c=__CrMd5II(c,d,a,b0,x[6],15,-1560198380); b0=__CrMd5II(b0,c,d,a,x[13],21,1309151649);
    a=__CrMd5II(a,b0,c,d,x[4],6,-145523070); d=__CrMd5II(d,a,b0,c,x[11],10,-1120210379); c=__CrMd5II(c,d,a,b0,x[2],15,718787259); b0=__CrMd5II(b0,c,d,a,x[9],21,-343485551);
    a = (a + aa) & 0xffffffff; b0 = (b0 + bb) & 0xffffffff; c = (c + cc) & 0xffffffff; d = (d + dd) & 0xffffffff;
  }
  function h(n){ var s=''; for(var i=0;i<4;i++){ s += ('0'+((n>>>(i*8))&0xff).toString(16)).slice(-2); } return s; }
  return h(a)+h(b0)+h(c)+h(d);
}
java.md5 = function(s){ return __CrMd5(s); };
java.md5Encode = function(s){ return __CrMd5(s); };

// ===================== 简易 HTML 解析器 + CSS 选择器（org.jsoup 兼容层） =====================
var __CR_VOID_TAGS = {area:1,base:1,br:1,col:1,embed:1,hr:1,img:1,input:1,link:1,meta:1,param:1,source:1,track:1,wbr:1};
function __CrHtmlParse(html){
  html = String(html == null ? '' : html);
  var root = {tag:'#root', attrs:{}, children:[], text:''};
  var stack = [root];
  var i = 0, n = html.length;
  while (i < n) {
    if (html[i] === '<') {
      if (html.substr(i,4) === '<!--') {
        var ce = html.indexOf('-->', i+4);
        i = ce < 0 ? n : ce + 3;
        continue;
      }
      if (html[i+1] === '!' || html[i+1] === '?') {
        var ge = html.indexOf('>', i);
        i = ge < 0 ? n : ge + 1;
        continue;
      }
      if (html[i+1] === '/') {
        var cend = html.indexOf('>', i);
        if (cend < 0) break;
        var ctag = html.substring(i+2, cend).trim().toLowerCase();
        for (var s = stack.length-1; s > 0; s--) {
          if (stack[s].tag === ctag) { stack.length = s; break; }
        }
        i = cend + 1;
        continue;
      }
      var tend = html.indexOf('>', i);
      if (tend < 0) break;
      var tInner = html.substring(i+1, tend);
      var selfClose = tInner.endsWith('/');
      if (selfClose) tInner = tInner.slice(0, -1);
      var tm = tInner.match(/^([a-zA-Z][\w:-]*)/);
      if (!tm) { i = tend + 1; continue; }
      var tag = tm[1].toLowerCase();
      var attrStr = tInner.substring(tm[0].length);
      var attrs = {};
      var are = /([a-zA-Z_:][\w:.-]*)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s]+))?/g;
      var am;
      while ((am = are.exec(attrStr)) !== null) {
        var k = am[1].toLowerCase();
        var v = am[2] || '';
        if (v.length >= 2 && (v.charAt(0)==='"'||v.charAt(0)==="'")) v = v.slice(1, -1);
        attrs[k] = v;
      }
      var node = {tag:tag, attrs:attrs, children:[], text:'', parent:stack[stack.length-1]};
      stack[stack.length-1].children.push(node);
      if (!__CR_VOID_TAGS[tag] && !selfClose) stack.push(node);
      i = tend + 1;
    } else {
      var nx = html.indexOf('<', i);
      if (nx < 0) nx = n;
      var txt = html.substring(i, nx);
      if (txt.trim().length) {
        var top = stack[stack.length-1];
        top.children.push({tag:'#text', text:txt, children:[], attrs:{}, parent:top});
      }
      i = nx;
    }
  }
  return root;
}
function __CrNodeText(node){
  if (!node) return '';
  if (node.tag === '#text') return node.text;
  var out = '';
  for (var i=0;i<node.children.length;i++) out += __CrNodeText(node.children[i]);
  return out;
}
function __CrNodeHtml(node){
  if (!node) return '';
  if (node.tag === '#text') return node.text;
  var out = '<' + node.tag;
  for (var k in node.attrs) { if (node.attrs.hasOwnProperty(k)) out += ' ' + k + '="' + node.attrs[k] + '"'; }
  out += '>';
  for (var i=0;i<node.children.length;i++) out += __CrNodeHtml(node.children[i]);
  if (!__CR_VOID_TAGS[node.tag]) out += '</' + node.tag + '>';
  return out;
}
function __CrParseSimpleSel(str){
  // 解析单个 compound selector：tag.class#id[attr]:pseudo
  var m;
  var tag = null, id = null, classes = [], attrs = [], pseudos = [];
  var re = /([#.]?[\w-]+)|\[([^\]]+)\]|:([\w-]+)(?:\(([^)]*)\))?/g;
  while ((m = re.exec(str)) !== null) {
    if (m[1]) {
      if (m[1].charAt(0) === '#') id = m[1].substring(1);
      else if (m[1].charAt(0) === '.') classes.push(m[1].substring(1));
      else tag = m[1].toLowerCase();
    } else if (m[2]) {
      attrs.push(m[2]);
    } else if (m[3]) {
      pseudos.push({name:m[3].toLowerCase(), arg:m[4]});
    }
  }
  return {tag:tag, id:id, classes:classes, attrs:attrs, pseudos:pseudos};
}
function __CrMatchAttr(node, attrExpr){
  var m = attrExpr.match(/^([\w-]+)\s*(?:([*^$~|!]?=)\s*(["']?)([^"']*)\3)?$/);
  if (!m) return false;
  var key = m[1].toLowerCase();
  var val = node.attrs[key];
  if (val == null) {
    // try case-insensitive lookup
    for (var k in node.attrs) { if (k.toLowerCase() === key) { val = node.attrs[k]; break; } }
  }
  if (!m[2]) return val != null;
  var op = m[2], expected = m[4];
  if (val == null) return false;
  switch (op) {
    case '=': return val === expected;
    case '*=': return val.indexOf(expected) >= 0;
    case '^=': return val.indexOf(expected) === 0;
    case '$=': return val.lastIndexOf(expected) === val.length - expected.length;
    case '~=': return val.split(/\s+/).indexOf(expected) >= 0;
    case '|=': return val === expected || val.indexOf(expected + '-') === 0;
    case '!=': return val !== expected;
  }
  return false;
}
function __CrIndexAmongSiblings(node){
  if (!node.parent) return 0;
  var idx = 0;
  for (var i=0;i<node.parent.children.length;i++){
    var c = node.parent.children[i];
    if (c.tag === '#text') continue;
    if (c === node) return idx;
    idx++;
  }
  return -1;
}
function __CrMatchPseudo(node, pseudo){
  switch (pseudo.name) {
    case 'first-child': return __CrIndexAmongSiblings(node) === 0;
    case 'last-child':
      var sibs = node.parent ? node.parent.children.filter(function(c){return c.tag !== '#text';}) : [];
      return sibs.length > 0 && sibs[sibs.length-1] === node;
    case 'nth-child':
      var arg = pseudo.arg || '1';
      if (arg === 'odd') return (__CrIndexAmongSiblings(node)+1) % 2 === 1;
      if (arg === 'even') return (__CrIndexAmongSiblings(node)+1) % 2 === 0;
      var nm = arg.match(/^(\d+)$/);
      if (nm) return __CrIndexAmongSiblings(node) + 1 === parseInt(nm[1],10);
      var em = arg.match(/^(\d*)n([+-]\d+)?$/);
      if (em) {
        var step = em[1] === '' ? 1 : parseInt(em[1],10);
        var off = em[2] ? parseInt(em[2],10) : 0;
        var pos = __CrIndexAmongSiblings(node)+1;
        return step === 0 ? pos === off : (pos - off) % step === 0 && (pos - off) / step >= 0;
      }
      return true;
    case 'first': return true; // handled at collection level
    case 'last': return true;
    case 'eq': case 'gt': case 'lt': return true; // index-based, handled at collection
    case 'contains': return __CrNodeText(node).indexOf(pseudo.arg || '') >= 0;
    case 'has': return true; // simplified
    case 'not': return true; // simplified
  }
  return true;
}
function __CrMatchesCompound(node, comp){
  if (node.tag === '#text' || node.tag === '#root') return false;
  if (comp.tag && node.tag !== comp.tag) return false;
  if (comp.id && node.attrs['id'] !== comp.id) return false;
  for (var i=0;i<comp.classes.length;i++){
    var cls = node.attrs['class'] || '';
    if (cls.split(/\s+/).indexOf(comp.classes[i]) < 0) return false;
  }
  for (var j=0;j<comp.attrs.length;j++){
    if (!__CrMatchAttr(node, comp.attrs[j])) return false;
  }
  for (var k=0;k<comp.pseudos.length;k++){
    if (!__CrMatchPseudo(node, comp.pseudos[k])) return false;
  }
  return true;
}
function __CrDescendants(root, out){
  for (var i=0;i<root.children.length;i++){
    var c = root.children[i];
    if (c.tag !== '#text' && c.tag !== '#root') out.push(c);
    __CrDescendants(c, out);
  }
}
function __CrSelectGroup(root, group){
  // group: [{comp, combinator}, ...]  combinator: 'desc' | 'child' | 'adj' | 'sib'
  if (group.length === 0) return [];
  var candidates = [];
  __CrDescendants(root, candidates);
  // 从右向左匹配
  var last = group[group.length-1];
  var matched = candidates.filter(function(n){ return __CrMatchesCompound(n, last.comp); });
  // 处理 :first/:last/:eq/:gt/:lt（基于最后一个 compound）
  var indexPseudos = last.comp.pseudos.filter(function(p){ return ['first','last','eq','gt','lt'].indexOf(p.name)>=0; });
  if (indexPseudos.length) {
    for (var ip=0; ip<indexPseudos.length; ip++){
      var p = indexPseudos[ip];
      if (p.name === 'first') matched = matched.slice(0,1);
      else if (p.name === 'last') matched = matched.slice(-1);
      else if (p.name === 'eq') { var ei = parseInt(p.arg||'0',10); matched = (ei>=0&&ei<matched.length)?[matched[ei]]:[]; }
      else if (p.name === 'gt') { var gi = parseInt(p.arg||'0',10); matched = matched.slice(gi+1); }
      else if (p.name === 'lt') { var li = parseInt(p.arg||'0',10); matched = matched.slice(0,li); }
    }
  }
  if (group.length === 1) return matched;
  // 向左验证祖先/兄弟关系
  var result = [];
  for (var mi=0; mi<matched.length; mi++){
    var node = matched[mi];
    var ok = true;
    for (var gi = group.length-2; gi >= 0; gi--){
      var combinator = group[gi+1].combinator;
      var need = group[gi].comp;
      var found = false;
      if (combinator === 'desc') {
        var anc = node.parent;
        while (anc) { if (__CrMatchesCompound(anc, need)) { found = true; break; } anc = anc.parent; }
      } else if (combinator === 'child') {
        if (node.parent && __CrMatchesCompound(node.parent, need)) found = true;
      } else if (combinator === 'adj') {
        var sibs = node.parent ? node.parent.children : [];
        var idx = sibs.indexOf(node);
        for (var si = idx-1; si >= 0; si--){ if (sibs[si].tag !== '#text') { if (__CrMatchesCompound(sibs[si], need)) found = true; break; } }
      } else if (combinator === 'sib') {
        var psibs = node.parent ? node.parent.children : [];
        var pidx = psibs.indexOf(node);
        for (var psi = 0; psi < pidx; psi++){ if (psibs[psi].tag !== '#text' && __CrMatchesCompound(psibs[psi], need)) { found = true; break; } }
      }
      if (!found) { ok = false; break; }
      node = node.parent; // 继续向左
    }
    if (ok) result.push(matched[mi]);
  }
  return result;
}
function __CrCssSelect(root, selector){
  if (!selector) return [];
  var groups = String(selector).split(',');
  var all = [];
  for (var g=0; g<groups.length; g++){
    var sel = groups[g].trim();
    if (!sel) continue;
    var compounds = [];
    var buf = '';
    var i = 0;
    while (i < sel.length) {
      var c = sel[i];
      if (c === '>' || c === '+' || c === '~') {
        if (buf.trim()) compounds.push(__CrParseSimpleSel(buf.trim()));
        buf = '';
        var comb = c === '>' ? 'child' : (c === '+' ? 'adj' : 'sib');
        i++;
        while (i < sel.length && sel[i] === ' ') i++;
        var next = '';
        while (i < sel.length && sel[i] !== '>' && sel[i] !== '+' && sel[i] !== '~' && sel[i] !== ' ') {
          next += sel[i]; i++;
        }
        if (next) {
          var comp = __CrParseSimpleSel(next);
          comp._combinator = comb;
          compounds.push(comp);
        }
        continue;
      }
      if (c === ' ') {
        if (buf.trim()) {
          compounds.push(__CrParseSimpleSel(buf.trim()));
          buf = '';
        }
        i++;
        continue;
      }
      buf += c;
      i++;
    }
    if (buf.trim()) compounds.push(__CrParseSimpleSel(buf.trim()));
    if (compounds.length === 0) continue;
    var group = [];
    for (var ci=0; ci<compounds.length; ci++){
      var cp = compounds[ci];
      group.push({comp: cp, combinator: cp._combinator || 'desc'});
    }
    all = all.concat(__CrSelectGroup(root, group));
  }
  var seen = {};
  return all.filter(function(n){
    if (n.__cr_id && seen[n.__cr_id]) return false;
    n.__cr_id = n.__cr_id || Math.random().toString(36);
    seen[n.__cr_id] = true;
    return true;
  });
}

// org.jsoup 兼容对象
function __CrJsoupElements(nodes){
  this.nodes = nodes || [];
  this.length = this.nodes.length;
}
__CrJsoupElements.prototype.get = function(i){ return this.nodes[i]; };
__CrJsoupElements.prototype.eq = function(i){ return new __CrJsoupElements(this.nodes.slice(i, i+1)); };
__CrJsoupElements.prototype.first = function(){ return new __CrJsoupElements(this.nodes.slice(0,1)); };
__CrJsoupElements.prototype.last = function(){ return new __CrJsoupElements(this.nodes.slice(-1)); };
__CrJsoupElements.prototype.size = function(){ return this.nodes.length; };
__CrJsoupElements.prototype.each = function(fn){ for (var i=0;i<this.nodes.length;i++) fn(i, this.nodes[i]); return this; };
__CrJsoupElements.prototype.forEach = function(fn){ for (var i=0;i<this.nodes.length;i++) fn(this.nodes[i], i); return this; };
__CrJsoupElements.prototype.attr = function(a){ return this.nodes.length ? (this.nodes[0].attrs[a] || '') : ''; };
__CrJsoupElements.prototype.text = function(){ return this.nodes.map(__CrNodeText).join(''); };
__CrJsoupElements.prototype.html = function(){ return this.nodes.map(__CrNodeHtml).join(''); };
__CrJsoupElements.prototype.select = function(css){
  var out = [];
  for (var i=0;i<this.nodes.length;i++) out = out.concat(__CrCssSelect(this.nodes[i], css));
  return new __CrJsoupElements(out);
};
__CrJsoupElements.prototype.toArray = function(){ return this.nodes.slice(); };
function __CrJsoupDoc(html, url){
  this.root = __CrHtmlParse(html);
  this.url = url || '';
}
__CrJsoupDoc.prototype.select = function(css){ return new __CrJsoupElements(__CrCssSelect(this.root, css)); };
__CrJsoupDoc.prototype.text = function(){ return __CrNodeText(this.root); };
__CrJsoupDoc.prototype.html = function(){ return __CrNodeHtml(this.root); };
__CrJsoupDoc.prototype.body = function(){ return new __CrJsoupElements(this.root.children.filter(function(c){return c.tag==='body';})); };
__CrJsoupDoc.prototype.head = function(){ return new __CrJsoupElements(this.root.children.filter(function(c){return c.tag==='head';})); };
org.jsoup = {
  Jsoup: {
    connect: function(url){
      return {
        _url: url,
        get: function(){ var html = java.ajax(this._url); return new __CrJsoupDoc(html, this._url); },
        post: function(){ var html = java.post ? java.post(this._url) : java.ajax(this._url); return new __CrJsoupDoc(html, this._url); },
        userAgent: function(ua){ java._ua = ua; return this; },
        header: function(k, v){ return this; },
        timeout: function(){ return this; }
      };
    },
    parse: function(html, baseUrl){ return new __CrJsoupDoc(html, baseUrl || ''); }
  },
  nodes: { Element: {} }
};
Packages.org = org;
''';

  void dispose() {
    _runtime?.dispose();
    _ready = false;
  }
}
