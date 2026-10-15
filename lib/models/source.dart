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
      ruleBookContent: pick([json['ruleBookContent'], rContent['content']]),
      ruleFindUrl: _str(json['ruleFindUrl']),
      enable: json['enable'] is bool ? json['enable'] as bool : true,
      sourceRemark: _str(json['sourceRemark']),
      weight: json['weight'] is int
          ? json['weight'] as int
          : int.tryParse(_str(json['weight'])) ?? 0,
    );
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

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
        'ruleBookContent': ruleBookContent,
        'ruleFindUrl': ruleFindUrl,
        'enable': enable,
        'sourceRemark': sourceRemark,
        'weight': weight,
      };

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
