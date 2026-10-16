import 'package:hive/hive.dart';

part 'comic.g.dart';

@HiveType(typeId: 1)
class Comic extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String author;

  @HiveField(2)
  String coverUrl;

  @HiveField(3)
  String introduce;

  @HiveField(4)
  String kind;

  @HiveField(5)
  String lastChapter;

  @HiveField(6)
  String noteUrl;

  @HiveField(7)
  String sourceUrl;

  @HiveField(8)
  String sourceName;

  @HiveField(9)
  bool isFavorite;

  @HiveField(10)
  DateTime? updateTime;

  /// 所属自定义书架文件夹，空字符串表示「全部」（未归类）
  @HiveField(11)
  String folder;

  Comic({
    this.name = '',
    this.author = '',
    this.coverUrl = '',
    this.introduce = '',
    this.kind = '',
    this.lastChapter = '',
    this.noteUrl = '',
    this.sourceUrl = '',
    this.sourceName = '',
    this.isFavorite = false,
    this.updateTime,
    this.folder = '',
  });

  /// 稳定的单本标识：优先用详情页地址，为空时回退书名
  /// （分类页 / 发现页的漫画常常没有 noteUrl，若直接用空串当键，
  /// 会导致同一图源下所有漫画互相覆盖，出现「爱心全亮」「封面重复」）。
  String get identity => noteUrl.isNotEmpty ? noteUrl : name;

  /// 全局唯一键：图源地址 + 标识。收藏、去重、Hero 标签统一使用它。
  String get uniqueKey => '$sourceUrl\u0000$identity';

  /// Hero 动画标签：列表页与详情页保持同一本漫画的一致标签。
  String get heroTag => 'cover-$sourceUrl-$identity';

  Map<String, dynamic> toJson() => {
        'name': name,
        'author': author,
        'coverUrl': coverUrl,
        'introduce': introduce,
        'kind': kind,
        'lastChapter': lastChapter,
        'noteUrl': noteUrl,
        'sourceUrl': sourceUrl,
        'sourceName': sourceName,
        'isFavorite': isFavorite,
        'folder': folder,
      };
}

@HiveType(typeId: 2)
class Chapter extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String url;

  @HiveField(2)
  int index;

  Chapter({this.name = '', this.url = '', this.index = 0});
}
