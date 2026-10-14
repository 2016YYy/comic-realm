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
    return ComicSource(
      bookSourceUrl: json['bookSourceUrl'] ?? '',
      bookSourceName: json['bookSourceName'] ?? '',
      bookSourceGroup: json['bookSourceGroup'] ?? '',
      bookSourceType: json['bookSourceType'] ?? '漫画',
      httpUserAgent: json['httpUserAgent'] ?? '',
      ruleSearchUrl: json['ruleSearchUrl'] ?? '',
      ruleSearchList: json['ruleSearchList'] ?? '',
      ruleSearchName: json['ruleSearchName'] ?? '',
      ruleSearchAuthor: json['ruleSearchAuthor'] ?? '',
      ruleSearchCoverUrl: json['ruleSearchCoverUrl'] ?? '',
      ruleSearchNoteUrl: json['ruleSearchNoteUrl'] ?? '',
      ruleBookName: json['ruleBookName'] ?? '',
      ruleCoverUrl: json['ruleCoverUrl'] ?? '',
      ruleBookAuthor: json['ruleBookAuthor'] ?? '',
      ruleBookKind: json['ruleBookKind'] ?? '',
      ruleIntroduce: json['ruleIntroduce'] ?? '',
      ruleChapterList: json['ruleChapterList'] ?? '',
      ruleChapterName: json['ruleChapterName'] ?? '',
      ruleContentUrl: json['ruleContentUrl'] ?? '',
      ruleBookContent: json['ruleBookContent'] ?? '',
      ruleFindUrl: json['ruleFindUrl'] ?? '',
      enable: json['enable'] ?? true,
      sourceRemark: json['sourceRemark'] ?? '',
      weight: json['weight'] ?? 0,
    );
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
