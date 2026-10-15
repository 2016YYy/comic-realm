import 'dart:convert';

import 'package:hive/hive.dart';

part 'source.g.dart';

/// 漫画图源规则，兼容 开源阅读(legado) / 异次元 的图源 JSON 格式。
@HiveType(typeId: 0)
class ComicSource extends HiveObject {
  @HiveField(0)
  String bookSourceUrl;

  @HiveField(1)
  String bookSourceName;

  @HiveField(2)
  String bookSourceGroup;

  @HiveField(3)
  String bookSourceType;

  @HiveField(4)
  String httpUserAgent;

  @HiveField(5)
  String ruleSearchUrl;

  @HiveField(6)
  String ruleSearchList;

  @HiveField(7)
  String ruleSearchName;

  @HiveField(8)
  String ruleSearchAuthor;

  @HiveField(9)
  String ruleSearchCoverUrl;

  @HiveField(10)
  String ruleSearchNoteUrl;

  @HiveField(11)
  String ruleBookName;

  @HiveField(12)
  String ruleCoverUrl;

  @HiveField(13)
  String ruleBookAuthor;

  @HiveField(14)
  String ruleBookKind;

  @HiveField(15)
  String ruleIntroduce;

  @HiveField(16)
  String ruleChapterList;

  @HiveField(17)
  String ruleChapterName;

  @HiveField(18)
  String ruleContentUrl;

  @HiveField(24)
  String ruleChapterUrl;

  @HiveField(19)
  String ruleBookContent;

  @HiveField(20)
  String ruleFindUrl;

  @HiveField(21)
  bool enable;

  @HiveField(22)
  String sourceRemark;

  @HiveField(23)
  int weight;

  ComicSource({
    this.bookSourceUrl = '',
    this.bookSourceName = '',
    this.bookSourceGroup = '',
    this.bookSourceType = '漫画',
    this.httpUserAgent = '',
    this.ruleSearchUrl = '',
    this.ruleSearchList = '',
    this.ruleSearchName = '',
    this.ruleSearchAuthor = '',
    this.ruleSearchCoverUrl = '',
    this.ruleSearchNoteUrl = '',
    this.ruleBookName = '',
    this.ruleCoverUrl = '',
    this.ruleBookAuthor = '',
    this.ruleBookKind = '',
    this.ruleIntroduce = '',
    this.ruleChapterList = '',
    this.ruleChapterName = '',
    this.ruleContentUrl = '',
    this.ruleChapterUrl = '',
    this.ruleBookContent = '',
    this.ruleFindUrl = '',
    this.enable = true,
    this.sourceRemark = '',
    this.weight = 0,
  });

  factory ComicSource.fromJson(Map<String, dynamic> json) {
    // 兼容 legado（开源阅读）的嵌套规则对象
    final rSearch = _asMap(json['ruleSearch']);
    final rInfo = _asMap(json['ruleBookInfo']);
    final rToc = _asMap(json['ruleToc']);
    final rContent = _asMap(json['ruleContent']);

    String pick(List<dynamic> candidates) {
      for (final c in candidates) {
        final s = _str(c);
        if (s.isNotEmpty) return s;
      }
      return '';
    }

    return ComicSource(
      bookSourceUrl: _str(json['bookSourceUrl']),
      bookSourceName: _str(json['bookSourceName']),
      bookSourceGroup: _str(json['bookSourceGroup']),
      bookSourceType: pick([json['bookSourceType'], '漫画']),
      httpUserAgent: _str(json['httpUserAgent']),
      ruleSearchUrl: pick([json['ruleSearchUrl'], json['searchUrl']]),
      ruleSearchList: pick([json['ruleSearchList'], rSearch['bookList']]),
      ruleSearchName: pick([json['ruleSearchName'], rSearch['name']]),
      ruleSearchAuthor: pick([json['ruleSearchAuthor'], rSearch['author']]),
      ruleSearchCoverUrl: pick([json['ruleSearchCoverUrl'], rSearch['coverUrl']]),
      ruleSearchNoteUrl: pick([json['ruleSearchNoteUrl'], rSearch['bookUrl']]),
      ruleBookName: pick([json['ruleBookName'], rInfo['name']]),
      ruleCoverUrl: pick([json['ruleCoverUrl'], rInfo['coverUrl']]),
      ruleBookAuthor: pick([json['ruleBookAuthor'], rInfo['author']]),
      ruleBookKind: pick([json['ruleBookKind'], rInfo['kind']]),
      ruleIntroduce: pick([json['ruleIntroduce'], rInfo['intro']]),
      ruleChapterList: pick([json['ruleChapterList'], rToc['chapterList']]),
      ruleChapterName: pick([json['ruleChapterName'], rToc['chapterName']]),
      ruleContentUrl: pick([json['ruleContentUrl'], rToc['chapterUrl']]),
      ruleChapterUrl: _str(json['ruleChapterUrl']),
      ruleBookContent: pick([json['ruleBookContent'], rContent['content']]),
      ruleFindUrl: _parseFindUrl(json),
      enable: json['enable'] is bool ? json['enable'] as bool : true,
      sourceRemark: _str(json['sourceRemark']),
      weight: json['weight'] is int
          ? json['weight'] as int
          : int.tryParse(_str(json['weight'])) ?? 0,
    );
  }

  /// 解析规则字段：支持原生 Map 以及 legado 字符串字典字面量
  /// （如 `{'author': '...', 'bookList': '...'}`，使用单引号）。
  /// 解析发现页规则：兼容 app 原生「标题::url」多行格式与 legado `exploreUrl`
  /// （JSON 数组字符串 `[{"title":"...","url":"..."}]`）。
  static String _parseFindUrl(Map<String, dynamic> json) {
    final direct = _str(json['ruleFindUrl']);
    if (direct.isNotEmpty) return direct;

    final explore = _str(json['exploreUrl']);
    if (explore.isEmpty) return '';

    try {
      // legado exploreUrl 可能使用单引号字典数组
      final normalized = explore
          .replaceAllMapped(
              RegExp(r"'((?:\\.|[^'\\])*)'"), (m) => '"${m.group(1)!.replaceAll('"', '\\"')}"');
      final list = jsonDecode(normalized);
      if (list is List) {
        final lines = <String>[];
        for (final item in list) {
          if (item is! Map) continue;
          final title = _str(item['title']);
          final url = _str(item['url']);
          if (title.isNotEmpty) {
            lines.add('$title::$url');
          }
        }
        return lines.join('\n');
      }
    } catch (_) {}
    return '';
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      final s = v.trim();
      if (s.startsWith('{') && s.endsWith('}')) {
        // 将 Python 风格单引号字典转为 JSON 双引号后解析。
        // 简单替换单引号为双引号；若值内含有引号可能失败，此时返回空 map。
        try {
          final jsonStr = s
              .replaceAllMapped(
                  RegExp(r"'((?:\\.|[^'\\])*)'"), (m) => '"${m.group(1)!.replaceAll('"', '\\"')}"');
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }
    return const {};
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  Map<String, dynamic> toJson() => {
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        'httpUserAgent': httpUserAgent,
        'ruleSearchUrl': ruleSearchUrl,
        'ruleSearchList': ruleSearchList,
        'ruleSearchName': ruleSearchName,
        'ruleSearchAuthor': ruleSearchAuthor,
        'ruleSearchCoverUrl': ruleSearchCoverUrl,
        'ruleSearchNoteUrl': ruleSearchNoteUrl,
        'ruleBookName': ruleBookName,
        'ruleCoverUrl': ruleCoverUrl,
        'ruleBookAuthor': ruleBookAuthor,
        'ruleBookKind': ruleBookKind,
        'ruleIntroduce': ruleIntroduce,
        'ruleChapterList': ruleChapterList,
        'ruleChapterName': ruleChapterName,
        'ruleContentUrl': ruleContentUrl,
        'ruleChapterUrl': ruleChapterUrl,
        'ruleBookContent': ruleBookContent,
        'ruleFindUrl': ruleFindUrl,
        'enable': enable,
        'sourceRemark': sourceRemark,
        'weight': weight,
      };

  /// 是否为小说（文本）源。
  ///
  /// legado 书源 bookSourceType 通常为 0（文本）或字符串「0」/「文本」；
  /// 异次元图源 bookSourceType 为「漫画」或 1。未配置时按漫画处理。
  bool get isNovel {
    final t = bookSourceType.toString().trim();
    if (t.isEmpty) return false;
    if (t == '0' || t.toLowerCase() == 'text' || t == '文本' || t == '小说') return true;
    return false;
  }

  /// 是否为漫画（图片）源。
  bool get isComic => !isNovel;

  /// 发现页分类列表：标题::url
  List<FindCategory> get findCategories {
    if (ruleFindUrl.isEmpty) return [];
    final list = <FindCategory>[];
    for (final line in ruleFindUrl.split('\n')) {
      if (line.trim().isEmpty) continue;
      final idx = line.indexOf('::');
      if (idx > 0) {
        list.add(FindCategory(line.substring(0, idx), line.substring(idx + 2)));
      }
    }
    return list;
  }
}

class FindCategory {
  final String title;
  final String url;
  FindCategory(this.title, this.url);
}
